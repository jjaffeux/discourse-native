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
      emitDiagnostic("callkit.start.requested")
      request(action, result: result)
    case "connected":
      if let uuid = activeCall {
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
        emitDiagnostic("callkit.connected.reported")
      } else {
        emitDiagnostic("callkit.connected.skipped", data: ["reason": "no_active_call"])
      }
      result(nil)
    case "failed":
      emitDiagnostic("callkit.failed.reported")
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
        emitDiagnostic(
          "callkit.mute.skipped",
          data: ["reason": "already_in_state", "muted": requested]
        )
        result(nil)
      } else {
        request(CXSetMutedCallAction(call: uuid, muted: requested), result: result)
      }
    case "end":
      guard let uuid = activeCall else {
        emitDiagnostic("callkit.end.skipped", data: ["reason": "no_active_call"])
        result(nil)
        return
      }
      request(CXEndCallAction(call: uuid), result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func request(_ action: CXAction, result: @escaping FlutterResult) {
    let actionName = diagnosticName(for: action)
    emitDiagnostic("callkit.transaction.requested", data: ["action": actionName])
    controller.request(CXTransaction(action: action)) { error in
      DispatchQueue.main.async {
        if let error {
          let failureData: [String: Any] = ["action": actionName]
          self.emitDiagnostic(
            "callkit.transaction.failed",
            data: failureData.merging(self.errorData(error)) { _, new in new }
          )
          result(FlutterError(
            code: "callkit_transaction",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          self.emitDiagnostic(
            "callkit.transaction.accepted",
            data: ["action": actionName]
          )
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
    emitDiagnostic("callkit.provider.reset")
    channel.invokeMethod("end", arguments: nil)
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playAndRecord,
        mode: .videoChat,
        options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
      )
      provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
      action.fulfill()
      emitDiagnostic("callkit.provider.start.fulfilled")
    } catch {
      action.fail()
      emitDiagnostic(
        "callkit.provider.start.failed",
        data: errorData(error)
      )
    }
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    muted = action.isMuted
    channel.invokeMethod(action.isMuted ? "mute" : "unmute", arguments: nil)
    action.fulfill()
    emitDiagnostic(
      "callkit.provider.mute.fulfilled",
      data: ["muted": action.isMuted]
    )
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    activeCall = nil
    muted = false
    channel.invokeMethod("end", arguments: nil)
    action.fulfill()
    emitDiagnostic("callkit.provider.end.fulfilled")
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    emitDiagnostic("audio_session.activated")
    channel.invokeMethod("audioActivated", arguments: nil)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    emitDiagnostic("audio_session.deactivated")
    channel.invokeMethod("audioDeactivated", arguments: nil)
  }

  private func emitDiagnostic(_ event: String, data: [String: Any] = [:]) {
    channel.invokeMethod(
      "diagnostic",
      arguments: [
        "event": event,
        "component": "callkit",
        "data": data,
      ]
    )
  }

  private func diagnosticName(for action: CXAction) -> String {
    switch action {
    case is CXStartCallAction:
      return "start"
    case is CXSetMutedCallAction:
      return "mute"
    case is CXEndCallAction:
      return "end"
    default:
      return "unknown"
    }
  }

  private func errorData(_ error: Error) -> [String: Any] {
    let value = error as NSError
    return ["errorDomain": value.domain, "errorCode": value.code]
  }
}
