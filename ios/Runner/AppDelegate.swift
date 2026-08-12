import AVFoundation
import CallKit
import Flutter
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

final class ResenhaCallKitCoordinator: NSObject, CXProviderDelegate {
  typealias TransactionRequester = (CXAction, @escaping (Error?) -> Void) -> Void

  private let requestTransaction: TransactionRequester
  private let reportOutgoingCallStarted: (UUID) -> Void
  private let reportOutgoingCallConnected: (UUID) -> Void
  private let reportCallEnded: (UUID, CXCallEndedReason) -> Void
  private let emitMethod: (String) -> Void
  private let emitDiagnosticEvent: (String, [String: Any]) -> Void
  private let configureAudioSession: () throws -> Void
  private var activeCall: UUID?
  private var muted = false

  convenience init(messenger: FlutterBinaryMessenger) {
    let configuration = CXProviderConfiguration(localizedName: "Discourse")
    configuration.supportsVideo = true
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    configuration.supportedHandleTypes = [.generic]
    let provider = CXProvider(configuration: configuration)
    let controller = CXCallController()
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/resenha_callkit",
      binaryMessenger: messenger
    )

    self.init(
      requestTransaction: { action, completion in
        controller.request(CXTransaction(action: action), completion: completion)
      },
      reportOutgoingCallStarted: { uuid in
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
      },
      reportOutgoingCallConnected: { uuid in
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
      },
      reportCallEnded: { uuid, reason in
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
      },
      emitMethod: { method in
        channel.invokeMethod(method, arguments: nil)
      },
      emitDiagnosticEvent: { event, data in
        let arguments: [String: Any] = [
          "event": event,
          "component": "callkit",
          "data": data,
        ]
        channel.invokeMethod(
          "diagnostic",
          arguments: arguments
        )
      },
      configureAudioSession: {
        try AVAudioSession.sharedInstance().setCategory(
          .playAndRecord,
          mode: .videoChat,
          options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
        )
      }
    )

    provider.setDelegate(self, queue: nil)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  init(
    requestTransaction: @escaping TransactionRequester,
    reportOutgoingCallStarted: @escaping (UUID) -> Void = { _ in },
    reportOutgoingCallConnected: @escaping (UUID) -> Void = { _ in },
    reportCallEnded: @escaping (UUID, CXCallEndedReason) -> Void = { _, _ in },
    emitMethod: @escaping (String) -> Void = { _ in },
    emitDiagnosticEvent: @escaping (String, [String: Any]) -> Void = { _, _ in },
    configureAudioSession: @escaping () throws -> Void = {}
  ) {
    self.requestTransaction = requestTransaction
    self.reportOutgoingCallStarted = reportOutgoingCallStarted
    self.reportOutgoingCallConnected = reportOutgoingCallConnected
    self.reportCallEnded = reportCallEnded
    self.emitMethod = emitMethod
    self.emitDiagnosticEvent = emitDiagnosticEvent
    self.configureAudioSession = configureAudioSession
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
        reportOutgoingCallConnected(uuid)
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
        let requested = arguments["muted"] as? Bool
      else {
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
    requestTransaction(action) { error in
      DispatchQueue.main.async {
        if let error {
          let failureData: [String: Any] = ["action": actionName]
          self.emitDiagnostic(
            "callkit.transaction.failed",
            data: failureData.merging(self.errorData(error)) { _, new in new }
          )
          result(
            FlutterError(
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
    reportCallEnded(uuid, reason)
    activeCall = nil
    muted = false
  }

  func providerDidReset(_ provider: CXProvider) {
    handleProviderReset()
  }

  func handleProviderReset() {
    activeCall = nil
    muted = false
    emitDiagnostic("callkit.provider.reset")
    emitMethod("end")
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    handleStartAction(action)
  }

  func handleStartAction(_ action: CXStartCallAction) {
    do {
      try configureAudioSession()
      reportOutgoingCallStarted(action.callUUID)
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
    handleSetMutedAction(action)
  }

  func handleSetMutedAction(_ action: CXSetMutedCallAction) {
    muted = action.isMuted
    emitMethod(action.isMuted ? "mute" : "unmute")
    action.fulfill()
    emitDiagnostic(
      "callkit.provider.mute.fulfilled",
      data: ["muted": action.isMuted]
    )
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    handleEndAction(action)
  }

  func handleEndAction(_ action: CXEndCallAction) {
    activeCall = nil
    muted = false
    emitMethod("end")
    action.fulfill()
    emitDiagnostic("callkit.provider.end.fulfilled")
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    emitDiagnostic("audio_session.activated")
    emitMethod("audioActivated")
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    emitDiagnostic("audio_session.deactivated")
    emitMethod("audioDeactivated")
  }

  private func emitDiagnostic(_ event: String, data: [String: Any] = [:]) {
    emitDiagnosticEvent(event, data)
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
