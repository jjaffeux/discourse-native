import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pushNotifications = IOSPushNotifications()
  private var materialAccessibilityChannel: FlutterMethodChannel?
  private var materialAccessibilityObserver: NSObjectProtocol?
  private var keyboardChannel: FlutterMethodChannel?
  private var keyboardObservers: [NSObjectProtocol] = []
  private var keyboardReady = false
  private let videoThumbnails = VideoThumbnailChannel()
  private let pdfThumbnails = PdfThumbnailChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeKeyboardTransitions") {
      let channel = FlutterMethodChannel(
        name: "org.discourse.native/keyboard", binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "keyboardReady" { result(self?.keyboardReady ?? false) }
        else { result(FlutterMethodNotImplemented) }
      }
      keyboardChannel = channel
      for (notification, ready) in [
        (UIResponder.keyboardWillShowNotification, false),
        (UIResponder.keyboardDidShowNotification, true),
        (UIResponder.keyboardDidHideNotification, false),
      ] {
        keyboardObservers.append(NotificationCenter.default.addObserver(
          forName: notification, object: nil, queue: .main
        ) { [weak self] _ in
          self?.keyboardReady = ready
          channel.invokeMethod("keyboardReady", arguments: ready)
        })
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeMaterialAccessibility") {
      let channel = FlutterMethodChannel(name: "org.discourse.native/material_accessibility", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "reduceTransparency" { result(UIAccessibility.isReduceTransparencyEnabled) }
        else { result(FlutterMethodNotImplemented) }
      }
      materialAccessibilityChannel = channel
      materialAccessibilityObserver = NotificationCenter.default.addObserver(
        forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
        object: nil, queue: .main
      ) { _ in channel.invokeMethod("reduceTransparencyChanged", arguments: UIAccessibility.isReduceTransparencyEnabled) }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NativeVideoThumbnails"
    ) {
      videoThumbnails.attach(to: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativePdfThumbnails") {
      pdfThumbnails.attach(to: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NativePushRegistration"
    ) {
      pushNotifications.attach(to: registrar.messenger())
    }
  }

  deinit {
    if let materialAccessibilityObserver { NotificationCenter.default.removeObserver(materialAccessibilityObserver) }
    for observer in keyboardObservers { NotificationCenter.default.removeObserver(observer) }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
    pushNotifications.didRegister(deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
    pushNotifications.didFailToRegister()
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    handleNotificationResponse(response)
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  func handleNotificationResponse(_ response: UNNotificationResponse) {
    pushNotifications.didOpen(response)
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

final class IOSPushNotifications: NSObject, FlutterStreamHandler {
  private var registrationChannel: FlutterMethodChannel?
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
    registerForRemoteNotifications: {
      UIApplication.shared.registerForRemoteNotifications()
    }
  )

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
      guard let self else {
        result(nil)
        return
      }
      self.registrationToken(result)
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

  private func registrationToken(_ result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(nil)
        return
      }
      self.registration.registrationToken { result($0) }
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
