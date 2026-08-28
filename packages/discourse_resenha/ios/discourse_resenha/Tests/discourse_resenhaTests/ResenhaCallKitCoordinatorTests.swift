import CallKit
import Flutter
import XCTest

@testable import discourse_resenha

final class ResenhaCallKitCoordinatorTests: XCTestCase {
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

  func testProviderResetCompletesPendingEnd() {
    let transactions = TransactionRecorder()
    let coordinator = ResenhaCallKitCoordinator(
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
