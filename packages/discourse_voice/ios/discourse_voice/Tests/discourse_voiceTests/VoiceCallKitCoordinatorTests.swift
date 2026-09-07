import CallKit
import Flutter
import XCTest

@testable import discourse_voice

final class VoiceCallKitCoordinatorTests: XCTestCase {
  func testStartRequestsCallAndConfiguresProviderAction() {
    let transactions = TransactionRecorder()
    var configuredAudio = false
    var startedCall: UUID?
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportOutgoingCallStarted: { startedCall = $0 },
      configureAudioSession: { configuredAudio = true }
    )

    XCTAssertNil(
      invoke(
        coordinator,
        method: "start",
        arguments: ["roomName": "Team room"]
      ))

    let action = tryUnwrap(transactions.actions.first as? CXStartCallAction)
    XCTAssertEqual(action.handle.type, .generic)
    XCTAssertEqual(action.handle.value, "Team room")
    XCTAssertFalse(action.isVideo)

    coordinator.handleStartAction(action)

    XCTAssertTrue(configuredAudio)
    XCTAssertEqual(startedCall, action.callUUID)
  }

  func testAudioConfigurationFailureClearsCallAndEmitsEnd() {
    let transactions = TransactionRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) },
      configureAudioSession: {
        throw NSError(domain: "RunnerTests", code: 8)
      }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let start = tryUnwrap(transactions.actions.first as? CXStartCallAction)
    coordinator.handleStartAction(start)

    XCTAssertEqual(emittedMethods, ["end"])
    XCTAssertNil(invoke(coordinator, method: "end"))
    XCTAssertEqual(transactions.actions.count, 1)
  }

  func testStaleProviderActionsDoNotAffectNewCall() {
    let transactions = TransactionRecorder()
    var startedCalls: [UUID] = []
    var emittedMethods: [String] = []
    var audioConfigurations = 0
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportOutgoingCallStarted: { startedCalls.append($0) },
      emitMethod: { emittedMethods.append($0) },
      configureAudioSession: { audioConfigurations += 1 }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let firstStart = tryUnwrap(transactions.actions.last as? CXStartCallAction)
    XCTAssertNil(invoke(coordinator, method: "start"))
    let secondStart = tryUnwrap(transactions.actions.last as? CXStartCallAction)

    coordinator.handleStartAction(firstStart)
    coordinator.handleSetMutedAction(
      CXSetMutedCallAction(call: firstStart.callUUID, muted: true)
    )

    XCTAssertEqual(audioConfigurations, 0)
    XCTAssertTrue(startedCalls.isEmpty)
    XCTAssertTrue(emittedMethods.isEmpty)

    coordinator.handleStartAction(secondStart)
    coordinator.handleSetMutedAction(
      CXSetMutedCallAction(call: secondStart.callUUID, muted: true)
    )

    XCTAssertEqual(audioConfigurations, 1)
    XCTAssertEqual(startedCalls, [secondStart.callUUID])
    XCTAssertEqual(emittedMethods, ["mute"])
  }

  func testMuteRequestsActionAndEmitsProviderCallback() {
    let transactions = TransactionRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let startAction = tryUnwrap(transactions.actions.first as? CXStartCallAction)
    XCTAssertNil(
      invoke(
        coordinator,
        method: "setMuted",
        arguments: ["muted": true]
      ))

    let muteAction = tryUnwrap(transactions.actions.last as? CXSetMutedCallAction)
    XCTAssertEqual(muteAction.callUUID, startAction.callUUID)
    XCTAssertTrue(muteAction.isMuted)

    coordinator.handleSetMutedAction(muteAction)

    XCTAssertEqual(emittedMethods, ["mute"])
    XCTAssertNil(
      invoke(
        coordinator,
        method: "setMuted",
        arguments: ["muted": true]
      ))
    XCTAssertEqual(transactions.actions.count, 2)
  }

  func testEndRequestsActionAndClearsCallOnProviderCallback() {
    let transactions = TransactionRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let startAction = tryUnwrap(transactions.actions.first as? CXStartCallAction)
    let endCompleted = expectation(description: "end completed")
    var endResult: Any?
    coordinator.handle(
      FlutterMethodCall(methodName: "end", arguments: nil)
    ) { result in
      endResult = result
      endCompleted.fulfill()
    }

    let endAction = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertEqual(endAction.callUUID, startAction.callUUID)
    XCTAssertEqual(emittedMethods, [])

    coordinator.handleEndAction(endAction)
    wait(for: [endCompleted], timeout: 1)

    XCTAssertNil(endResult)
    XCTAssertEqual(emittedMethods, ["end"])
    XCTAssertNil(invoke(coordinator, method: "end"))
    XCTAssertEqual(transactions.actions.count, 2)
  }

  func testReportedFailureCompletesPendingEndExactlyOnce() {
    let transactions = TransactionRecorder()
    var endedCall: UUID?
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportCallEnded: { uuid, reason in
        endedCall = uuid
        XCTAssertEqual(reason, .failed)
      }
    )
    XCTAssertNil(invoke(coordinator, method: "start"))
    var endResults: [Any?] = []
    coordinator.handle(FlutterMethodCall(methodName: "end", arguments: nil)) {
      endResults.append($0)
    }
    let end = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertTrue(endResults.isEmpty)

    XCTAssertNil(invoke(coordinator, method: "failed"))

    XCTAssertEqual(endedCall, end.callUUID)
    XCTAssertEqual(endResults.count, 1)
    XCTAssertNil(endResults.first ?? nil)
    coordinator.handleEndAction(end)
    coordinator.handleProviderReset()
    XCTAssertEqual(endResults.count, 1)
  }

  func testExpiredRingCompletesPendingDeclineExactlyOnce() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report
    )
    XCTAssertEqual(invoke(coordinator, method: "reportIncomingCall") as? Bool, true)
    var declineResults: [Any?] = []
    coordinator.handle(FlutterMethodCall(methodName: "declineIncomingCall", arguments: nil)) {
      declineResults.append($0)
    }
    let decline = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertTrue(declineResults.isEmpty)

    XCTAssertNil(invoke(coordinator, method: "endIncomingCall", arguments: ["reason": "unanswered"]))

    XCTAssertEqual(declineResults.count, 1)
    XCTAssertNil(declineResults.first ?? nil)
    coordinator.handleEndAction(decline)
    coordinator.handleProviderReset()
    XCTAssertEqual(declineResults.count, 1)
  }

  func testProviderResetClearsCallAndEmitsEnd() {
    let transactions = TransactionRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))

    coordinator.handleProviderReset()

    XCTAssertEqual(emittedMethods, ["end"])
    XCTAssertNil(invoke(coordinator, method: "end"))
    XCTAssertEqual(transactions.actions.count, 1)
  }

  func testProviderResetCompletesPendingEnd() {
    let transactions = TransactionRecorder()
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let completed = expectation(description: "end completed after reset")
    coordinator.handle(
      FlutterMethodCall(methodName: "end", arguments: nil)
    ) { result in
      XCTAssertNil(result)
      completed.fulfill()
    }

    coordinator.handleProviderReset()

    wait(for: [completed], timeout: 1)
  }

  func testTransactionFailureReturnsFlutterError() {
    let transactions = TransactionRecorder()
    transactions.error = NSError(
      domain: "RunnerTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "request rejected"]
    )
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request
    )

    let result = invoke(coordinator, method: "start")

    let error = tryUnwrap(result as? FlutterError)
    XCTAssertEqual(error.code, "callkit_transaction")
    XCTAssertEqual(error.message, "request rejected")
    XCTAssertNil(error.details)

    transactions.error = nil
    XCTAssertNil(invoke(coordinator, method: "end"))
    XCTAssertEqual(transactions.actions.count, 1)
  }

  func testStaleEndActionDoesNotClearNewCall() {
    let transactions = TransactionRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let firstStart = tryUnwrap(transactions.actions.last as? CXStartCallAction)
    let firstEndCompleted = expectation(description: "stale end completed")
    coordinator.handle(
      FlutterMethodCall(methodName: "end", arguments: nil)
    ) { result in
      XCTAssertNil(result)
      firstEndCompleted.fulfill()
    }
    let firstEnd = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertEqual(firstEnd.callUUID, firstStart.callUUID)

    XCTAssertNil(invoke(coordinator, method: "start"))
    let secondStart = tryUnwrap(transactions.actions.last as? CXStartCallAction)
    coordinator.handleEndAction(firstEnd)
    wait(for: [firstEndCompleted], timeout: 1)

    XCTAssertTrue(emittedMethods.isEmpty)
    XCTAssertNil(
      invoke(
        coordinator,
        method: "setMuted",
        arguments: ["muted": true]
      )
    )
    let mute = tryUnwrap(transactions.actions.last as? CXSetMutedCallAction)
    XCTAssertEqual(mute.callUUID, secondStart.callUUID)
  }

  func testIncomingCallIsPresentedAnsweredAndReusedByStart() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    var emittedMethods: [String] = []
    var configuredAudio = 0
    var connectedCalls: [UUID] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report,
      reportOutgoingCallConnected: { connectedCalls.append($0) },
      emitMethod: { emittedMethods.append($0) },
      configureAudioSession: { configuredAudio += 1 }
    )

    let presented = invoke(
      coordinator,
      method: "reportIncomingCall",
      arguments: ["callerName": "Kim", "roomName": "Call", "handle": "kim"]
    )

    XCTAssertEqual(presented as? Bool, true)
    let reported = tryUnwrap(incoming.reported.first)
    XCTAssertEqual(reported.update.localizedCallerName, "Kim")
    XCTAssertEqual(reported.update.remoteHandle?.value, "kim")
    XCTAssertEqual(reported.update.hasVideo, false)

    coordinator.handleAnswerAction(CXAnswerCallAction(call: reported.uuid))

    XCTAssertEqual(configuredAudio, 1)
    XCTAssertEqual(emittedMethods, ["answer"])

    // Dart joins the room: the system call already exists.
    XCTAssertNil(invoke(coordinator, method: "start", arguments: ["roomName": "Call"]))
    XCTAssertTrue(transactions.actions.isEmpty)
    XCTAssertNil(invoke(coordinator, method: "connected"))
    XCTAssertTrue(connectedCalls.isEmpty)

    XCTAssertNil(
      invoke(coordinator, method: "setMuted", arguments: ["muted": true])
    )
    let mute = tryUnwrap(transactions.actions.last as? CXSetMutedCallAction)
    XCTAssertEqual(mute.callUUID, reported.uuid)

    let endCompleted = expectation(description: "end completed")
    coordinator.handle(FlutterMethodCall(methodName: "end", arguments: nil)) { _ in
      endCompleted.fulfill()
    }
    let end = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertEqual(end.callUUID, reported.uuid)
    coordinator.handleEndAction(end)
    wait(for: [endCompleted], timeout: 1)

    XCTAssertEqual(emittedMethods, ["answer", "end"])
    // With the incoming call gone, a start places an outgoing call again.
    XCTAssertNil(invoke(coordinator, method: "start"))
    XCTAssertTrue(transactions.actions.last is CXStartCallAction)
  }

  func testEndingAnUnansweredIncomingCallDeclinesIt() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report,
      emitMethod: { emittedMethods.append($0) }
    )
    XCTAssertEqual(invoke(coordinator, method: "reportIncomingCall") as? Bool, true)
    let uuid = tryUnwrap(incoming.reported.first).uuid

    coordinator.handleEndAction(CXEndCallAction(call: uuid))

    XCTAssertEqual(emittedMethods, ["decline"])
    XCTAssertNil(invoke(coordinator, method: "start"))
    XCTAssertTrue(transactions.actions.last is CXStartCallAction)
  }

  func testLocalAnswerRequestsTheAnswerActionWithoutEchoingIt() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report,
      emitMethod: { emittedMethods.append($0) }
    )
    XCTAssertEqual(invoke(coordinator, method: "reportIncomingCall") as? Bool, true)
    let uuid = tryUnwrap(incoming.reported.first).uuid

    XCTAssertNil(invoke(coordinator, method: "answerIncomingCall"))

    let answer = tryUnwrap(transactions.actions.last as? CXAnswerCallAction)
    XCTAssertEqual(answer.callUUID, uuid)
    coordinator.handleAnswerAction(answer)
    XCTAssertTrue(emittedMethods.isEmpty)

    XCTAssertNil(invoke(coordinator, method: "start"))
    XCTAssertEqual(transactions.actions.count, 1)
    XCTAssertNil(invoke(coordinator, method: "answerIncomingCall"))
    XCTAssertEqual(transactions.actions.count, 1)
  }

  func testLocalDeclineEndsTheIncomingCallThroughCallKit() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report,
      emitMethod: { emittedMethods.append($0) }
    )
    XCTAssertEqual(invoke(coordinator, method: "reportIncomingCall") as? Bool, true)
    let uuid = tryUnwrap(incoming.reported.first).uuid

    let declined = expectation(description: "decline completed")
    coordinator.handle(
      FlutterMethodCall(methodName: "declineIncomingCall", arguments: nil)
    ) { result in
      XCTAssertNil(result)
      declined.fulfill()
    }
    let end = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertEqual(end.callUUID, uuid)
    coordinator.handleEndAction(end)
    wait(for: [declined], timeout: 1)

    XCTAssertEqual(emittedMethods, ["decline"])
  }

  func testAnUnansweredRingIsReportedEnded() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    var ended: [(UUID, CXCallEndedReason)] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report,
      reportCallEnded: { ended.append(($0, $1)) }
    )
    XCTAssertEqual(invoke(coordinator, method: "reportIncomingCall") as? Bool, true)
    let uuid = tryUnwrap(incoming.reported.first).uuid

    XCTAssertNil(
      invoke(
        coordinator,
        method: "endIncomingCall",
        arguments: ["reason": "answered_elsewhere"]
      )
    )

    XCTAssertEqual(ended.count, 1)
    XCTAssertEqual(ended.first?.0, uuid)
    XCTAssertEqual(ended.first?.1, .answeredElsewhere)
    XCTAssertNil(invoke(coordinator, method: "endIncomingCall"))
    XCTAssertEqual(ended.count, 1)
    XCTAssertNil(invoke(coordinator, method: "start"))
    XCTAssertTrue(transactions.actions.last is CXStartCallAction)
  }

  func testIncomingCallIsRefusedWhileACallIsUpOrWhenCallKitFails() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    XCTAssertEqual(invoke(coordinator, method: "reportIncomingCall") as? Bool, false)
    XCTAssertTrue(incoming.reported.isEmpty)

    let fresh = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report
    )
    incoming.error = NSError(domain: "RunnerTests", code: 3)
    XCTAssertEqual(invoke(fresh, method: "reportIncomingCall") as? Bool, false)
    incoming.error = nil
    XCTAssertEqual(invoke(fresh, method: "reportIncomingCall") as? Bool, true)
    XCTAssertEqual(incoming.reported.count, 1)
  }

  func testProviderResetDuringARingDeclinesIt() {
    let transactions = TransactionRecorder()
    let incoming = IncomingCallRecorder()
    var emittedMethods: [String] = []
    let coordinator = VoiceCallKitCoordinator(
      requestTransaction: transactions.request,
      reportIncomingCall: incoming.report,
      emitMethod: { emittedMethods.append($0) }
    )
    XCTAssertEqual(invoke(coordinator, method: "reportIncomingCall") as? Bool, true)

    coordinator.handleProviderReset()

    XCTAssertEqual(emittedMethods, ["decline"])
    XCTAssertNil(invoke(coordinator, method: "endIncomingCall"))
  }

  func testRetiredIncomingReportReturnsFalseWithoutWithdrawingAReplacement() {
    let replacements: [IncomingCallState?] = [nil, .ringing, .answered, .reused]
    for retirement in IncomingCallRetirement.allCases {
      for fails in [false, true] {
        for replacementState in replacements {
          let name = "\(retirement), fails=\(fails), replacement=\(String(describing: replacementState))"
          XCTContext.runActivity(named: name) { _ in
            let transactions = TransactionRecorder()
            let incoming = HeldIncomingCallRecorder()
            defer { incoming.requests.removeAll() }
            var ended: [UUID] = []
            var events: [String] = []
            let coordinator = VoiceCallKitCoordinator(
              requestTransaction: transactions.request,
              reportIncomingCall: incoming.report,
              reportCallEnded: { uuid, _ in ended.append(uuid) },
              emitDiagnosticEvent: { event, _ in events.append(event) }
            )
            let completed = expectation(description: "retired report completed")
            completed.assertForOverFulfill = true
            var results: [Bool?] = []
            coordinator.handle(FlutterMethodCall(methodName: "reportIncomingCall", arguments: nil)) {
              results.append($0 as? Bool)
              // Dart withdraws a presentation reported for a ring it has retired.
              if $0 as? Bool == true {
                coordinator.handle(FlutterMethodCall(methodName: "endIncomingCall", arguments: nil)) {
                  XCTAssertNil($0)
                }
              }
              completed.fulfill()
            }
            let first = tryUnwrap(incoming.requests.first)
            retirement.retire(coordinator, uuid: first.uuid)
            XCTAssertTrue(results.isEmpty)

            if let replacementState {
              let replacementCompleted = expectation(description: "replacement presented")
              replacementCompleted.assertForOverFulfill = true
              coordinator.handle(FlutterMethodCall(methodName: "reportIncomingCall", arguments: nil)) {
                XCTAssertEqual($0 as? Bool, true)
                replacementCompleted.fulfill()
              }
              let replacement = tryUnwrap(incoming.requests.last)
              replacement.completion(nil)
              wait(for: [replacementCompleted], timeout: 1)
              replacementState.apply(coordinator, uuid: replacement.uuid)
              if replacementState != .ringing {
                coordinator.handleSetMutedAction(
                  CXSetMutedCallAction(call: replacement.uuid, muted: true)
                )
              }
            }
            let previouslyEnded = ended
            let previouslyPresented = events.filter { $0 == "callkit.incoming.presented" }.count

            first.completion(fails ? NSError(domain: "RunnerTests", code: 3) : nil)
            wait(for: [completed], timeout: 1)

            XCTAssertEqual(results, [false])
            XCTAssertEqual(ended, previouslyEnded)
            XCTAssertEqual(
              events.filter { $0 == "callkit.incoming.presented" }.count, previouslyPresented
            )
            if let replacementState {
              let replacement = tryUnwrap(incoming.requests.last)
              if replacementState != .ringing {
                XCTAssertNil(invoke(coordinator, method: "setMuted", arguments: ["muted": false]))
                XCTAssertEqual(transactions.actions.count, 1)
                XCTAssertEqual(
                  (transactions.actions.last as? CXSetMutedCallAction)?.callUUID, replacement.uuid
                )
              }
              if replacementState == .answered {
                XCTAssertNil(invoke(coordinator, method: "endIncomingCall"))
                XCTAssertEqual(ended, previouslyEnded)
              }
              let requestedTransactions = transactions.actions.count
              XCTAssertNil(invoke(coordinator, method: "start"))
              XCTAssertEqual(transactions.actions.count, requestedTransactions)
              coordinator.handleAnswerAction(CXAnswerCallAction(call: replacement.uuid))
              XCTAssertNil(invoke(coordinator, method: "endIncomingCall"))
              XCTAssertEqual(ended, previouslyEnded)
              XCTAssertNil(invoke(coordinator, method: "setMuted", arguments: ["muted": true]))
              XCTAssertEqual(
                (transactions.actions.last as? CXSetMutedCallAction)?.callUUID, replacement.uuid
              )
            } else {
              XCTAssertNil(invoke(coordinator, method: "start"))
              XCTAssertTrue(transactions.actions.last is CXStartCallAction)
            }
            coordinator.handleEndAction(CXEndCallAction(call: first.uuid))
            coordinator.handleProviderReset()
            XCTAssertEqual(results, [false])
          }
        }
      }
    }
  }

  func testCurrentIncomingReportSuccessPreservesRingingAnsweredAndReusedCalls() {
    for state in IncomingCallState.allCases {
      XCTContext.runActivity(named: "\(state)") { _ in
        let transactions = TransactionRecorder()
        let incoming = HeldIncomingCallRecorder()
        defer { incoming.requests.removeAll() }
        var connected: [UUID] = []
        var ended: [UUID] = []
        let coordinator = VoiceCallKitCoordinator(
          requestTransaction: transactions.request,
          reportIncomingCall: incoming.report,
          reportOutgoingCallConnected: { connected.append($0) },
          reportCallEnded: { uuid, _ in ended.append(uuid) }
        )
        let completed = expectation(description: "current report completed")
        completed.assertForOverFulfill = true
        var results: [Bool?] = []
        coordinator.handle(FlutterMethodCall(methodName: "reportIncomingCall", arguments: nil)) {
          results.append($0 as? Bool)
          completed.fulfill()
        }
        let request = tryUnwrap(incoming.requests.first)
        state.apply(coordinator, uuid: request.uuid)

        request.completion(nil)
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(results, [true])
        XCTAssertNil(invoke(coordinator, method: "start"))
        XCTAssertNil(invoke(coordinator, method: "connected"))
        XCTAssertTrue(connected.isEmpty)
        XCTAssertTrue(transactions.actions.isEmpty)
        XCTAssertNil(invoke(coordinator, method: "setMuted", arguments: ["muted": true]))
        XCTAssertEqual(
          (transactions.actions.last as? CXSetMutedCallAction)?.callUUID, request.uuid
        )
        XCTAssertNil(invoke(coordinator, method: "endIncomingCall"))
        XCTAssertEqual(ended, state == .answered ? [] : [request.uuid])
        coordinator.handleProviderReset()
        XCTAssertEqual(results, [true])
      }
    }
  }

  func testCurrentIncomingReportFailureClearsCallAndCompletesPendingEndExactlyOnce() {
    for state in IncomingCallState.allCases {
      XCTContext.runActivity(named: "\(state)") { _ in
        let transactions = TransactionRecorder()
        let incoming = HeldIncomingCallRecorder()
        defer { incoming.requests.removeAll() }
        var connected: [UUID] = []
        let coordinator = VoiceCallKitCoordinator(
          requestTransaction: transactions.request,
          reportIncomingCall: incoming.report,
          reportOutgoingCallConnected: { connected.append($0) }
        )
        let completed = expectation(description: "failed report completed")
        completed.assertForOverFulfill = true
        var results: [Bool?] = []
        coordinator.handle(FlutterMethodCall(methodName: "reportIncomingCall", arguments: nil)) {
          results.append($0 as? Bool)
          completed.fulfill()
        }
        let request = tryUnwrap(incoming.requests.first)
        state.apply(coordinator, uuid: request.uuid)
        var endResults: [Any?] = []
        coordinator.handle(
          FlutterMethodCall(
            methodName: state == .answered ? "end" : "declineIncomingCall", arguments: nil
          )
        ) { endResults.append($0) }
        let end = tryUnwrap(transactions.actions.last as? CXEndCallAction)
        XCTAssertTrue(endResults.isEmpty)

        request.completion(NSError(domain: "RunnerTests", code: 3))
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(results, [false])
        XCTAssertEqual(endResults.count, 1)
        XCTAssertNil(endResults.first ?? nil)
        XCTAssertNil(invoke(coordinator, method: "connected"))
        XCTAssertTrue(connected.isEmpty)
        XCTAssertNil(invoke(coordinator, method: "setMuted", arguments: ["muted": true]))
        XCTAssertEqual(transactions.actions.count, 1)

        let replacementCompleted = expectation(description: "replacement accepted after failure")
        coordinator.handle(FlutterMethodCall(methodName: "reportIncomingCall", arguments: nil)) {
          XCTAssertEqual($0 as? Bool, true)
          replacementCompleted.fulfill()
        }
        if incoming.requests.count == 2 {
          incoming.requests[1].completion(nil)
        }
        wait(for: [replacementCompleted], timeout: 1)
        XCTAssertEqual(incoming.requests.count, 2)
        coordinator.handleEndAction(end)
        coordinator.handleProviderReset()
        XCTAssertEqual(results, [false])
        XCTAssertEqual(endResults.count, 1)
      }
    }
  }

  private func invoke(
    _ coordinator: VoiceCallKitCoordinator,
    method: String,
    arguments: Any? = nil
  ) -> Any? {
    let completed = expectation(description: "\(method) completed")
    var output: Any?
    coordinator.handle(
      FlutterMethodCall(methodName: method, arguments: arguments)
    ) { result in
      output = result
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)
    return output
  }

  private func tryUnwrap<T>(
    _ value: T?,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> T {
    guard let value else {
      XCTFail("Expected a non-nil value", file: file, line: line)
      fatalError("Expected a non-nil value")
    }
    return value
  }
}

