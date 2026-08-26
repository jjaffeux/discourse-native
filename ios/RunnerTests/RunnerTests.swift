import CallKit
import Flutter
import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
  func testPushTokenUsesAPNsHexEncoding() {
    XCTAssertEqual(pushTokenHex(Data([0x00, 0x0f, 0xa0, 0xff])), "000fa0ff")
  }

  func testDiscourseURLComesFromNotificationPayload() {
    let url = "https://meta.discourse.org/t/native-push/42/3"

    XCTAssertEqual(discourseUrl(in: ["discourse_url": url]), url)
    XCTAssertNil(discourseUrl(in: ["discourse_url": 42]))
    XCTAssertNil(
      discourseUrl(in: ["discourse_url": String(repeating: "x", count: 2049)])
    )
  }

  func testStartRequestsCallAndConfiguresProviderAction() {
    let transactions = TransactionRecorder()
    var configuredAudio = false
    var startedCall: UUID?
    let coordinator = ResenhaCallKitCoordinator(
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
    let coordinator = ResenhaCallKitCoordinator(
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
    let coordinator = ResenhaCallKitCoordinator(
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
    let coordinator = ResenhaCallKitCoordinator(
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
    let coordinator = ResenhaCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let startAction = tryUnwrap(transactions.actions.first as? CXStartCallAction)
    XCTAssertNil(invoke(coordinator, method: "end"))

    let endAction = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertEqual(endAction.callUUID, startAction.callUUID)

    coordinator.handleEndAction(endAction)

    XCTAssertEqual(emittedMethods, ["end"])
    XCTAssertNil(invoke(coordinator, method: "end"))
    XCTAssertEqual(transactions.actions.count, 2)
  }

  func testProviderResetClearsCallAndEmitsEnd() {
    let transactions = TransactionRecorder()
    var emittedMethods: [String] = []
    let coordinator = ResenhaCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))

    coordinator.handleProviderReset()

    XCTAssertEqual(emittedMethods, ["end"])
    XCTAssertNil(invoke(coordinator, method: "end"))
    XCTAssertEqual(transactions.actions.count, 1)
  }

  func testTransactionFailureReturnsFlutterError() {
    let transactions = TransactionRecorder()
    transactions.error = NSError(
      domain: "RunnerTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "request rejected"]
    )
    let coordinator = ResenhaCallKitCoordinator(
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
    let coordinator = ResenhaCallKitCoordinator(
      requestTransaction: transactions.request,
      emitMethod: { emittedMethods.append($0) }
    )

    XCTAssertNil(invoke(coordinator, method: "start"))
    let firstStart = tryUnwrap(transactions.actions.last as? CXStartCallAction)
    XCTAssertNil(invoke(coordinator, method: "end"))
    let firstEnd = tryUnwrap(transactions.actions.last as? CXEndCallAction)
    XCTAssertEqual(firstEnd.callUUID, firstStart.callUUID)

    XCTAssertNil(invoke(coordinator, method: "start"))
    let secondStart = tryUnwrap(transactions.actions.last as? CXStartCallAction)
    coordinator.handleEndAction(firstEnd)

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

  private func invoke(
    _ coordinator: ResenhaCallKitCoordinator,
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

private final class TransactionRecorder {
  var actions: [CXAction] = []
  var error: Error?

  func request(_ action: CXAction, completion: @escaping (Error?) -> Void) {
    actions.append(action)
    completion(error)
  }
}
