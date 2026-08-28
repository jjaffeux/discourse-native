import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // A notification activation can be the first event of a cold launch, so
    // its delegate must exist before AppKit finishes launching the process.
    UNUserNotificationCenter.current().delegate = self
  }

  override func application(
    _ application: NSApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    MacOSPushNotifications.shared.didRegister(deviceToken)
  }

  override func application(
    _ application: NSApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    MacOSPushNotifications.shared.didFailToRegister()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    MacOSPushNotifications.shared.didOpen(response)
    completionHandler()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound, .badge])
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

func pushTokenHex(_ data: Data) -> String {
  data.map { String(format: "%02x", $0) }.joined()
}

func discourseUrl(in userInfo: [AnyHashable: Any]) -> String? {
  guard let url = userInfo["discourse_url"] as? String,
    !url.isEmpty,
    url.utf8.count <= 2048
  else {
    return nil
  }
  return url
}

final class MacOSPushNotifications: NSObject, FlutterStreamHandler {
  static let shared = MacOSPushNotifications()
  private static let registrationTimeout: TimeInterval = 15

  private var registrationChannel: FlutterMethodChannel?
  private var notificationOpenChannel: FlutterEventChannel?
  private var notificationOpenSink: FlutterEventSink?
  private var pendingNotificationUrls: [String] = []
  private var handledResponseIdentifiers: [String] = []
  private var token: String?
  private var pendingResults: [FlutterResult] = []
  private var registrationInProgress = false
  private var registrationTimeoutWorkItem: DispatchWorkItem?

  private override init() {
    super.init()
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let registrationChannel = FlutterMethodChannel(
      name: "org.discourse.native/push_notifications",
      binaryMessenger: messenger
    )
    registrationChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "registrationToken" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.registrationToken(result)
    }
    self.registrationChannel = registrationChannel

    let notificationOpenChannel = FlutterEventChannel(
      name: "org.discourse.native/notification_opens",
      binaryMessenger: messenger
    )
    notificationOpenChannel.setStreamHandler(self)
    self.notificationOpenChannel = notificationOpenChannel
  }

  func didRegister(_ deviceToken: Data) {
    finish(with: pushTokenHex(deviceToken))
  }

  func didFailToRegister() {
    finish(with: nil)
  }

  func didOpen(_ response: UNNotificationResponse) {
    guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
      let url = discourseUrl(in: response.notification.request.content.userInfo)
    else {
      return
    }

    let identifier = response.notification.request.identifier
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if !identifier.isEmpty {
        guard !self.handledResponseIdentifiers.contains(identifier) else {
          return
        }
        self.handledResponseIdentifiers.append(identifier)
        if self.handledResponseIdentifiers.count > 32 {
          self.handledResponseIdentifiers.removeFirst()
        }
      }
      self.emitNotificationUrl(url)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.notificationOpenSink = events
      let pending = self.pendingNotificationUrls
      self.pendingNotificationUrls.removeAll()
      pending.forEach { events($0) }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    DispatchQueue.main.async { [weak self] in
      self?.notificationOpenSink = nil
    }
    return nil
  }

  private func registrationToken(_ result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(nil)
        return
      }
      if let token = self.token {
        result(token)
        return
      }

      self.pendingResults.append(result)
      guard !self.registrationInProgress else { return }
      self.registrationInProgress = true

      let timeout = DispatchWorkItem { [weak self] in
        guard let self, self.registrationInProgress else { return }
        self.finish(with: nil)
      }
      self.registrationTimeoutWorkItem = timeout
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.registrationTimeout,
        execute: timeout
      )

      UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .badge, .sound]
      ) { granted, error in
        DispatchQueue.main.async {
          guard granted, error == nil else {
            self.finish(with: nil)
            return
          }
          NSApplication.shared.registerForRemoteNotifications()
        }
      }
    }
  }

  private func finish(with token: String?) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard self.registrationInProgress else {
        // A successful APNs reply which arrives just after the timeout is still
        // useful for the next caller. A late failure must not erase a token.
        if let token { self.token = token }
        return
      }
      self.registrationTimeoutWorkItem?.cancel()
      self.registrationTimeoutWorkItem = nil
      self.token = token
      self.registrationInProgress = false
      let results = self.pendingResults
      self.pendingResults.removeAll()
      results.forEach { $0(token) }
    }
  }

  private func emitNotificationUrl(_ url: String) {
    if let notificationOpenSink {
      notificationOpenSink(url)
      return
    }
    pendingNotificationUrls.append(url)
    if pendingNotificationUrls.count > 16 {
      pendingNotificationUrls.removeFirst()
    }
  }
}
