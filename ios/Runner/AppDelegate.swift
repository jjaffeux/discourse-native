import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pushNotifications = IOSPushNotifications()
  private var keyboardChannel: FlutterMethodChannel?
  private var keyboardObservers: [NSObjectProtocol] = []
  private var keyboardReady = false
  private var keyboardTransition: [String: Any]?
  private var keyboardTransitionStarted: CFTimeInterval = 0
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
        switch call.method {
        case "keyboardReady": result(self?.keyboardReady ?? false)
        case "keyboardTransition":
          var transition = self?.keyboardTransition
          if transition != nil, let self {
            transition?["elapsed"] = max(0, CACurrentMediaTime() - self.keyboardTransitionStarted)
          }
          result(transition)
        default: result(FlutterMethodNotImplemented)
        }
      }
      keyboardChannel = channel
      keyboardObservers.append(NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
      ) { [weak self, weak registrar] notification in
        guard let self, let view = registrar?.viewController?.viewIfLoaded,
          let transition = keyboardTransitionPayload(notification, in: view)
        else { return }
        self.keyboardTransitionStarted = CACurrentMediaTime()
        self.keyboardTransition = transition
        channel.invokeMethod("keyboardTransition", arguments: transition)
      })
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

// Keyboard frames arrive in screen coordinates; Flutter lays out in view points.
func keyboardTransitionPayload(_ notification: Notification, in view: UIView) -> [String: Any]? {
  guard let info = notification.userInfo,
    let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
    let screen = view.window?.screen
  else { return nil }
  if let source = notification.object as? UIScreen, source !== screen { return nil }
  let frame = view.convert(end.cgRectValue, from: screen.coordinateSpace)
  let overlap = view.bounds.intersection(frame)
  let docked = !overlap.isNull && frame.maxY >= view.bounds.maxY - 1
    && overlap.width >= view.bounds.width - 1
  let bottomInset: CGFloat = docked ? max(0, overlap.height) : 0
  let duration = max(0, (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0)
  let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? 0
  var payload: [String: Any] = [
    "frame": ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)],
    "bottomInset": Double(bottomInset),
    "duration": duration,
    "curve": curve,
    "elapsed": 0.0,
  ]
  // UIKit's keyboard curve can be a spring. Resolve its actual timing just as
  // Flutter's keyboard inset manager does, without guessing a curve for value 7.
  if duration > 0 {
    let timing = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    timing.isHidden = true
    view.addSubview(timing)
    UIView.animate(withDuration: duration, delay: 0,
      options: UIView.AnimationOptions(rawValue: UInt(curve) << 16)
    ) {
      timing.center.y += 1
      timing.layoutIfNeeded()
    }
    let animation = timing.layer.animation(forKey: "position")
    if let animation, animation.duration > 0 { payload["duration"] = animation.duration }
    if let spring = animation as? CASpringAnimation {
      payload["spring"] = [
        "mass": spring.mass, "stiffness": spring.stiffness,
        "damping": spring.damping, "velocity": spring.initialVelocity,
      ]
    } else if let function = animation?.timingFunction {
      var first = [Float](repeating: 0, count: 2)
      var second = [Float](repeating: 0, count: 2)
      function.getControlPoint(at: 1, values: &first)
      function.getControlPoint(at: 2, values: &second)
      payload["controlPoints"] = (first + second).map(Double.init)
    }
    timing.layer.removeAllAnimations()
    timing.removeFromSuperview()
  }
  return payload
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
