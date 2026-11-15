import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let response = connectionOptions.notificationResponse,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    {
      appDelegate.handleNotificationResponse(response)
    }
    connectionOptions.urlContexts.forEach { LinkOpens.shared.didOpen($0.url) }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    URLContexts.forEach { LinkOpens.shared.didOpen($0.url) }
    super.scene(scene, openURLContexts: URLContexts)
  }
}

/// Hands `discourse://open` requests to Dart unparsed: Dart owns their
/// validation. Sign-in's `discourse://auth_redirect` never arrives here; its
/// web authentication session receives that callback in-process.
final class LinkOpens {
  static let shared = LinkOpens()

  private var channel: FlutterMethodChannel?
  private var listening = false
  private var pending: [String] = []

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/link_opens",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "listen" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
      DispatchQueue.main.async { self?.startDelivery() }
    }
    self.channel = channel
  }

  func didOpen(_ url: URL) {
    guard let request = linkOpenRequest(url) else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.listening, let channel = self.channel {
        channel.invokeMethod("open", arguments: request)
        return
      }
      // A request can launch the app before Dart is listening.
      self.pending.append(request)
      if self.pending.count > 16 { self.pending.removeFirst() }
    }
  }

  private func startDelivery() {
    listening = true
    let pending = self.pending
    self.pending.removeAll()
    pending.forEach { channel?.invokeMethod("open", arguments: $0) }
  }
}

func linkOpenRequest(_ url: URL) -> String? {
  guard url.scheme?.lowercased() == "discourse", url.host?.lowercased() == "open" else {
    return nil
  }
  let request = url.absoluteString
  return request.utf8.count <= 8192 ? request : nil
}
