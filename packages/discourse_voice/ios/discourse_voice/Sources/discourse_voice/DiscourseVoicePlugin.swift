import AVFoundation
import CallKit
import Flutter

/// The sole iOS registration point for Voice.
///
/// Core runners know nothing about this channel. Flutter invokes this class
/// only when `discourse_voice` is present in the application's package
/// graph, and the registrar retains the instance for the engine lifetime.
public final class DiscourseVoicePlugin: NSObject, FlutterPlugin {
  private let coordinator: VoiceCallKitCoordinator

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = DiscourseVoicePlugin(messenger: registrar.messenger())
    registrar.publish(plugin)
  }

  private init(messenger: FlutterBinaryMessenger) {
    coordinator = VoiceCallKitCoordinator(messenger: messenger)
    super.init()
  }
}

final class VoiceCallKitCoordinator: NSObject, CXProviderDelegate {
  typealias TransactionRequester = (CXAction, @escaping (Error?) -> Void) -> Void
  typealias IncomingCallReporter = (UUID, CXCallUpdate, @escaping (Error?) -> Void) -> Void

  private let requestTransaction: TransactionRequester
  private let reportIncomingCall: IncomingCallReporter
  private let reportOutgoingCallStarted: (UUID) -> Void
  private let reportOutgoingCallConnected: (UUID) -> Void
  private let reportCallEnded: (UUID, CXCallEndedReason) -> Void
  private let emitMethod: (String) -> Void
  private let emitDiagnosticEvent: (String, [String: Any]) -> Void
  private let configureAudioSession: () throws -> Void
  private var activeCall: UUID?
  /// The call CallKit is ringing (or has answered) for this user. Dart's
  /// `start` reuses it instead of placing a second, outgoing call, and
  /// `connected` must not report it as an outgoing call that connected.
  private var incomingCall: UUID?
  private var incomingAnswered = false
  /// Set when Dart answered from its own UI: CallKit's answer action then
  /// confirms a choice Dart already acted on, and must not be echoed back.
  private var answerRequestedLocally = false
  private var muted = false
  private var pendingEndResults: [UUID: [FlutterResult]] = [:]

