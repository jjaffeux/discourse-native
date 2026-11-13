import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_video_handle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

final class FakeVoiceMediaFactory implements VoiceMediaFactory {
  final List<FakeVoiceMediaSession> sessions = [];

  Completer<void>? nextConnectGate;
  Completer<void>? nextConnectStarted;
  Completer<void>? nextMuteGate;
  Completer<void>? nextMuteStarted;
  Object? nextAudioInputFailure;
  Object? nextAudioOutputFailure;
  Future<void> Function(String)? nextAudioInputSelection;
  Future<void> Function(String)? nextAudioOutputSelection;
  Object? nextCameraFailure;

  @override
  VoiceMediaSession create({
    required VoiceJoinResponse join,
    required int localUserId,
    required VoiceSignalSender sendSignal,
    required VoiceLiveKitCredentialRefresher refreshLiveKitCredentials,
  }) {
    final session =
        FakeVoiceMediaSession(
            join.transport,
            sendSignal: sendSignal,
            refreshLiveKitCredentials: refreshLiveKitCredentials,
            connectGate: nextConnectGate,
            connectStarted: nextConnectStarted,
          )
          ..muteGate = nextMuteGate
          ..muteStarted = nextMuteStarted
          ..audioInputFailure = nextAudioInputFailure
          ..audioOutputFailure = nextAudioOutputFailure
          ..onSelectAudioInput = nextAudioInputSelection
          ..onSelectAudioOutput = nextAudioOutputSelection
          ..cameraFailure = nextCameraFailure;
    nextConnectGate = null;
    nextConnectStarted = null;
    nextMuteGate = null;
    nextMuteStarted = null;
    nextAudioInputFailure = null;
    nextAudioOutputFailure = null;
    nextAudioInputSelection = null;
    nextAudioOutputSelection = null;
    nextCameraFailure = null;

    sessions.add(session);
    return session;
  }
}

