import Foundation

/// Owns one registration attempt for all waiting callers. The native adapters
/// deliver platform events on the main queue; permission replies may arrive on
/// any queue and are brought back here before inspecting the current attempt.
final class PushRegistrationCoordinator {
  typealias AuthorizationRequest = (@escaping (Bool) -> Void) -> Void
  typealias TimeoutScheduler = (@escaping () -> Void) -> () -> Void

  private let requestAuthorization: AuthorizationRequest
  private let authorizationGranted: AuthorizationRequest
  private let registerForRemoteNotifications: () -> Void
  private let scheduleTimeout: TimeoutScheduler
  private var token: String?
  private var attempt: UUID?
  private var attemptMayPrompt = false
  private var pending: [(String?) -> Void] = []
  private var cancelTimeout: (() -> Void)?

  init(
    requestAuthorization: @escaping AuthorizationRequest,
    authorizationGranted: @escaping AuthorizationRequest,
    registerForRemoteNotifications: @escaping () -> Void,
    scheduleTimeout: @escaping TimeoutScheduler = PushRegistrationCoordinator.scheduleRegistrationTimeout
  ) {
    self.requestAuthorization = requestAuthorization
    self.authorizationGranted = authorizationGranted
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
    begin(result, mayPrompt: true)
  }

  /// The token this installation holds now, without ever asking the user for
  /// permission. APNs is asked again rather than trusting the cached token:
  /// this is how a rotated token or a revoked permission is noticed.
  func currentToken(_ result: @escaping (String?) -> Void) {
    precondition(Thread.isMainThread)
    begin(result, mayPrompt: false)
  }

  private func begin(_ result: @escaping (String?) -> Void, mayPrompt: Bool) {
    pending.append(result)
    // A sign-in must not inherit a passive check's refusal to ask the user.
    guard attempt == nil || (mayPrompt && !attemptMayPrompt) else { return }
    cancelTimeout?()
    let current = UUID()
    attempt = current
    attemptMayPrompt = mayPrompt
    cancelTimeout = scheduleTimeout { [weak self] in
      self?.finish(with: nil, attempt: current)
    }
    let authorization = mayPrompt ? requestAuthorization : authorizationGranted
    authorization { [weak self] granted in
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
