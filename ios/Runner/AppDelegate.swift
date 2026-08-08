import Flutter
import CallKit
import AVFoundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var resenhaCallKit: ResenhaCallKitCoordinator?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ResenhaCallKit") {
      resenhaCallKit = ResenhaCallKitCoordinator(messenger: registrar.messenger())
    }
  }
}

private final class ResenhaCallKitCoordinator: NSObject, CXProviderDelegate {
  private let provider: CXProvider
  private let controller = CXCallController()
  private let channel: FlutterMethodChannel
  private var activeCall: UUID?
  private var muted = false

  init(messenger: FlutterBinaryMessenger) {
    let configuration = CXProviderConfiguration(localizedName: "Discourse")
    configuration.supportsVideo = true
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    configuration.supportedHandleTypes = [.generic]
    provider = CXProvider(configuration: configuration)
    channel = FlutterMethodChannel(
      name: "org.discourse.native/resenha_callkit",
      binaryMessenger: messenger
    )
    super.init()
    provider.setDelegate(self, queue: nil)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      let arguments = call.arguments as? [String: Any]
      let roomName = arguments?["roomName"] as? String ?? "Voice room"
      let uuid = UUID()
      activeCall = uuid
      muted = false
      let action = CXStartCallAction(
        call: uuid,
        handle: CXHandle(type: .generic, value: roomName)
      )
      action.isVideo = false
      request(action, result: result)
    case "connected":
      if let uuid = activeCall {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
      }
      result(nil)
    case "failed":
      end(reason: .failed)
      result(nil)
    case "setMuted":
      guard let uuid = activeCall,
            let arguments = call.arguments as? [String: Any],
            let requested = arguments["muted"] as? Bool else {
        result(nil)
        return
      }
      if requested == muted {
        result(nil)
      } else {
        request(CXSetMutedCallAction(call: uuid, muted: requested), result: result)
      }
    case "end":
      guard let uuid = activeCall else {
        result(nil)
        return
      }
      request(CXEndCallAction(call: uuid), result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func request(_ action: CXAction, result: @escaping FlutterResult) {
    controller.request(CXTransaction(action: action)) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "callkit_transaction",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private func end(reason: CXCallEndedReason) {
    guard let uuid = activeCall else { return }
    provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    activeCall = nil
    muted = false
  }

  func providerDidReset(_ provider: CXProvider) {
    activeCall = nil
    muted = false
    channel.invokeMethod("end", arguments: nil)
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    muted = action.isMuted
    channel.invokeMethod(action.isMuted ? "mute" : "unmute", arguments: nil)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    activeCall = nil
    muted = false
    channel.invokeMethod("end", arguments: nil)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    channel.invokeMethod("audioActivated", arguments: nil)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    channel.invokeMethod("audioDeactivated", arguments: nil)
  }
}
