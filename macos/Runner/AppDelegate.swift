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

  override func application(_ application: NSApplication, open urls: [URL]) {
    urls.forEach { LinkOpens.shared.didOpen($0) }
    super.application(application, open: urls)
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

func setAppBadgeCount(_ count: Int) {
  NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
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

  private var registrationChannel: FlutterMethodChannel?
  private var badgeChannel: FlutterMethodChannel?
  private var notificationOpenChannel: FlutterEventChannel?
  private var notificationOpenSink: FlutterEventSink?
  private var pendingNotificationUrls: [String] = []
  private var handledResponseIdentifiers: [String] = []
  private let registration = PushRegistrationCoordinator(
    requestAuthorization: { completion in
      UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .badge, .sound]
      ) { granted, error in
        completion(granted && error == nil)
      }
    },
    authorizationGranted: { completion in
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        completion(
          settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        )
      }
    },
    registerForRemoteNotifications: {
      NSApplication.shared.registerForRemoteNotifications()
    }
  )

  private override init() {
    super.init()
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let registrationChannel = FlutterMethodChannel(
      name: "org.discourse.native/push_notifications",
      binaryMessenger: messenger
    )
    registrationChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "registrationToken" || call.method == "currentRegistrationToken"
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(nil)
        return
      }
      self.registrationToken(result, mayPrompt: call.method == "registrationToken")
    }
    self.registrationChannel = registrationChannel

    let badgeChannel = FlutterMethodChannel(
      name: "org.discourse.native/app_badge",
      binaryMessenger: messenger
    )
    badgeChannel.setMethodCallHandler { call, result in
      guard call.method == "setBadgeCount", let count = call.arguments as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        setAppBadgeCount(max(0, count))
        result(nil)
      }
    }
    self.badgeChannel = badgeChannel

    let notificationOpenChannel = FlutterEventChannel(
      name: "org.discourse.native/notification_opens",
      binaryMessenger: messenger
    )
    notificationOpenChannel.setStreamHandler(self)
    self.notificationOpenChannel = notificationOpenChannel
  }

  func didRegister(_ deviceToken: Data) {
    DispatchQueue.main.async { [weak self] in
      self?.registration.didRegister(pushTokenHex(deviceToken))
    }
  }

  func didFailToRegister() {
    DispatchQueue.main.async { [weak self] in
      self?.registration.didFailToRegister()
    }
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

  private func registrationToken(_ result: @escaping FlutterResult, mayPrompt: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(nil)
        return
      }
      if mayPrompt {
        self.registration.registrationToken { result($0) }
      } else {
        self.registration.currentToken { result($0) }
      }
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