final class FakeVoiceMediaSession extends ChangeNotifier
    implements VoiceMediaSession {
  FakeVoiceMediaSession(
    this.transport, {
    required this.sendSignal,
    required this.refreshLiveKitCredentials,
    this.connectGate,
    this.connectStarted,
  });

  @override
  final VoiceTransport transport;
  final VoiceSignalSender sendSignal;
  final VoiceLiveKitCredentialRefresher refreshLiveKitCredentials;
  final Completer<void>? connectGate;
  final Completer<void>? connectStarted;

  @override
  VoiceMediaConnectionState connectionState =
      VoiceMediaConnectionState.connected;
  @override
  Object? connectionFailure;
  int disposeCount = 0;
  bool muted = false;
  bool deafened = false;
  bool camera = false;
  bool screen = false;
  bool audioPublishingAllowed = true;
  Object? signalFailure;
  Future<void> Function()? onHandleSignal;
  Future<void> Function()? onSyncParticipants;
  Object? audioPublishingFailure;
  Object? muteFailure;
  Future<void> Function(bool)? onSetMuted;
  Future<void> Function(bool)? onSetDeafened;
  Future<void> Function(bool)? onSetScreenSharing;
  Object? participantSyncFailure;
  Object? disposeFailure;
  Completer<void>? disposeStarted;
  Completer<void>? disposeGate;
  Object? audioInputFailure;
  Object? audioOutputFailure;
  Future<void> Function(String)? onSelectAudioInput;
  Future<void> Function(String)? onSelectAudioOutput;
  final List<String> audioInputSelections = [];
  final List<String> audioOutputSelections = [];
  Object? cameraFailure;
  Future<void> Function(bool)? onSetCamera;
  void Function(bool)? afterSetCamera;
  final List<bool> cameraRequests = [];
  Completer<void>? muteGate;
  Completer<void>? muteStarted;
  Completer<void>? audioPublishingGate;
  String? selectedAudioInput;
  String? selectedAudioOutput;
  String? selectedCamera;
  final Map<int, double> participantVolumes = {};
  List<VoiceParticipant> participants = const [];
  final List<(int, Map<String, dynamic>)> signals = [];

  @override
  VoiceVideoHandle? localVideoTrack;

  @override
  bool get screenSharing => screen;

  Set<int> speaking = const {};

  @override
  Set<int> get speakingParticipantIds => speaking;

  @override
  VoiceVideoHandle? videoTrackFor(int participantId) => null;

  @override
  Future<void> connect() async {
    if (connectStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await connectGate?.future;
  }

  @override
  Future<List<rtc.MediaDeviceInfo>> devices() async => const [];

  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {
    signals.add((senderId, data));
    await onHandleSignal?.call();
    if (signalFailure case final failure?) throw failure;
  }

  @override
  Future<void> selectAudioOutput(String deviceId) async {
    audioOutputSelections.add(deviceId);
    await onSelectAudioOutput?.call(deviceId);
    if (audioOutputFailure case final failure?) throw failure;
    selectedAudioOutput = deviceId;
  }

  @override
  Future<void> selectAudioInput(String deviceId) async {
    audioInputSelections.add(deviceId);
    await onSelectAudioInput?.call(deviceId);
    if (audioInputFailure case final failure?) throw failure;
    selectedAudioInput = deviceId;
  }

  @override
  Future<void> setAudioPublishingAllowed(bool allowed) async {
    audioPublishingAllowed = allowed;
    await audioPublishingGate?.future;
    if (audioPublishingFailure case final failure?) throw failure;
  }

  @override
  VoiceCameraFacing cameraFacing = VoiceCameraFacing.front;

  @override
  Future<void> setCameraEnabled(
    bool enabled, {
    String? deviceId,
    VoiceCameraFacing? facing,
    bool Function()? shouldContinue,
  }) async {
    cameraRequests.add(enabled);
    await onSetCamera?.call(enabled);
    if (cameraFailure case final failure?) throw failure;
    if (enabled && shouldContinue?.call() == false) return;
    camera = enabled;
    if (enabled && facing != null) cameraFacing = facing;
    afterSetCamera?.call(enabled);
    if (deviceId != null) selectedCamera = deviceId;
  }

  @override
  Future<void> setDeafened(bool enabled) async {
    if (onSetDeafened case final update?) await update(enabled);
    deafened = enabled;
  }

  @override
  Future<void> setMuted(bool enabled) async {
    if (onSetMuted case final update?) await update(enabled);
    muted = enabled;
    if (muteStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await muteGate?.future;
    if (muteFailure case final failure?) throw failure;
  }

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {
    participantVolumes[participantId] = volume;
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    if (onSetScreenSharing case final update?) await update(enabled);
    screen = enabled;
  }

  @override
  Future<void> syncParticipants(List<VoiceParticipant> value) async {
    participants = value;
    await onSyncParticipants?.call();
    if (participantSyncFailure case final failure?) throw failure;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    disposeStarted?.complete();
    await disposeGate?.future;
    if (disposeFailure case final failure?) throw failure;
    super.dispose();
  }
}

final class FakeVoicePreferences implements VoicePreferences {
  VoiceDevicePreferences devices = const VoiceDevicePreferences();
  bool rejectWrites = false;
  bool rejectVolumeReads = false;
  Completer<void>? deviceWriteStarted;
  Completer<void>? deviceWriteGate;
  final List<String> writes = [];
  final Map<(String, int, int), double> volumes = {};
  final Map<(String, int), bool> cameraEnabled = {};
  Future<bool> Function(String, int)? onReadCamera;
  Future<void> Function(int userId)? onReadVolume;
  Future<void> Function(bool)? onWriteCamera;
  Future<VoiceDevicePreferences> Function()? onReadDevices;
  Future<bool?> Function()? onReadAutoStatus;
  Future<void> Function(VoiceDevicePreference, String)? onWriteDevice;
  Future<void> Function(bool)? onWritePushToTalk;

  @override
  Future<bool> readCameraEnabled(String siteUrl, int userId) async =>
      onReadCamera != null
      ? await onReadCamera!(siteUrl, userId)
      : cameraEnabled[(siteUrl, userId)] ?? false;

  @override
  Future<void> writeCameraEnabled(
    String siteUrl,
    int userId,
    bool enabled,
  ) async {
    await onWriteCamera?.call(enabled);
    if (rejectWrites) throw StateError('camera preference write rejected');
    cameraEnabled[(siteUrl, userId)] = enabled;
  }

  @override
  Future<VoiceDevicePreferences> readDevices() async =>
      onReadDevices == null ? devices : await onReadDevices!();

  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async {
    if (rejectVolumeReads) throw StateError('volume storage unavailable');
    // Storage answers with what it held when the read was queued, so a write
    // made while [onReadVolume] holds the read is not seen by it.
    final saved = volumes[(siteUrl, roomId, userId)];
    await onReadVolume?.call(userId);
    return saved;
  }

  @override
  Future<void> writeDevice(
    VoiceDevicePreference preference,
    String value,
  ) async {
    writes.add('device:${preference.name}:$value');
    await onWriteDevice?.call(preference, value);
    deviceWriteStarted?.complete();
    await deviceWriteGate?.future;
    if (rejectWrites) throw StateError('device write rejected');
  }

  @override
  Future<void> writeParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
    double volume,
  ) async {
    writes.add('volume:$userId:$volume');
    if (rejectWrites) throw StateError('volume write rejected');
    volumes[(siteUrl, roomId, userId)] = volume;
  }

  @override
  Future<void> writePushToTalk(bool enabled) async {
    writes.add('pushToTalk:$enabled');
    await onWritePushToTalk?.call(enabled);
    if (rejectWrites) throw StateError('push-to-talk write rejected');
  }

  bool meshPrivacyAcknowledged = false;
  Completer<void>? meshPrivacyReadStarted;
  Completer<void>? meshPrivacyReadGate;
  bool? autoStatusEnabled;

  @override
  Future<bool> readMeshPrivacyAcknowledged() async {
    meshPrivacyReadStarted?.complete();
    await meshPrivacyReadGate?.future;
    return meshPrivacyAcknowledged;
  }

  @override
  Future<void> writeMeshPrivacyAcknowledged(bool acknowledged) async {
    writes.add('meshPrivacy:$acknowledged');
    if (rejectWrites) throw StateError('privacy write rejected');
    meshPrivacyAcknowledged = acknowledged;
  }

  @override
  Future<bool?> readAutoStatusEnabled() async =>
      onReadAutoStatus == null ? autoStatusEnabled : await onReadAutoStatus!();

  @override
  Future<void> writeAutoStatusEnabled(bool enabled) async {
    writes.add('autoStatus:$enabled');
    if (rejectWrites) throw StateError('status write rejected');
    autoStatusEnabled = enabled;
  }
}

class FakeVoiceSystemCall implements VoiceSystemCall {
  final StreamController<VoiceSystemCallAction> controller =
      StreamController.broadcast();
  int starts = 0;
  int connectedCalls = 0;
  int ends = 0;
  bool? systemMuted;
  Object? endFailure;
  Completer<void>? endStarted;
  Completer<void>? endGate;
  Completer<void>? disposeStarted;
  Completer<void>? disposeGate;
  Object? disposeFailure;
  int disposeCount = 0;

  @override
  Stream<VoiceSystemCallAction> get actions => controller.stream;

  void send(VoiceSystemCallAction action) => controller.add(action);

  @override
  Future<void> connected() async => connectedCalls++;

  @override
  Future<void> dispose() async {
    disposeCount++;
    disposeStarted?.complete();
    await disposeGate?.future;
    await controller.close();
    if (disposeFailure case final failure?) throw failure;
  }

  @override
  Future<void> end() async {
    ends++;
    endStarted?.complete();
    await endGate?.future;
    if (endFailure case final failure?) throw failure;
  }

  @override
  Future<void> failed() async {
    failures++;
  }

  @override
  Future<void> setMuted(bool muted) async => systemMuted = muted;

  @override
  Future<void> start({
    required String roomName,
    required String siteName,
  }) async {
    starts++;
  }

  int failures = 0;
  bool presentsIncomingCalls = false;
  Object? reportIncomingFailure;
  Completer<void>? reportIncomingGate;
  final List<({String callerName, String roomName, String handle})>
  reportedIncomingCalls = [];
  int incomingAnswers = 0;
  Completer<void>? incomingAnswerGate;
  int incomingDeclines = 0;
  final List<VoiceIncomingCallEndReason> incomingEnds = [];

  @override
  Future<bool> reportIncomingCall({
    required String callerName,
    required String roomName,
    required String handle,
  }) async {
    reportedIncomingCalls.add((
      callerName: callerName,
      roomName: roomName,
      handle: handle,
    ));
    await reportIncomingGate?.future;
    if (reportIncomingFailure case final failure?) throw failure;
    return presentsIncomingCalls;
  }

  @override
  Future<void> answerIncomingCall() async {
    incomingAnswers++;
    await incomingAnswerGate?.future;
  }

  @override
  Future<void> declineIncomingCall() async => incomingDeclines++;

  @override
  Future<void> endIncomingCall(VoiceIncomingCallEndReason reason) async {
    incomingEnds.add(reason);
  }
}
