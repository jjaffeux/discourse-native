import XCTest
@testable import DiscourseNativeSupport

@MainActor
final class PushRegistrationCoordinatorTests: XCTestCase {
  func testConcurrentCallersShareRegistrationAndReuseTheToken() async {
    let host = RegistrationHost()
    let coordinator = host.makeCoordinator()
    var results: [String?] = []
    coordinator.registrationToken { results.append($0) }
    coordinator.registrationToken { results.append($0) }
    XCTAssertEqual(host.authorizations.count, 1)
    XCTAssertEqual(host.timeouts.count, 1)

    host.authorizations[0](true)
    await drainMainQueue()
    XCTAssertEqual(host.registrations, 1)
    XCTAssertTrue(results.isEmpty)

    coordinator.didRegister("device-token")
    coordinator.registrationToken { results.append($0) }
    XCTAssertEqual(results, ["device-token", "device-token", "device-token"])
    XCTAssertEqual(host.authorizations.count, 1)
    XCTAssertEqual(host.cancelledTimeouts, [0])
  }

  func testTimeoutSettlesEveryCallerAndAllowsAnotherAttempt() {
    let host = RegistrationHost()
    let coordinator = host.makeCoordinator()
    var results: [String?] = []
    coordinator.registrationToken { results.append($0) }
    coordinator.registrationToken { results.append($0) }

    host.timeouts[0]()
    XCTAssertEqual(results, [nil, nil])
    XCTAssertEqual(host.cancelledTimeouts, [0])

    coordinator.registrationToken { results.append($0) }
    XCTAssertEqual(host.authorizations.count, 2)
    // Cancellation cannot recall a callback which was already dispatched.
    host.timeouts[0]()
    XCTAssertEqual(results, [nil, nil])
    coordinator.didRegister("retry-token")
    XCTAssertEqual(results, [nil, nil, "retry-token"])
  }

  func testOldPermissionRepliesCannotFinishOrRegisterANewerAttempt() async {
    let host = RegistrationHost()
    let coordinator = host.makeCoordinator()
    var results: [String?] = []
    coordinator.registrationToken { results.append($0) }
    host.timeouts[0]()
    coordinator.registrationToken { results.append($0) }

    host.authorizations[0](false)
    await drainMainQueue()
    XCTAssertEqual(results, [nil])
    XCTAssertEqual(host.cancelledTimeouts, [0])
    host.authorizations[0](true)
    await drainMainQueue()
    XCTAssertEqual(host.registrations, 0)

    host.authorizations[1](true)
    await drainMainQueue()
    XCTAssertEqual(host.registrations, 1)
    coordinator.didRegister("new-token")
    XCTAssertEqual(results, [nil, "new-token"])
  }

  func testLateAPNsSuccessIsCachedAndLateFailureCannotEraseIt() {
    let host = RegistrationHost()
    let coordinator = host.makeCoordinator()
    var results: [String?] = []
    coordinator.registrationToken { results.append($0) }
    host.timeouts[0]()
    coordinator.didRegister("late-token")
    coordinator.didFailToRegister()

    coordinator.registrationToken { results.append($0) }
    XCTAssertEqual(results, [nil, "late-token"])
    XCTAssertEqual(host.authorizations.count, 1)
  }

  func testDeniedPermissionSettlesCallersWithoutContactingAPNs() async {
    let host = RegistrationHost()
    let coordinator = host.makeCoordinator()
    var results: [String?] = []
    coordinator.registrationToken { results.append($0) }
    host.authorizations[0](false)
    await drainMainQueue()

    XCTAssertEqual(results, [nil])
    XCTAssertEqual(host.registrations, 0)
    XCTAssertEqual(host.cancelledTimeouts, [0])
    coordinator.registrationToken { results.append($0) }
    XCTAssertEqual(host.authorizations.count, 2)
  }

  func testFailureCallbackCanRetryWithoutJoiningTheFinishedAttempt() {
    let host = RegistrationHost()
    let coordinator = host.makeCoordinator()
    var results: [String?] = []
    coordinator.registrationToken { token in
      results.append(token)
      coordinator.registrationToken { results.append($0) }
    }
    coordinator.didFailToRegister()
    XCTAssertEqual(host.authorizations.count, 2)
    XCTAssertEqual(results, [nil])

    coordinator.didRegister("retried-token")
    XCTAssertEqual(results, [nil, "retried-token"])
    XCTAssertEqual(host.cancelledTimeouts, [0, 1])
  }

  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}

@MainActor
private final class RegistrationHost {
  var authorizations: [(Bool) -> Void] = []
  var timeouts: [() -> Void] = []
  var cancelledTimeouts: [Int] = []
  var registrations = 0

  func makeCoordinator() -> PushRegistrationCoordinator {
    PushRegistrationCoordinator(
      requestAuthorization: { self.authorizations.append($0) },
      registerForRemoteNotifications: { self.registrations += 1 },
      scheduleTimeout: { callback in
        let index = self.timeouts.count
        self.timeouts.append(callback)
        return { self.cancelledTimeouts.append(index) }
      }
    )
  }
}