  convenience init(messenger: FlutterBinaryMessenger) {
    let configuration = CXProviderConfiguration(localizedName: "Discourse")
    configuration.supportsVideo = true
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    configuration.supportedHandleTypes = [.generic]
    let provider = CXProvider(configuration: configuration)
    let controller = CXCallController()
    let channel = FlutterMethodChannel(
      name: "org.discourse.native/voice_callkit",
      binaryMessenger: messenger
    )

    self.init(
      requestTransaction: { action, completion in
        controller.request(CXTransaction(action: action), completion: completion)
      },
      reportIncomingCall: { uuid, update, completion in
        provider.reportNewIncomingCall(with: uuid, update: update, completion: completion)
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
        channel.invokeMethod("diagnostic", arguments: arguments)
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
    reportIncomingCall: @escaping IncomingCallReporter = { _, _, completion in completion(nil) },
    reportOutgoingCallStarted: @escaping (UUID) -> Void = { _ in },
    reportOutgoingCallConnected: @escaping (UUID) -> Void = { _ in },
    reportCallEnded: @escaping (UUID, CXCallEndedReason) -> Void = { _, _ in },
    emitMethod: @escaping (String) -> Void = { _ in },
    emitDiagnosticEvent: @escaping (String, [String: Any]) -> Void = { _, _ in },
    configureAudioSession: @escaping () throws -> Void = {}
  ) {
    self.requestTransaction = requestTransaction
    self.reportIncomingCall = reportIncomingCall
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
      // Joining the call CallKit is already ringing (or has answered):
      // the system call exists, so there is nothing to place.
      if let uuid = incomingCall {
        activeCall = uuid
        muted = false
        emitDiagnostic("callkit.start.reused_incoming")
        result(nil)
        return
      }
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
        if uuid == incomingCall {
          // An answered incoming call is connected from CallKit's point of
          // view once its answer action was fulfilled.
          emitDiagnostic("callkit.connected.skipped", data: ["reason": "incoming_call"])
        } else {
          reportOutgoingCallConnected(uuid)
          emitDiagnostic("callkit.connected.reported")
        }
      } else {
        emitDiagnostic(
          "callkit.connected.skipped",
          data: ["reason": "no_active_call"]
        )
      }
      result(nil)
    case "reportIncomingCall":
      handleReportIncomingCall(call.arguments as? [String: Any], result: result)
    case "answerIncomingCall":
      guard let uuid = incomingCall, !incomingAnswered else {
        emitDiagnostic(
          "callkit.answer.skipped",
          data: ["reason": incomingCall == nil ? "no_incoming_call" : "already_in_state"]
        )
        result(nil)
        return
      }
      answerRequestedLocally = true
      request(CXAnswerCallAction(call: uuid), result: result)
    case "declineIncomingCall":
      guard let uuid = incomingCall, !incomingAnswered else {
        emitDiagnostic(
          "callkit.decline.skipped",
          data: ["reason": incomingCall == nil ? "no_incoming_call" : "already_in_state"]
        )
        result(nil)
        return
      }
      requestEnd(call: uuid, result: result)
    case "endIncomingCall":
      guard let uuid = incomingCall, !incomingAnswered else {
        emitDiagnostic(
          "callkit.incoming_end.skipped",
          data: ["reason": incomingCall == nil ? "no_incoming_call" : "already_in_state"]
        )
        result(nil)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let reason = arguments?["reason"] as? String ?? "unanswered"
      let ended: CXCallEndedReason = reason == "answered_elsewhere" ? .answeredElsewhere : .unanswered
      reportCallEnded(uuid, ended)
      clearIncomingCall()
      if activeCall == uuid {
        activeCall = nil
        muted = false
      }
      emitDiagnostic("callkit.incoming_end.reported", data: ["reason": reason])
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
        emitDiagnostic(
          "callkit.end.skipped",
          data: ["reason": "no_active_call"]
        )
        result(nil)
        return
      }
      requestEnd(call: uuid, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Rings the user through the system: the phone rings with the system
  /// ringtone, on the lock screen too, and the answer arrives as a provider
  /// action. Answers `false` when the system would not present it (a call
  /// already up, Do Not Disturb filtering, CallKit unavailable) so Dart
  /// can fall back to its own banner.
  private func handleReportIncomingCall(
    _ arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard incomingCall == nil, activeCall == nil else {
      emitDiagnostic(
        "callkit.incoming.skipped",
        data: ["reason": incomingCall == nil ? "call_active" : "already_ringing"]
      )
      result(false)
      return
    }
    let callerName = arguments?["callerName"] as? String ?? "Voice call"
    let handle = arguments?["handle"] as? String ?? callerName
    let uuid = UUID()
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: handle)
    update.localizedCallerName = callerName
    update.hasVideo = false
    update.supportsDTMF = false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    incomingCall = uuid
    incomingAnswered = false
    answerRequestedLocally = false
    emitDiagnostic("callkit.incoming.requested")
    reportIncomingCall(uuid, update) { error in
      DispatchQueue.main.async {
        if let error {
          if self.incomingCall == uuid {
            self.clearIncomingCall()
          }
          self.emitDiagnostic("callkit.incoming.failed", data: self.errorData(error))
          result(false)
        } else {
          self.emitDiagnostic("callkit.incoming.presented")
          result(true)
        }
      }
    }
  }

  private func clearIncomingCall() {
    incomingCall = nil
    incomingAnswered = false
    answerRequestedLocally = false
  }

  private func request(_ action: CXAction, result: @escaping FlutterResult) {
    let actionName = diagnosticName(for: action)
    emitDiagnostic("callkit.transaction.requested", data: ["action": actionName])
    requestTransaction(action) { error in
      DispatchQueue.main.async {
        if let error {
          if let startAction = action as? CXStartCallAction,
            self.activeCall == startAction.callUUID
          {
            self.activeCall = nil
            self.muted = false
          }
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

  private func requestEnd(call uuid: UUID, result: @escaping FlutterResult) {
    if pendingEndResults[uuid] != nil {
      pendingEndResults[uuid, default: []].append(result)
      emitDiagnostic("callkit.transaction.coalesced", data: ["action": "end"])
      return
    }

    pendingEndResults[uuid] = [result]
    let action = CXEndCallAction(call: uuid)
    emitDiagnostic("callkit.transaction.requested", data: ["action": "end"])
    requestTransaction(action) { error in
      DispatchQueue.main.async {
        if let error {
          let failureData: [String: Any] = ["action": "end"]
          self.emitDiagnostic(
            "callkit.transaction.failed",
            data: failureData.merging(self.errorData(error)) { _, new in new }
          )
          self.completePendingEnd(
            call: uuid,
            result: FlutterError(
              code: "callkit_transaction",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          // The Dart future deliberately remains pending until CallKit invokes
          // handleEndAction. Transaction acceptance alone is not teardown.
          self.emitDiagnostic(
            "callkit.transaction.accepted",
            data: ["action": "end"]
          )
        }
      }
    }
  }

  private func completePendingEnd(call uuid: UUID, result: Any?) {
    let completions = pendingEndResults.removeValue(forKey: uuid) ?? []
    for completion in completions {
      completion(result)
    }
  }

  private func completeAllPendingEnds() {
    let pending = pendingEndResults
    pendingEndResults.removeAll()
    for completions in pending.values {
      for completion in completions {
        completion(nil)
      }
    }
  }

  private func end(reason: CXCallEndedReason) {
    guard let uuid = activeCall else { return }
    reportCallEnded(uuid, reason)
    activeCall = nil
    muted = false
    if incomingCall == uuid {
      clearIncomingCall()
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    handleProviderReset()
  }

  func handleProviderReset() {
    let unansweredIncoming = incomingCall != nil && !incomingAnswered
    activeCall = nil
    muted = false
    clearIncomingCall()
    completeAllPendingEnds()
    emitDiagnostic("callkit.provider.reset")
    emitMethod(unansweredIncoming ? "decline" : "end")
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    handleAnswerAction(action)
  }

  func handleAnswerAction(_ action: CXAnswerCallAction) {
    guard incomingCall == action.callUUID, !incomingAnswered else {
      action.fail()
      emitDiagnostic(
        "callkit.provider.answer.skipped",
        data: ["reason": incomingCall == action.callUUID ? "already_in_state" : "stale_call"]
      )
      return
    }
    do {
      try configureAudioSession()
      incomingAnswered = true
      activeCall = action.callUUID
      muted = false
      action.fulfill()
      emitDiagnostic("callkit.provider.answer.fulfilled")
      if answerRequestedLocally {
        // Dart is already joining; telling it again would join twice.
        answerRequestedLocally = false
      } else {
        emitMethod("answer")
      }
    } catch {
      clearIncomingCall()
      if activeCall == action.callUUID {
        activeCall = nil
        muted = false
      }
      action.fail()
      emitDiagnostic("callkit.provider.answer.failed", data: errorData(error))
      emitMethod("decline")
    }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    handleStartAction(action)
  }

  func handleStartAction(_ action: CXStartCallAction) {
    guard activeCall == action.callUUID else {
      action.fail()
      emitDiagnostic(
        "callkit.provider.start.skipped",
        data: ["reason": "stale_call"]
      )
      return
    }
    do {
      try configureAudioSession()
      reportOutgoingCallStarted(action.callUUID)
      action.fulfill()
      emitDiagnostic("callkit.provider.start.fulfilled")
    } catch {
      if activeCall == action.callUUID {
        activeCall = nil
        muted = false
        emitMethod("end")
      }
      action.fail()
      emitDiagnostic("callkit.provider.start.failed", data: errorData(error))
    }
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    handleSetMutedAction(action)
  }

  func handleSetMutedAction(_ action: CXSetMutedCallAction) {
    guard activeCall == action.callUUID else {
      action.fail()
      emitDiagnostic(
        "callkit.provider.mute.skipped",
        data: ["reason": "stale_call"]
      )
      return
    }
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
    if incomingCall == action.callUUID, !incomingAnswered {
      // Ending a call that was never answered is declining it.
      clearIncomingCall()
      if activeCall == action.callUUID {
        activeCall = nil
        muted = false
      }
      emitMethod("decline")
      emitDiagnostic("callkit.provider.decline.fulfilled")
    } else if activeCall == action.callUUID {
      activeCall = nil
      muted = false
      if incomingCall == action.callUUID {
        clearIncomingCall()
      }
      emitMethod("end")
      emitDiagnostic("callkit.provider.end.fulfilled")
    } else {
      emitDiagnostic(
        "callkit.provider.end.skipped",
        data: ["reason": "stale_call"]
      )
    }
    action.fulfill()
    completePendingEnd(call: action.callUUID, result: nil)
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
    case is CXAnswerCallAction:
      return "answer"
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