private enum IncomingCallRetirement: CaseIterable {
  case providerReset, expired, providerEnd

  func retire(_ coordinator: VoiceCallKitCoordinator, uuid: UUID) {
    switch self {
    case .providerReset:
      coordinator.handleProviderReset()
    case .expired:
      coordinator.handle(FlutterMethodCall(methodName: "endIncomingCall", arguments: nil)) {
        XCTAssertNil($0)
      }
    case .providerEnd:
      coordinator.handleEndAction(CXEndCallAction(call: uuid))
    }
  }
}

private enum IncomingCallState: CaseIterable {
  case ringing, answered, reused

  func apply(_ coordinator: VoiceCallKitCoordinator, uuid: UUID) {
    switch self {
    case .ringing:
      break
    case .answered:
      coordinator.handleAnswerAction(CXAnswerCallAction(call: uuid))
    case .reused:
      coordinator.handle(FlutterMethodCall(methodName: "start", arguments: nil)) {
        XCTAssertNil($0)
      }
    }
  }
}

private final class HeldIncomingCallRecorder {
  var requests: [(uuid: UUID, completion: (Error?) -> Void)] = []

  func report(
    _ uuid: UUID,
    _ update: CXCallUpdate,
    completion: @escaping (Error?) -> Void
  ) {
    requests.append((uuid: uuid, completion: completion))
  }
}

private final class TransactionRecorder {
  var actions: [CXAction] = []
  var error: Error?

  func request(_ action: CXAction, completion: @escaping (Error?) -> Void) {
    actions.append(action)
    completion(error)
  }
}

private final class IncomingCallRecorder {
  var reported: [(uuid: UUID, update: CXCallUpdate)] = []
  var error: Error?

  func report(
    _ uuid: UUID,
    _ update: CXCallUpdate,
    completion: @escaping (Error?) -> Void
  ) {
    if error == nil {
      reported.append((uuid: uuid, update: update))
    }
    completion(error)
  }
}
