import Foundation

/// Owns one registration attempt for all waiting callers. The native adapters
/// deliver platform events on the main queue; permission replies may arrive on
/// any queue and are brought back here before inspecting the current attempt.
final class PushRegistrationCoordinator {
  typealias AuthorizationRequest = (@escaping (Bool) -> Void) -> Void
  typealias TimeoutScheduler = (@escaping () -> Void) -> () -> Void

  private let requestAuthorization: AuthorizationRequest
  private let registerForRemoteNotifications: () -> Void
  private let scheduleTimeout: TimeoutScheduler
  private var token: String?
  private var attempt: UUID?
  private var pending: [(String?) -> Void] = []
  private var cancelTimeout: (() -> Void)?

  init(
    requestAuthorization: @escaping AuthorizationRequest,
    registerForRemoteNotifications: @escaping () -> Void,
    scheduleTimeout: @escaping TimeoutScheduler = PushRegistrationCoordinator.scheduleRegistrationTimeout
  ) {
    self.requestAuthorization = requestAuthorization
    self.registerForRemoteNotifications = registerForRemoteNotifications
    self.scheduleTimeout = scheduleTimeout
  }

  deinit {
    cancelTimeout?()
  }

  func registrationToken(_ result: @escaping (String?) -> Void) {
    precondition(Thread.isMainThread)
    if let token {
      result(token)
      return
    }

    pending.append(result)
    guard attempt == nil else { return }
    let current = UUID()
    attempt = current
    cancelTimeout = scheduleTimeout { [weak self] in
      self?.finish(with: nil, attempt: current)
    }
    requestAuthorization { [weak self] granted in
      DispatchQueue.main.async { [weak self] in
        guard let self, self.attempt == current else { return }
        guard granted else {
          self.finish(with: nil, attempt: current)
          return
        }
        self.registerForRemoteNotifications()
      }
    }
  }

  func didRegister(_ token: String) {
    precondition(Thread.isMainThread)
    // APNs tokens belong to this installation, not to a permission request.
    // A successful reply after the deadline is still useful to the next caller.
    self.token = token
    if let attempt { finish(with: token, attempt: attempt) }
  }

  func didFailToRegister() {
    precondition(Thread.isMainThread)
    // A late failure must not erase a successfully cached token.
    if let attempt { finish(with: nil, attempt: attempt) }
  }

  private func finish(with token: String?, attempt completed: UUID) {
    precondition(Thread.isMainThread)
    guard attempt == completed else { return }
    attempt = nil
    let cancel = cancelTimeout
    cancelTimeout = nil
    let results = pending
    pending.removeAll()
    cancel?()
    // Clear the attempt before callbacks: a failed caller can retry immediately.
    results.forEach { $0(token) }
  }

  private static func scheduleRegistrationTimeout(_ timeout: @escaping () -> Void) -> () -> Void {
    let item = DispatchWorkItem(block: timeout)
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: item)
    return { item.cancel() }
  }
}
