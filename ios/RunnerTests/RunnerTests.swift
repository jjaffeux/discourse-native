import CallKit
import Flutter
import XCTest

@testable import Runner

final class RunnerTests: XCTestCase {
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
