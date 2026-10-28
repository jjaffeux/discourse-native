import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_test.dart'
    show PluginTestRequestHost, RecordingPluginLiveChannels;
import 'package:discourse_native/src/data/discourse_api.dart';

import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugins/chat/chat_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';

import 'package:discourse_native/src/plugins/voice/voice_idle.dart';
import 'package:discourse_native/src/plugins/voice/voice_incoming_calls.dart'
    show voiceAnswerConfirmationWindow;
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/plugins/voice/voice_video_handle.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'support/fake_voice_video_handle.dart';
import 'support/manual_scheduler.dart';
import 'support/voice_fake_chat_conversations.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

RecordingPluginLiveChannels tracker(String _) => RecordingPluginLiveChannels();

VoiceNamespace _beforeLiveRename(String _) => VoiceNamespace.voice;

Map<String, dynamic> renamedRoomEvent({
  String type = 'updated',
  int? messageBusLastId,
}) => {
  'type': type,
  'room': {
    'id': 7,
    'name': 'Renamed Room',
    'slug': 'conf-room-1',
    'public': false,
    'ephemeral': false,
    'room_type': 'stage',
    'message_bus_last_id': ?messageBusLastId,
    'active_participants': const <Object?>[],
  },
};

Map<String, dynamic> speakerRosterEvent(String username) => {
  'type': 'participants',
  'participants': [
    {'id': 2, 'username': username, 'role': 'speaker'},
  ],
};

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

abstract class _RequestHostBase implements PluginRequestHost {
  @override
  PluginSiteLease capture(String siteUrl) => const _CurrentSiteLease();

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    final credentials = await credentialsFor(siteUrl);
    return (
      credentials: credentials.apiKey == null
          ? null
          : PluginRequestCredentials(apiKey: credentials.apiKey, clientId: ''),
      failure: credentials.apiKey == null
          ? const WriteException(WriteFailure.forbidden)
          : null,
    );
  }
}

final class _StaticRequestHost extends _RequestHostBase {
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
}

final class _ScopedRequestHost extends _RequestHostBase {
  static final scope = Object();

  Future<T> _run<T>(String kind, Future<T> Function() request) =>
      runZoned(request, zoneValues: {scope: kind});

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      PluginRequestCredentials(
        apiKey: 'key',
        clientId: 'client',
        execute: <T>(request) => _run<T>('full', request),
      );

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async => (
    credentials: PluginRequestCredentials(
      apiKey: 'key',
      clientId: '',
      execute: <T>(request) => _run<T>('key', request),
    ),
    failure: null,
  );
}

final class _GatedRequestHost extends _RequestHostBase {
  _GatedRequestHost({required this.credentialsGate});

  final Completer<void> credentialsGate;

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    await credentialsGate.future;
    return const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
  }
}

final class _NextGatedRequestHost extends _RequestHostBase {
  bool gateNextRead = false;
  Completer<void> readStarted = Completer<void>();
  Completer<void> readGate = Completer<void>();

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    if (gateNextRead) {
      gateNextRead = false;
      if (!readStarted.isCompleted) readStarted.complete();
      await readGate.future;
    }
    return const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
  }
}

final class _DeferredRequestHost extends _RequestHostBase {
  bool deferNextRun = false;
  final runStarted = Completer<void>();
  final runGate = Completer<void>();

  Future<T> _run<T>(Future<T> Function() request) async {
    if (deferNextRun) {
      deferNextRun = false;
      runStarted.complete();
      await runGate.future;
    }
    return request();
  }

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      PluginRequestCredentials(
        apiKey: 'key',
        clientId: 'client',
        execute: _run,
      );

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async => (
    credentials: PluginRequestCredentials(
      apiKey: 'key',
      clientId: '',
      execute: _run,
    ),
    failure: null,
  );
}

final class _FailingRequestHost extends _RequestHostBase {
  Object? failure;

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    if (failure case final failure?) throw failure;
    return const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
  }
}

final class _CountingRequestHost extends _RequestHostBase {
  int credentialCalls = 0;

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async {
    credentialCalls++;
    return const PluginRequestCredentials(apiKey: 'key', clientId: 'client');
  }
}

final class _CurrentSiteLease implements PluginSiteLease {
  const _CurrentSiteLease();

  @override
  bool get isCurrent => true;

  @override
  bool commit(void Function() mutation) {
    mutation();
    return true;
  }
}

final class FakeVoiceSystemCall implements VoiceSystemCall {
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

/// The least forgiving mute bridge Dart can face: a request equal to the
/// state CallKit has committed is skipped, and any other is committed and
/// echoed back only when CallKit performs it, after the request has already
/// returned. A stale request that reaches it can overturn a newer choice.
final class _CallKitMuteSystemCall extends FakeVoiceSystemCall {
  bool committedMuted = false;

  @override
  Future<void> setMuted(bool muted) async {
    if (muted == committedMuted) return;
    Timer(Duration.zero, () {
      committedMuted = muted;
      if (controller.isClosed) return;
      send(muted ? VoiceSystemCallAction.mute : VoiceSystemCallAction.unmute);
    });
  }
}

final class _AwaitableVoiceSubscription
    implements
        PluginLiveChannelSubscription,
        VoiceAwaitableSubscriptionTeardown {
  _AwaitableVoiceSubscription(this._delegate, this._cancelAndWait);

  final PluginLiveChannelSubscription _delegate;
  final Future<void> Function() _cancelAndWait;
  Future<void>? _cancellation;

  @override
  void cancel() {
    unawaited(cancelAndWait());
  }

  @override
  Future<void> cancelAndWait() {
    final active = _cancellation;
    if (active != null) return active;
    _delegate.cancel();
    return _cancellation = _cancelAndWait();
  }
}

final class _AwaitableSubscriptionTracker extends RecordingPluginLiveChannels {
  final Completer<void> firstCancellationStarted = Completer<void>();
  final Completer<void> cancellationGate = Completer<void>();
  int cancellationsStarted = 0;

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) => _wrap(super.subscribe(channel, onMessage, lastId: lastId));

  PluginLiveChannelSubscription _wrap(
    PluginLiveChannelSubscription subscription,
  ) => _AwaitableVoiceSubscription(subscription, () async {
    cancellationsStarted++;
    if (!firstCancellationStarted.isCompleted) {
      firstCancellationStarted.complete();
    }
    await cancellationGate.future;
  });
}

/// Counts subscribe calls per channel. [RecordingPluginLiveChannels] shows
/// only the registrations that are live, which a cancel followed by a fresh
/// subscribe leaves unchanged.
final class _CountingTracker extends RecordingPluginLiveChannels {
  final Map<String, int> subscribeCounts = {};

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    subscribeCounts.update(channel, (count) => count + 1, ifAbsent: () => 1);
    return super.subscribe(channel, onMessage, lastId: lastId);
  }
}

final class _QueuedCallbackTracker extends RecordingPluginLiveChannels {
  final Map<String, void Function(Object?, int)> callbacks = {};

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    callbacks[channel] = onMessage;
    return super.subscribe(channel, onMessage, lastId: lastId);
  }
}

final class _PendingPluginGet {
  _PendingPluginGet(this.path);

  final String path;
  final Completer<Map<String, dynamic>> response = Completer();
}

final class _PendingPluginWrite {
  _PendingPluginWrite({required this.method, required this.path});

  final String method;
  final String path;
  final Completer<Map<String, dynamic>> response = Completer();
}

final class _ControlledVoiceTransport extends RecordingPluginTransport {
  _ControlledVoiceTransport({super.responses});

  final Set<String> heldPluginPaths = {};
  final Set<String> heldPluginWritePaths = {};
  final Map<String, SiteLookupException> pluginGetFailures = {};
  final List<String> pluginGets = [];
  final List<_PendingPluginGet> pendingPluginGets = [];
  final List<_PendingPluginWrite> pendingPluginWrites = [];
  final List<({int count, Completer<void> completer})> _writeWaiters = [];

  Object? operationFailure;

  Future<void> waitForPendingPluginWrites(int count) {
    if (pendingPluginWrites.length >= count) return Future<void>.value();
    final completer = Completer<void>();
    _writeWaiters.add((count: count, completer: completer));
    return completer.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () {
        _writeWaiters.removeWhere(
          (waiter) => identical(waiter.completer, completer),
        );
        throw TestFailure(
          'Expected $count pending plugin writes, but received '
          '${pendingPluginWrites.length}.',
        );
      },
    );
  }

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    pluginGets.add(path);
    if (operationFailure case final failure?) return Future.error(failure);
    if (pluginGetFailures[path] case final failure?) {
      return Future.error(failure);
    }
    if (!heldPluginPaths.contains(path)) {
      return super.pluginGetJson(
        siteUrl: siteUrl,
        path: path,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    final pending = _PendingPluginGet(path);
    pendingPluginGets.add(pending);
    return pending.response.future;
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) {
    if (operationFailure case final failure?) return Future.error(failure);
    if (!heldPluginWritePaths.contains(path)) {
      return super.pluginWriteJson(
        siteUrl: siteUrl,
        path: path,
        method: method,
        apiKey: apiKey,
        body: body,
        clientId: clientId,
      );
    }
    final pending = _PendingPluginWrite(method: method, path: path);
    pendingPluginWrites.add(pending);
    for (final waiter in _writeWaiters.toList()) {
      if (pendingPluginWrites.length < waiter.count) continue;
      _writeWaiters.remove(waiter);
      waiter.completer.complete();
    }
    return pending.response.future;
  }
}

Future<List<Object>> _captureUncaught(Future<void> Function() action) async {
  final uncaught = <Object>[];
  final operation = runZonedGuarded<Future<void>>(
    action,
    (error, _) => uncaught.add(error),
  );
  await operation;
  return uncaught;
}

ChatMessagePage _chatPage(int id, {bool canLoadMorePast = false}) => (
  messages: [
    ChatMessage(
      id: id,
      channelId: 42,
      cooked: '<p>message $id</p>',
      author: const ChatMessageAuthor(id: 1, username: 'sam'),
    ),
  ],
  canLoadMorePast: canLoadMorePast,
  canLoadMoreFuture: false,
  targetMessageId: null,
);

void main() {
  const firstSite = 'https://one.example.com';
  const secondSite = 'https://two.example.com';
  late RecordingPluginTransport transport;
  late PluginRequestHost requests;
  late FakeVoicePreferences preferences;
  late FakeVoiceMediaFactory mediaFactory;
  late FakeVoiceSystemCall systemCall;

  late RecordingPluginLiveChannels firstTracker;
  late RecordingPluginLiveChannels secondTracker;
  late FakeChatConversationCapability chatConversations;
  late VoiceController controller;

  FakeChatConversationCapability seededChatConversations({
    ChatConversationSnapshot? snapshotAfterSend,
  }) {
    final capability = FakeChatConversationCapability();
    capability.seed(
      siteUrl: firstSite,
      channelId: 42,
      threadId: 99,
      snapshot: ChatConversationSnapshot(
        messages: _chatPage(10).messages,
        canLoadMorePast: true,
      ),
      snapshotAfterLoadOlder: ChatConversationSnapshot(
        messages: [..._chatPage(5).messages, ..._chatPage(10).messages],
        canLoadMorePast: false,
      ),
      snapshotAfterSend: snapshotAfterSend,
    );
    return capability;
  }

  void useTransport(
    RecordingPluginTransport value, {
    VoiceCapabilityResolver? capabilityEnabledFor,
    VoiceTrackerLookup? trackerLookup,
    VoiceUserIdLookup? userIdFor,
    int Function(String)? videoMaxPublishersFor,
    FakeChatConversationCapability? conversations,
    Duration heartbeatInterval = const Duration(days: 1),
    FakeVoiceSystemCall? system,
    VoiceNamespace Function(String siteUrl) namespaceFor = _beforeLiveRename,
  }) {
    controller.dispose();
    transport = value;
    chatConversations = conversations ?? seededChatConversations();
    mediaFactory = FakeVoiceMediaFactory();
    systemCall = system ?? FakeVoiceSystemCall();
    controller = VoiceController(
      api: VoiceApi(transport, namespaceFor: namespaceFor),
      chatConversations: chatConversations,
      requests: requests,
      trackerFor:
          trackerLookup ??
          (siteUrl) => siteUrl == firstSite
              ? firstTracker
              : siteUrl == secondSite
              ? secondTracker
              : null,
      userIdFor: userIdFor ?? (_) => 1,
      videoMaxPublishersFor: videoMaxPublishersFor,
      capabilityEnabledFor: capabilityEnabledFor,
      onCallSiteChanged: () {},
      mediaFactory: mediaFactory,
      systemCall: systemCall,

      preferences: preferences,
      heartbeatInterval: heartbeatInterval,
      signalBatchDelay: Duration.zero,
    );
  }

  setUp(() {
    final joinPayload = fixture('join_mesh');
    (joinPayload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
    transport = RecordingPluginTransport(
      responses: {
        'GET /voice/rooms.json': fixture('directory'),
        'POST /voice/rooms/7/join.json': joinPayload,
        'POST /voice/rooms/7/heartbeat.json': {},
        'DELETE /voice/rooms/7/leave.json': {},
        'POST /voice/rooms/7/state.json': {},
        'GET /voice/rooms/7/chat_session.json': fixture('chat'),
      },
    );
    requests = _StaticRequestHost();
    preferences = FakeVoicePreferences();
    mediaFactory = FakeVoiceMediaFactory();
    systemCall = FakeVoiceSystemCall();

    firstTracker = tracker(firstSite);
    secondTracker = tracker(secondSite);
    chatConversations = seededChatConversations();
    controller = VoiceController(
      api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
      chatConversations: chatConversations,
      requests: requests,
      trackerFor: (siteUrl) => siteUrl == firstSite
          ? firstTracker
          : siteUrl == secondSite
          ? secondTracker
          : null,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: mediaFactory,
      systemCall: systemCall,

      preferences: preferences,
      heartbeatInterval: const Duration(days: 1),
      signalBatchDelay: Duration.zero,
    );
  });

  tearDown(() => controller.dispose());

  test(
    'a late failed unmute cannot claim a newer open microphone is muted',
    () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;
      expect(controller.call?.muted, isTrue);
      final gate = Completer<void>();
      media.muteGate = gate;
      final oldUnmute = controller.setMuted(false);
      await pumpEventQueue();
      media.muteGate = null;
      await controller.setMuted(true);
      await controller.setMuted(false);
      expect(media.muted, isFalse);
      expect(controller.call?.muted, isFalse);
      gate.completeError(StateError('old unmute failed'));
      await oldUnmute;
      expect(controller.call?.muted, media.muted);
    },
  );

  group('media control settlement', () {
    Future<FakeVoiceMediaSession> join() async {
      final room =
          transport.responses['POST /voice/rooms/7/join.json']!['room']
              as Map<String, dynamic>;
      room.addAll({
        'room_type': 'open',
        'video_enabled': true,
        'video_allowed': true,
      });
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      return mediaFactory.sessions.single;
    }

    for (final setting in ['mute', 'deafen', 'share']) {
      Future<void> set(bool value) => switch (setting) {
        'mute' => controller.setMuted(value),
        'deafen' => controller.setDeafened(value),
        _ => controller.setScreenSharing(value),
      };
      bool? value() => switch (setting) {
        'mute' => controller.call?.muted,
        'deafen' => controller.call?.deafened,
        _ => controller.call?.screenSharing,
      };
      bool actual(FakeVoiceMediaSession media) => switch (setting) {
        'mute' => media.muted,
        'deafen' => media.deafened,
        _ => media.screen,
      };
      void hold(
        FakeVoiceMediaSession media,
        Future<void> Function(bool)? operation,
      ) {
        switch (setting) {
          case 'mute':
            media.onSetMuted = operation;
          case 'deafen':
            media.onSetDeafened = operation;
          case 'share':
            media.onSetScreenSharing = operation;
        }
      }

      test('newer successful $setting survives an older failure', () async {
        final media = await join();
        await set(true);
        final gate = Completer<void>();
        hold(media, (_) => gate.future);
        final older = set(false);
        hold(media, null);
        await set(true);
        await set(false);
        gate.completeError(StateError('older operation rejected'));
        await older;

        expect(value(), isFalse);
        expect(actual(media), isFalse);
        expect(controller.call?.error, isNull);
      });

      test(
        'an older $setting failure stays quiet while a newer one is pending',
        () async {
          final media = await join();
          final gates = [Completer<void>(), Completer<void>()];
          var next = 0;
          hold(media, (_) => gates[next++].future);
          final older = set(true);
          final newer = set(false);
          gates[0].completeError(StateError('older operation rejected'));
          await older;
          expect(controller.call?.error, isNull);

          gates[1].complete();
          await newer;
          expect(value(), isFalse);
          expect(controller.call?.error, isNull);
        },
      );

      for (final newerFirst in [false, true]) {
        test(
          '$setting restores accepted state when both fail, newer first $newerFirst',
          () async {
            final media = await join();
            await set(true);
            final gates = [Completer<void>(), Completer<void>()];
            var next = 0;
            hold(media, (_) => gates[next++].future);
            final older = set(false);
            final newer = set(true);
            final first = newerFirst ? 1 : 0;
            gates[first].completeError(StateError('first rejection'));
            await (newerFirst ? newer : older);
            gates[1 - first].completeError(StateError('second rejection'));
            await (newerFirst ? older : newer);

            expect(value(), isTrue);
            expect(actual(media), isTrue);
            expect(
              controller.call?.error,
              'The media setting was not applied.',
            );
          },
        );
      }

      test(
        '$setting rollback reconciles an already synced optimistic state',
        () async {
          final media = await join();
          await set(true);
          final gates = [Completer<void>(), Completer<void>()];
          var next = 0;
          hold(media, (_) => gates[next++].future);
          final older = set(false);
          final newer = set(true);
          gates[0].complete();
          await older;
          expect(value(), isTrue);
          gates[1].completeError(StateError('newer operation rejected'));
          await newer;

          expect(value(), isFalse);
          expect(actual(media), isFalse);
          final state = transport.writes.lastWhere(
            (write) => write.path.endsWith('/state.json'),
          );
          final key = switch (setting) {
            'mute' => 'muted',
            'deafen' => 'deafened',
            _ => 'screen',
          };
          expect(state.body[key], isFalse);
          if (setting == 'mute') expect(systemCall.systemMuted, isFalse);
        },
      );

      for (final replacing in [false, true]) {
        for (final fails in [false, true]) {
          test(
            'late $setting settlement after ${replacing ? 'replacement' : 'retirement'}, fails $fails',
            () async {
              final media = await join();
              final gate = Completer<void>();
              hold(media, (_) => gate.future);
              final pending = set(false);
              await controller.leave();
              if (replacing) {
                await controller.join(
                  siteUrl: firstSite,
                  siteName: 'One',
                  room: controller.room(firstSite, 7)!,
                );
              }
              final current = controller.call;
              final writes = transport.writes.length;
              systemCall.systemMuted = null;
              if (fails) {
                gate.completeError(StateError('retired operation rejected'));
              } else {
                gate.complete();
              }
              await pending;

              expect(controller.call, same(current));
              expect(transport.writes, hasLength(writes));
              expect(systemCall.systemMuted, isNull);
            },
          );
        }
      }
    }

    test(
      'mute failure preserves roster and independent deafen settlement',
      () async {
        final media = await join();
        final gate = Completer<void>();
        media.onSetMuted = (_) => gate.future;
        final pending = controller.setMuted(false);
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 1, 'username': 'sam', 'role': 'moderator'},
            {'id': 2, 'username': 'lee', 'role': 'participant'},
          ],
        });
        await controller.setDeafened(true);
        gate.completeError(StateError('mute rejected'));
        await pending;

        expect(controller.call?.muted, isTrue);
        expect(controller.call?.deafened, isTrue);
        expect(
          controller.call?.room.participants.map((user) => user.username),
          containsAll(['sam', 'lee']),
        );
      },
    );

    test('external share end invalidates a pending failed stop', () async {
      final media = await join();
      await controller.setScreenSharing(true);
      final gate = Completer<void>();
      media.onSetScreenSharing = (_) => gate.future;
      final pending = controller.setScreenSharing(false);
      media.screen = false;
      media.notifyListeners();
      gate.completeError(StateError('stop rejected after capture ended'));
      await pending;

      expect(controller.call?.screenSharing, isFalse);
      expect(controller.call?.error, isNull);
    });

    test(
      'a pending share restart survives the older stop media event',
      () async {
        final media = await join();
        await controller.setScreenSharing(true);
        media.notifyListeners();
        final gates = [Completer<void>(), Completer<void>()];
        var next = 0;
        media.onSetScreenSharing = (_) => gates[next++].future;
        final stopping = controller.setScreenSharing(false);
        final restarting = controller.setScreenSharing(true);
        media.screen = false;
        media.notifyListeners();
        expect(controller.call?.screenSharing, isTrue);
        gates[0].complete();
        await stopping;
        gates[1].complete();
        await restarting;

        expect(controller.call?.screenSharing, isTrue);
        expect(media.screen, isTrue);
      },
    );

    test(
      'share failures after an observed stop retain the stopped state',
      () async {
        final media = await join();
        await controller.setScreenSharing(true);
        media.notifyListeners();
        final gates = [Completer<void>(), Completer<void>()];
        var next = 0;
        media.onSetScreenSharing = (_) => gates[next++].future;
        final stopping = controller.setScreenSharing(false);
        final restarting = controller.setScreenSharing(true);
        media.screen = false;
        media.notifyListeners();
        gates[0].completeError(StateError('stop rejected after capture ended'));
        await stopping;
        gates[1].completeError(StateError('restart rejected'));
        await restarting;

        expect(controller.call?.screenSharing, isFalse);
        expect(media.screen, isFalse);
        final state = transport.writes.lastWhere(
          (write) => write.path.endsWith('/state.json'),
        );
        expect(state.body['screen'], isFalse);
      },
    );

    test(
      'unrelated media event does not cancel a pending share start',
      () async {
        final media = await join();
        final gate = Completer<void>();
        media.onSetScreenSharing = (_) => gate.future;
        final pending = controller.setScreenSharing(true);
        media.localVideoTrack = FakeVoiceVideoHandle();
        media.notifyListeners();
        expect(controller.call?.screenSharing, isTrue);
        gate.complete();
        await pending;

        expect(controller.call?.screenSharing, isTrue);
        expect(media.screen, isTrue);
      },
    );

    for (final fails in [false, true]) {
      test(
        'stage demotion owns mute over late settlement, fails $fails',
        () async {
          final payload = fixture('join_mesh');
          final room = payload['room'] as Map<String, dynamic>;
          room['room_type'] = 'open';
          transport.responses['POST /voice/rooms/7/join.json'] = payload;
          final media = await join();
          expect(controller.call?.muted, isFalse);
          final gate = Completer<void>();
          media.onSetMuted = (_) => gate.future;
          final pending = controller.setMuted(true);
          media.onSetMuted = null;
          firstTracker.deliver('/voice/rooms/index', {
            'type': 'updated',
            'room': {...room, 'room_type': 'stage'},
          });
          await pumpEventQueue();
          if (fails) {
            gate.completeError(StateError('old mute rejected'));
          } else {
            gate.complete();
          }
          await pending;

          expect(controller.call?.muted, isTrue);
          expect(media.muted, isTrue);
          expect(controller.call?.error, isNull);
        },
      );
    }
  });

  _ControlledVoiceTransport privilegedTransport() {
    final joinPayload = fixture('join_mesh');
    (joinPayload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
    return _ControlledVoiceTransport(
      responses: {
        'POST /voice/rooms/7/join.json': joinPayload,
        'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
        'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
        'POST /voice/rooms/7/state.json': <String, dynamic>{},
        'POST /voice/rooms/7/request_to_speak.json': <String, dynamic>{},
        'DELETE /voice/rooms/7/kick.json': <String, dynamic>{},
        'GET /site.json': {
          'post_action_types': [
            {'name_key': 'notify_moderators', 'id': 3},
          ],
        },
        'POST /voice/rooms/7/flag.json': <String, dynamic>{},
        'POST /voice/rooms/7/recording.json': <String, dynamic>{},
        'GET /voice/rooms/7/memberships.json': {'memberships': <Object?>[]},
        'POST /voice/rooms/7/memberships.json': <String, dynamic>{},
        'PUT /voice/rooms/7/memberships/9.json': <String, dynamic>{},
        'DELETE /voice/rooms/7/memberships/9.json': <String, dynamic>{},
      },
    );
  }

  Future<VoiceMembershipEditor> openMembershipEditor() async {
    final result = await controller.openMembershipEditor(firstSite, 7);
    expect(result, isA<VoiceMembershipOpened>());
    final editor = (result as VoiceMembershipOpened).editor;
    addTearDown(editor.dispose);
    return editor;
  }

  group('membership editor', () {
    const rosterPath = '/voice/rooms/7/memberships.json';
    const memberPath = '/voice/rooms/7/memberships/9.json';

    Map<String, dynamic> roster({int id = 9, String role = 'participant'}) => {
      'memberships': [
        {'id': id, 'room_id': 7, 'user_id': 2, 'role': role},
      ],
    };

    test('keeps opening failures bound to the captured account', () async {
      final controlled = privilegedTransport();
      controlled.operationFailure = StateError('server unavailable');
      useTransport(controlled);

      final result = await controller.openMembershipEditor(firstSite, 7);
      expect(result, isA<VoiceMembershipOpenFailure>());
      final failure = result as VoiceMembershipOpenFailure;
      expect(failure.isCurrent, isTrue);

      controller.forget(firstSite);

      expect(failure.isCurrent, isFalse);
    });

    test(
      'keeps all edits excluded until the accepted roster is refreshed',
      () async {
        final controlled = privilegedTransport();
        controlled.responses['GET $rosterPath'] = roster();
        useTransport(controlled);
        final editor = await openMembershipEditor();
        controlled.heldPluginWritePaths.add(rosterPath);
        controlled.heldPluginPaths.add(rosterPath);
        var accepted = 0;

        final operation = editor.add(
          'lee',
          VoiceRole.speaker,
          onAccepted: () => accepted++,
        );
        await controlled.waitForPendingPluginWrites(1);
        expect(editor.available, isFalse);
        expect(
          await editor.add('sam', VoiceRole.participant),
          VoiceMembershipEditStatus.busy,
        );
        expect(
          await editor.changeRole(9, VoiceRole.speaker),
          VoiceMembershipEditStatus.busy,
        );
        expect(await editor.remove(9), VoiceMembershipEditStatus.busy);
        expect(accepted, 0);

        controlled.pendingPluginWrites.single.response.complete({});
        await pumpEventQueue();
        expect(accepted, 1);
        expect(controlled.pendingPluginGets, hasLength(1));
        expect(editor.available, isFalse);
        expect(
          await editor.add('sam', VoiceRole.participant),
          VoiceMembershipEditStatus.busy,
        );
        expect(
          await editor.changeRole(9, VoiceRole.speaker),
          VoiceMembershipEditStatus.busy,
        );
        expect(await editor.remove(9), VoiceMembershipEditStatus.busy);

        expect(editor.memberships.single.role, VoiceRole.participant);

        controlled.pendingPluginGets.single.response.complete(
          roster(role: 'speaker'),
        );
        expect(await operation, VoiceMembershipEditStatus.accepted);
        expect(editor.memberships.single.role, VoiceRole.speaker);
        expect(editor.available, isTrue);
      },
    );

    test(
      'publishes immutable rosters and retains the last roster after failures',
      () async {
        final controlled = privilegedTransport();
        controlled.responses['GET $rosterPath'] = roster();
        useTransport(controlled);
        final editor = await openMembershipEditor();
        final initialRoster = editor.memberships;
        expect(() => initialRoster.clear(), throwsUnsupportedError);

        controlled.responses['GET $rosterPath'] = roster(
          id: 10,
          role: 'speaker',
        );
        expect(
          await editor.add('lee', VoiceRole.speaker),
          VoiceMembershipEditStatus.accepted,
        );
        expect(editor.memberships.single.id, 10);
        expect(initialRoster.single.id, 9);
        expect(() => editor.memberships.clear(), throwsUnsupportedError);
        final acceptedRoster = editor.memberships;
        final readsBefore = controlled.pluginGets.length;

        controlled.operationFailure = StateError('server unavailable');
        final refused = await editor.changeRole(9, VoiceRole.participant);
        expect(refused, isA<VoiceMembershipEditRefused>());
        expect(
          (refused as VoiceMembershipEditRefused).message,
          "Couldn't change the member's role.",
        );
        expect(controlled.pluginGets.length, readsBefore);
        expect(editor.memberships, same(acceptedRoster));
        expect(editor.available, isTrue);

        controlled.operationFailure = null;
        controlled.pluginGetFailures[rosterPath] = const SiteLookupException(
          SiteLookupFailure.unreachable,
          'server unavailable',
        );
        var accepted = 0;
        expect(
          await editor.add(
            'sam',
            VoiceRole.participant,
            onAccepted: () => accepted++,
          ),
          VoiceMembershipEditStatus.refreshFailed,
        );
        expect(accepted, 1);
        expect(editor.memberships, same(acceptedRoster));
        expect(editor.available, isTrue);

        controlled.pluginGetFailures.clear();
        controlled.responses['GET $rosterPath'] = {'memberships': <Object?>[]};
        expect(await editor.remove(9), VoiceMembershipEditStatus.accepted);
        expect(editor.memberships, isEmpty);
        expect(acceptedRoster.single.id, 10);
      },
    );

    for (final pending in ['write', 'refresh']) {
      for (final retirement in ['editor', 'account']) {
        test(
          'ignores a pending $pending after $retirement retirement',
          () async {
            final controlled = privilegedTransport();
            controlled.responses['GET $rosterPath'] = roster();
            useTransport(controlled);
            final editor = await openMembershipEditor();
            final initialRoster = editor.memberships;
            final readsBefore = controlled.pluginGets.length;
            var accepted = 0;
            if (pending == 'write') {
              controlled.heldPluginWritePaths.add(rosterPath);
            } else {
              controlled.heldPluginPaths.add(rosterPath);
            }
            final operation = editor.add(
              'lee',
              VoiceRole.speaker,
              onAccepted: () => accepted++,
            );
            if (pending == 'write') {
              await controlled.waitForPendingPluginWrites(1);
            } else {
              await pumpEventQueue();
              expect(controlled.pendingPluginGets, hasLength(1));
            }

            if (retirement == 'editor') {
              editor.retire();
            } else {
              controller.forget(firstSite);
            }
            expect(editor.isCurrent, isFalse);
            expect(editor.available, isFalse);
            if (pending == 'write') {
              controlled.pendingPluginWrites.single.response.complete({});
            } else {
              controlled.pendingPluginGets.single.response.complete(
                roster(role: 'speaker'),
              );
            }

            expect(await operation, VoiceMembershipEditStatus.retired);
            expect(editor.memberships, same(initialRoster));
            expect(editor.memberships.single.role, VoiceRole.participant);
            expect(accepted, pending == 'write' ? 0 : 1);
            expect(
              controlled.pluginGets.length,
              readsBefore + (pending == 'refresh' ? 1 : 0),
            );

            expect(
              await editor.add('sam', VoiceRole.participant),
              VoiceMembershipEditStatus.retired,
            );
            expect(
              await editor.changeRole(9, VoiceRole.speaker),
              VoiceMembershipEditStatus.retired,
            );
            expect(await editor.remove(9), VoiceMembershipEditStatus.retired);
          },
        );
      }
    }

    test(
      'retains credential execution scopes for opening, writes and refreshes',
      () async {
        final controlled = privilegedTransport();
        final scopes = <Object?>[];
        for (final route in [
          'GET $rosterPath',
          'POST $rosterPath',
          'PUT $memberPath',
          'DELETE $memberPath',
        ]) {
          final response = controlled.responses[route]!;
          controlled.responders[route] = (_) {
            scopes.add(Zone.current[_ScopedRequestHost.scope]);
            return response;
          };
        }
        requests = _ScopedRequestHost();
        useTransport(controlled);
        final editor = await openMembershipEditor();

        expect(
          await editor.add('lee', VoiceRole.participant),
          VoiceMembershipEditStatus.accepted,
        );
        expect(
          await editor.changeRole(9, VoiceRole.speaker),
          VoiceMembershipEditStatus.accepted,
        );
        expect(await editor.remove(9), VoiceMembershipEditStatus.accepted);

        expect(scopes, List.filled(7, 'key'));
      },
    );

    test(
      'allows the acceptance callback to retire before roster refresh',
      () async {
        final controlled = privilegedTransport();
        useTransport(controlled);
        final editor = await openMembershipEditor();
        final readsBefore = controlled.pluginGets.length;
        var accepted = 0;

        final result = await editor.add(
          'lee',
          VoiceRole.participant,
          onAccepted: () {
            accepted++;
            editor.retire();
          },
        );

        expect(result, VoiceMembershipEditStatus.retired);
        expect(accepted, 1);
        expect(controlled.writes.single.method, 'POST');
        expect(controlled.pluginGets.length, readsBefore);
        expect(editor.available, isFalse);
      },
    );

    test('propagates callback errors and releases the edit lock', () async {
      final controlled = privilegedTransport();
      useTransport(controlled);
      final editor = await openMembershipEditor();
      final readsBefore = controlled.pluginGets.length;
      final callbackError = StateError('acceptance callback failed');

      await expectLater(
        editor.add(
          'lee',
          VoiceRole.participant,
          onAccepted: () => throw callbackError,
        ),
        throwsA(same(callbackError)),
      );

      expect(editor.available, isTrue);
      expect(controlled.pluginGets.length, readsBefore);

      expect(await editor.remove(9), VoiceMembershipEditStatus.accepted);
    });
  });

  test(
    'call requests retain capabilities while leave has its own lifetime',
    () async {
      final scopes = <String, Object?>{};
      for (final method in ['join', 'heartbeat', 'state', 'leave']) {
        final request =
            '${method == 'leave' ? 'DELETE' : 'POST'} /voice/rooms/7/$method.json';
        final response = transport.responses[request]!;
        transport.responders[request] = (_) {
          scopes[method] = Zone.current[_ScopedRequestHost.scope];
          return response;
        };
      }
      requests = _ScopedRequestHost();
      useTransport(transport);

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: VoiceRoom.fromJson(fixture('room')),
      );
      await controller.setMuted(!controller.call!.muted);
      controller.setForeground(false);
      await pumpEventQueue();
      await controller.leave();

      expect(scopes, {
        'join': 'full',
        'state': 'key',
        'heartbeat': 'key',
        'leave': null,
      });
      expect(mediaFactory.sessions.single.disposeCount, 1);
      expect(systemCall.ends, 1);
    },
  );

  group('directory loading', () {
    for (final oldResponseFirst in [true, false]) {
      test('a forgotten directory response cannot affect a replacement load '
          'when it completes ${oldResponseFirst ? 'first' : 'last'}', () async {
        final controlled = _ControlledVoiceTransport()
          ..heldPluginPaths.add('/voice/rooms.json');
        useTransport(controlled);

        final oldLoad = controller.ensureLoaded(firstSite);
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));

        controller.forget(firstSite);
        final newLoad = controller.ensureLoaded(firstSite);
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(2));
        expect(controller.isLoading(firstSite), isTrue);

        var notifications = 0;
        controller.addListener(() => notifications++);
        final newDirectory = fixture('directory');
        final replacement =
            (newDirectory['rooms'] as List<dynamic>).first
                as Map<String, dynamic>;
        replacement['name'] = 'Replacement room';

        if (oldResponseFirst) {
          controlled.pendingPluginGets.first.response.complete(
            fixture('directory'),
          );
          await oldLoad;
          expect(controller.isLoading(firstSite), isTrue);
          expect(controller.directory(firstSite), isNull);
          expect(notifications, 0);
        }

        controlled.pendingPluginGets.last.response.complete(newDirectory);
        await newLoad;
        expect(controller.isLoading(firstSite), isFalse);
        expect(
          controller.directory(firstSite)?.rooms.single.name,
          'Replacement room',
        );

        if (!oldResponseFirst) {
          final successorNotifications = notifications;
          controlled.pendingPluginGets.first.response.complete(
            fixture('directory'),
          );
          await oldLoad;
          expect(
            controller.directory(firstSite)?.rooms.single.name,
            'Replacement room',
          );
          expect(controller.isLoading(firstSite), isFalse);
          expect(notifications, successorNotifications);
        }
      });
    }

    test(
      'caches confirmed plugin unavailability until the site is forgotten',
      () async {
        final unsupportedFailures = <SiteLookupException>[
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            firstSite,
            statusCode: HttpStatus.notFound,
          ),
          const SiteLookupException(
            SiteLookupFailure.notDiscourse,
            firstSite,
            statusCode: HttpStatus.forbidden,
          ),
        ];

        for (final failure in unsupportedFailures) {
          final controlled = _ControlledVoiceTransport()
            ..pluginGetFailures['/voice/rooms.json'] = failure;
          useTransport(controlled);

          await controller.ensureLoaded(firstSite);
          await controller.ensureLoaded(firstSite);
          await controller.ensureLoaded(firstSite, force: true);

          expect(
            controlled.pluginGets,
            ['/voice/rooms.json'],
            reason:
                'a confirmed unavailable capability is stable for the session',
          );

          controller.forget(firstSite);
          await controller.ensureLoaded(firstSite);

          expect(
            controlled.pluginGets,
            ['/voice/rooms.json', '/voice/rooms.json'],
            reason:
                'forget starts a new site session and clears the capability',
          );
        }
      },
    );

    test('skips room-route probes when site settings disable Voice', () async {
      final controlled = _ControlledVoiceTransport(
        responses: {'GET /voice/rooms.json': fixture('directory')},
      );
      useTransport(controlled, capabilityEnabledFor: (_) async => false);

      await controller.ensureLoaded(firstSite);
      final linkedRoom = await controller.resolveRoom(firstSite, 'conf-room-1');

      expect(controlled.pluginGets, isEmpty);
      expect(linkedRoom, isNull);
      expect(controller.directory(firstSite), isNull);
    });

    test('probes room routes when site settings cannot be resolved', () async {
      final controlled = _ControlledVoiceTransport(
        responses: {'GET /voice/rooms.json': fixture('directory')},
      );
      useTransport(controlled, capabilityEnabledFor: (_) async => null);

      await controller.ensureLoaded(firstSite);

      expect(controlled.pluginGets, ['/voice/rooms.json']);
      expect(controller.directory(firstSite), isNotNull);
    });

    test('retries after an unreachable directory response', () async {
      final controlled =
          _ControlledVoiceTransport(
              responses: {'GET /voice/rooms.json': fixture('directory')},
            )
            ..pluginGetFailures['/voice/rooms.json'] =
                const SiteLookupException(
                  SiteLookupFailure.unreachable,
                  firstSite,
                  statusCode: HttpStatus.serviceUnavailable,
                );
      useTransport(controlled);

      await controller.ensureLoaded(firstSite);
      controlled.pluginGetFailures.remove('/voice/rooms.json');
      await controller.ensureLoaded(firstSite);

      expect(controlled.pluginGets, ['/voice/rooms.json', '/voice/rooms.json']);
      expect(controller.directory(firstSite), isNotNull);
    });

    for (final unavailableByCapability in [true, false]) {
      test(
        'an active call survives '
        '${unavailableByCapability ? 'disabled capability' : 'directory absence'}',
        () async {
          var capabilityEnabled = true;
          final controlled = _ControlledVoiceTransport(
            responses: transport.responses,
          );
          useTransport(
            controlled,
            capabilityEnabledFor: (_) async => capabilityEnabled,
          );
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          await controller.selectAudioInput('chosen-microphone');
          final call = controller.call!;
          final media = mediaFactory.sessions.single;
          expect(firstTracker.subscriberCount('/voice/call-ring/1'), 1);
          expect(firstTracker.subscriberCount('/voice/rooms/7'), 1);

          if (unavailableByCapability) {
            capabilityEnabled = false;
          } else {
            controlled.pluginGetFailures['/voice/rooms.json'] =
                const SiteLookupException(
                  SiteLookupFailure.unreachable,
                  firstSite,
                  statusCode: HttpStatus.notFound,
                );
          }
          await controller.ensureLoaded(firstSite, force: true);

          expect(controller.directory(firstSite), isNull);
          expect(controller.call, same(call));
          expect(controller.call!.media, same(media));
          expect(media.disposeCount, 0);
          expect(systemCall.ends, 0);
          expect(controller.audioInputDeviceId, 'chosen-microphone');
          expect(media.selectedAudioInput, 'chosen-microphone');
          expect(firstTracker.subscriberCount('/voice/call-ring/1'), 1);
          expect(firstTracker.subscriberCount('/voice/rooms/7'), 1);

          await controller.setMuted(!call.muted);
          expect(controller.call!.muted, !call.muted);
          expect(media.muted, !call.muted);
        },
      );
    }

    test('rechecks site ownership before reading credentials', () async {
      final counting = _CountingRequestHost();
      final controlled = _ControlledVoiceTransport(
        responses: {'GET /voice/rooms.json': fixture('directory')},
      );
      requests = counting;
      useTransport(controlled);
      controller.addListener(() {
        if (controller.isLoading(firstSite)) controller.forget(firstSite);
      });

      await controller.ensureLoaded(firstSite);

      expect(counting.credentialCalls, 1);
      expect(controlled.pluginGets, isEmpty);
    });
  });

  group('credential and session boundaries', () {
    test(
      'credits a pending room invitation on the next matching join',
      () async {
        final room = VoiceRoom.fromJson(fixture('room'));
        controller.rememberInviteRef(
          siteUrl: firstSite,
          roomSlug: room.slug,
          username: 'inviter',
        );

        await controller.join(siteUrl: firstSite, siteName: 'One', room: room);

        final request = transport.writes.firstWhere(
          (request) => request.path == '/voice/rooms/7/join.json',
        );
        expect(request.body['invited_by'], 'inviter');
      },
    );

    test(
      'prevent a credential-gated join after the site is forgotten',
      () async {
        final gate = Completer<void>();
        requests = _GatedRequestHost(credentialsGate: gate);
        final controlled = _ControlledVoiceTransport();
        useTransport(controlled);

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await pumpEventQueue();
        expect(controller.isJoining(firstSite, 7), isTrue);

        controller.forget(firstSite);
        expect(controller.isJoining(firstSite, 7), isFalse);
        gate.complete();
        await joining;

        expect(controlled.writes, isEmpty);
        expect(controller.call, isNull);
        expect(mediaFactory.sessions, isEmpty);
      },
    );

    test('forgetting the site clears room-list join loading while the retired '
        'join is still in flight', () async {
      final gate = Completer<void>();
      requests = _GatedRequestHost(credentialsGate: gate);
      useTransport(_ControlledVoiceTransport());
      final loading = <bool>[];
      controller.roomListenable.addListener(
        () => loading.add(controller.isJoining(firstSite, 7)),
      );

      final retired = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: VoiceRoom.fromJson(fixture('room')),
      );
      await pumpEventQueue();
      expect(loading, [true]);

      controller.forget(firstSite);
      expect(loading, [true, false]);

      gate.complete();
      await retired;
      expect(loading, [true, false]);
    });

    test(
      'a rejoin after the site is forgotten does not wait on the retired join',
      () async {
        final gate = Completer<void>();
        requests = _GatedRequestHost(credentialsGate: gate);
        useTransport(transport);
        final room = VoiceRoom.fromJson(fixture('room'));

        final retired = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: room,
        );
        await pumpEventQueue();
        controller.forget(firstSite);
        final rejoining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: room,
        );
        gate.complete();
        await Future.wait([retired, rejoining]);

        expect(
          transport.writes.where((write) => write.path.endsWith('/join.json')),
          hasLength(1),
        );
        expect(controller.call?.room.id, 7);
        expect(mediaFactory.sessions, hasLength(1));
      },
    );

    test(
      'a retired join finishing does not hide the rejoin still pending',
      () async {
        final controlled = _ControlledVoiceTransport()
          ..heldPluginWritePaths.add('/voice/rooms/7/join.json');
        useTransport(controlled);
        final room = VoiceRoom.fromJson(fixture('room'));

        final retired = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: room,
        );
        await pumpEventQueue();
        controller.forget(firstSite);
        final rejoining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: room,
        );
        controlled.pendingPluginWrites
            .removeAt(0)
            .response
            .complete(fixture('join_mesh'));
        await retired;
        await pumpEventQueue();

        expect(
          controlled.writes.where(
            (write) => write.path.endsWith('/leave.json'),
          ),
          hasLength(1),
        );
        expect(controlled.pendingPluginWrites, hasLength(1));
        expect(controller.isJoining(firstSite, 7), isTrue);
        controlled.pendingPluginWrites.single.response.complete(
          fixture('join_mesh'),
        );
        await rejoining;
        expect(controller.isJoining(firstSite, 7), isFalse);
        expect(controller.call?.room.id, 7);
      },
    );

    test(
      'prevent an in-flight join response from creating media after the site is forgotten',
      () async {
        final controlled = _ControlledVoiceTransport()
          ..heldPluginWritePaths.add('/voice/rooms/7/join.json');
        useTransport(controlled);

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await pumpEventQueue();
        expect(controlled.pendingPluginWrites, hasLength(1));

        controller.forget(firstSite);
        controlled.pendingPluginWrites.single.response.complete(
          fixture('join_mesh'),
        );
        await joining;

        expect(controller.call, isNull);
        expect(mediaFactory.sessions, isEmpty);
        expect(systemCall.starts, 0);
      },
    );

    test('recheck join ownership before starting the system call', () async {
      controller.addListener(() {
        if (controller.call?.status == VoiceCallStatus.joining) {
          controller.forget(firstSite);
        }
      });

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: VoiceRoom.fromJson(fixture('room')),
      );
      await pumpEventQueue();

      expect(systemCall.starts, 0);
      expect(mediaFactory.sessions.single.disposeCount, 1);
    });

    for (final action
        in <
          ({
            String name,
            Set<String> paths,
            Future<void> Function(VoiceController controller) begin,
          })
        >[
          (
            name: 'raise-hand write',
            paths: {'/voice/rooms/7/request_to_speak.json'},
            begin: (controller) => controller.requestToSpeak(),
          ),
          (
            name: 'participant role write',
            paths: {'/voice/rooms/7/memberships.json'},
            begin: (controller) =>
                controller.setParticipantRole(2, VoiceRole.speaker),
          ),
          (
            name: 'kick write',
            paths: {'/voice/rooms/7/kick.json'},
            begin: (controller) => controller.kick(2),
          ),
          (
            name: 'participant flag',
            paths: {'/site.json', '/voice/rooms/7/flag.json'},
            begin: (controller) async {
              await controller.flagParticipant(2, 'Please review');
            },
          ),
          (
            name: 'recording write',
            paths: {'/voice/rooms/7/recording.json'},
            begin: (controller) => controller.setRecording(true),
          ),
          (
            name: 'state write',
            paths: {'/voice/rooms/7/state.json'},
            begin: (controller) => controller.setMuted(true),
          ),
          (
            name: 'heartbeat write',
            paths: {'/voice/rooms/7/heartbeat.json'},
            begin: (controller) async {
              controller.setForeground(false);
              await pumpEventQueue();
            },
          ),
        ]) {
      for (final replaceCall in [false, true]) {
        test(
          'prevent stale ${action.name} during credential lookup when '
          '${replaceCall ? 'the call is replaced' : 'the site is forgotten'}',
          () async {
            final gated = _NextGatedRequestHost();
            requests = gated;
            final controlled = privilegedTransport();
            useTransport(controlled);
            await controller.join(
              siteUrl: firstSite,
              siteName: 'One',
              room: VoiceRoom.fromJson(fixture('room')),
            );

            gated.gateNextRead = true;
            final operation = action.begin(controller);
            await gated.readStarted.future;
            if (replaceCall) {
              await controller.leave();
              await controller.join(
                siteUrl: firstSite,
                siteName: 'One',
                room: VoiceRoom.fromJson(fixture('room')),
              );
            } else {
              controller.forget(firstSite);
            }
            final writesBefore = controlled.writes.length;
            final getsBefore = controlled.pluginGets.length;
            gated.readGate.complete();
            await operation;
            await pumpEventQueue();

            final paths = <String>{
              for (final write in controlled.writes.skip(writesBefore))
                write.path,
              ...controlled.pluginGets.skip(getsBefore),
            };
            expect(paths.intersection(action.paths), isEmpty);
          },
        );
      }
    }

    test(
      'prevent a stale membership open when forgotten during credential lookup',
      () async {
        final gated = _NextGatedRequestHost()..gateNextRead = true;
        requests = gated;
        final controlled = privilegedTransport();
        useTransport(controlled);

        final operation = controller.openMembershipEditor(firstSite, 7);
        await gated.readStarted.future;
        controller.forget(firstSite);
        gated.readGate.complete();

        final result = await operation;
        expect(result, isA<VoiceMembershipOpenFailure>());
        expect((result as VoiceMembershipOpenFailure).isCurrent, isFalse);
        expect(controlled.pluginGets, isEmpty);
        expect(controlled.writes, isEmpty);
      },
    );

    for (final action
        in <
          ({
            String name,
            String path,
            Future<VoiceMembershipEditResult> Function(
              VoiceMembershipEditor editor,
            )
            begin,
          })
        >[
          (
            name: 'membership add',
            path: '/voice/rooms/7/memberships.json',
            begin: (editor) => editor.add('lee', VoiceRole.participant),
          ),
          (
            name: 'membership update',
            path: '/voice/rooms/7/memberships/9.json',
            begin: (editor) => editor.changeRole(9, VoiceRole.speaker),
          ),
          (
            name: 'membership removal',
            path: '/voice/rooms/7/memberships/9.json',
            begin: (editor) => editor.remove(9),
          ),
        ]) {
      test(
        'prevent stale ${action.name} when forgotten during credential lookup',
        () async {
          final gated = _NextGatedRequestHost();
          requests = gated;
          final controlled = privilegedTransport();
          useTransport(controlled);
          final editor = await openMembershipEditor();
          final readsBefore = controlled.pluginGets.length;

          gated.gateNextRead = true;
          final operation = action.begin(editor);
          await gated.readStarted.future;
          controller.forget(firstSite);
          gated.readGate.complete();

          expect(await operation, VoiceMembershipEditStatus.retired);
          expect(
            controlled.writes.where((write) => write.path == action.path),
            isEmpty,
          );
          expect(controlled.pluginGets.skip(readsBefore), isEmpty);
        },
      );
    }

    test(
      'contain secure-store failures across detached public entry points',
      () async {
        const privateCause =
            'credential-private-user device-private 203.0.113.130';
        final failingRequests = _FailingRequestHost();
        requests = failingRequests;
        useTransport(transport);
        await controller.openChat(firstSite, 7);

        failingRequests.failure = PlatformException(
          code: 'secure_store_read',
          message: privateCause,
          details: {'account': 'credential-private-user'},
        );

        final uncaught = await _captureUncaught(() async {
          unawaited(controller.ensureLoaded(firstSite, force: true));
          unawaited(
            controller.join(
              siteUrl: firstSite,
              siteName: 'Private site',
              room: VoiceRoom.fromJson(fixture('room')),
            ),
          );
          unawaited(controller.openChat(firstSite, 7, force: true));
          unawaited(controller.loadOlderChat(firstSite, 7));
          unawaited(controller.sendChatMessage(firstSite, 7, 'hello'));
          for (var index = 0; index < 8; index++) {
            await pumpEventQueue();
          }
        });

        expect(uncaught, isEmpty);
      },
    );
  });

  group('media preferences and device selection', () {
    for (final kind in ['audio_input', 'audio_output']) {
      test('falls back when the saved $kind is unavailable', () async {
        preferences.devices = const VoiceDevicePreferences(
          audioInputDeviceId: 'saved-input',
          audioOutputDeviceId: 'saved-output',
        );
        useTransport(transport);
        if (kind == 'audio_input') {
          mediaFactory.nextAudioInputSelection = (deviceId) async {
            if (deviceId == 'saved-input') {
              throw const VoiceMicrophoneException(
                VoiceMicrophoneFailureKind.unavailable,
              );
            }
          };
        } else {
          mediaFactory.nextAudioOutputSelection = (deviceId) async {
            if (deviceId == 'saved-output') {
              throw PlatformException(
                code: 'selectAudioOutputFailed',
                message: 'Error: deviceId not found!',
              );
            }
          };
        }
        final room = VoiceRoom.fromJson(fixture('room'));

        await controller.join(siteUrl: firstSite, siteName: 'One', room: room);

        final media = mediaFactory.sessions.single;
        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(controller.errorFor(firstSite), isNull);
        expect(media.disposeCount, 0);
        expect(systemCall.connectedCalls, 1);
        expect(media.audioInputSelections, [
          'saved-input',
          if (kind == 'audio_input') 'default',
        ]);
        expect(media.audioOutputSelections, [
          'saved-output',
          if (kind == 'audio_output') 'default',
        ]);
        expect(
          transport.writes.where((write) => write.path.endsWith('/leave.json')),
          isEmpty,
        );

        expect(preferences.writes, isEmpty);

        // A temporarily disconnected device is still preferred next time.
        await controller.leave();
        await controller.join(siteUrl: firstSite, siteName: 'One', room: room);
        final nextMedia = mediaFactory.sessions.last;
        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(nextMedia.selectedAudioInput, 'saved-input');
        expect(nextMedia.selectedAudioOutput, 'saved-output');
      });
    }

    for (final deviceId in ['saved-output', 'default']) {
      test('cleans up when $deviceId and the default output fail', () async {
        preferences.devices = VoiceDevicePreferences(
          audioOutputDeviceId: deviceId,
        );
        useTransport(transport);
        mediaFactory.nextAudioOutputFailure = PlatformException(
          code: 'selectAudioOutputFailed',
          message: 'Error: deviceId not found!',
        );

        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );

        final media = mediaFactory.sessions.single;
        expect(media.audioOutputSelections, [
          deviceId,
          if (deviceId != 'default') 'default',
        ]);
        expect(controller.call, isNull);
        expect(controller.errorFor(firstSite), isNotNull);
        expect(media.disposeCount, 1);
        expect(systemCall.connectedCalls, 0);
        expect(
          transport.writes.where((write) => write.path.endsWith('/leave.json')),
          hasLength(1),
        );
      });
    }

    test(
      'does not restore a default device after leaving during selection',
      () async {
        preferences.devices = const VoiceDevicePreferences(
          audioOutputDeviceId: 'saved-output',
        );
        useTransport(transport);
        final selectionStarted = Completer<void>();
        final selectionGate = Completer<void>();
        mediaFactory.nextAudioOutputSelection = (_) async {
          selectionStarted.complete();
          await selectionGate.future;
          throw PlatformException(
            code: 'selectAudioOutputFailed',
            message: 'Error: deviceId not found!',
          );
        };

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await selectionStarted.future;
        await controller.leave();
        selectionGate.complete();
        await joining;

        final media = mediaFactory.sessions.single;
        expect(media.audioOutputSelections, ['saved-output']);
        expect(media.disposeCount, 1);
        expect(controller.call, isNull);
        expect(systemCall.connectedCalls, 0);
      },
    );

    test(
      'preserve live call controls when preference operations fail',
      () async {
        await pumpEventQueue();
        preferences
          ..rejectWrites = true
          ..rejectVolumeReads = true;

        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;

        await controller.selectAudioInput('microphone');
        await controller.selectAudioOutput('speakers');
        await controller.setPushToTalkEnabled(true);
        await controller.setParticipantVolume(firstSite, 7, 2, 0.4);

        expect(media.selectedAudioInput, 'microphone');
        expect(media.selectedAudioOutput, 'speakers');
        expect(media.muted, isTrue);
        expect(media.participantVolumes[2], 0.4);
        expect(await controller.participantVolume(firstSite, 7, 2), 1);
      },
    );

    group('saved participant volumes', () {
      const sam = {'id': 1, 'username': 'sam', 'role': 'participant'};
      const lee = {'id': 2, 'username': 'lee', 'role': 'participant'};
      const kim = {'id': 3, 'username': 'kim', 'role': 'participant'};

      void joinResponseLists(List<Map<String, Object>> participants) {
        (transport.responses['POST /voice/rooms/7/join.json']!['room']
                as Map<String, dynamic>)['active_participants'] =
            participants;
      }

      ({Completer<void> started, Completer<void> gate}) holdVolumeReads() {
        final started = Completer<void>();
        final gate = Completer<void>();
        preferences.onReadVolume = (_) async {
          if (!started.isCompleted) started.complete();
          await gate.future;
        };
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        return (started: started, gate: gate);
      }

      test('joining applies them before the media connects', () async {
        joinResponseLists([sam, lee, kim]);
        preferences.volumes[(firstSite, 7, 2)] = 0.4;
        final connectStarted = mediaFactory.nextConnectStarted =
            Completer<void>();
        final connectGate = mediaFactory.nextConnectGate = Completer<void>();
        await controller.ensureLoaded(firstSite);

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        await connectStarted.future;
        await pumpEventQueue();
        final media = mediaFactory.sessions.single;
        expect(media.participantVolumes, {2: 0.4});

        connectGate.complete();
        await joining;
        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(media.participantVolumes, {2: 0.4});
      });

      test('a participant who arrives later gets theirs', () async {
        preferences.volumes[(firstSite, 7, 2)] = 0.4;
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        expect(media.participantVolumes, isEmpty);

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [sam, lee],
        });
        await pumpEventQueue();

        expect(media.participantVolumes, {2: 0.4});
      });

      test('a slider change made during the read wins', () async {
        joinResponseLists([sam, lee]);
        preferences.volumes[(firstSite, 7, 2)] = 0.4;
        final read = holdVolumeReads();
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        await read.started.future;
        final media = mediaFactory.sessions.single;

        await controller.setParticipantVolume(firstSite, 7, 2, 0.7);
        read.gate.complete();
        await pumpEventQueue();

        expect(media.participantVolumes, {2: 0.7});
        expect(preferences.volumes[(firstSite, 7, 2)], 0.7);
      });

      for (final (siteUrl, roomId) in [(firstSite, 8), (secondSite, 7)]) {
        test('a different volume preference target leaves current media alone '
            '($siteUrl room $roomId)', () async {
          joinResponseLists([sam, lee]);
          preferences.volumes[(firstSite, 7, 2)] = 0.4;
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          await pumpEventQueue();
          final media = mediaFactory.sessions.single;
          await controller.setParticipantVolume(siteUrl, roomId, 2, 0.7);
          expect(media.participantVolumes, {2: 0.4});
          expect(preferences.volumes[(siteUrl, roomId, 2)], 0.7);
        });
      }

      test('leaving during the read leaves the old media alone; rejoining '
          'applies them to the new one', () async {
        joinResponseLists([sam, lee]);
        preferences.volumes[(firstSite, 7, 2)] = 0.4;
        final read = holdVolumeReads();
        await controller.ensureLoaded(firstSite);
        final room = controller.room(firstSite, 7)!;
        await controller.join(siteUrl: firstSite, siteName: 'One', room: room);
        await read.started.future;
        final left = mediaFactory.sessions.single;

        await controller.leave();
        preferences.onReadVolume = null;
        read.gate.complete();
        await pumpEventQueue();
        expect(left.participantVolumes, isEmpty);

        await controller.join(siteUrl: firstSite, siteName: 'One', room: room);
        await pumpEventQueue();
        final rejoined = mediaFactory.sessions.last;
        expect(rejoined, isNot(same(left)));
        expect(rejoined.participantVolumes, {2: 0.4});
        expect(left.participantVolumes, isEmpty);
      });
    });

    test(
      'stop after a pending preference write when the controller is disposed',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        final writeStarted = Completer<void>();
        final writeGate = Completer<void>();
        preferences
          ..deviceWriteStarted = writeStarted
          ..deviceWriteGate = writeGate;

        final selection = controller.selectAudioInput('late-microphone');
        await writeStarted.future;
        controller.dispose();
        writeGate.complete();
        await selection;

        expect(media.selectedAudioInput, isNull);
        final writesAfterDispose = preferences.writes.length;
        await controller.selectAudioOutput('late-speakers');
        expect(preferences.writes, hasLength(writesAfterDispose));
        expect(await controller.mediaDevices(), isEmpty);
      },
    );
  });

  group('site invalidation', () {
    test('close drains watches detached by tracker replacement', () async {
      final awaitable = _AwaitableSubscriptionTracker();
      firstTracker = awaitable;
      useTransport(transport, userIdFor: (_) => null);
      await controller.ensureLoaded(firstSite);

      final replacement = tracker(firstSite);
      controller.attachTracker(firstSite, replacement);
      await awaitable.firstCancellationStarted.future;
      expect(awaitable.channels, isEmpty);
      expect(awaitable.cancellationsStarted, 2);
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      await pumpEventQueue();
      expect(replacement.channels, isEmpty);
      expect(closed, isFalse);

      awaitable.cancellationGate.complete();
      await closing;
      expect(closed, isTrue);
    });

    test(
      'close drains a directory already retired by account removal',
      () async {
        final awaitable = _AwaitableSubscriptionTracker();
        firstTracker = awaitable;
        useTransport(transport, userIdFor: (_) => null);
        await controller.ensureLoaded(firstSite);

        controller.forget(firstSite);
        await awaitable.firstCancellationStarted.future;
        expect(controller.directory(firstSite), isNull);
        expect(awaitable.channels, isEmpty);
        expect(awaitable.cancellationsStarted, 2);
        var closed = false;
        final closing = controller.close().then((_) => closed = true);
        await pumpEventQueue();
        expect(closed, isFalse);

        awaitable.cancellationGate.complete();
        await closing;
        expect(closed, isTrue);
      },
    );

    test(
      'discards a late directory response after the site is forgotten',
      () async {
        final controlled = _ControlledVoiceTransport()
          ..heldPluginPaths.add('/voice/rooms.json');
        useTransport(controlled);

        final load = controller.ensureLoaded(firstSite);
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));

        controller.forget(firstSite);
        controlled.pendingPluginGets.single.response.complete(
          fixture('directory'),
        );
        await load;

        expect(controller.directory(firstSite), isNull);
        expect(firstTracker.lastIds, isEmpty);
      },
    );

    test(
      'discards a late linked-room lookup after the site is forgotten',
      () async {
        final controlled = _ControlledVoiceTransport()
          ..heldPluginPaths.add('/voice/rooms/conf-room-1.json');
        useTransport(controlled);

        final lookup = controller.resolveRoom(firstSite, 'conf-room-1');
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));

        controller.forget(firstSite);
        controlled.pendingPluginGets.single.response.complete({
          'room': fixture('room'),
        });

        expect(await lookup, isNull);
        expect(controller.room(firstSite, 7), isNull);
      },
    );

    test(
      'discards a late room-Chat response after the site is forgotten',
      () async {
        final controlled = _ControlledVoiceTransport()
          ..heldPluginPaths.add('/voice/rooms/7/chat_session.json');
        useTransport(controlled);

        final load = controller.openChat(firstSite, 7);
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));

        controller.forget(firstSite);
        controlled.pendingPluginGets.single.response.complete(fixture('chat'));
        await load;

        expect(controller.chat(firstSite, 7), isNull);
        expect(firstTracker.lastIds, isEmpty);
      },
    );

    test('discards a late room save after the site is forgotten', () async {
      final controlled = _ControlledVoiceTransport(
        responses: {'GET /voice/rooms.json': fixture('directory')},
      )..heldPluginWritePaths.add('/voice/rooms.json');
      useTransport(controlled);

      final save = controller.saveRoom(
        siteUrl: firstSite,
        draft: const VoiceRoomDraft(
          name: 'Late room',
          isPublic: true,
          type: VoiceRoomType.open,
        ),
      );
      await pumpEventQueue();
      expect(controlled.pendingPluginWrites, hasLength(1));

      controller.forget(firstSite);
      controlled.pendingPluginWrites.single.response.complete({
        'room': fixture('room'),
      });

      expect(await save, isNull);
      expect(controller.directory(firstSite), isNull);
      expect(controller.errorFor(firstSite), isNull);
    });

    test('discards a late Chat send after the site is forgotten', () async {
      final controlled = _ControlledVoiceTransport()
        ..heldPluginWritePaths.add('/voice/rooms/7/chat_session.json');
      useTransport(controlled);

      final send = controller.sendChatMessage(firstSite, 7, 'hello');
      await pumpEventQueue();
      expect(controlled.pendingPluginWrites, hasLength(1));

      controller.forget(firstSite);
      controlled.pendingPluginWrites.single.response.complete(fixture('chat'));
      await send;

      expect(controller.chat(firstSite, 7), isNull);
      expect(controller.errorFor(firstSite), isNull);
    });
  });

  group('room Chat request ordering', () {
    test(
      'preserves the newer association when an older response arrives late',
      () async {
        final controlled = _ControlledVoiceTransport()
          ..heldPluginPaths.add('/voice/rooms/7/chat_session.json');
        final conversations = FakeChatConversationCapability();
        conversations.seed(
          siteUrl: firstSite,
          channelId: 42,
          threadId: 99,
          snapshot: ChatConversationSnapshot(messages: _chatPage(20).messages),
        );
        useTransport(controlled, conversations: conversations);

        final older = controller.openChat(firstSite, 7, force: true);
        await pumpEventQueue();
        final newer = controller.openChat(firstSite, 7, force: true);
        await pumpEventQueue();
        controlled.pendingPluginGets[1].response.complete(fixture('chat'));
        await newer;
        controlled.pendingPluginGets[0].response.complete(fixture('chat'));
        await older;

        expect(
          controller.chat(firstSite, 7)?.messages.map((message) => message.id),
          [20],
        );
        expect(conversations.opened, hasLength(1));
      },
    );

    test(
      'pages through the Chat conversation capability without rereading credentials',
      () async {
        final controlled = _ControlledVoiceTransport(
          responses: {'GET /voice/rooms/7/chat_session.json': fixture('chat')},
        );
        final countingRequests = _CountingRequestHost();
        requests = countingRequests;
        useTransport(controlled);
        await controller.openChat(firstSite, 7);
        final conversation = chatConversations.find(
          siteUrl: firstSite,
          channelId: 42,
          threadId: 99,
        )!;
        expect(countingRequests.credentialCalls, 1);

        await controller.loadOlderChat(firstSite, 7);

        expect(
          controller.chat(firstSite, 7)?.messages.map((message) => message.id),
          [5, 10],
        );
        expect(conversation.loadOlderCalls, 1);
        expect(countingRequests.credentialCalls, 1);
      },
    );
  });

  group('live tracking and media signaling', () {
    for (final withoutTracker in [false, true]) {
      test('tracker attachment retains served cursors without delivery '
          '(initial tracker: ${!withoutTracker})', () async {
        if (withoutTracker) useTransport(transport, trackerLookup: (_) => null);
        await controller.ensureLoaded(firstSite);
        for (final cursor in [200, 100]) {
          transport.responses['GET /voice/rooms.json'] = {
            'index_message_bus_last_id': cursor,
            'rooms': [
              {...fixture('room'), 'message_bus_last_id': cursor},
            ],
          };
          await controller.ensureLoaded(firstSite, force: true);
        }

        final replacement = tracker(firstSite);
        controller.attachTracker(firstSite, replacement);

        expect(replacement.lastIds['/voice/rooms/index'], 200);
        expect(replacement.lastIds['/voice/rooms/7'], 200);
      });
    }

    test(
      'room-list join loading notifies once per effective transition',
      () async {
        final connectStarted = Completer<void>();
        final connectGate = Completer<void>();
        mediaFactory
          ..nextConnectStarted = connectStarted
          ..nextConnectGate = connectGate;
        addTearDown(() {
          if (!connectGate.isCompleted) connectGate.complete();
        });
        final loading = <bool>[];
        controller.roomListenable.addListener(
          () => loading.add(controller.isJoining(firstSite, 7)),
        );

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await connectStarted.future;
        expect(loading, [true]);
        connectGate.complete();
        await joining;

        expect(loading, [true, false]);
      },
    );

    for (final replacement in [false, true]) {
      test(
        'ignores queued directory callbacks after '
        '${replacement ? 'tracker replacement' : 'account retirement'}',
        () async {
          final queued = _QueuedCallbackTracker();
          firstTracker = queued;
          await controller.ensureLoaded(firstSite);
          final directoryCallback = queued.callbacks['/voice/rooms/index']!;
          final roomCallback = queued.callbacks['/voice/rooms/7']!;
          final next = tracker(firstSite);
          if (replacement) {
            controller.attachTracker(firstSite, next);
          } else {
            controller.forget(firstSite);
            await controller.ensureLoaded(firstSite);
            controller.attachTracker(firstSite, next);
          }
          var notifications = 0;
          controller.roomListenable.addListener(() => notifications++);
          final directory = controller.directory(firstSite);

          directoryCallback(renamedRoomEvent(type: 'destroyed'), 999);
          roomCallback(speakerRosterEvent('retired'), 999);

          expect(controller.directory(firstSite), same(directory));
          expect(notifications, 0);
          final lastTracker = tracker(firstSite);
          controller.attachTracker(firstSite, lastTracker);
          expect(lastTracker.lastIds['/voice/rooms/index'], 144);
          expect(lastTracker.lastIds['/voice/rooms/7'], 91);
        },
      );
    }

    test(
      'subscribe from both snapshot cursors and apply live roster updates',
      () async {
        await controller.ensureLoaded(firstSite);

        expect(firstTracker.lastIds['/voice/rooms/index'], 144);
        expect(firstTracker.lastIds['/voice/rooms/7'], 91);

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 2, 'username': 'lee', 'role': 'speaker'},
          ],
        });
        expect(
          controller.room(firstSite, 7)?.participants.single.username,
          'lee',
        );

        firstTracker.deliver('/voice/rooms/index', {
          'type': 'updated',
          'room': {
            'id': 7,
            'name': 'Renamed Room',
            'slug': 'conf-room-1',
            'public': false,
            'ephemeral': false,
            'room_type': 'stage',
            'active_participants': const <Object?>[],
          },
        });
        expect(controller.room(firstSite, 7)?.name, 'Renamed Room');
      },
    );

    test(
      'transfer only Voice-owned watches when the tracker changes',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.openChat(firstSite, 7);
        final replacement = tracker(firstSite);

        controller.attachTracker(firstSite, replacement);

        for (final channel in const ['/voice/rooms/index', '/voice/rooms/7']) {
          expect(firstTracker.subscriberCount(channel), 0);
          expect(replacement.subscriberCount(channel), 1);
        }
        expect(firstTracker.subscriberCount('/chat/42'), 0);
        expect(replacement.subscriberCount('/chat/42'), 0);
        expect(replacement.lastIds['/voice/rooms/index'], 144);
        expect(replacement.lastIds['/voice/rooms/7'], 91);

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 2, 'username': 'old', 'role': 'speaker'},
          ],
        });
        expect(
          controller
              .room(firstSite, 7)
              ?.participants
              .map((participant) => participant.username),
          ['sam'],
        );

        replacement.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 3, 'username': 'new', 'role': 'speaker'},
          ],
        });
        expect(
          controller.room(firstSite, 7)?.participants.single.username,
          'new',
        );
      },
    );

    test(
      'apply a directory event without re-subscribing the directory channel',
      () async {
        final counting = _CountingTracker();
        firstTracker = counting;
        await controller.ensureLoaded(firstSite);
        expect(counting.subscribeCounts, {
          '/voice/rooms/index': 1,
          '/voice/call-ring/1': 1,
          '/voice/rooms/7': 1,
        });

        counting.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(),
          messageId: 145,
        );

        expect(controller.room(firstSite, 7)?.name, 'Renamed Room');
        expect(counting.subscribeCounts, {
          '/voice/rooms/index': 1,
          '/voice/call-ring/1': 1,
          '/voice/rooms/7': 1,
        });
        expect(counting.subscriberCount('/voice/rooms/index'), 1);
      },
    );

    test(
      'reuse live subscriptions across repeated and forced directory loads',
      () async {
        final counting = _CountingTracker();
        firstTracker = counting;
        await controller.ensureLoaded(firstSite);

        await controller.ensureLoaded(firstSite);
        expect(counting.subscribeCounts, {
          '/voice/rooms/index': 1,
          '/voice/call-ring/1': 1,
          '/voice/rooms/7': 1,
        });

        await controller.ensureLoaded(firstSite, force: true);
        expect(counting.subscribeCounts, {
          '/voice/rooms/index': 1,
          '/voice/call-ring/1': 1,
          '/voice/rooms/7': 1,
        });
      },
    );

    test('reuse live subscriptions across a join', () async {
      final counting = _CountingTracker();
      firstTracker = counting;
      await controller.ensureLoaded(firstSite);

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      expect(counting.subscribeCounts, {
        '/voice/rooms/index': 1,
        '/voice/call-ring/1': 1,
        '/voice/rooms/7': 1,
      });
    });

    test(
      'resume a replacement tracker from the last delivered directory id',
      () async {
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(),
          messageId: 145,
        );
        final replacement = tracker(firstSite);

        controller.attachTracker(firstSite, replacement);

        expect(replacement.lastIds['/voice/rooms/index'], 145);
        expect(replacement.lastIds['/voice/rooms/7'], 91);
      },
    );

    test(
      'resume a replacement tracker from the last delivered room id',
      () async {
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver(
          '/voice/rooms/7',
          speakerRosterEvent('lee'),
          messageId: 95,
        );
        final replacement = tracker(firstSite);

        controller.attachTracker(firstSite, replacement);

        expect(replacement.lastIds['/voice/rooms/7'], 95);
        expect(replacement.lastIds['/voice/rooms/index'], 144);
      },
    );

    test(
      'advance both cursors past messages the client does not understand',
      () async {
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(type: 'archived'),
          messageId: 146,
        );
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'archived',
        }, messageId: 96);
        final replacement = tracker(firstSite);

        controller.attachTracker(firstSite, replacement);

        expect(controller.room(firstSite, 7)?.name, 'Conf Room 1');
        expect(replacement.lastIds['/voice/rooms/index'], 146);
        expect(replacement.lastIds['/voice/rooms/7'], 96);
      },
    );

    test(
      'keep a delivered id below the snapshot cursor from moving it back',
      () async {
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(),
          messageId: 1,
        );
        firstTracker.deliver(
          '/voice/rooms/7',
          speakerRosterEvent('lee'),
          messageId: 1,
        );
        final replacement = tracker(firstSite);

        controller.attachTracker(firstSite, replacement);

        expect(replacement.lastIds['/voice/rooms/index'], 144);
        expect(replacement.lastIds['/voice/rooms/7'], 91);
      },
    );

    test(
      'keep the held room cursor when a directory update carries none or an older one',
      () async {
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/rooms/index', renamedRoomEvent());
        firstTracker.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(messageBusLastId: 90),
        );
        final replacement = tracker(firstSite);

        controller.attachTracker(firstSite, replacement);

        expect(replacement.lastIds['/voice/rooms/7'], 91);
      },
    );

    test(
      'resume a replacement tracker from the delivered ids after a forced reload served older ones',
      () async {
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(),
          messageId: 145,
        );
        firstTracker.deliver(
          '/voice/rooms/7',
          speakerRosterEvent('lee'),
          messageId: 95,
        );
        await controller.ensureLoaded(firstSite, force: true);
        final replacement = tracker(firstSite);

        controller.attachTracker(firstSite, replacement);

        expect(replacement.lastIds['/voice/rooms/index'], 145);
        expect(replacement.lastIds['/voice/rooms/7'], 95);
      },
    );

    group('a forced reload answered after a live event', () {
      late _ControlledVoiceTransport controlled;
      late Future<void> reloading;

      Map<String, dynamic> listing(List<Map<String, dynamic>> rooms) => {
        'rooms': rooms,
        'can_create_room': true,
        'index_message_bus_last_id': 144,
      };

      setUp(() async {
        controlled = _ControlledVoiceTransport(
          responses: {
            'GET /voice/rooms.json': listing([fixture('room')]),
          },
        );
        useTransport(controlled);
        await controller.ensureLoaded(firstSite);
      });

      Future<void> requestReload() async {
        controlled.heldPluginPaths.add('/voice/rooms.json');
        reloading = controller.ensureLoaded(firstSite, force: true);
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));
      }

      Future<void> answerReload([Map<String, dynamic>? room]) async {
        controlled.pendingPluginGets
            .removeAt(0)
            .response
            .complete(listing([room ?? fixture('room')]));
        await reloading;
      }

      List<String> roster() => [
        for (final participant in controller.room(firstSite, 7)!.participants)
          participant.username,
      ];

      test('keeps a rename received after it was requested', () async {
        await requestReload();
        firstTracker.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(),
          messageId: 145,
        );

        await answerReload();

        expect(controller.room(firstSite, 7)?.name, 'Renamed Room');
      });

      test(
        'takes the reload over a kick, which carries no room state',
        () async {
          await requestReload();
          firstTracker.deliver('/voice/rooms/7', {
            'type': 'kicked',
            'room_id': 7,
          }, messageId: 95);

          await answerReload({...fixture('room'), 'name': 'Reloaded Room'});

          expect(controller.room(firstSite, 7)?.name, 'Reloaded Room');
        },
      );

      test('keeps a roster received after it was requested', () async {
        await requestReload();
        firstTracker.deliver(
          '/voice/rooms/7',
          speakerRosterEvent('kim'),
          messageId: 95,
        );

        await answerReload();

        expect(roster(), ['kim']);
      });

      test('still takes the user fields broadcasts omit', () async {
        await requestReload();
        firstTracker.deliver(
          '/voice/rooms/7',
          speakerRosterEvent('kim'),
          messageId: 95,
        );

        await answerReload({
          ...fixture('room'),
          'can_manage': false,
          'can_invite': false,
          'membership': null,
        });

        final room = controller.room(firstSite, 7)!;
        expect(room.canManage, isFalse);
        expect(room.canInvite, isFalse);
        expect(room.membership, isNull);
        expect(roster(), ['kim']);
      });

      test(
        'does not bring back a room destroyed after it was requested',
        () async {
          await requestReload();
          firstTracker.deliver(
            '/voice/rooms/index',
            renamedRoomEvent(type: 'destroyed'),
            messageId: 145,
          );

          await answerReload();

          expect(controller.room(firstSite, 7), isNull);
          expect(controller.directory(firstSite)?.rooms, isEmpty);
          expect(firstTracker.subscriberCount('/voice/rooms/7'), 0);
        },
      );

      test('keeps a room created after it was requested', () async {
        await requestReload();
        firstTracker.deliver('/voice/rooms/index', {
          'type': 'created',
          'room': {'id': 99, 'name': 'New room', 'slug': 'new-room'},
        }, messageId: 145);

        await answerReload();

        expect(controller.directory(firstSite)?.rooms.map((room) => room.id), [
          7,
          99,
        ]);
        expect(firstTracker.subscriberCount('/voice/rooms/99'), 1);
      });

      test('applies a reload requested after the event', () async {
        firstTracker.deliver(
          '/voice/rooms/index',
          renamedRoomEvent(),
          messageId: 145,
        );
        firstTracker.deliver(
          '/voice/rooms/7',
          speakerRosterEvent('kim'),
          messageId: 95,
        );
        await requestReload();

        await answerReload({...fixture('room'), 'name': 'Edited room'});

        expect(controller.room(firstSite, 7)?.name, 'Edited room');
        expect(roster(), ['lee', 'sam']);
      });

      test(
        'lists a room a reload requested after its destroy still lists',
        () async {
          firstTracker.deliver(
            '/voice/rooms/index',
            renamedRoomEvent(type: 'destroyed'),
            messageId: 145,
          );
          expect(controller.room(firstSite, 7), isNull);
          await requestReload();

          await answerReload();

          expect(controller.room(firstSite, 7)?.name, 'Conf Room 1');
        },
      );
    });

    test(
      'update microphone publication when the local stage role changes',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 1, 'username': 'sam', 'role': 'participant'},
          ],
        });
        await Future<void>.delayed(Duration.zero);
        expect(media.audioPublishingAllowed, isFalse);

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'role_change',
          'user_id': 1,
          'role': 'speaker',
        });
        await Future<void>.delayed(Duration.zero);
        expect(media.audioPublishingAllowed, isTrue);

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 1, 'username': 'sam', 'role': 'speaker'},
          ],
        });
        await Future<void>.delayed(Duration.zero);
        expect(media.audioPublishingAllowed, isTrue);
      },
    );

    test(
      'silence a demoted speaker before the publishing change settles',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'role_change',
          'user_id': 1,
          'role': 'speaker',
        });
        await pumpEventQueue();
        await controller.setMuted(false);
        expect(media.muted, isFalse);
        final publishing = Completer<void>();
        media.audioPublishingGate = publishing;
        addTearDown(() {
          if (!publishing.isCompleted) publishing.complete();
        });

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'role_change',
          'user_id': 1,
          'role': 'participant',
        });
        await pumpEventQueue();

        expect(controller.call?.muted, isTrue);
        expect(media.muted, isTrue);
        publishing.complete();
        await pumpEventQueue();
        expect(media.audioPublishingAllowed, isFalse);
        expect(media.muted, isTrue);
      },
    );

    test('reference-count room video watches across calls', () async {
      controller.watchRoomVideo(siteUrl: firstSite, roomId: 7);
      controller.watchRoomVideo(siteUrl: firstSite, roomId: 7);

      expect(
        transport.writes.where((write) => write.path.endsWith('/state.json')),
        isEmpty,
      );

      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      await pumpEventQueue();

      var stateWrites = transport.writes
          .where((write) => write.path.endsWith('/state.json'))
          .toList();
      expect(stateWrites, isNotEmpty);
      expect(
        stateWrites.every((write) => write.body.containsKey('watching')),
        isTrue,
      );
      expect(stateWrites.last.body['watching'], isTrue);

      await controller.leave();
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      await pumpEventQueue();
      stateWrites = transport.writes
          .where((write) => write.path.endsWith('/state.json'))
          .toList();
      expect(stateWrites.last.body['watching'], isTrue);

      controller.stopWatchingRoomVideo(siteUrl: firstSite, roomId: 7);
      await pumpEventQueue();
      expect(
        transport.writes.where((write) => write.path.endsWith('/state.json')),
        hasLength(stateWrites.length),
      );

      controller.stopWatchingRoomVideo(siteUrl: firstSite, roomId: 7);
      await pumpEventQueue();
      stateWrites = transport.writes
          .where((write) => write.path.endsWith('/state.json'))
          .toList();
      expect(stateWrites.last.body['watching'], isFalse);
      expect(
        stateWrites.every((write) => write.body.containsKey('watching')),
        isTrue,
      );
    });

    test('contains asynchronous signal and roster-media failures', () async {
      await pumpEventQueue();
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single
        ..signalFailure = StateError('signal rejected')
        ..audioPublishingFailure = StateError('publishing rejected')
        ..muteFailure = StateError('mute rejected')
        ..participantSyncFailure = StateError('roster rejected');

      firstTracker.deliver('/voice/rooms/7', {
        'type': 'signal',
        'sender_id': 2,
        'data': {'type': 'offer'},
      });
      firstTracker.deliver('/voice/rooms/7', {
        'type': 'participants',
        'participants': [
          {'id': 1, 'username': 'sam', 'role': 'participant'},
        ],
      });
      await pumpEventQueue();

      expect(controller.call?.muted, isTrue);
      expect(media.audioPublishingAllowed, isFalse);
      expect(media.participants.single.id, 1);
    });

    for (final retirement in ['call replacement', 'account replacement']) {
      for (final blockedAt in ['roster sync', 'first signal']) {
        test(
          'signal batch preserves $blockedAt ordering across $retirement',
          () async {
            final joinPayload = fixture('join_mesh');
            transport.responses['POST /voice/rooms/7/join.json'] = joinPayload;
            await controller.ensureLoaded(firstSite);
            await controller.join(
              siteUrl: firstSite,
              siteName: 'One',
              room: controller.room(firstSite, 7)!,
            );
            final media = mediaFactory.sessions.single;
            final started = Completer<void>();
            final release = Completer<void>();
            addTearDown(() {
              if (!release.isCompleted) release.complete();
            });
            Future<void> block() async {
              if (!started.isCompleted) started.complete();
              await release.future;
            }

            if (blockedAt == 'roster sync') {
              media.onSyncParticipants = block;
            } else {
              media.onHandleSignal = block;
            }
            firstTracker.deliver('/voice/rooms/7', {
              'type': 'signal',
              'sender_id': 2,
              'sender': {'id': 2, 'username': 'early'},
              'events': [
                for (var i = 0; i < 30; i++) {'type': 'offer', 'sdp': '$i'},
              ],
            });
            await started.future;
            expect(controller.call?.room.participants.map((p) => p.id), [2, 1]);
            if (retirement == 'account replacement') {
              controller.forget(firstSite);
              await pumpEventQueue();
              await controller.ensureLoaded(firstSite);
            } else {
              await controller.leave();
            }
            await controller.join(
              siteUrl: firstSite,
              siteName: 'One',
              room: controller.room(firstSite, 7)!,
            );
            final replacement = mediaFactory.sessions.last;
            expect(replacement, isNot(same(media)));
            release.complete();
            await pumpEventQueue();
            expect(
              media.signals.map((s) => s.$2['sdp']),
              blockedAt == 'roster sync'
                  ? isEmpty
                  : [for (var i = 0; i < 25; i++) '$i'],
            );
            expect(replacement.signals, isEmpty);
            expect(controller.call?.media, same(replacement));
          },
        );
      }
    }

    test('an unattested early sender cannot enter the roster', () async {
      transport.responses['POST /voice/rooms/7/join.json'] = fixture(
        'join_mesh',
      );
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      firstTracker.deliver('/voice/rooms/7', {
        'type': 'signal',
        'sender_id': 2,
        'sender': {'id': 3, 'username': 'impostor'},
        'data': {'type': 'offer', 'sdp': 'legacy'},
      });
      await pumpEventQueue();
      expect(controller.call?.room.participants.map((p) => p.id), [1]);
      final signal = mediaFactory.sessions.single.signals.single;
      expect(signal.$1, 2);
      expect(signal.$2, {'type': 'offer', 'sdp': 'legacy'});
    });

    group('signal sender admission', () {
      const offer = {'type': 'offer', 'sdp': 'private-offer'};
      const candidate = {
        'type': 'candidate',
        'candidate': {'candidate': 'private-candidate'},
      };

      final overflowedEnvelope =
          jsonDecode(
                '{"type":"signal","sender_id":1e400,'
                '"events":[{"type":"offer","sdp":"overflowed-offer"}]}',
              )
              as Map<String, dynamic>;

      for (final (label, sender) in <(String, Object?)>[
        ('fractional', 2.9),
        ('zero', 0),
        ('negative', -2),
        ('infinite', double.infinity),
        ('negative infinite', double.negativeInfinity),
        ('NaN', double.nan),
        ('out-of-range integral', 9223372036854775808.0),
        ('oversized finite', 1e100),
        ('numeric string', '2'),
        ('boolean', true),
        ('missing', null),
        ('JSON numeric overflow', overflowedEnvelope['sender_id']),
      ]) {
        test('rejects $label sender', () async {
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          // Keep user 2 in the authoritative roster: 2.9 must never route
          // to that participant by truncating its fractional part.
          firstTracker.deliver('/voice/rooms/7', {
            'type': 'participants',
            'participants': [
              {'id': 1, 'username': 'sam', 'role': 'speaker'},
              {'id': 2, 'username': 'lee', 'role': 'speaker'},
            ],
          });
          await pumpEventQueue();
          final media = mediaFactory.sessions.single;
          final participants = media.participants;
          final activeCall = controller.call;

          for (final envelope in <Map<String, dynamic>>[
            if (label == 'JSON numeric overflow')
              overflowedEnvelope
            else
              {
                'type': 'signal',
                'sender_id': ?sender,
                'sender': {'id': 2, 'username': 'private-sender'},
                'events': [offer, candidate],
              },
            {'type': 'signal', 'sender_id': ?sender, 'data': offer},
            {'type': 'signal', 'sender_id': ?sender, 'data': candidate},
          ]) {
            firstTracker.deliver('/voice/rooms/7', envelope);
          }
          await pumpEventQueue();

          expect(media.signals, isEmpty);
          expect(media.participants, same(participants));
          expect(controller.call, same(activeCall));
          expect(controller.errorFor(firstSite), isNull);

          firstTracker.deliver('/voice/rooms/7', {
            'type': 'signal',
            'sender_id': 2.0,
            'events': [offer, candidate],
          });
          await pumpEventQueue();

          expect(media.signals.map((signal) => signal.$1), [2, 2]);
          expect(media.signals.map((signal) => signal.$2), [offer, candidate]);
        });
      }
    });

    for (final (roomType, sender) in [
      ('open', 2),
      ('open', 2.0),
      ('stage', 2),
      ('stage', 2.0),
    ]) {
      test(
        'preserve ordered signals and $roomType roster admission for sender $sender',
        () async {
          final joinPayload = fixture('join_mesh');
          final room = joinPayload['room']! as Map<String, dynamic>;
          room['room_type'] = roomType;
          room['active_participants'] = [
            {'id': 1, 'username': 'sam', 'role': 'participant'},
          ];
          useTransport(
            RecordingPluginTransport(
              responses: {
                'GET /voice/rooms.json': fixture('directory'),
                'POST /voice/rooms/7/join.json': joinPayload,
                'POST /voice/rooms/7/state.json': <String, dynamic>{},
                'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
                'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
              },
            ),
          );
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );

          final media = mediaFactory.sessions.single;
          final initialParticipants = media.participants;
          firstTracker.deliver('/voice/rooms/7', {
            'type': 'signal',
            'sender_id': 2.9,
            'sender': {'id': sender, 'username': 'early'},
            'events': [
              {'type': 'offer', 'sdp': 'fractional-sender-offer'},
            ],
          });
          await pumpEventQueue();
          expect(media.signals, isEmpty);
          expect(media.participants, same(initialParticipants));
          expect(controller.call?.room.participants.map((p) => p.id), [1]);

          firstTracker.deliver('/voice/rooms/7', {
            'type': 'signal',
            'sender_id': sender,
            'sender': {'id': sender, 'username': 'early'},
            'events': [
              {'type': 'offer', 'sdp': 'offer'},
              {
                'type': 'candidate',
                'candidate': {'candidate': 'candidate:first'},
              },
            ],
          });
          await pumpEventQueue();
          firstTracker.deliver('/voice/rooms/7', {
            'type': 'signal',
            'sender_id': sender,
            'data': {'type': 'answer', 'sdp': 'legacy-answer'},
          });
          await pumpEventQueue();

          expect(
            media.participants.map((participant) => participant.id),
            roomType == 'open'
                ? [2, 1]
                : initialParticipants.map((participant) => participant.id),
          );
          expect(media.signals.map((signal) => signal.$1), [2, 2, 2]);
          expect(media.signals.map((signal) => signal.$2['type']), [
            'offer',
            'candidate',
            'answer',
          ]);
          expect(
            controller.call?.room.participants.first.username,
            roomType == 'open' ? 'early' : 'sam',
          );
        },
      );
    }
  });

  group('media reconnect failures', () {
    for (final failureCase in [
      (
        failure: const WriteException(
          WriteFailure.validation,
          statusCode: 422,
          errors: ['This room is full.'],
        ),
        message: 'This room is full.',
      ),
      (
        failure: const WriteException(
          WriteFailure.validation,
          statusCode: 422,
          errors: ['A different refusal.', 'Please try again.'],
        ),
        message: 'A different refusal.\nPlease try again.',
      ),
      (
        failure: const WriteException(WriteFailure.validation, statusCode: 422),
        message: "That wasn't accepted.",
      ),
      (
        failure: StateError('private SDK detail'),
        message: 'The media connection could not be restored.',
      ),
    ]) {
      test(
        'surfaces ${failureCase.message} and clears it on recovery',
        () async {
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          final media = mediaFactory.sessions.single;
          media.connectionState = VoiceMediaConnectionState.reconnecting;
          media.notifyListeners();
          media.connectionFailure = failureCase.failure;
          media.connectionState = VoiceMediaConnectionState.failed;
          media.notifyListeners();
          expect(controller.call?.status, VoiceCallStatus.failed);
          expect(controller.call?.error, failureCase.message);
          expect(media.disposeCount, 0);

          media.connectionFailure = null;
          media.connectionState = VoiceMediaConnectionState.reconnecting;
          media.notifyListeners();
          expect(controller.call?.error, isNull);
          media.connectionState = VoiceMediaConnectionState.connected;
          media.notifyListeners();
          expect(controller.call?.status, VoiceCallStatus.connected);
          expect(controller.call?.error, isNull);
        },
      );
    }

    test(
      'an ended instance tears down locally and allows a new join',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        const message =
            'This call has ended. Rejoin the room to start a new one.';
        media.connectionFailure = const WriteException(
          WriteFailure.validation,
          statusCode: 410,
          errors: [message],
        );
        media.connectionState = VoiceMediaConnectionState.failed;
        media.notifyListeners();
        await pumpEventQueue();
        expect(controller.call, isNull);
        expect(controller.errorFor(firstSite), message);
        expect(media.disposeCount, 1);
        expect(systemCall.ends, 1);
        expect(
          transport.writes.where((write) => write.path.endsWith('/leave.json')),
          isEmpty,
        );

        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(controller.errorFor(firstSite), isNull);
        expect(controller.call?.media, isNot(same(media)));
      },
    );

    test(
      'a refused token keeps its cause and session until refresh recovers',
      () async {
        transport.responses['POST /voice/rooms/7/join.json'] = fixture(
          'join_livekit',
        );
        const refusal = WriteException(
          WriteFailure.validation,
          statusCode: 422,
          errors: ['This room is full.'],
        );
        transport.responders['POST /voice/rooms/7/livekit_token.json'] = (_) =>
            throw refusal;
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        await expectLater(
          media.refreshLiveKitCredentials(),
          throwsA(same(refusal)),
        );
        await controller.setMuted(true);
        final stateBeforeRecovery = transport.writes.lastWhere(
          (write) => write.path.endsWith('/state.json'),
        );
        expect(
          stateBeforeRecovery.body['participant_session_id'],
          fixture('join_livekit')['participant_session_id'],
        );

        transport.responders.remove('POST /voice/rooms/7/livekit_token.json');
        transport.responses['POST /voice/rooms/7/livekit_token.json'] = {
          ...(fixture('join_livekit')['livekit'] as Map<String, dynamic>),
          'participant_session_id': 'recovered-session',
        };
        await media.refreshLiveKitCredentials();
        await controller.setMuted(false);
        final stateAfterRecovery = transport.writes.lastWhere(
          (write) => write.path.endsWith('/state.json'),
        );
        expect(
          stateAfterRecovery.body['participant_session_id'],
          'recovered-session',
        );
      },
    );
  });

  group('call commands', () {
    Future<_ControlledVoiceTransport> joinCommands() async {
      final controlled = privilegedTransport();
      useTransport(controlled);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: VoiceRoom.fromJson(fixture('room')),
      );
      return controlled;
    }

    test(
      'dispatches through each credential capability without changing the roster',
      () async {
        requests = _ScopedRequestHost();
        final controlled = await joinCommands();
        final scopes = <String, Object?>{};
        for (final path in [
          '/voice/rooms/7/request_to_speak.json',
          '/voice/rooms/7/memberships.json',
          '/voice/rooms/7/kick.json',
          '/voice/rooms/7/flag.json',
          '/voice/rooms/7/recording.json',
          '/site.json',
        ]) {
          final method = path == '/site.json'
              ? 'GET'
              : path.endsWith('/kick.json')
              ? 'DELETE'
              : 'POST';
          controlled.responders['$method $path'] = (_) {
            scopes[path] = Zone.current[_ScopedRequestHost.scope];
            return controlled.responses['$method $path']!;
          };
        }
        final participants = controller.call!.room.participants;
        await controller.requestToSpeak(userId: 2);
        await controller.setParticipantRole(2, VoiceRole.speaker);
        await controller.kick(2);
        expect(
          await controller.flagParticipant(2, '  Please review  '),
          isTrue,
        );
        await controller.setRecording(true);

        expect(scopes, {
          '/voice/rooms/7/request_to_speak.json': 'key',
          '/voice/rooms/7/memberships.json': 'full',
          '/voice/rooms/7/kick.json': 'key',
          '/site.json': 'full',
          '/voice/rooms/7/flag.json': 'key',
          '/voice/rooms/7/recording.json': 'key',
        });
        expect(controller.call!.room.participants, same(participants));
        expect(
          controlled.writes
              .singleWhere((w) => w.path.endsWith('/flag.json'))
              .body,
          {'user_id': 2, 'flag_type_id': 3, 'message': 'Please review'},
        );
      },
    );

    test('retains silent failures and false flag results', () async {
      final controlled = await joinCommands();
      controlled.operationFailure = StateError('request failed');
      final uncaught = await _captureUncaught(() async {
        await controller.requestToSpeak();
        await controller.setParticipantRole(2, VoiceRole.speaker);
        await controller.kick(2);
        expect(await controller.flagParticipant(2, 'Please review'), isFalse);
        await controller.setRecording(true);
      });
      expect(uncaught, isEmpty);
      expect(controller.call!.error, isNull);
    });

    test(
      'does not flag after the call changes during flag-type lookup',
      () async {
        final controlled = await joinCommands();
        controlled.heldPluginPaths.add('/site.json');
        final flagging = controller.flagParticipant(2, 'Please review');
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));
        await controller.leave();
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        controlled.pendingPluginGets.single.response.complete({
          'post_action_types': [
            {'name_key': 'notify_moderators', 'id': 3},
          ],
        });
        expect(await flagging, isFalse);
        expect(
          controlled.writes.where((w) => w.path.endsWith('/flag.json')),
          isEmpty,
        );
      },
    );

    test('rejects a deferred dispatch after its call is replaced', () async {
      final deferred = _DeferredRequestHost();
      requests = deferred;
      final controlled = await joinCommands();
      deferred.deferNextRun = true;
      final kicking = controller.kick(2);
      await deferred.runStarted.future;
      await controller.leave();
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: VoiceRoom.fromJson(fixture('room')),
      );
      deferred.runGate.complete();
      await kicking;
      expect(
        controlled.writes.where((w) => w.path.endsWith('/kick.json')),
        isEmpty,
      );
    });

    test(
      'does not flag after replacement during write credential lookup',
      () async {
        final gated = _NextGatedRequestHost();
        requests = gated;
        final controlled = await joinCommands();
        controlled.responders['GET /site.json'] = (_) {
          gated.gateNextRead = true;
          return controlled.responses['GET /site.json']!;
        };
        final flagging = controller.flagParticipant(2, 'Please review');
        await gated.readStarted.future;
        await controller.leave();
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        gated.readGate.complete();
        expect(await flagging, isFalse);
        expect(
          controlled.writes.where((w) => w.path.endsWith('/flag.json')),
          isEmpty,
        );
      },
    );

    test('returns false when the flag type is unavailable', () async {
      final controlled = await joinCommands();
      controlled.responses['GET /site.json'] = {};
      expect(await controller.flagParticipant(2, 'Please review'), isFalse);
      expect(
        controlled.writes.where((w) => w.path.endsWith('/flag.json')),
        isEmpty,
      );
    });

    test('recording remains independent of a pending kick', () async {
      final controlled = await joinCommands();
      controlled.heldPluginWritePaths.add('/voice/rooms/7/kick.json');
      final kicking = controller.kick(2);
      await controlled.waitForPendingPluginWrites(1);
      await controller.setRecording(true);
      expect(
        controlled.writes.where((w) => w.path.endsWith('/recording.json')),
        hasLength(1),
      );
      controlled.pendingPluginWrites.single.response.complete({});
      await kicking;
    });
  });

  group('participant session propagation', () {
    test(
      'raise hand keeps its admitted session across token refresh',
      () async {
        final gated = _NextGatedRequestHost();
        requests = gated;
        transport.responses.addAll({
          'POST /voice/rooms/7/join.json': fixture('join_livekit'),
          'POST /voice/rooms/7/livekit_token.json': {
            ...(fixture('join_livekit')['livekit'] as Map<String, dynamic>),
            'participant_session_id': 'refreshed-session',
          },
          'POST /voice/rooms/7/request_to_speak.json': <String, dynamic>{},
        });
        useTransport(transport);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        gated.gateNextRead = true;
        final raising = controller.requestToSpeak();
        await gated.readStarted.future;
        await mediaFactory.sessions.single.refreshLiveKitCredentials();
        gated.readGate.complete();
        await raising;
        await controller.requestToSpeak();
        final raises = transport.writes.where(
          (w) => w.path.endsWith('/request_to_speak.json'),
        );
        expect(raises.map((w) => w.body['participant_session_id']), [
          fixture('join_livekit')['participant_session_id'],
          'refreshed-session',
        ]);
      },
    );

    test('includes the joined session on protected writes', () async {
      transport.responses.addAll({
        'POST /voice/rooms/7/signal.json': <String, dynamic>{},
        'POST /voice/rooms/7/request_to_speak.json': <String, dynamic>{},
      });
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;

      await media.sendSignal(2, {'type': 'offer', 'sdp': 'offer'});
      await controller.requestToSpeak();
      await controller.setMuted(true);
      await controller.leave();

      final protected = transport.writes.where(
        (write) => {
          '/voice/rooms/7/signal.json',
          '/voice/rooms/7/request_to_speak.json',
          '/voice/rooms/7/state.json',
          '/voice/rooms/7/heartbeat.json',
          '/voice/rooms/7/leave.json',
        }.contains(write.path),
      );
      expect(protected, isNotEmpty);
      expect(
        protected.every(
          (write) =>
              write.body['participant_session_id'] ==
              'mesh-participant-session',
        ),
        isTrue,
      );
      final signal = protected.singleWhere(
        (write) => write.path.endsWith('/signal.json'),
      );
      expect(
        (signal.body['payload']! as Map<String, Object?>)['messages'],
        isNotEmpty,
      );
    });

    test('adopts a session rotated by LiveKit token refresh', () async {
      final tokenResponse = <String, dynamic>{
        ...(fixture('join_livekit')['livekit'] as Map<String, dynamic>),
        'participant_session_id': 'rotated-livekit-session',
      };
      useTransport(
        RecordingPluginTransport(
          responses: {
            'GET /voice/rooms.json': fixture('directory'),
            'POST /voice/rooms/7/join.json': fixture('join_livekit'),
            'POST /voice/rooms/7/livekit_token.json': tokenResponse,
            'POST /voice/rooms/7/state.json': <String, dynamic>{},
            'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
            'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
          },
        ),
      );
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      final refreshed = await mediaFactory.sessions.single
          .refreshLiveKitCredentials();
      expect(refreshed.participantSessionId, 'rotated-livekit-session');
      await controller.setMuted(true);
      await controller.leave();

      final stateAndLeave = transport.writes.where(
        (write) =>
            write.path.endsWith('/state.json') ||
            write.path.endsWith('/leave.json'),
      );
      expect(
        stateAndLeave.last.body['participant_session_id'],
        'rotated-livekit-session',
      );
    });
  });

  group('room Chat lifecycle', () {
    for (final fails in [false, true]) {
      test('a retired send cannot change a replacement room Chat '
          '(failure=$fails)', () async {
        final controlled = _ControlledVoiceTransport(
          responses: {
            'GET /voice/rooms.json': fixture('directory'),
            'GET /voice/rooms/7/chat_session.json': {
              'channel_id': 42,
              'thread_id': 100,
            },
          },
        )..heldPluginWritePaths.add('/voice/rooms/7/chat_session.json');
        useTransport(controlled);
        chatConversations.seed(
          siteUrl: firstSite,
          channelId: 42,
          threadId: 100,
          snapshot: ChatConversationSnapshot(messages: _chatPage(20).messages),
        );
        await controller.ensureLoaded(firstSite);
        final sending = controller.sendChatMessage(firstSite, 7, 'old send');
        await controlled.waitForPendingPluginWrites(1);

        firstTracker.deliver('/voice/rooms/index', {
          'type': 'destroyed',
          'room': (fixture('directory')['rooms'] as List<dynamic>).first,
        });
        expect(controller.chat(firstSite, 7), isNull);
        await controller.openChat(firstSite, 7);

        final oldWrite = controlled.pendingPluginWrites.single.response;
        if (fails) {
          oldWrite.completeError(
            const SiteLookupException(SiteLookupFailure.unreachable, 'one'),
          );
        } else {
          oldWrite.complete(fixture('chat'));
        }
        await sending;

        final chat = controller.chat(firstSite, 7)!;
        expect(chat.session.threadId, 100);
        expect(chat.messages.map((message) => message.id), [20]);
        expect(chat.error, isNull);
        expect(chat.sending, isFalse);
        expect(chatConversations.opened.map((key) => key.threadId), [100]);
        expect(firstTracker.subscriberCount('/voice/rooms/7/chat'), 1);
      });
    }

    test(
      'a hidden temporary send releases its handle after retirement',
      () async {
        transport.responses['POST /voice/rooms/7/chat_session.json'] = fixture(
          'chat',
        );
        final conversation = chatConversations.find(
          siteUrl: firstSite,
          channelId: 42,
          threadId: 99,
        )!;
        final gate = Completer<void>();
        conversation.sendGate = gate;
        final sending = controller.sendChatMessage(firstSite, 7, 'hidden');
        await pumpEventQueue();
        expect(conversation.sentMessages, ['hidden']);
        expect(conversation.closeCalls, 0);

        controller.forget(firstSite);
        gate.complete();
        await sending;

        expect(controller.chat(firstSite, 7), isNull);
        expect(conversation.closeCalls, 1);
        expect(firstTracker.subscriberCount('/voice/rooms/7/chat'), 0);
      },
    );

    test(
      'hiding during a first send keeps the write and releases the reader',
      () async {
        final controlled = _ControlledVoiceTransport(
          responses: {
            'GET /voice/rooms/7/chat_session.json': {'channel_id': 42},
          },
        )..heldPluginWritePaths.add('/voice/rooms/7/chat_message.json');
        useTransport(controlled);
        await controller.openChat(firstSite, 7);
        final sending = controller.sendChatMessage(firstSite, 7, 'first');
        await controlled.waitForPendingPluginWrites(1);

        controller.closeChat(firstSite, 7);
        controlled.pendingPluginWrites.single.response.complete(
          fixture('chat'),
        );
        await sending;

        expect(controller.chat(firstSite, 7)?.session.threadId, 99);
        expect(controller.chat(firstSite, 7)?.sending, isFalse);
        expect(controller.chat(firstSite, 7)?.error, isNull);
        expect(chatConversations.opened, isEmpty);
        expect(firstTracker.subscriberCount('/voice/rooms/7/chat'), 0);
        expect(
          controlled.pendingPluginWrites.where(
            (write) => write.path.endsWith('/chat_message.json'),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'loads, pages, and sends through the associated Discourse Chat thread',
      () async {
        await controller.openChat(firstSite, 7);
        final conversation = chatConversations.find(
          siteUrl: firstSite,
          channelId: 42,
          threadId: 99,
        )!;
        expect(
          controller.chat(firstSite, 7)?.messages.map((message) => message.id),
          [10],
        );
        expect(controller.chat(firstSite, 7)?.canLoadMorePast, isTrue);
        expect(conversation.refreshCalls, 1);

        await controller.loadOlderChat(firstSite, 7);
        expect(
          controller.chat(firstSite, 7)?.messages.map((message) => message.id),
          [5, 10],
        );
        expect(controller.chat(firstSite, 7)?.canLoadMorePast, isFalse);
        expect(conversation.loadOlderCalls, 1);

        await controller.sendChatMessage(firstSite, 7, '  hello room  ');
        expect(conversation.sentMessages, ['  hello room  ']);
      },
    );

    test(
      'relays live conversation state and releases it when the site is forgotten',
      () async {
        await controller.openChat(firstSite, 7);
        final conversation = chatConversations.find(
          siteUrl: firstSite,
          channelId: 42,
          threadId: 99,
        )!;
        conversation.setSnapshot(
          ChatConversationSnapshot(
            messages: _chatPage(20).messages,
            error: 'Chat is reconnecting.',
          ),
        );

        expect(
          controller.chat(firstSite, 7)?.messages.map((message) => message.id),
          [20],
        );
        expect(controller.chat(firstSite, 7)?.error, 'Chat is reconnecting.');

        controller.forget(firstSite);

        expect(controller.chat(firstSite, 7), isNull);
        expect(conversation.closeCalls, 1);
      },
    );

    test('releases the viewing handle when room Chat closes', () async {
      await controller.openChat(firstSite, 7);
      final conversation = chatConversations.find(
        siteUrl: firstSite,
        channelId: 42,
        threadId: 99,
      )!;

      controller.closeChat(firstSite, 7);

      expect(conversation.closeCalls, 1);
      expect(controller.chat(firstSite, 7)?.messages, isEmpty);
    });

    test('retains failures reported by temporary sends', () async {
      transport.responses['POST /voice/rooms/7/chat_session.json'] = fixture(
        'chat',
      );
      final conversations = seededChatConversations(
        snapshotAfterSend: ChatConversationSnapshot(
          messages: _chatPage(10).messages,
          canLoadMorePast: true,
          error: 'Message not sent.',
        ),
      );
      useTransport(transport, conversations: conversations);
      final conversation = chatConversations.find(
        siteUrl: firstSite,
        channelId: 42,
        threadId: 99,
      )!;

      await controller.sendChatMessage(firstSite, 7, 'hello');

      expect(conversation.sentMessages, ['hello']);
      expect(conversation.closeCalls, 1);
      expect(controller.chat(firstSite, 7)?.error, 'Message not sent.');
    });

    test('discards retained associations when rooms are destroyed', () async {
      await controller.ensureLoaded(firstSite);
      await controller.openChat(firstSite, 7);
      final conversation = chatConversations.find(
        siteUrl: firstSite,
        channelId: 42,
        threadId: 99,
      )!;

      firstTracker.deliver('/voice/rooms/index', {
        'type': 'destroyed',
        'room': (fixture('directory')['rooms'] as List<dynamic>).first,
      });

      expect(controller.chat(firstSite, 7), isNull);
      expect(conversation.closeCalls, 1);
    });

    test('prunes retained associations removed by directory refresh', () async {
      final responses = <String, Map<String, dynamic>>{
        'GET /voice/rooms.json': fixture('directory'),
        'GET /voice/rooms/7/chat_session.json': fixture('chat'),
      };
      final mutableTransport = RecordingPluginTransport(responses: responses);
      useTransport(mutableTransport);
      await controller.ensureLoaded(firstSite);
      await controller.openChat(firstSite, 7);
      final conversation = chatConversations.find(
        siteUrl: firstSite,
        channelId: 42,
        threadId: 99,
      )!;
      mutableTransport.responses['GET /voice/rooms.json'] = {
        ...fixture('directory'),
        'rooms': <Object>[],
      };

      await controller.ensureLoaded(firstSite, force: true);

      expect(controller.chat(firstSite, 7), isNull);
      expect(conversation.closeCalls, 1);
    });

    test(
      'invalidates a pre-credential open when directory refresh removes the room',
      () async {
        final gated = _NextGatedRequestHost();
        requests = gated;
        final responses = <String, Map<String, dynamic>>{
          'GET /voice/rooms.json': fixture('directory'),
          'GET /voice/rooms/7/chat_session.json': fixture('chat'),
        };
        final mutableTransport = RecordingPluginTransport(responses: responses);
        useTransport(mutableTransport);
        await controller.ensureLoaded(firstSite);
        gated.gateNextRead = true;

        final opening = controller.openChat(firstSite, 7);
        await gated.readStarted.future;
        mutableTransport.responses['GET /voice/rooms.json'] = {
          ...fixture('directory'),
          'rooms': <Object>[],
        };
        await controller.ensureLoaded(firstSite, force: true);
        gated.readGate.complete();
        await opening;

        expect(controller.chat(firstSite, 7), isNull);
        expect(chatConversations.opened, isEmpty);
      },
    );
  });

  group('call orchestration', () {
    test('enforces one global call while switching sites', () async {
      await controller.ensureLoaded(firstSite);
      await controller.ensureLoaded(secondSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final firstMedia = mediaFactory.sessions.single;

      await controller.join(
        siteUrl: secondSite,
        siteName: 'Two',
        room: controller.room(secondSite, 7)!,
      );

      expect(controller.call?.siteUrl, secondSite);
      expect(firstMedia.disposeCount, 1);
      expect(mediaFactory.sessions, hasLength(2));
      expect(systemCall.starts, 2);
      expect(systemCall.ends, 1);
      expect(
        transport.writes
            .where((write) => write.path.endsWith('/leave.json'))
            .single
            .siteUrl,
        firstSite,
      );
    });

    test('retries one rate-limited join after its delay', () async {
      transport.failures['POST /voice/rooms/7/join.json'] =
          const WriteException(
            WriteFailure.rateLimited,
            statusCode: 429,
            retryAfter: Duration.zero,
          );

      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      expect(controller.call?.room.id, 7);
      expect(controller.call?.status, VoiceCallStatus.connected);
      expect(
        transport.writes.where((write) => write.path.endsWith('/join.json')),
        hasLength(2),
      );
      expect(controller.errorFor(firstSite), isNull);
    });

    test(
      'a rate-limited join retired during its delay is not retried',
      () async {
        transport.failures['POST /voice/rooms/7/join.json'] =
            const WriteException(
              WriteFailure.rateLimited,
              statusCode: 429,
              retryAfter: Duration.zero,
            );

        await controller.ensureLoaded(firstSite);
        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        await pumpEventQueue();
        expect(
          transport.writes.where((write) => write.path.endsWith('/join.json')),
          hasLength(1),
        );
        controller.forget(firstSite);
        await joining;

        expect(
          transport.writes.where((write) => write.path.endsWith('/join.json')),
          hasLength(1),
        );
        expect(controller.call, isNull);
      },
    );

    test(
      'explains a denied microphone and leaves the partial server join',
      () async {
        final connectGate = Completer<void>();
        final connectStarted = Completer<void>();
        mediaFactory.nextConnectGate = connectGate;
        mediaFactory.nextConnectStarted = connectStarted;

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await connectStarted.future;
        connectGate.completeError(
          const VoiceMicrophoneException(
            VoiceMicrophoneFailureKind.permissionDenied,
          ),
        );
        await joining;

        expect(controller.call, isNull);
        expect(
          controller.errorFor(firstSite),
          'Microphone access is blocked. Allow microphone access in your '
          'system settings, then try joining again.',
        );
        expect(systemCall.failures, 1);
        expect(mediaFactory.sessions.single.disposeCount, 1);
        final leave = transport.writes.singleWhere(
          (write) => write.path.endsWith('/leave.json'),
        );
        expect(
          leave.body['participant_session_id'],
          'mesh-participant-session',
        );
      },
    );

    test('joining the room already held leaves it', () async {
      final room = VoiceRoom.fromJson(fixture('room'));
      await controller.join(siteUrl: firstSite, siteName: 'One', room: room);
      expect(controller.call?.room.id, 7);

      await controller.join(siteUrl: firstSite, siteName: 'One', room: room);
      await pumpEventQueue();

      expect(controller.call, isNull);
      expect(
        transport.writes.where((write) => write.path.endsWith('/join.json')),
        hasLength(1),
      );
      expect(mediaFactory.sessions.single.disposeCount, 1);
    });

    test(
      'media connecting mid-join does not announce the call early',
      () async {
        final connectGate = Completer<void>();
        final connectStarted = Completer<void>();
        mediaFactory.nextConnectGate = connectGate;
        mediaFactory.nextConnectStarted = connectStarted;

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await connectStarted.future;
        final media = mediaFactory.sessions.single
          ..connectionState = VoiceMediaConnectionState.connected;
        media.notifyListeners();

        expect(controller.call?.status, VoiceCallStatus.joining);
        connectGate.complete();
        await joining;
        expect(controller.call?.status, VoiceCallStatus.connected);
      },
    );

    test(
      'disposes media once when the controller is disposed during a failed connect',
      () async {
        final connectGate = Completer<void>();
        final connectStarted = Completer<void>();
        mediaFactory.nextConnectGate = connectGate;
        mediaFactory.nextConnectStarted = connectStarted;

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await connectStarted.future;
        final media = mediaFactory.sessions.single;

        controller.dispose();
        connectGate.completeError(StateError('connection closed by teardown'));
        await joining;
        await pumpEventQueue();

        expect(media.disposeCount, 1);
      },
    );

    test(
      'skips roster and system synchronization after disposal interrupts a media setting',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        final muteGate = Completer<void>();
        media.muteGate = muteGate;
        systemCall.systemMuted = null;
        final stateWritesBefore = transport.writes
            .where((write) => write.path.endsWith('/state.json'))
            .length;

        final muting = controller.setMuted(true);
        controller.dispose();
        muteGate.complete();
        await muting;
        await pumpEventQueue();

        expect(media.disposeCount, 1);
        expect(systemCall.systemMuted, isNull);
        expect(
          transport.writes.where((write) => write.path.endsWith('/state.json')),
          hasLength(stateWritesBefore),
        );
      },
    );

    test(
      'switches rooms even when the old room echoes the explicit leave',
      () async {
        final secondJoinPayload = fixture('join_mesh');
        final secondRoomJson =
            secondJoinPayload['room'] as Map<String, dynamic>;
        secondRoomJson
          ..['id'] = 8
          ..['name'] = 'Breakroom'
          ..['slug'] = 'breakroom';
        transport.responses['POST /voice/rooms/8/join.json'] =
            secondJoinPayload;

        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final firstMedia = mediaFactory.sessions.single;

        final switching = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(secondRoomJson),
        );
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': const <Object?>[],
        });
        await switching;

        expect(controller.call?.room.id, 8);
        expect(controller.call?.room.name, 'Breakroom');
        expect(firstMedia.disposeCount, 1);
        expect(systemCall.ends, 1);
        expect(mediaFactory.sessions, hasLength(2));
      },
    );

    test(
      'serializes a second room switch while the first is connecting',
      () async {
        Map<String, dynamic> joinPayloadFor(int id, String name, String slug) {
          final payload = fixture('join_mesh');
          final room = payload['room'] as Map<String, dynamic>;
          room
            ..['id'] = id
            ..['name'] = name
            ..['slug'] = slug;
          return payload;
        }

        final breakroom = joinPayloadFor(8, 'Breakroom', 'breakroom');
        final kitchen = joinPayloadFor(9, 'Kitchen', 'kitchen');
        transport.responses
          ..['POST /voice/rooms/8/join.json'] = breakroom
          ..['DELETE /voice/rooms/8/leave.json'] = <String, dynamic>{}
          ..['POST /voice/rooms/9/join.json'] = kitchen;

        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );

        final connectGate = Completer<void>();
        final connectStarted = Completer<void>();
        mediaFactory.nextConnectGate = connectGate;
        mediaFactory.nextConnectStarted = connectStarted;
        final firstSwitch = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(breakroom['room'] as Map<String, dynamic>),
        );
        await connectStarted.future;

        final secondSwitch = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(kitchen['room'] as Map<String, dynamic>),
        );
        final duplicateSecondSwitch = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(kitchen['room'] as Map<String, dynamic>),
        );
        await Future<void>.delayed(Duration.zero);

        expect(duplicateSecondSwitch, same(secondSwitch));
        expect(mediaFactory.sessions, hasLength(2));
        connectGate.complete();
        await Future.wait([firstSwitch, secondSwitch]);

        expect(controller.call?.room.id, 9);
        expect(controller.call?.room.name, 'Kitchen');
        expect(mediaFactory.sessions, hasLength(3));
        expect(mediaFactory.sessions[0].disposeCount, 1);
        expect(mediaFactory.sessions[1].disposeCount, 1);
        expect(mediaFactory.sessions[2].disposeCount, 0);
      },
    );
  });

  group('active call synchronization', () {
    test(
      'sends heartbeats, synchronizes controls, and responds to CallKit',
      () async {
        final heartbeatSent = Completer<void>();
        transport.responders['POST /voice/rooms/7/heartbeat.json'] = (_) {
          if (!heartbeatSent.isCompleted) heartbeatSent.complete();
          return <String, dynamic>{};
        };
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        await controller.setMuted(true);
        await controller.setDeafened(true);
        controller.setForeground(false);
        await heartbeatSent.future.timeout(const Duration(seconds: 1));

        expect(controller.call?.muted, isTrue);
        expect(controller.call?.deafened, isTrue);
        expect(mediaFactory.sessions.single.muted, isTrue);
        expect(systemCall.systemMuted, isTrue);
        expect(
          transport.writes.where(
            (write) => write.path.endsWith('/heartbeat.json'),
          ),
          isNotEmpty,
        );

        systemCall.send(VoiceSystemCallAction.unmute);
        await Future<void>.delayed(Duration.zero);
        expect(controller.call?.muted, isFalse);

        systemCall.send(VoiceSystemCallAction.end);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.call, isNull);
      },
    );

    test(
      'hands CallKit the latest mute choice when toggles share a state sync',
      () async {
        final controlled = _ControlledVoiceTransport(
          responses: {
            'GET /voice/rooms.json': fixture('directory'),
            'POST /voice/rooms/7/join.json': fixture('join_mesh'),
            'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
            'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
            'POST /voice/rooms/7/state.json': <String, dynamic>{},
          },
        );
        final callKit = _CallKitMuteSystemCall();
        useTransport(controlled, system: callKit);
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        await controller.setMuted(true);
        await pumpEventQueue();
        expect(callKit.committedMuted, isTrue);

        controlled.heldPluginWritePaths.add('/voice/rooms/7/state.json');
        final unmuting = controller.setMuted(false);
        await controlled.waitForPendingPluginWrites(1);
        // The user takes the unmute back while its roster write is out, so
        // both toggles resume together once the sync drains.
        final muting = controller.setMuted(true);
        controlled.pendingPluginWrites[0].response.complete({});
        await controlled.waitForPendingPluginWrites(2);
        controlled.pendingPluginWrites[1].response.complete({});
        await Future.wait([unmuting, muting]);
        await pumpEventQueue();

        expect(controller.call?.muted, isTrue);
        expect(media.muted, isTrue);
        expect(callKit.committedMuted, isTrue);
      },
    );

    test('skips CallKit for a mute whose call ended during its sync', () async {
      final controlled = _ControlledVoiceTransport(
        responses: {
          'GET /voice/rooms.json': fixture('directory'),
          'POST /voice/rooms/7/join.json': fixture('join_mesh'),
          'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
          'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
          'POST /voice/rooms/7/state.json': <String, dynamic>{},
        },
      );
      useTransport(controlled);
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      await pumpEventQueue();
      systemCall.systemMuted = null;

      controlled.heldPluginWritePaths.add('/voice/rooms/7/state.json');
      final muting = controller.setMuted(true);
      await controlled.waitForPendingPluginWrites(1);
      await controller.leave();
      controlled.pendingPluginWrites.single.response.complete({});
      await muting;

      expect(controller.call, isNull);
      expect(systemCall.systemMuted, isNull);
    });

    test('keeps at most one slow heartbeat in flight', () async {
      final joinPayload = fixture('join_mesh');
      (joinPayload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
      final controlled = _ControlledVoiceTransport(
        responses: {
          'GET /voice/rooms.json': fixture('directory'),
          'POST /voice/rooms/7/join.json': joinPayload,
          'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
          'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
          'POST /voice/rooms/7/state.json': <String, dynamic>{},
          'GET /voice/rooms/7/chat_session.json': fixture('chat'),
        },
      )..heldPluginWritePaths.add('/voice/rooms/7/heartbeat.json');
      useTransport(controlled);

      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      expect(controller.call?.status, VoiceCallStatus.connected);
      controller.setForeground(false);
      await controlled.waitForPendingPluginWrites(1);
      expect(controlled.pendingPluginWrites, hasLength(1));

      controller.setForeground(true);
      controller.setForeground(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        controlled.pendingPluginWrites.where(
          (write) => !write.response.isCompleted,
        ),
        hasLength(1),
      );

      controlled.pendingPluginWrites[0].response.complete({});
      await controlled.waitForPendingPluginWrites(2);
      expect(controlled.pendingPluginWrites, hasLength(2));
      expect(
        controlled.pendingPluginWrites.where(
          (write) => !write.response.isCompleted,
        ),
        hasLength(1),
      );

      controlled.pendingPluginWrites[1].response.complete({});
      await controller.leave();
    });

    test('resumes heartbeats after media reconnects', () async {
      useTransport(
        transport,
        heartbeatInterval: const Duration(milliseconds: 15),
      );
      final heartbeatAfterReconnect = Completer<void>();
      var reconnected = false;
      transport.responders['POST /voice/rooms/7/heartbeat.json'] = (_) {
        if (reconnected && !heartbeatAfterReconnect.isCompleted) {
          heartbeatAfterReconnect.complete();
        }
        return <String, dynamic>{};
      };
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;

      media.connectionState = VoiceMediaConnectionState.reconnecting;
      media.notifyListeners();
      expect(controller.call?.status, VoiceCallStatus.reconnecting);
      controller.setForeground(false);
      await Future<void>.delayed(Duration.zero);
      final heartbeatsBefore = transport.writes
          .where((write) => write.path.endsWith('/heartbeat.json'))
          .length;

      reconnected = true;
      media.connectionState = VoiceMediaConnectionState.connected;
      media.notifyListeners();
      expect(controller.call?.status, VoiceCallStatus.connected);
      await heartbeatAfterReconnect.future.timeout(const Duration(seconds: 1));

      expect(
        transport.writes
            .where((write) => write.path.endsWith('/heartbeat.json'))
            .length,
        greaterThan(heartbeatsBefore),
      );
    });

    test(
      'keeps a local media setting while roster-state persistence is rate limited',
      () async {
        final cameraRoom = fixture('join_mesh');
        (cameraRoom['room'] as Map<String, dynamic>).addAll({
          'video_enabled': true,
          'video_allowed': true,
        });
        transport.responses['POST /voice/rooms/7/join.json'] = cameraRoom;
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final stateWritesBefore = transport.writes
            .where((write) => write.path.endsWith('/state.json'))
            .length;
        transport.failures['POST /voice/rooms/7/state.json'] =
            const WriteException(
              WriteFailure.rateLimited,
              statusCode: 429,
              retryAfter: Duration.zero,
            );
        final retried = Completer<void>();
        transport.responders['POST /voice/rooms/7/state.json'] = (_) {
          if (!retried.isCompleted) retried.complete();
          return <String, dynamic>{};
        };

        await controller.setCameraEnabled(true);

        expect(controller.call?.cameraEnabled, isTrue);
        expect(controller.call?.error, isNull);
        expect(mediaFactory.sessions.single.camera, isTrue);
        await retried.future.timeout(const Duration(seconds: 1));
        expect(
          transport.writes.where((write) => write.path.endsWith('/state.json')),
          hasLength(stateWritesBefore + 2),
        );
      },
    );

    test(
      'preserves in-flight roster updates when a media toggle fails',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        expect(controller.call?.muted, isTrue);
        final muteGate = Completer<void>();
        media.muteGate = muteGate;
        media.muteFailure = StateError('mute rejected');

        final unmuting = controller.setMuted(false);
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 1, 'username': 'sam', 'role': 'moderator'},
            {'id': 2, 'username': 'lee', 'role': 'participant'},
          ],
        });
        await Future<void>.delayed(Duration.zero);
        muteGate.complete();
        await unmuting;

        expect(controller.call?.muted, isTrue);
        expect(controller.call?.error, 'The media setting was not applied.');
        expect(
          controller.call?.room.participants.map(
            (participant) => participant.username,
          ),
          containsAll(['sam', 'lee']),
        );
      },
    );

    test(
      'publishes roster state when screen sharing ends externally',
      () async {
        final room =
            transport.responses['POST /voice/rooms/7/join.json']!['room']
                as Map<String, dynamic>;
        room.addAll({
          'room_type': 'open',
          'video_enabled': true,
          'video_allowed': true,
        });
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;

        await controller.setScreenSharing(true);
        expect(controller.call?.screenSharing, isTrue);

        media.screen = false;
        media.notifyListeners();
        await Future<void>.delayed(Duration.zero);

        expect(controller.call?.screenSharing, isFalse);
        final stateWrites = transport.writes
            .where((write) => write.path.endsWith('/state.json'))
            .toList();
        expect(stateWrites.last.body['screen'], isFalse);
      },
    );

    // The sidebar, the chat inbox and the call port all redraw on this
    // controller, while participant tiles listen to the media session.
    test('stays quiet for media events that change only speakers', () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      await pumpEventQueue();
      final media = mediaFactory.sessions.single;
      var notifications = 0;
      controller.addListener(() => notifications++);

      for (var event = 0; event < 20; event++) {
        media.speaking = event.isEven ? const {2} : const {};
        media.notifyListeners();
      }
      await pumpEventQueue();

      expect(notifications, 0);
      expect(controller.call?.status, VoiceCallStatus.connected);
    });

    test('notifies for media state read through the call', () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      await pumpEventQueue();
      final media = mediaFactory.sessions.single;
      var notifications = 0;
      controller.addListener(() => notifications++);

      // The call port draws its local preview from the media session.
      media.localVideoTrack = FakeVoiceVideoHandle();
      media.notifyListeners();
      expect(notifications, 1);
      media.notifyListeners();
      expect(notifications, 1);
      media.localVideoTrack = FakeVoiceVideoHandle();
      media.notifyListeners();
      expect(notifications, 2);
      media.localVideoTrack = null;
      media.notifyListeners();
      expect(notifications, 3);

      media.screen = true;
      media.notifyListeners();
      expect(notifications, 4);
      media.notifyListeners();
      expect(notifications, 4);

      media.connectionState = VoiceMediaConnectionState.reconnecting;
      media.notifyListeners();
      expect(notifications, 5);
      expect(controller.call?.status, VoiceCallStatus.reconnecting);
    });
  });

  group('remembered camera', () {
    void watch() => controller.watchRoomVideo(siteUrl: firstSite, roomId: 7);
    void hide() =>
        controller.stopWatchingRoomVideo(siteUrl: firstSite, roomId: 7);

    Future<void> joinRoom({String siteUrl = firstSite}) async {
      await controller.ensureLoaded(siteUrl);
      await controller.join(
        siteUrl: siteUrl,
        siteName: 'Test site',
        room: controller.room(siteUrl, 7)!,
      );
    }

    setUp(() {
      final payload = fixture('join_mesh');
      (payload['room'] as Map<String, dynamic>).addAll({
        'video_enabled': true,
        'video_allowed': true,
      });
      transport.responses['POST /voice/rooms/7/join.json'] = payload;
    });

    test('switches front and back while preserving the audio call', () async {
      await joinRoom();
      await controller.setCameraEnabled(true);
      final media = mediaFactory.sessions.single;
      final muted = controller.call!.muted;

      await controller.switchCamera();
      expect(media.cameraFacing, VoiceCameraFacing.back);
      await controller.switchCamera();
      expect(media.cameraFacing, VoiceCameraFacing.front);
      expect(media.cameraRequests, [true, false, true, false, true]);
      expect(controller.call?.cameraEnabled, isTrue);
      expect(controller.call?.muted, muted);
      expect(controller.call?.status, VoiceCallStatus.connected);
      expect(media.disposeCount, 0);
    });

    test(
      'switches from the active rear camera and retains the new facing',
      () async {
        await joinRoom();
        await controller.selectCamera('saved-rear-camera');
        await controller.setCameraEnabled(true);
        final media = mediaFactory.sessions.single;
        media.cameraFacing = VoiceCameraFacing.back;

        await controller.switchCamera();
        expect(media.cameraFacing, VoiceCameraFacing.front);
        expect(controller.cameraDeviceId, isNull);
        await controller.setCameraEnabled(false);
        media.cameraFacing = VoiceCameraFacing.back;
        await controller.setCameraEnabled(true);
        expect(media.cameraFacing, VoiceCameraFacing.front);

        await controller.selectCamera('another-camera');
        expect(controller.cameraDeviceId, 'another-camera');
        expect(media.selectedCamera, 'another-camera');
      },
    );

    test('switch camera does not enable an inactive camera', () async {
      await controller.switchCamera();
      await joinRoom();
      await controller.switchCamera();
      expect(mediaFactory.sessions.single.cameraRequests, isEmpty);
      expect(controller.call?.cameraEnabled, isFalse);
    });

    for (final cancellation in ['camera off', 'leave']) {
      test(
        'a pending camera switch honors $cancellation and ignores repeat taps',
        () async {
          await joinRoom();
          await controller.setCameraEnabled(true);
          final media = mediaFactory.sessions.single;
          final capturing = Completer<void>();
          final captured = Completer<void>();
          addTearDown(() {
            if (!captured.isCompleted) captured.complete();
          });
          media.onSetCamera = (enabled) async {
            if (!enabled) return;
            capturing.complete();
            await captured.future;
          };
          final switching = controller.switchCamera();
          await capturing.future;
          expect(controller.cameraStarting, isTrue);
          await controller.switchCamera();
          final cancelling = cancellation == 'leave'
              ? controller.leave()
              : controller.setCameraEnabled(false);
          captured.complete();
          await Future.wait([switching, cancelling]);
          expect(
            media.cameraRequests.where((enabled) => enabled),
            hasLength(2),
          );
          expect(controller.call?.cameraEnabled ?? false, isFalse);
          expect(controller.cameraStarting, isFalse);
          if (cancellation == 'camera off') expect(media.camera, isFalse);
        },
      );
    }

    test(
      'a failed camera switch leaves audio connected and reports the error',
      () async {
        await joinRoom();
        await controller.setCameraEnabled(true);
        final media = mediaFactory.sessions.single;
        media.onSetCamera = (enabled) async {
          if (enabled) throw StateError('camera unavailable');
        };

        await controller.switchCamera();

        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(controller.call?.cameraEnabled, isFalse);
        expect(controller.call?.error, isNotNull);
        expect(controller.cameraStarting, isFalse);
        expect(media.disposeCount, 0);
      },
    );

    test(
      'starts with audio only until the account explicitly enables its camera',
      () async {
        watch();
        await joinRoom();
        await pumpEventQueue();
        expect(mediaFactory.sessions.single.cameraRequests, isEmpty);

        await controller.setCameraEnabled(true);
        expect(preferences.cameraEnabled, {(firstSite, 1): true});

        await controller.leave();
        await joinRoom();
        await pumpEventQueue();
        expect(mediaFactory.sessions.last.camera, isTrue);
        expect(controller.call?.cameraEnabled, isTrue);
        expect(transport.writes.last.body['video'], isTrue);
      },
    );

    test(
      'restores the selected device only when the connected room becomes visible',
      () async {
        preferences.cameraEnabled[(firstSite, 1)] = true;
        preferences.devices = const VoiceDevicePreferences(
          cameraDeviceId: 'saved-camera',
        );
        useTransport(transport);
        await joinRoom();
        await pumpEventQueue();
        final media = mediaFactory.sessions.single;
        expect(media.cameraRequests, isEmpty);

        watch();
        await pumpEventQueue();
        expect(media.cameraRequests, [true]);
        expect(media.selectedCamera, 'saved-camera');
        expect(controller.call?.cameraEnabled, isTrue);
      },
    );

    test(
      'a late device read does not replace a newly selected camera',
      () async {
        final devices = Completer<VoiceDevicePreferences>();
        preferences.onReadDevices = () => devices.future;
        preferences.cameraEnabled[(firstSite, 1)] = true;
        addTearDown(() {
          if (!devices.isCompleted) {
            devices.complete(const VoiceDevicePreferences());
          }
        });
        useTransport(transport);
        // A join waits for the device read, so the selection lands while the
        // join is waiting and the read answers after it.
        final joining = joinRoom();
        watch();
        await controller.selectCamera('new-camera');

        devices.complete(
          const VoiceDevicePreferences(cameraDeviceId: 'old-camera'),
        );
        await joining;
        await pumpEventQueue();

        expect(controller.cameraDeviceId, 'new-camera');
        expect(mediaFactory.sessions.single.selectedCamera, 'new-camera');
        expect(mediaFactory.sessions.single.cameraRequests, [true]);
      },
    );

    test(
      'retries with the newly selected device after cancelling an old capture',
      () async {
        preferences.cameraEnabled[(firstSite, 1)] = true;
        await joinRoom();
        final media = mediaFactory.sessions.single;
        final capturing = Completer<void>();
        final captured = Completer<void>();
        media.onSetCamera = (_) async {
          media.onSetCamera = null;
          capturing.complete();
          await captured.future;
        };
        addTearDown(() {
          if (!captured.isCompleted) captured.complete();
        });
        watch();
        await capturing.future;
        final switching = controller.selectCamera('new-camera');

        captured.complete();
        await switching;
        await pumpEventQueue();

        expect(media.cameraRequests, [true, false, false, true]);
        expect(media.selectedCamera, 'new-camera');
        expect(controller.call?.cameraEnabled, isTrue);
      },
    );

    for (final action in ['manual start', 'device switch']) {
      for (final revoked in [
        'video forbidden',
        'video disabled',
        'speaking role',
        'publisher limit',
      ]) {
        test('cancels $action when $revoked changes during capture', () async {
          if (revoked == 'speaking role') {
            final room =
                transport.responses['POST /voice/rooms/7/join.json']!['room']
                    as Map<String, dynamic>;
            room['room_type'] = 'stage';
            room['active_participants'] = [
              {'id': 1, 'username': 'sam', 'role': 'speaker'},
            ];
          }
          var maxPublishers = 8;
          useTransport(transport, videoMaxPublishersFor: (_) => maxPublishers);
          await joinRoom();
          watch();
          final media = mediaFactory.sessions.single;
          if (action == 'device switch') {
            await controller.setCameraEnabled(true);
          }
          final capturing = Completer<void>();
          final captured = Completer<void>();
          media.onSetCamera = (enabled) async {
            if (!enabled) return;
            capturing.complete();
            await captured.future;
          };
          addTearDown(() {
            if (!captured.isCompleted) captured.complete();
          });
          final operation = action == 'device switch'
              ? controller.selectCamera('new-camera')
              : controller.setCameraEnabled(true);
          await capturing.future;
          switch (revoked) {
            case 'video forbidden':
            case 'video disabled':
              firstTracker.deliver('/voice/rooms/index', {
                'type': 'updated',
                'room': {
                  ...(transport
                          .responses['POST /voice/rooms/7/join.json']!['room']
                      as Map<String, dynamic>),
                  if (revoked == 'video forbidden') 'video_allowed': false,
                  if (revoked == 'video disabled') 'video_enabled': false,
                },
              });
            case 'speaking role':
              firstTracker.deliver('/voice/rooms/7', {
                'type': 'participants',
                'participants': [
                  {'id': 1, 'username': 'sam', 'role': 'participant'},
                ],
              });
            case 'publisher limit':
              maxPublishers = 0;
          }
          captured.complete();
          await operation;
          expect(media.camera, isFalse);
          expect(controller.call?.cameraEnabled, isFalse);
          expect(controller.cameraStarting, isFalse);
          expect(
            preferences.cameraEnabled[(firstSite, 1)],
            action == 'device switch' ? isTrue : isNull,
          );
        });
      }
    }

    for (final cancel in [false, true]) {
      test(
        'a device selected during first manual capture ${cancel ? 'can be cancelled' : 'retains camera-on intent'}',
        () async {
          await joinRoom();
          watch();
          final media = mediaFactory.sessions.single;
          final capturing = Completer<void>();
          final captured = Completer<void>();
          media.onSetCamera = (enabled) async {
            if (!enabled) return;
            media.onSetCamera = null;
            capturing.complete();
            await captured.future;
          };
          addTearDown(() {
            if (!captured.isCompleted) captured.complete();
          });
          final enabling = controller.setCameraEnabled(true);
          await capturing.future;
          final switching = controller.selectCamera('new-camera');
          expect(controller.cameraStarting, isTrue);
          final cancelling = cancel
              ? controller.setCameraEnabled(false)
              : Future<void>.value();
          captured.complete();
          await Future.wait([enabling, switching, cancelling]);
          expect(media.camera, !cancel);
          expect(controller.call?.cameraEnabled, !cancel);
          expect(preferences.cameraEnabled[(firstSite, 1)], !cancel);
          if (!cancel) expect(media.selectedCamera, 'new-camera');
          expect(controller.cameraStarting, isFalse);
        },
      );
    }

    test(
      'camera off stops capture before an earlier preference write completes',
      () async {
        await joinRoom();
        final started = Completer<void>();
        final saved = Completer<void>();
        preferences.onWriteCamera = (enabled) async {
          if (enabled) {
            started.complete();
            await saved.future;
          }
        };
        addTearDown(() {
          if (!saved.isCompleted) saved.complete();
        });
        final enabling = controller.setCameraEnabled(true);
        await started.future;
        final media = mediaFactory.sessions.single;
        final stopped = Completer<void>();
        media.afterSetCamera = (enabled) {
          if (!enabled && !stopped.isCompleted) stopped.complete();
        };
        final disabling = controller.setCameraEnabled(false);
        await stopped.future;
        expect(media.camera, isFalse);
        expect(saved.isCompleted, isFalse);
        saved.complete();
        await Future.wait([enabling, disabling]);
        expect(controller.call?.cameraEnabled, isFalse);
      },
    );

    test('keeps another site and account audio only', () async {
      preferences.cameraEnabled[(firstSite, 1)] = true;
      var userId = 2;
      useTransport(transport, userIdFor: (_) => userId);
      watch();
      await joinRoom();
      await pumpEventQueue();
      expect(mediaFactory.sessions.last.cameraRequests, isEmpty);

      await controller.leave();
      userId = 1;
      controller.watchRoomVideo(siteUrl: secondSite, roomId: 7);
      await joinRoom(siteUrl: secondSite);
      await pumpEventQueue();
      expect(mediaFactory.sessions.last.cameraRequests, isEmpty);
    });

    test(
      'a cancelled device switch reports camera off and can restore when shown',
      () async {
        await joinRoom();
        watch();
        await controller.setCameraEnabled(true);
        final media = mediaFactory.sessions.single;
        final capturing = Completer<void>();
        final captured = Completer<void>();
        media.onSetCamera = (enabled) async {
          if (!enabled) return;
          media.onSetCamera = null;
          capturing.complete();
          await captured.future;
        };
        addTearDown(() {
          if (!captured.isCompleted) captured.complete();
        });
        final switching = controller.selectCamera('new-camera');
        await capturing.future;
        hide();
        captured.complete();
        await switching;

        expect(media.camera, isFalse);
        expect(controller.call?.cameraEnabled, isFalse);
        watch();
        await pumpEventQueue();
        expect(media.selectedCamera, 'new-camera');
        expect(controller.call?.cameraEnabled, isTrue);
      },
    );

    test(
      'explicit off cancels a pending preference read and survives rejoining',
      () async {
        final reading = Completer<bool>();
        final started = Completer<void>();
        preferences.onReadCamera = (_, _) {
          started.complete();
          return reading.future;
        };
        addTearDown(() {
          if (!reading.isCompleted) reading.complete(false);
        });
        await joinRoom();
        watch();
        await started.future;

        await controller.setCameraEnabled(false);
        reading.complete(true);
        await pumpEventQueue();
        expect(mediaFactory.sessions.single.cameraRequests, [false]);
        expect(preferences.cameraEnabled[(firstSite, 1)], isFalse);

        await controller.leave();
        await joinRoom();
        await pumpEventQueue();
        expect(mediaFactory.sessions.last.cameraRequests, isEmpty);
      },
    );

    for (final invalidation in [
      'camera off',
      'hidden',
      'background',
      'leave',
      'account changed',
      'screen sharing',
      'video forbidden',
      'publisher limit',
    ]) {
      test('does not publish a pending capture after $invalidation', () async {
        preferences.cameraEnabled[(firstSite, 1)] = true;
        var userId = 1;
        var maxPublishers = 6;
        useTransport(
          transport,
          userIdFor: (_) => userId,
          videoMaxPublishersFor: (_) => maxPublishers,
        );
        await joinRoom();
        final media = mediaFactory.sessions.single;
        final capturing = Completer<void>();
        final captured = Completer<void>();
        media.onSetCamera = (enabled) async {
          if (!enabled) return;
          capturing.complete();
          await captured.future;
        };
        addTearDown(() {
          if (!captured.isCompleted) captured.complete();
        });
        watch();
        await capturing.future;

        Future<void>? turningOff;
        switch (invalidation) {
          case 'camera off':
            turningOff = controller.setCameraEnabled(false);
          case 'hidden':
            hide();
          case 'background':
            controller.setForeground(false);
          case 'leave':
            await controller.leave();
          case 'account changed':
            userId = 2;
          case 'screen sharing':
            await controller.setScreenSharing(true);
          case 'video forbidden':
            firstTracker.deliver('/voice/rooms/index', {
              'type': 'updated',
              'room': {
                ...(transport
                        .responses['POST /voice/rooms/7/join.json']!['room']
                    as Map<String, dynamic>),
                'video_allowed': false,
              },
            });
          case 'publisher limit':
            maxPublishers = 0;
        }
        captured.complete();
        await turningOff;
        await pumpEventQueue();

        expect(media.camera, isFalse);
        expect(controller.call?.cameraEnabled, isNot(true));
        expect(
          transport.writes.where(
            (write) =>
                write.path.endsWith('/state.json') &&
                write.body['video'] == true,
          ),
          isEmpty,
        );
      });
    }

    test(
      'coalesces watches and retries when a pending capture is hidden then shown',
      () async {
        preferences.cameraEnabled[(firstSite, 1)] = true;
        await joinRoom();
        final media = mediaFactory.sessions.single;
        final capturing = Completer<void>();
        final captured = Completer<void>();
        media.onSetCamera = (_) async {
          media.onSetCamera = null;
          capturing.complete();
          await captured.future;
        };
        addTearDown(() {
          if (!captured.isCompleted) captured.complete();
        });
        watch();
        watch();
        await capturing.future;
        expect(media.cameraRequests, [true]);
        hide();
        hide();
        watch();

        captured.complete();
        await pumpEventQueue();
        expect(media.cameraRequests, [true, false, true]);
        expect(controller.call?.cameraEnabled, isTrue);
      },
    );

    for (final reason in [
      'video disabled',
      'video forbidden',
      'stage listener',
      'publisher limit',
    ]) {
      test('does not start the camera when blocked by $reason', () async {
        preferences.cameraEnabled[(firstSite, 1)] = true;
        final room =
            transport.responses['POST /voice/rooms/7/join.json']!['room']
                as Map<String, dynamic>;
        switch (reason) {
          case 'video disabled':
            room['video_enabled'] = false;
          case 'video forbidden':
            room['video_allowed'] = false;
          case 'stage listener':
            room['room_type'] = 'stage';
          case 'publisher limit':
            room['active_participants'] = [
              {'id': 1, 'username': 'sam', 'role': 'participant'},
              {
                'id': 2,
                'username': 'other',
                'role': 'participant',
                'is_screen_sharing': true,
              },
            ];
            useTransport(transport, videoMaxPublishersFor: (_) => 1);
        }
        watch();
        await joinRoom();
        await pumpEventQueue();
        expect(mediaFactory.sessions.single.cameraRequests, isEmpty);
        expect(controller.call?.status, VoiceCallStatus.connected);
      });
    }

    test(
      'defers restoration until the app returns to the foreground',
      () async {
        preferences.cameraEnabled[(firstSite, 1)] = true;
        controller.setForeground(false);
        watch();
        await joinRoom();
        await pumpEventQueue();
        expect(mediaFactory.sessions.single.cameraRequests, isEmpty);

        controller.setForeground(true);
        await pumpEventQueue();
        expect(controller.call?.cameraEnabled, isTrue);
      },
    );

    for (final ending in ['user', 'system']) {
      test(
        'restores the preference when screen sharing ends by $ending',
        () async {
          preferences.cameraEnabled[(firstSite, 1)] = true;
          await joinRoom();
          final media = mediaFactory.sessions.single;
          await controller.setScreenSharing(true);
          watch();
          await pumpEventQueue();
          expect(media.cameraRequests, isEmpty);

          if (ending == 'user') {
            await controller.setScreenSharing(false);
          } else {
            media.screen = false;
            media.notifyListeners();
          }
          await pumpEventQueue();
          expect(controller.call?.screenSharing, isFalse);
          expect(controller.call?.cameraEnabled, isTrue);
          expect(media.cameraRequests, [true]);
        },
      );
    }

    for (final automatic in [false, true]) {
      test(
        'releases a ${automatic ? 'restored' : 'manual'} camera invalidated as capture completes',
        () async {
          preferences.cameraEnabled[(firstSite, 1)] = automatic;
          await joinRoom();
          final media = mediaFactory.sessions.single;
          media.afterSetCamera = (enabled) {
            if (enabled) hide();
          };
          watch();
          if (!automatic) await controller.setCameraEnabled(true);
          await pumpEventQueue();

          expect(media.cameraRequests, [true, false]);
          expect(media.camera, isFalse);
          expect(controller.call?.cameraEnabled, isFalse);
          expect(controller.cameraStarting, isFalse);
        },
      );

      test(
        'camera off does not wait for the ${automatic ? 'automatic' : 'manual'} enable state write',
        () async {
          preferences.cameraEnabled[(firstSite, 1)] = automatic;
          final controlled = _ControlledVoiceTransport(
            responses: transport.responses,
          );
          useTransport(controlled);
          await joinRoom();
          final media = mediaFactory.sessions.single;
          controlled.heldPluginWritePaths.add('/voice/rooms/7/state.json');
          addTearDown(() {
            controlled.heldPluginWritePaths.clear();
            for (final write in controlled.pendingPluginWrites) {
              if (!write.response.isCompleted) write.response.complete({});
            }
          });
          Future<void>? enabling;
          if (automatic) {
            watch();
          } else {
            enabling = controller.setCameraEnabled(true);
          }
          await controlled.waitForPendingPluginWrites(1);
          await pumpEventQueue();
          expect(controller.call?.cameraEnabled, isTrue);
          final disabled = Completer<void>();
          controller.addListener(() {
            if (controller.call?.cameraEnabled == false &&
                !disabled.isCompleted) {
              disabled.complete();
            }
          });

          final disabling = controller.setCameraEnabled(false);
          await disabled.future;

          expect(media.camera, isFalse);
          expect(preferences.cameraEnabled[(firstSite, 1)], isFalse);
          expect(
            controlled.pendingPluginWrites.single.response.isCompleted,
            isFalse,
          );
          controlled.heldPluginWritePaths.clear();
          controlled.pendingPluginWrites.single.response.complete({});
          await enabling;
          await disabling;
        },
      );
    }

    test(
      'finishes turning the camera off when the app backgrounds during the stop',
      () async {
        await joinRoom();
        await controller.setCameraEnabled(true);
        final media = mediaFactory.sessions.single;
        final stopping = Completer<void>();
        final stopped = Completer<void>();
        media.onSetCamera = (_) async {
          stopping.complete();
          await stopped.future;
        };
        addTearDown(() {
          if (!stopped.isCompleted) stopped.complete();
        });

        final disabling = controller.setCameraEnabled(false);
        await stopping.future;
        controller.setForeground(false);
        stopped.complete();
        await disabling;

        expect(media.camera, isFalse);
        expect(controller.call?.cameraEnabled, isFalse);
        expect(preferences.cameraEnabled[(firstSite, 1)], isFalse);
      },
    );

    test('restores after reconnecting cancels an unfinished capture', () async {
      preferences.cameraEnabled[(firstSite, 1)] = true;
      await joinRoom();
      final media = mediaFactory.sessions.single;
      final capturing = Completer<void>();
      final captured = Completer<void>();
      media.onSetCamera = (_) async {
        media.onSetCamera = null;
        capturing.complete();
        await captured.future;
      };
      addTearDown(() {
        if (!captured.isCompleted) captured.complete();
      });
      watch();
      await capturing.future;
      media.connectionState = VoiceMediaConnectionState.reconnecting;
      media.notifyListeners();
      captured.complete();
      await pumpEventQueue();
      expect(media.camera, isFalse);

      media.connectionState = VoiceMediaConnectionState.connected;
      media.notifyListeners();
      await pumpEventQueue();
      expect(media.cameraRequests, [true, false, true]);
      expect(controller.call?.cameraEnabled, isTrue);
    });

    test(
      'a preference read failure leaves the camera off and the call usable',
      () async {
        preferences.onReadCamera = (_, _) async =>
            throw StateError('unavailable');
        watch();
        await joinRoom();
        await pumpEventQueue();

        expect(mediaFactory.sessions.single.cameraRequests, isEmpty);
        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(controller.call?.error, isNull);
      },
    );

    test(
      'automatic capture failure leaves the audio call usable without an error',
      () async {
        preferences.cameraEnabled[(firstSite, 1)] = true;
        mediaFactory.nextCameraFailure = StateError('permission denied');
        watch();
        await joinRoom();
        await pumpEventQueue();

        expect(mediaFactory.sessions.single.cameraRequests, [true]);
        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(controller.call?.cameraEnabled, isFalse);
        expect(controller.call?.error, isNull);
        expect(preferences.cameraEnabled[(firstSite, 1)], isTrue);
      },
    );

    test(
      'a failed explicit camera enable does not opt the account in',
      () async {
        await joinRoom();
        mediaFactory.sessions.single.cameraFailure = StateError(
          'permission denied',
        );
        await controller.setCameraEnabled(true);

        expect(preferences.cameraEnabled, isEmpty);
        expect(controller.call?.cameraEnabled, isFalse);
        expect(controller.call?.error, 'The media setting was not applied.');
      },
    );
  });

  group('call teardown', () {
    for (final source in ['directory', 'room link']) {
      test(
        'removes the local participant from the $source before leave completes',
        () async {
          final room = fixture('room');
          final otherRoom = {...room, 'id': 8, 'slug': 'other-room'};
          final controlled = _ControlledVoiceTransport(
            responses: {
              ...transport.responses,
              'GET /voice/rooms.json': {
                'rooms': [if (source == 'directory') room, otherRoom],
              },
              'GET /voice/rooms/conf-room-1.json': room,
              'POST /voice/rooms/7/join.json': {
                ...fixture('join_mesh'),
                'room': room,
              },
            },
          )..heldPluginWritePaths.add('/voice/rooms/7/leave.json');
          useTransport(controlled);
          await controller.ensureLoaded(firstSite);
          await controller.ensureLoaded(secondSite);
          final resolved = await controller.resolveRoom(
            firstSite,
            'conf-room-1',
          );

          expect(controller.call, isNull);
          expect(resolved!.participants.map((participant) => participant.id), [
            2,
            1,
          ]);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: resolved,
          );

          final leaving = controller.leave();
          addTearDown(() async {
            for (final write in controlled.pendingPluginWrites) {
              if (!write.response.isCompleted) write.response.complete({});
            }
            await leaving;
          });
          await controlled.waitForPendingPluginWrites(1);

          expect(controller.call?.status, VoiceCallStatus.leaving);
          expect(
            controller.call!.room.participants.map(
              (participant) => participant.id,
            ),
            [2],
          );
          expect(
            controller
                .room(firstSite, 7)!
                .participants
                .map((participant) => participant.id),
            [2],
          );
          for (final siteUrl in [firstSite, secondSite]) {
            expect(
              controller
                  .room(siteUrl, 8)!
                  .participants
                  .map((participant) => participant.id),
              [2, 1],
            );
          }

          controlled.pendingPluginWrites.single.response.complete({});
          await leaving;

          expect(controller.call, isNull);
          expect(
            controller
                .room(firstSite, 7)!
                .participants
                .map((participant) => participant.id),
            [2],
          );
        },
      );
    }

    _ControlledVoiceTransport heldLeaveTransport({
      Map<String, Map<String, dynamic>> extraResponses = const {},
    }) => _ControlledVoiceTransport(
      responses: {
        'GET /voice/rooms.json': fixture('directory'),
        'POST /voice/rooms/7/join.json': fixture('join_mesh'),
        'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
        'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
        'POST /voice/rooms/7/state.json': <String, dynamic>{},
        ...extraResponses,
      },
    )..heldPluginWritePaths.add('/voice/rooms/7/leave.json');

    test('stops local media before the leave request settles', () async {
      final controlled = heldLeaveTransport();
      useTransport(controlled);
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;

      final leaving = controller.leave();
      addTearDown(() async {
        for (final write in controlled.pendingPluginWrites) {
          if (!write.response.isCompleted) write.response.complete({});
        }
        await leaving;
      });
      await controlled.waitForPendingPluginWrites(1);
      await pumpEventQueue();

      expect(controller.call?.status, VoiceCallStatus.leaving);
      expect(media.disposeCount, 1);
      expect(systemCall.ends, 0);

      controlled.pendingPluginWrites.single.response.complete({});
      await leaving;

      expect(controller.call, isNull);
      expect(systemCall.ends, 1);
      expect(controlled.pendingPluginWrites.map((write) => write.path), [
        '/voice/rooms/7/leave.json',
      ]);
      expect(
        controlled.writes.where((write) => write.path.endsWith('/leave.json')),
        isEmpty,
      );
    });

    test('ignores call controls once leaving starts', () async {
      final controlled = heldLeaveTransport();
      useTransport(controlled);
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;
      await controller.setMuted(true);

      final leaving = controller.leave();
      addTearDown(() async {
        for (final write in controlled.pendingPluginWrites) {
          if (!write.response.isCompleted) write.response.complete({});
        }
        await leaving;
      });
      await controlled.waitForPendingPluginWrites(1);
      await controller.setMuted(false);
      await controller.setScreenSharing(true);
      await controller.setDeafened(true);

      expect(media.muted, isTrue);
      expect(media.screen, isFalse);
      expect(media.deafened, isFalse);
      expect(controller.call?.muted, isTrue);
      expect(controller.call?.screenSharing, isFalse);
      expect(controller.call?.deafened, isFalse);

      controlled.pendingPluginWrites.single.response.complete({});
      await leaving;
      expect(controller.call, isNull);
    });

    test(
      'stops the previous room media before its leave request settles on a room switch',
      () async {
        final breakroomPayload = fixture('join_mesh');
        final breakroomJson = breakroomPayload['room'] as Map<String, dynamic>;
        breakroomJson
          ..['id'] = 8
          ..['name'] = 'Breakroom'
          ..['slug'] = 'breakroom';
        final controlled = heldLeaveTransport(
          extraResponses: {
            'POST /voice/rooms/8/join.json': breakroomPayload,
            'POST /voice/rooms/8/state.json': <String, dynamic>{},
          },
        );
        useTransport(controlled);
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final previousMedia = mediaFactory.sessions.single;

        final switching = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(breakroomJson),
        );
        addTearDown(() async {
          for (final write in controlled.pendingPluginWrites) {
            if (!write.response.isCompleted) write.response.complete({});
          }
          await switching;
        });
        await controlled.waitForPendingPluginWrites(1);
        await pumpEventQueue();

        expect(controller.call?.room.id, 7);
        expect(controller.call?.status, VoiceCallStatus.leaving);
        expect(previousMedia.disposeCount, 1);
        expect(mediaFactory.sessions, hasLength(1));

        controlled.pendingPluginWrites.single.response.complete({});
        await switching;

        expect(controller.call?.room.id, 8);
        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(mediaFactory.sessions, hasLength(2));
        expect(mediaFactory.sessions.last.disposeCount, 0);
        expect(controlled.pendingPluginWrites.map((write) => write.path), [
          '/voice/rooms/7/leave.json',
        ]);
      },
    );

    test('removes the local participant after media fails to join', () async {
      await controller.ensureLoaded(firstSite);
      final connectGate = Completer<void>();
      final connectStarted = Completer<void>();
      mediaFactory.nextConnectGate = connectGate;
      mediaFactory.nextConnectStarted = connectStarted;

      final joining = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      addTearDown(() async {
        if (!connectGate.isCompleted) connectGate.complete();
        await joining;
      });
      await connectStarted.future;
      firstTracker.deliver('/voice/rooms/7', {
        'type': 'participants',
        'participants': [
          {'id': 1, 'username': 'sam', 'role': 'participant'},
          {'id': 2, 'username': 'lee', 'role': 'participant'},
        ],
      });

      connectGate.completeError(StateError('media connection failed'));
      await joining;

      expect(controller.call, isNull);
      expect(
        controller
            .room(firstSite, 7)!
            .participants
            .map((participant) => participant.id),
        [2],
      );
      expect(
        transport.writes.where((write) => write.path.endsWith('/leave.json')),
        hasLength(1),
      );
    });

    test('preserves server presence when the join request fails', () async {
      final controlled = _ControlledVoiceTransport(
        responses: {...transport.responses},
      );
      useTransport(controlled);
      await controller.ensureLoaded(firstSite);
      controlled.operationFailure = StateError('server unavailable');

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      expect(controller.call, isNull);
      expect(
        controller
            .room(firstSite, 7)!
            .participants
            .map((participant) => participant.id),
        [1],
      );
    });

    test(
      'keeps a connected mesh call while the local participant resumes',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        final localIds = controller.call!.room.participants
            .map((p) => p.id)
            .toList();
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': const <Object?>[],
          'resuming_ids': localIds,
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.call, isNotNull);
        expect(media.disposeCount, 0);
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': const <Object?>[],
          'resuming_ids': const <int>[],
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.call, isNull);
        expect(media.disposeCount, 1);
      },
    );

    test(
      'ends the local call when another client removes it from the roster',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': const <Object?>[],
        });
        await Future<void>.delayed(Duration.zero);

        expect(controller.call, isNull);
        expect(media.disposeCount, 1);
        expect(systemCall.ends, 1);

        expect(
          transport.writes.where((write) => write.path.endsWith('/leave.json')),
          isEmpty,
        );
      },
    );

    test(
      'does not abort an in-progress join for a stale roster without the local user',
      () async {
        await controller.ensureLoaded(firstSite);
        final connectGate = Completer<void>();
        final connectStarted = Completer<void>();
        mediaFactory.nextConnectGate = connectGate;
        mediaFactory.nextConnectStarted = connectStarted;

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        await connectStarted.future;
        expect(controller.call?.status, VoiceCallStatus.joining);

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': const <Object?>[],
        });
        await Future<void>.delayed(Duration.zero);
        connectGate.complete();
        await joining;

        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(mediaFactory.sessions.single.disposeCount, 0);
      },
    );

    for (final notifyServer in [true, false]) {
      test(
        'late join failure respects leave notifyServer=$notifyServer',
        () async {
          final connectGate = Completer<void>();
          final connectStarted = Completer<void>();
          mediaFactory
            ..nextConnectGate = connectGate
            ..nextConnectStarted = connectStarted;
          final joining = controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: VoiceRoom.fromJson(fixture('room')),
          );
          addTearDown(() async {
            if (!connectGate.isCompleted) connectGate.complete();
            await joining;
          });
          await connectStarted.future;
          final media = mediaFactory.sessions.single;
          await controller.leave(notifyServer: notifyServer);
          expect(controller.call, isNull);
          connectGate.completeError(StateError('late connection failure'));
          await joining;
          expect(media.disposeCount, 1);
          expect(
            transport.writes.where(
              (write) => write.path.endsWith('/leave.json'),
            ),
            hasLength(notifyServer ? 1 : 0),
          );
          expect(systemCall.ends, 1);
          expect(systemCall.failures, 0);
        },
      );
    }

    for (final action in ['close', 'leave', 'forget']) {
      test('closes unpublished media on $action', () async {
        final muteGate = Completer<void>();
        final muteStarted = Completer<void>();
        mediaFactory
          ..nextMuteGate = muteGate
          ..nextMuteStarted = muteStarted;
        addTearDown(() {
          if (!muteGate.isCompleted) muteGate.complete();
        });
        var callPublished = false;
        controller.addListener(() {
          if (controller.call != null) callPublished = true;
        });

        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        await muteStarted.future;
        final media = mediaFactory.sessions.single;
        expect(controller.call, isNull);

        var completed = false;
        final closing = switch (action) {
          'close' => controller.close(),
          'leave' => controller.leave(),
          _ => () {
            controller.forget(firstSite);
            return joining;
          }(),
        };
        if (action == 'leave') expect(controller.leave(), same(closing));
        unawaited(closing.then((_) => completed = true));
        await pumpEventQueue();

        expect(completed, isFalse);
        expect(media.disposeCount, 1);
        expect(systemCall.starts, 0);

        muteGate.complete();
        await joining;
        await closing;

        expect(completed, isTrue);
        expect(media.disposeCount, 1);
        final leave = transport.writes.singleWhere(
          (write) => write.path.endsWith('/leave.json'),
        );
        expect(
          leave.body['participant_session_id'],
          'mesh-participant-session',
        );
        expect(systemCall.starts, 0);
        expect(controller.call, isNull);
        expect(callPublished, isFalse);
      });
    }

    test(
      'awaits leave, media, subscriptions, and CallKit during session close',
      () async {
        final joinPayload = fixture('join_mesh');
        (joinPayload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
        final controlled = _ControlledVoiceTransport(
          responses: {
            'GET /voice/rooms.json': fixture('directory'),
            'POST /voice/rooms/7/join.json': joinPayload,
            'POST /voice/rooms/7/heartbeat.json': <String, dynamic>{},
            'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
            'POST /voice/rooms/7/state.json': <String, dynamic>{},
            'GET /voice/rooms/7/chat_session.json': fixture('chat'),
          },
        )..heldPluginWritePaths.add('/voice/rooms/7/leave.json');
        final awaitableTracker = _AwaitableSubscriptionTracker();
        firstTracker = awaitableTracker;
        useTransport(controlled);

        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        final mediaDisposeStarted = Completer<void>();
        final mediaDisposeGate = Completer<void>();
        media
          ..disposeStarted = mediaDisposeStarted
          ..disposeGate = mediaDisposeGate;
        final endStarted = Completer<void>();
        final endGate = Completer<void>();
        final callKitDisposeStarted = Completer<void>();
        final callKitDisposeGate = Completer<void>();
        systemCall
          ..endStarted = endStarted
          ..endGate = endGate
          ..disposeStarted = callKitDisposeStarted
          ..disposeGate = callKitDisposeGate;

        var completed = false;
        final closing = controller.close();
        unawaited(closing.then((_) => completed = true));
        expect(controller.close(), same(closing));
        await awaitableTracker.firstCancellationStarted.future;
        expect(awaitableTracker.channels, isEmpty);
        expect(completed, isFalse);

        await controlled.waitForPendingPluginWrites(1);
        // Local media stops without waiting for the server to accept the leave.
        await mediaDisposeStarted.future;
        expect(media.disposeCount, 1);
        controlled.pendingPluginWrites.single.response.complete({});
        await pumpEventQueue();
        expect(endStarted.isCompleted, isFalse);
        expect(completed, isFalse);

        mediaDisposeGate.complete();
        await endStarted.future;
        expect(systemCall.ends, 1);
        expect(completed, isFalse);

        endGate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(callKitDisposeStarted.isCompleted, isFalse);
        expect(completed, isFalse);

        awaitableTracker.cancellationGate.complete();
        await callKitDisposeStarted.future;
        expect(completed, isFalse);

        callKitDisposeGate.complete();
        await closing;

        expect(completed, isTrue);
        expect(media.disposeCount, 1);
        expect(systemCall.disposeCount, 1);
      },
    );

    test(
      'reaches every teardown step after native session-close failures',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single
          ..disposeFailure = StateError('media disposal rejected');
        systemCall
          ..endFailure = StateError('system end rejected')
          ..disposeFailure = StateError('CallKit disposal rejected');

        await controller.close().timeout(const Duration(seconds: 1));

        expect(controller.call, isNull);
        expect(media.disposeCount, 1);
        expect(systemCall.ends, 1);
        expect(systemCall.disposeCount, 1);
      },
    );

    test(
      'keeps leave terminal and idempotent when native teardown fails',
      () async {
        await pumpEventQueue();
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single
          ..disposeFailure = StateError('media disposal rejected');
        systemCall.endFailure = StateError('system end rejected');

        final firstLeave = controller.leave();
        final duplicateLeave = controller.leave();

        expect(duplicateLeave, same(firstLeave));
        await Future.wait([firstLeave, duplicateLeave]);
        expect(controller.call, isNull);
        expect(media.disposeCount, 1);
        expect(systemCall.ends, 1);

        await controller.leave();
        expect(media.disposeCount, 1);
        expect(systemCall.ends, 1);
      },
    );

    test('events from another room leave the call alone', () async {
      transport.responses['GET /voice/rooms.json'] = {
        'index_message_bus_last_id': 144,
        'rooms': [
          fixture('room'),
          {...fixture('room'), 'id': 8, 'slug': 'other-room'},
        ],
      };
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;

      firstTracker.deliver('/voice/rooms/8', {
        'type': 'signal',
        'sender_id': 2,
        'data': {'type': 'offer'},
      });
      firstTracker.deliver('/voice/rooms/8', {
        'type': 'recording',
        'room_id': 8,
        'recording': {
          'started_at': 1786204800,
          'started_by': {'id': 2, 'username': 'lee'},
        },
      });
      firstTracker.deliver('/voice/rooms/8', {'type': 'kicked', 'room_id': 8});
      await pumpEventQueue();

      expect(controller.call?.room.id, 7);
      expect(controller.call?.room.recording, isNull);
      expect(controller.room(firstSite, 8)?.recording?.active, isTrue);
      expect(media.signals, isEmpty);
      expect(media.disposeCount, 0);
    });

    test(
      'tears media down after kicks, room destruction, and account removal',
      () async {
        Future<void> join() async {
          await controller.ensureLoaded(firstSite, force: true);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
        }

        await join();
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'kicked',
          'room_id': 7,
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.call, isNull);
        expect(
          transport.writes.where((write) => write.path.endsWith('/leave.json')),
          isEmpty,
        );

        await join();
        firstTracker.deliver('/voice/rooms/index', {
          'type': 'destroyed',
          'room': (fixture('directory')['rooms'] as List<dynamic>).first,
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.call, isNull);

        await join();
        controller.forget(firstSite);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.call, isNull);
        expect(controller.directory(firstSite), isNull);
      },
    );
  });

  group('rooms reached by link', () {
    Map<String, dynamic> callRoom({int id = 9, String slug = 'call-1a2b'}) => {
      'id': id,
      'name': '📞 sam + kim',
      'slug': slug,
      'public': false,
      'ephemeral': true,
      'room_type': 'open',
      'message_bus_last_id': 12,
      'can_manage': true,
      'active_participants': [
        {'id': 3, 'username': 'kim', 'role': 'moderator'},
      ],
      'ringing': const <Object?>[],
    };

    test(
      'subscribes a linked call room from its cursor and applies its events',
      () async {
        transport.responses['GET /voice/rooms/call-1a2b.json'] = callRoom();
        await controller.ensureLoaded(firstSite);

        final resolved = await controller.resolveRoom(firstSite, 'call-1a2b');

        expect(resolved?.ephemeral, isTrue);
        expect(firstTracker.subscriberCount('/voice/rooms/9'), 1);
        expect(firstTracker.lastIds['/voice/rooms/9'], 12);

        firstTracker.deliver('/voice/rooms/9', {
          'type': 'participants',
          'participants': [
            {'id': 3, 'username': 'kim', 'role': 'moderator'},
            {'id': 1, 'username': 'sam', 'role': 'moderator'},
          ],
        });
        expect(controller.room(firstSite, 9)?.participants.map((p) => p.id), [
          3,
          1,
        ]);

        firstTracker.deliver('/voice/rooms/9', {
          'type': 'ringing',
          'room_id': 9,
          'user': {'id': 4, 'username': 'ann'},
          'notified_at': 1786204800,
        });
        expect(
          controller.room(firstSite, 9)?.ringing.single.user.username,
          'ann',
        );

        firstTracker.deliver('/voice/rooms/9', {
          'type': 'recording',
          'room_id': 9,
          'recording': {
            'started_at': 1786204800,
            'started_by': {'id': 3, 'username': 'kim'},
          },
        });
        expect(controller.room(firstSite, 9)?.recording?.startedById, 3);

        firstTracker.deliver('/voice/rooms/9', {
          'type': 'hand_raise',
          'room_id': 9,
          'user_id': 1,
          'raised': true,
          'raised_at': 1786204801.5,
          'reason': 'raised',
        });
        expect(
          controller
              .room(firstSite, 9)
              ?.participants
              .singleWhere((p) => p.id == 1)
              .handRaisedAt,
          DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
        );
      },
    );

    test('delivers signals for a call joined through a link', () async {
      transport.responses['GET /voice/rooms/call-1a2b.json'] = callRoom();
      transport.responses['POST /voice/rooms/9/join.json'] = {
        ...fixture('join_mesh'),
        'room': callRoom(),
      };
      transport.responses['DELETE /voice/rooms/9/leave.json'] = {};
      transport.responses['POST /voice/rooms/9/state.json'] = {};
      await controller.ensureLoaded(firstSite);
      final resolved = await controller.resolveRoom(firstSite, 'call-1a2b');

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: resolved!,
      );
      firstTracker.deliver('/voice/rooms/9', {
        'type': 'signal',
        'room_id': 9,
        'sender_id': 3,
        'sender': {'id': 3, 'username': 'kim'},
        'events': [
          {'type': 'offer', 'sdp': 'offer'},
        ],
      });
      await pumpEventQueue();

      final media = mediaFactory.sessions.single;
      expect(media.signals.map((signal) => signal.$1), [3]);
      expect(firstTracker.subscriberCount('/voice/rooms/9'), 1);

      await controller.leave();
      expect(firstTracker.subscriberCount('/voice/rooms/9'), 1);
    });

    test(
      'bounds linked rooms per site, never evicting the active call',
      () async {
        transport.responses['GET /voice/rooms/call-1a2b.json'] = callRoom();
        transport.responses['POST /voice/rooms/9/join.json'] = {
          ...fixture('join_mesh'),
          'room': callRoom(),
        };
        transport.responses['DELETE /voice/rooms/9/leave.json'] = {};
        transport.responses['POST /voice/rooms/9/state.json'] = {};
        await controller.ensureLoaded(firstSite);
        final resolved = await controller.resolveRoom(firstSite, 'call-1a2b');
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: resolved!,
        );

        for (var id = 20; id < 30; id++) {
          transport.responses['GET /voice/rooms/link-$id.json'] = callRoom(
            id: id,
            slug: 'link-$id',
          );
          await controller.resolveRoom(firstSite, 'link-$id');
        }

        expect(firstTracker.subscriberCount('/voice/rooms/9'), 1);
        expect(
          [for (var id = 20; id < 30; id++) controller.room(firstSite, id)?.id],
          [null, null, null, 23, 24, 25, 26, 27, 28, 29],
        );
        expect(firstTracker.subscriberCount('/voice/rooms/22'), 0);
        expect(firstTracker.subscriberCount('/voice/rooms/29'), 1);
      },
    );

    test('drops a linked room the directory reports destroyed', () async {
      transport.responses['GET /voice/rooms/call-1a2b.json'] = callRoom();
      await controller.ensureLoaded(firstSite);
      await controller.resolveRoom(firstSite, 'call-1a2b');

      firstTracker.deliver('/voice/rooms/index', {
        'type': 'destroyed',
        'room': callRoom(),
      });

      expect(controller.room(firstSite, 9), isNull);
      expect(firstTracker.subscriberCount('/voice/rooms/9'), 0);
    });

    test('does not link a room destroyed while resolving it', () async {
      final controlled = _ControlledVoiceTransport(
        responses: {'GET /voice/rooms.json': fixture('directory')},
      )..heldPluginPaths.add('/voice/rooms/call-1a2b.json');
      useTransport(controlled);
      await controller.ensureLoaded(firstSite);
      final resolving = controller.resolveRoom(firstSite, 'call-1a2b');
      await pumpEventQueue();
      expect(controlled.pendingPluginGets, hasLength(1));

      firstTracker.deliver('/voice/rooms/index', {
        'type': 'destroyed',
        'room': callRoom(),
      });
      controlled.pendingPluginGets.single.response.complete(callRoom());

      expect(await resolving, isNull);
      expect(controller.room(firstSite, 9), isNull);
      expect(firstTracker.subscriberCount('/voice/rooms/9'), 0);
    });

    test("keeps a linked room's Chat across a directory refresh", () async {
      transport.responses['GET /voice/rooms/call-1a2b.json'] = callRoom();
      transport.responses['GET /voice/rooms/9/chat_session.json'] = fixture(
        'chat',
      );
      await controller.ensureLoaded(firstSite);
      await controller.resolveRoom(firstSite, 'call-1a2b');
      await controller.openChat(firstSite, 9);
      final conversation = chatConversations.find(
        siteUrl: firstSite,
        channelId: 42,
        threadId: 99,
      )!;

      await controller.ensureLoaded(firstSite, force: true);

      expect(
        controller.chat(firstSite, 9)?.messages.map((message) => message.id),
        [10],
      );
      expect(conversation.closeCalls, 0);
      expect(firstTracker.subscriberCount('/voice/rooms/9/chat'), 1);
    });
  });

  group('room permission updates', () {
    Map<String, dynamic> revokedRoom() => {
      ...fixture('room'),
      'can_manage': false,
      'can_invite': false,
      'membership': null,
      'chat_available': false,
      'chat_channel_id': null,
      'chat_idle_minutes': null,
      'livekit_enabled': false,
    };

    Object userFields(VoiceRoom room) => (
      room.canManage,
      room.canInvite,
      room.membership?.id,
      room.chatAvailable,
      room.chatChannelId,
      room.chatIdleMinutes,
      room.livekitEnabled,
    );

    Future<void> loadAndJoin({bool listed = true}) async {
      final rich = fixture('room');
      transport.responses['GET /voice/rooms.json'] = {
        'rooms': [if (listed) rich],
      };
      transport.responses['GET /voice/rooms/conf-room-1.json'] = {'room': rich};
      transport.responses['POST /voice/rooms/7/join.json'] = {
        ...fixture('join_mesh'),
        'room': rich,
      };
      await controller.ensureLoaded(firstSite);
      final room = await controller.resolveRoom(firstSite, 'conf-room-1');
      await controller.join(siteUrl: firstSite, siteName: 'One', room: room!);
    }

    for (final type in ['updated', 'created']) {
      test(
        '$type broadcasts preserve directory and active-call permissions',
        () async {
          await loadAndJoin();
          final call = controller.call!;
          final expected = userFields(call.room);
          for (var i = 0; i < 2; i++) {
            firstTracker.deliver(
              '/voice/rooms/index',
              renamedRoomEvent(type: type),
            );
            expect(userFields(controller.room(firstSite, 7)!), expected);
            expect(userFields(controller.call!.room), expected);
            expect(controller.call!.room.name, 'Renamed Room');
            expect(controller.call!.room.participants, call.room.participants);
            expect(controller.call!.room.ringing, call.room.ringing);
            expect(
              controller.call!.room.messageBusLastId,
              call.room.messageBusLastId,
            );
            expect(controller.call!.media, same(call.media));
          }

          firstTracker.deliver('/voice/rooms/index', {
            'type': type,
            'room': {'id': 99, 'name': 'New room'},
          });
          expect(controller.room(firstSite, 99)!.canInvite, isFalse);
          expect(controller.room(firstSite, 99)!.canManage, isFalse);
        },
      );
    }

    test(
      'authenticated directory responses revoke and restore every held permission',
      () async {
        await loadAndJoin();
        await controller.ensureLoaded(secondSite);
        final granted = userFields(controller.call!.room);
        final roster = controller.call!.room.participants;
        transport.responses['GET /voice/rooms.json'] = {
          'rooms': [revokedRoom()],
        };

        await controller.ensureLoaded(firstSite, force: true);

        const revoked = (false, false, null, false, null, null, false);
        expect(userFields(controller.room(firstSite, 7)!), revoked);
        expect(userFields(controller.call!.room), revoked);
        expect(controller.call!.room.participants, roster);
        expect(userFields(controller.room(secondSite, 7)!), granted);
        firstTracker.deliver('/voice/rooms/index', renamedRoomEvent());
        expect(userFields(controller.room(firstSite, 7)!), revoked);
        expect(userFields(controller.call!.room), revoked);

        transport.responses['GET /voice/rooms.json'] = {
          'rooms': [fixture('room')],
        };
        await controller.ensureLoaded(firstSite, force: true);
        expect(userFields(controller.room(firstSite, 7)!), granted);
        expect(userFields(controller.call!.room), granted);
      },
    );

    test(
      'a delayed directory response cannot undo a newer room save',
      () async {
        final controlled = _ControlledVoiceTransport();
        useTransport(controlled);
        await loadAndJoin();
        controlled.heldPluginPaths.add('/voice/rooms.json');
        final loading = controller.ensureLoaded(firstSite, force: true);
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));
        controlled.responses['PUT /voice/rooms/7.json'] = {
          'room': {...revokedRoom(), 'name': 'Edited room'},
        };
        await controller.saveRoom(
          siteUrl: firstSite,
          roomId: 7,
          draft: const VoiceRoomDraft(
            name: 'Edited room',
            isPublic: false,
            type: VoiceRoomType.stage,
          ),
        );
        controlled.pendingPluginGets.single.response.complete({
          'rooms': [fixture('room')],
        });
        await loading;

        const revoked = (false, false, null, false, null, null, false);
        expect(userFields(controller.room(firstSite, 7)!), revoked);
        expect(userFields(controller.call!.room), revoked);
        expect(controller.room(firstSite, 7)!.name, 'Edited room');
        expect(controller.call!.room.name, 'Edited room');
      },
    );

    test(
      'a directory read during a pending join cannot undo its grant',
      () async {
        final controlled = _ControlledVoiceTransport(
          responses: {
            'GET /voice/rooms.json': {
              'rooms': [revokedRoom()],
            },
            'POST /voice/rooms/7/state.json': <String, dynamic>{},
            'DELETE /voice/rooms/7/leave.json': <String, dynamic>{},
          },
        );
        useTransport(controlled);
        await controller.ensureLoaded(firstSite);
        controlled.heldPluginWritePaths.add('/voice/rooms/7/join.json');
        final joining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        await controlled.waitForPendingPluginWrites(1);
        controlled.heldPluginPaths.add('/voice/rooms.json');
        final loading = controller.ensureLoaded(firstSite, force: true);
        await pumpEventQueue();
        expect(controlled.pendingPluginGets, hasLength(1));
        controlled.pendingPluginWrites.single.response.complete({
          ...fixture('join_mesh'),
          'room': fixture('room'),
        });
        await joining;
        controlled.pendingPluginGets.single.response.complete({
          'rooms': [revokedRoom()],
        });
        await loading;

        final granted = userFields(VoiceRoom.fromJson(fixture('room')));
        expect(userFields(controller.room(firstSite, 7)!), granted);
        expect(userFields(controller.call!.room), granted);
      },
    );

    test(
      'a saved room refreshes permissions even if the directory reload fails',
      () async {
        await loadAndJoin();
        transport.responses['PUT /voice/rooms/7.json'] = {
          'room': revokedRoom(),
        };
        transport.failures['GET /voice/rooms.json'] = StateError('offline');

        final saved = await controller.saveRoom(
          siteUrl: firstSite,
          roomId: 7,
          draft: const VoiceRoomDraft(
            name: 'Conf Room 1',
            isPublic: false,
            type: VoiceRoomType.stage,
          ),
        );

        expect(saved, isNotNull);
        const revoked = (false, false, null, false, null, null, false);
        expect(userFields(controller.room(firstSite, 7)!), revoked);
        expect(userFields(controller.call!.room), revoked);
      },
    );

    test(
      'a linked room response revokes permissions in the active call and retained link',
      () async {
        await loadAndJoin(listed: false);
        transport.responses['GET /voice/rooms/conf-room-1.json'] = {
          'room': revokedRoom(),
        };
        await controller.resolveRoom(firstSite, 'conf-room-1');

        const revoked = (false, false, null, false, null, null, false);
        expect(userFields(controller.call!.room), revoked);
        await controller.leave();
        expect(userFields(controller.room(firstSite, 7)!), revoked);
      },
    );

    test(
      'join revocations update the directory and remain revoked after broadcasts',
      () async {
        transport.responses['GET /voice/rooms.json'] = {
          'rooms': [fixture('room')],
        };
        transport.responses['POST /voice/rooms/7/join.json'] = {
          ...fixture('join_mesh'),
          'room': revokedRoom(),
        };
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        firstTracker.deliver('/voice/rooms/index', renamedRoomEvent());

        const revoked = (false, false, null, false, null, null, false);
        expect(userFields(controller.room(firstSite, 7)!), revoked);
        expect(userFields(controller.call!.room), revoked);
      },
    );
  });

  group('room updates during a call', () {
    Map<String, dynamic> openJoin({bool video = false}) {
      final payload = fixture('join_mesh');
      final room = payload['room'] as Map<String, dynamic>;
      room['video_enabled'] = video;
      room['video_allowed'] = video;
      return payload;
    }

    test(
      'renames and retypes the active call room and re-applies the stage rule',
      () async {
        transport.responses['POST /voice/rooms/7/join.json'] = openJoin();
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        expect(controller.call?.muted, isFalse);
        final notices = <VoiceNotice>[];
        controller.notices.listen(notices.add);

        firstTracker.deliver('/voice/rooms/index', renamedRoomEvent());
        await pumpEventQueue();

        expect(controller.call?.room.name, 'Renamed Room');
        expect(controller.call?.room.type, VoiceRoomType.stage);
        expect(
          controller.call?.room.participants.map(
            (participant) => participant.id,
          ),
          [1],
        );
        expect(controller.call?.muted, isTrue);
        expect(media.audioPublishingAllowed, isFalse);
        expect(media.muted, isTrue);
        expect(notices, isEmpty);
      },
    );

    test(
      'silences a speaker the retype demotes before publishing settles',
      () async {
        transport.responses['POST /voice/rooms/7/join.json'] = openJoin();
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final media = mediaFactory.sessions.single;
        expect(media.muted, isFalse);
        final publishing = Completer<void>();
        media.audioPublishingGate = publishing;
        addTearDown(() {
          if (!publishing.isCompleted) publishing.complete();
        });

        firstTracker.deliver('/voice/rooms/index', renamedRoomEvent());
        await pumpEventQueue();

        expect(controller.call?.muted, isTrue);
        expect(media.muted, isTrue);
        publishing.complete();
        await pumpEventQueue();
        expect(media.audioPublishingAllowed, isFalse);
        expect(media.muted, isTrue);
      },
    );

    test('stops a camera the room no longer allows and says so', () async {
      transport.responses['POST /voice/rooms/7/join.json'] = openJoin(
        video: true,
      );
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;
      await controller.setCameraEnabled(true);
      expect(controller.call?.cameraEnabled, isTrue);
      final notices = <VoiceNotice>[];
      controller.notices.listen(notices.add);

      firstTracker.deliver('/voice/rooms/index', {
        'type': 'updated',
        'room': {
          ...openJoin()['room'] as Map<String, dynamic>,
          'video_enabled': false,
          'video_allowed': false,
        },
      });
      await pumpEventQueue();

      expect(controller.call?.cameraEnabled, isFalse);
      expect(media.camera, isFalse);
      expect(controller.call?.muted, isFalse);
      expect(notices.map((notice) => notice.message), [
        'Video was turned off in this room.',
      ]);
      final stateWrites = transport.writes
          .where((write) => write.path.endsWith('/state.json'))
          .toList();
      expect(stateWrites.last.body['video'], isFalse);
    });
  });

  group('heartbeat expulsion', () {
    Future<void> joinRoom() async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
    }

    test('leaves the call when a heartbeat is refused as expelled', () async {
      await joinRoom();
      transport
          .failures['POST /voice/rooms/7/heartbeat.json'] = const WriteException(
        WriteFailure.forbidden,
        statusCode: 403,
        errors: [
          'Your call session has expired. Rejoin the room to start a new one.',
        ],
      );

      controller.setForeground(true);
      await pumpEventQueue();

      expect(controller.call, isNull);
      expect(
        controller.errorFor(firstSite),
        'Your call session has expired. Rejoin the room to start a new one.',
      );
      expect(
        transport.writes.where((write) => write.path.endsWith('/leave.json')),
        hasLength(1),
      );
      expect(
        controller.room(firstSite, 7)!.participants.map((p) => p.id),
        isNot(contains(1)),
      );
      expect(mediaFactory.sessions.single.disposeCount, 1);
    });

    test('unwinds locally when the room behind a heartbeat is gone', () async {
      await joinRoom();
      transport.failures['POST /voice/rooms/7/heartbeat.json'] =
          const WriteException(WriteFailure.validation, statusCode: 404);

      controller.setForeground(true);
      await pumpEventQueue();

      expect(controller.call, isNull);
      expect(
        controller.errorFor(firstSite),
        'Your call session has expired. Rejoin the room to start a new one.',
      );
      expect(
        transport.writes.where((write) => write.path.endsWith('/leave.json')),
        isEmpty,
      );
    });

    test('keeps the call through a transient heartbeat failure', () async {
      await joinRoom();
      transport.failures['POST /voice/rooms/7/heartbeat.json'] =
          const WriteException(WriteFailure.unreachable, statusCode: 502);

      controller.setForeground(true);
      await pumpEventQueue();

      expect(controller.call?.status, VoiceCallStatus.connected);
      expect(controller.errorFor(firstSite), isNull);
    });
  });

  group('room notices', () {
    late List<VoiceNotice> notices;

    Future<void> joinAsManager({
      List<Map<String, Object?>> roster = const [
        {'id': 1, 'username': 'sam', 'role': 'participant'},
        {'id': 2, 'username': 'lee', 'role': 'participant'},
      ],
      bool canManage = true,
    }) async {
      final payload = fixture('join_mesh');
      final room = payload['room'] as Map<String, dynamic>;
      room['room_type'] = 'stage';
      room['can_manage'] = canManage;
      room['active_participants'] = roster;
      transport.responses['POST /voice/rooms/7/join.json'] = payload;
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      notices = [];
      controller.notices.listen(notices.add);
    }

    test(
      'applies a hand raise before the roster confirms it and tells managers',
      () async {
        await joinAsManager();
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 1, 'username': 'sam', 'role': 'participant'},
            {'id': 2, 'username': 'lee', 'role': 'participant'},
          ],
        });

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'hand_raise',
          'room_id': 7,
          'user_id': 2,
          'raised': true,
          'raised_at': 1786204801.5,
          'reason': 'raised',
        });
        await pumpEventQueue();

        expect(
          controller.call?.room.participants
              .singleWhere((participant) => participant.id == 2)
              .handRaisedAt,
          DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
        );
        expect(
          controller
              .room(firstSite, 7)
              ?.participants
              .singleWhere((participant) => participant.id == 2)
              .handRaisedAt,
          DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
        );
        expect(notices.map((notice) => notice.message), [
          'lee raised their hand to speak.',
        ]);

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'hand_raise',
          'room_id': 7,
          'user_id': 2,
          'raised': false,
          'reason': 'dismissed',
        });
        await pumpEventQueue();
        expect(
          controller.call?.room.participants
              .singleWhere((participant) => participant.id == 2)
              .handRaisedAt,
          isNull,
        );
        expect(notices, hasLength(1));

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'hand_raise',
          'room_id': 7,
          'user_id': 1,
          'raised': false,
          'reason': 'lowered',
        });
        await pumpEventQueue();
        expect(notices, hasLength(1));

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'hand_raise',
          'room_id': 7,
          'user_id': 1,
          'raised': false,
          'reason': 'dismissed',
        });
        await pumpEventQueue();
        expect(notices.last.message, 'Your request to speak was dismissed.');
      },
    );

    test('only managers hear about raised hands', () async {
      await joinAsManager(canManage: false);

      firstTracker.deliver('/voice/rooms/7', {
        'type': 'hand_raise',
        'room_id': 7,
        'user_id': 2,
        'raised': true,
        'raised_at': 1786204801.5,
        'reason': 'raised',
      });
      await pumpEventQueue();

      expect(
        controller.call?.room.participants
            .singleWhere((participant) => participant.id == 2)
            .handRaisedAt,
        isNotNull,
      );
      expect(notices, isEmpty);
    });

    test('announces own role changes only', () async {
      await joinAsManager();

      firstTracker.deliver('/voice/rooms/7', {
        'type': 'role_change',
        'room_id': 7,
        'user_id': 2,
        'role': 'speaker',
      });
      await pumpEventQueue();
      expect(notices, isEmpty);

      firstTracker.deliver('/voice/rooms/7', {
        'type': 'role_change',
        'room_id': 7,
        'user_id': 1,
        'role': 'speaker',
      });
      firstTracker.deliver('/voice/rooms/7', {
        'type': 'role_change',
        'room_id': 7,
        'user_id': 1,
        'role': 'participant',
      });
      await pumpEventQueue();
      expect(notices.map((notice) => notice.message), [
        "You've been made a speaker.",
        "You've been moved to listeners.",
      ]);
    });

    test('tells participants when someone else records the call', () async {
      await joinAsManager();

      firstTracker.deliver('/voice/rooms/7', {
        'type': 'recording',
        'room_id': 7,
        'recording': null,
      });
      firstTracker.deliver('/voice/rooms/7', {
        'type': 'recording',
        'room_id': 7,
        'recording': {
          'started_at': 1786204800,
          'started_by': {'id': 2, 'username': 'lee'},
        },
      });
      firstTracker.deliver('/voice/rooms/7', {
        'type': 'recording',
        'room_id': 7,
        'recording': null,
      });
      firstTracker.deliver('/voice/rooms/7', {
        'type': 'recording',
        'room_id': 7,
        'recording': {
          'started_at': 1786204900,
          'started_by': {'id': 1, 'username': 'sam'},
        },
      });
      await pumpEventQueue();

      expect(notices.map((notice) => notice.message), [
        'This call is now being recorded.',
        'The recording has stopped.',
      ]);
      expect(controller.call?.room.recording?.startedById, 1);
    });

    test('notices stop with the controller', () async {
      await joinAsManager();
      var done = false;
      controller.notices.listen(null, onDone: () => done = true);

      await controller.close();
      await pumpEventQueue();

      expect(done, isTrue);
    });
  });

  group('idle ladder', () {
    late ManualScheduler scheduler;
    late VoiceIdleThresholds thresholds;

    Future<void> joinOpenRoom() async {
      scheduler = ManualScheduler();
      thresholds = (
        idle: const Duration(minutes: 5),
        afk: const Duration(minutes: 15),
        disconnect: const Duration(minutes: 30),
      );
      controller.dispose();
      systemCall = FakeVoiceSystemCall();
      mediaFactory = FakeVoiceMediaFactory();
      transport.responses['POST /voice/rooms/7/join.json'] = fixture(
        'join_mesh',
      );
      controller = VoiceController(
        api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
        chatConversations: chatConversations,
        requests: requests,
        trackerFor: (siteUrl) => siteUrl == firstSite ? firstTracker : null,
        userIdFor: (_) => 1,
        onCallSiteChanged: () {},
        mediaFactory: mediaFactory,
        systemCall: systemCall,

        preferences: preferences,
        idleThresholdsFor: (_) => thresholds,
        idleClock: scheduler.now,
        timerFactory: scheduler.createTimer,
        heartbeatInterval: const Duration(days: 1),
        signalBatchDelay: Duration.zero,
      );
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
    }

    Iterable<Object?> heartbeatIdleStates() => transport.writes
        .where((write) => write.path.endsWith('/heartbeat.json'))
        .map((write) => write.body['idle_state']);

    VoiceIdleState? localIdleState() => controller.call?.room.participants
        .where((participant) => participant.id == 1)
        .firstOrNull
        ?.idleState;

    test('going to the background is not being away', () async {
      await joinOpenRoom();

      controller.setForeground(false);
      await pumpEventQueue();
      scheduler.advance(const Duration(minutes: 4));
      controller.setForeground(true);
      await pumpEventQueue();

      expect(heartbeatIdleStates(), everyElement('active'));
      expect(controller.call?.muted, isFalse);
      expect(localIdleState(), VoiceIdleState.active);
    });

    test(
      'climbs to idle, mutes when away, and reports the mute on return',
      () async {
        await joinOpenRoom();
        final notices = <VoiceNotice>[];
        controller.notices.listen(notices.add);
        final media = mediaFactory.sessions.single;

        scheduler.advance(const Duration(minutes: 5, seconds: 30));
        await pumpEventQueue();
        expect(heartbeatIdleStates().last, 'idle');
        expect(localIdleState(), VoiceIdleState.idle);
        expect(controller.call?.muted, isFalse);

        scheduler.advance(const Duration(minutes: 10));
        await pumpEventQueue();
        expect(heartbeatIdleStates().last, 'afk');
        expect(localIdleState(), VoiceIdleState.afk);
        expect(controller.call?.muted, isTrue);
        expect(media.muted, isTrue);
        expect(systemCall.systemMuted, isTrue);
        expect(notices, isEmpty);

        controller.setForeground(true);
        await pumpEventQueue();
        expect(heartbeatIdleStates().last, 'active');
        expect(localIdleState(), VoiceIdleState.active);
        expect(controller.call?.muted, isTrue);
        expect(notices.map((notice) => notice.message), [
          'You were auto-muted after being idle. Unmute to keep talking.',
        ]);
      },
    );

    test('a deliberate unmute is not reported as automatic later', () async {
      await joinOpenRoom();
      final notices = <VoiceNotice>[];
      controller.notices.listen(notices.add);

      scheduler.advance(const Duration(minutes: 16));
      await pumpEventQueue();
      expect(controller.call?.muted, isTrue);
      await controller.setMuted(false);
      scheduler.advance(const Duration(minutes: 16));
      await pumpEventQueue();
      expect(controller.call?.muted, isTrue);
      await controller.setMuted(false);
      await controller.setMuted(true);
      controller.setForeground(true);
      await pumpEventQueue();

      expect(notices, isEmpty);
    });

    test('speaking keeps the participant present', () async {
      await joinOpenRoom();
      final media = mediaFactory.sessions.single;

      for (var minute = 0; minute < 40; minute++) {
        scheduler.advance(const Duration(minutes: 1));
        media.speaking = const {1};
        media.notifyListeners();
      }
      await pumpEventQueue();

      expect(controller.call?.status, VoiceCallStatus.connected);
      expect(controller.call?.muted, isFalse);
      expect(heartbeatIdleStates(), everyElement('active'));
    });

    test('leaves the call after the disconnect threshold', () async {
      await joinOpenRoom();

      scheduler.advance(const Duration(minutes: 31));
      await pumpEventQueue();
      await pumpEventQueue();

      expect(controller.call, isNull);
      expect(
        controller.errorFor(firstSite),
        'You were disconnected from Conf Room 1 due to inactivity.',
      );
      expect(
        transport.writes.where((write) => write.path.endsWith('/leave.json')),
        hasLength(1),
      );
      expect(scheduler.activeTimerCount, 0);
    });

    test('stops the ladder with the call', () async {
      await joinOpenRoom();
      expect(scheduler.activeTimerCount, 1);

      await controller.leave();

      expect(scheduler.activeTimerCount, 0);
      scheduler.advance(const Duration(hours: 1));
      expect(controller.errorFor(firstSite), isNull);
    });
  });

  group('per-device choices', () {
    test(
      'late startup reads preserve explicit default-valued choices',
      () async {
        final devices = Completer<VoiceDevicePreferences>();
        final status = Completer<bool?>();
        preferences.onReadDevices = () => devices.future;
        preferences.onReadAutoStatus = () => status.future;
        useTransport(transport);
        await controller.setPushToTalkEnabled(false);
        await controller.setAutoStatusEnabled(true);
        devices.complete(
          const VoiceDevicePreferences(
            audioInputDeviceId: 'stored-input',
            audioOutputDeviceId: 'stored-output',
            pushToTalkEnabled: true,
          ),
        );
        status.complete(false);
        await pumpEventQueue();
        expect(
          (controller.pushToTalkEnabled, controller.autoStatusEnabled),
          (false, true),
        );
        expect(controller.audioInputDeviceId, 'stored-input');
        expect(controller.audioOutputDeviceId, 'stored-output');
      },
    );

    test('late startup reads preserve newer explicit choices', () async {
      final devices = Completer<VoiceDevicePreferences>();
      final status = Completer<bool?>();
      preferences.onReadDevices = () => devices.future;
      preferences.onReadAutoStatus = () => status.future;
      useTransport(transport);

      await controller.selectAudioInput('chosen-input');
      await controller.selectAudioOutput('chosen-output');
      await controller.setPushToTalkEnabled(true);
      await controller.setAutoStatusEnabled(false);
      devices.complete(
        const VoiceDevicePreferences(
          audioInputDeviceId: 'stored-input',
          audioOutputDeviceId: 'stored-output',
          cameraDeviceId: 'stored-camera',
        ),
      );
      status.complete(true);
      await pumpEventQueue();

      expect(
        (
          controller.audioInputDeviceId,
          controller.audioOutputDeviceId,
          controller.pushToTalkEnabled,
          controller.autoStatusEnabled,
        ),
        ('chosen-input', 'chosen-output', true, false),
      );
      expect(controller.cameraDeviceId, 'stored-camera');
    });

    for (final input in [true, false]) {
      test(
        'a newer ${input ? 'input' : 'output'} choice supersedes saved-device fallback',
        () async {
          preferences.devices = VoiceDevicePreferences(
            audioInputDeviceId: input ? 'saved' : null,
            audioOutputDeviceId: input ? null : 'saved',
          );
          useTransport(transport);
          final started = Completer<void>();
          final pending = Completer<void>();
          Future<void> failSaved(String value) async {
            if (value == 'saved') {
              started.complete();
              await pending.future;
              throw Exception('device disconnected');
            }
          }

          if (input) {
            mediaFactory.nextAudioInputSelection = failSaved;
          } else {
            mediaFactory.nextAudioOutputSelection = failSaved;
          }
          await controller.ensureLoaded(firstSite);
          final joining = controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          await started.future;
          final selected = input
              ? controller.selectAudioInput('new-choice')
              : controller.selectAudioOutput('new-choice');
          await pumpEventQueue();
          pending.complete();
          await Future.wait([joining, selected]);
          final media = mediaFactory.sessions.single;
          expect(
            input ? media.selectedAudioInput : media.selectedAudioOutput,
            'new-choice',
          );
          expect(
            input ? media.audioInputSelections : media.audioOutputSelections,
            isNot(contains('default')),
          );
        },
      );

      test(
        'newer ${input ? 'input' : 'output'} selection supersedes a pending write',
        () async {
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          final media = mediaFactory.sessions.single;
          final pending = Completer<void>();
          preferences.onWriteDevice = (_, value) async {
            if (value == 'old-choice') await pending.future;
          };
          final select = input
              ? controller.selectAudioInput
              : controller.selectAudioOutput;
          final older = select('old-choice');
          await pumpEventQueue();
          await select('new-choice');
          pending.complete();
          await older;

          expect(
            input
                ? controller.audioInputDeviceId
                : controller.audioOutputDeviceId,
            'new-choice',
          );
          expect(
            input ? media.selectedAudioInput : media.selectedAudioOutput,
            'new-choice',
          );
        },
      );

      test(
        'overlapping ${input ? 'input' : 'output'} SDK selections finish with the newest choice',
        () async {
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          final media = mediaFactory.sessions.single;
          final started = Completer<void>();
          final pending = Completer<void>();
          Future<void> holdOlder(String value) async {
            if (value == 'old-choice') {
              started.complete();
              await pending.future;
            }
          }

          if (input) {
            media.onSelectAudioInput = holdOlder;
          } else {
            media.onSelectAudioOutput = holdOlder;
          }
          final select = input
              ? controller.selectAudioInput
              : controller.selectAudioOutput;
          final older = select('old-choice');
          await started.future;
          final newer = select('new-choice');
          await pumpEventQueue();
          pending.complete();
          await Future.wait([older, newer]);
          expect(
            input ? media.selectedAudioInput : media.selectedAudioOutput,
            'new-choice',
          );
        },
      );

      test(
        'pending ${input ? 'input' : 'output'} preference write cannot select on a replacement call',
        () async {
          await controller.ensureLoaded(firstSite);
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          final original = mediaFactory.sessions.single;
          final started = Completer<void>();
          final pending = Completer<void>();
          preferences.onWriteDevice = (_, value) async {
            started.complete();
            await pending.future;
          };
          final selection = input
              ? controller.selectAudioInput('new-choice')
              : controller.selectAudioOutput('new-choice');
          await started.future;
          await controller.leave();
          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.room(firstSite, 7)!,
          );
          final replacement = mediaFactory.sessions.last;
          final before = List<String>.of(
            input
                ? replacement.audioInputSelections
                : replacement.audioOutputSelections,
          );
          pending.complete();
          await selection;
          expect(
            input
                ? replacement.audioInputSelections
                : replacement.audioOutputSelections,
            before,
          );
          expect(
            input ? original.selectedAudioInput : original.selectedAudioOutput,
            isNull,
          );
        },
      );
    }

    test(
      'an older push-to-talk enable cannot mute after a newer disable',
      () async {
        transport.responses['POST /voice/rooms/7/join.json'] = fixture(
          'join_mesh',
        );
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        final pending = Completer<void>();
        preferences.onWritePushToTalk = (value) async {
          if (value) await pending.future;
        };
        final older = controller.setPushToTalkEnabled(true);
        await controller.setPushToTalkEnabled(false);
        pending.complete();
        await older;
        expect(controller.pushToTalkEnabled, isFalse);
        expect(controller.call!.muted, isFalse);
      },
    );

    test('a restored status choice shapes the join request', () async {
      preferences.autoStatusEnabled = false;
      useTransport(transport);
      await pumpEventQueue();
      expect(controller.autoStatusEnabled, isFalse);

      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      final join = transport.writes.singleWhere(
        (write) => write.path.endsWith('/join.json'),
      );
      expect(join.body['skip_status'], isTrue);
    });

    Future<void> joinOpenRoom() async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
    }

    void expectJoinedMuted() {
      expect(controller.call!.muted, isTrue);
      expect(mediaFactory.sessions.single.muted, isTrue);
      expect(systemCall.systemMuted, isTrue);
      final state = transport.writes.lastWhere(
        (write) => write.path.endsWith('/state.json'),
      );
      expect(state.body['muted'], isTrue);
    }

    test('a restored push-to-talk choice joins an open room muted', () async {
      transport.responses['POST /voice/rooms/7/join.json'] = fixture(
        'join_mesh',
      );
      preferences.devices = const VoiceDevicePreferences(
        pushToTalkEnabled: true,
      );
      useTransport(transport);
      await pumpEventQueue();
      expect(controller.pushToTalkEnabled, isTrue);

      await joinOpenRoom();

      expectJoinedMuted();
    });

    test(
      'a join that starts before push-to-talk is restored still joins muted',
      () async {
        transport.responses['POST /voice/rooms/7/join.json'] = fixture(
          'join_mesh',
        );
        final devices = Completer<VoiceDevicePreferences>();
        preferences.onReadDevices = () => devices.future;
        addTearDown(() {
          if (!devices.isCompleted) {
            devices.complete(const VoiceDevicePreferences());
          }
        });
        useTransport(transport);

        final joining = joinOpenRoom();
        await pumpEventQueue();
        expect(controller.call, isNull);
        devices.complete(const VoiceDevicePreferences(pushToTalkEnabled: true));
        await joining;

        expectJoinedMuted();
      },
    );

    test('close cancels a join waiting for device preferences', () async {
      final devices = Completer<VoiceDevicePreferences>();
      preferences.onReadDevices = () => devices.future;
      addTearDown(() {
        if (!devices.isCompleted) {
          devices.complete(const VoiceDevicePreferences());
        }
      });
      useTransport(transport);
      final joining = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: VoiceRoom.fromJson(fixture('room')),
      );
      await pumpEventQueue();
      expect(controller.isJoining(firstSite, 7), isTrue);
      await controller.close().timeout(const Duration(seconds: 1));
      await joining;
      expect(devices.isCompleted, isFalse);
      expect(mediaFactory.sessions, isEmpty);
      expect(
        transport.writes.where((write) => write.path.endsWith('/join.json')),
        isEmpty,
      );
      expect(systemCall.starts, 0);
    });

    test('the default status choice leaves the join request alone', () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      final join = transport.writes.singleWhere(
        (write) => write.path.endsWith('/join.json'),
      );
      expect(join.body['skip_status'], isNull);
    });

    test('changing the status choice persists it', () async {
      await controller.setAutoStatusEnabled(false);

      expect(controller.autoStatusEnabled, isFalse);
      expect(preferences.writes, contains('autoStatus:false'));
    });

    test(
      'the privacy acknowledgement is read and written per device',
      () async {
        expect(await controller.meshPrivacyAcknowledged(), isFalse);

        await controller.acknowledgeMeshPrivacy();

        expect(await controller.meshPrivacyAcknowledged(), isTrue);
        expect(preferences.writes, contains('meshPrivacy:true'));
      },
    );

    test('an unreadable acknowledgement keeps the warning', () async {
      preferences.rejectVolumeReads = true;
      preferences.meshPrivacyAcknowledged = true;

      expect(await controller.meshPrivacyAcknowledged(), isTrue);
    });
  });

  group('stage role changes', () {
    test(
      'agent roster fields survive lightweight events and agent role edits make no requests',
      () async {
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'participants',
          'participants': [
            {'id': 1, 'username': 'sam', 'role': 'moderator'},
            {
              'id': -1400,
              'username': 'bot',
              'role': 'speaker',
              'external_agent': true,
              'livekit_identity': 'agent-dashboard',
            },
            {
              'id': 42,
              'username': 'flagged_bot',
              'role': 'speaker',
              'external_agent': true,
              'livekit_identity': 'another-agent',
            },
          ],
        });
        await pumpEventQueue();
        for (final event in [
          {'type': 'role_change', 'user_id': -1400, 'role': 'participant'},
          {
            'type': 'hand_raise',
            'user_id': -1400,
            'raised': true,
            'raised_at': '2026-09-21T10:00:00Z',
          },
        ]) {
          firstTracker.deliver('/voice/rooms/7', event);
          await pumpEventQueue();
          final agent = controller.call!.room.participants.firstWhere(
            (p) => p.id == -1400,
          );
          expect(agent.externalAgent, isTrue);
          expect(agent.livekitIdentity, 'agent-dashboard');
          expect(agent.role, VoiceRole.participant);
        }
        final previousWrites = transport.writes.length;
        await controller.setParticipantRole(-1400, VoiceRole.speaker);
        await controller.setParticipantRole(42, VoiceRole.participant);
        expect(transport.writes.length, previousWrites);
      },
    );

    test('write a membership for the active room', () async {
      transport.responses['POST /voice/rooms/7/memberships.json'] = {};
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      await controller.setParticipantRole(2, VoiceRole.speaker);
      await controller.setParticipantRole(2, VoiceRole.participant);

      final writes = transport.writes
          .where((write) => write.path.endsWith('/memberships.json'))
          .toList();
      expect(writes.map((write) => write.method), ['POST', 'POST']);
      // The transport drops null fields before sending; the fake records the
      // request as built.
      expect(
        writes.map(
          (write) => {...write.body}..removeWhere((_, value) => value == null),
        ),
        [
          {'user_id': 2, 'role': 'speaker'},
          {'user_id': 2, 'role': 'participant'},
        ],
      );
    });

    test('do nothing outside a call', () async {
      await controller.setParticipantRole(2, VoiceRole.speaker);

      expect(transport.writes, isEmpty);
    });
  });

  group('direct calls', () {
    late ManualScheduler scheduler;
    late _ControlledVoiceTransport callTransport;
    late PluginTestRequestHost callRequests;
    final ringSentAt = DateTime.utc(2026, 8, 8, 16);
    var now = DateTime.utc(2026, 8, 8, 16, 0, 10);
    var meshPrivacyWarning = false;
    Completer<bool?>? capabilityGate;
    VoidCallback? onAnswer;
    VoidCallback? onPrivacyFlag;
    VoidCallback? onSiteName;
    final answeredRooms = <({String siteUrl, int roomId})>[];

    Map<String, dynamic> callRoom() => {
      'id': 9,
      'name': '📞 kim + sam',
      'slug': 'call-1a2b',
      'public': false,
      'ephemeral': true,
      'room_type': 'open',
      'message_bus_last_id': 3,
      'active_participants': [
        {'id': 3, 'username': 'kim', 'role': 'moderator'},
      ],
      'ringing': [
        {
          'user': {'id': 1, 'username': 'sam'},
          'notified_at': 1786204800,
        },
      ],
    };

    Map<String, dynamic> ring({int sentAt = 1786204800}) => {
      'room_id': 9,
      'room_slug': 'call-1a2b',
      'room_name': '📞 kim + sam',
      'caller_username': 'kim',
      'caller_name': 'Kim',
      'caller_avatar_template': '/user_avatar/example.com/kim/{size}/3_2.png',
      'sent_at': sentAt,
      'ring_seconds': 60,
    };

    setUp(() {
      scheduler = ManualScheduler();
      now = DateTime.utc(2026, 8, 8, 16, 0, 10);
      meshPrivacyWarning = false;
      capabilityGate = null;
      onAnswer = null;
      onPrivacyFlag = null;
      onSiteName = null;
      answeredRooms.clear();
      controller.dispose();
      // Disposing the controller disposed the fakes it owned.
      systemCall = FakeVoiceSystemCall();
      mediaFactory = FakeVoiceMediaFactory();
      callTransport = _ControlledVoiceTransport(responses: transport.responses);
      transport = callTransport;
      callRequests = PluginTestRequestHost(apiKeys: {firstSite: 'key'});
      requests = callRequests;
      transport.responses['GET /voice/rooms/call-1a2b.json'] = callRoom();
      transport.responses['POST /voice/calls.json'] = {'room': callRoom()};
      transport.responses['POST /voice/rooms/9/join.json'] = {
        ...fixture('join_mesh'),
        'room': callRoom(),
      };
      transport.responses['DELETE /voice/rooms/9/leave.json'] = {};
      transport.responses['POST /voice/rooms/9/state.json'] = {};
      controller = VoiceController(
        api: VoiceApi(transport, namespaceFor: (_) => VoiceNamespace.voice),
        chatConversations: chatConversations,
        requests: requests,
        trackerFor: (siteUrl) => siteUrl == firstSite ? firstTracker : null,
        userIdFor: (_) => 1,
        capabilityEnabledFor: (_) => capabilityGate?.future ?? Future.value(),
        onCallSiteChanged: () {},
        mediaFactory: mediaFactory,
        systemCall: systemCall,

        preferences: preferences,
        timerFactory: scheduler.createTimer,
        clock: () => now,
        siteNameFor: (_) {
          onSiteName?.call();
          return 'One';
        },
        meshPrivacyWarningEnabledFor: (_) {
          onPrivacyFlag?.call();
          return meshPrivacyWarning;
        },
        onIncomingCallAnswered: (siteUrl, room) {
          answeredRooms.add((siteUrl: siteUrl, roomId: room.id));
          onAnswer?.call();
        },
        heartbeatInterval: const Duration(days: 1),
        signalBatchDelay: Duration.zero,
      );
    });

    test(
      'watches the per-user ring channel once the site is tracked',
      () async {
        await controller.ensureLoaded(firstSite);

        expect(firstTracker.subscriberCount('/voice/call-ring/1'), 1);
        expect(firstTracker.lastIds['/voice/call-ring/1'], isNull);

        controller.forget(firstSite);
        expect(firstTracker.subscriberCount('/voice/call-ring/1'), 0);
      },
    );

    test('a ring within its window is offered until it runs out', () async {
      await controller.ensureLoaded(firstSite);
      var notifications = 0;
      controller.addListener(() => notifications++);

      firstTracker.deliver('/voice/call-ring/1', ring());

      final incoming = controller.incomingCall!;
      expect(
        (
          roomId: incoming.roomId,
          slug: incoming.roomSlug,
          caller: incoming.caller.username,
          name: incoming.caller.name,
          sentAt: incoming.sentAt,
          remaining: incoming.remainingAt(now),
        ),
        (
          roomId: 9,
          slug: 'call-1a2b',
          caller: 'kim',
          name: 'Kim',
          sentAt: ringSentAt,
          remaining: const Duration(seconds: 50),
        ),
      );
      expect(controller.incomingCallSiteUrl, firstSite);
      expect(notifications, 1);

      scheduler.advance(const Duration(seconds: 49));
      expect(controller.incomingCall, isNotNull);
      scheduler.advance(const Duration(seconds: 1));
      expect(controller.incomingCall, isNull);
      expect(notifications, 2);
    });

    test('an expired or repeated ring is dropped', () async {
      await controller.ensureLoaded(firstSite);

      now = DateTime.utc(2026, 8, 8, 16, 1, 1);
      firstTracker.deliver('/voice/call-ring/1', ring());
      expect(controller.incomingCall, isNull);

      now = DateTime.utc(2026, 8, 8, 16, 0, 10);
      firstTracker.deliver('/voice/call-ring/1', ring());
      controller.declineIncomingCall();
      firstTracker.deliver('/voice/call-ring/1', ring());
      expect(controller.incomingCall, isNull);
      expect(scheduler.activeTimerCount, 0);

      firstTracker.deliver('/voice/call-ring/1', ring(sentAt: 1786204815));
      expect(
        controller.incomingCall?.sentAt,
        DateTime.utc(2026, 8, 8, 16, 0, 15),
      );
    });

    test(
      'ring replay history retains only the latest fifty identities',
      () async {
        await controller.ensureLoaded(firstSite);
        for (var index = 0; index < 51; index++) {
          firstTracker.deliver(
            '/voice/call-ring/1',
            ring(sentAt: 1786204800 + index),
          );
          controller.declineIncomingCall();
        }
        firstTracker.deliver('/voice/call-ring/1', ring(sentAt: 1786204850));
        expect(controller.incomingCall, isNull);
        firstTracker.deliver('/voice/call-ring/1', ring());
        expect(controller.incomingCall?.sentAt, ringSentAt);
      },
    );

    test('a ring for the room the user is already in is nothing new', () async {
      await controller.ensureLoaded(firstSite);
      final room = await controller.resolveRoom(firstSite, 'call-1a2b');
      await controller.join(siteUrl: firstSite, siteName: 'One', room: room!);

      firstTracker.deliver('/voice/call-ring/1', ring());

      expect(controller.incomingCall, isNull);
    });

    test('joining the ringing room settles the ring', () async {
      await controller.ensureLoaded(firstSite);
      firstTracker.deliver('/voice/call-ring/1', ring());
      expect(controller.incomingCall, isNotNull);

      final room = await controller.resolveRoom(firstSite, 'call-1a2b');
      await controller.join(siteUrl: firstSite, siteName: 'One', room: room!);

      expect(controller.incomingCall, isNull);
      expect(scheduler.activeTimerCount, 1, reason: 'only the idle check');
    });

    test('answering resolves the call room and credits the caller', () async {
      await controller.ensureLoaded(firstSite);
      firstTracker.deliver('/voice/call-ring/1', ring());

      final accepted = await controller.acceptIncomingCall();

      expect(accepted?.siteUrl, firstSite);
      expect(accepted?.room.id, 9);
      expect(controller.incomingCall, isNull);
      expect(firstTracker.subscriberCount('/voice/rooms/9'), 1);

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: accepted!.room,
      );
      final join = transport.writes.singleWhere(
        (write) => write.path.endsWith('/join.json'),
      );
      expect(join.body['invited_by'], 'kim');
      expect(await controller.acceptIncomingCall(), isNull);
    });

    group('answer lifetime', () {
      Future<void> offerCall() async {
        systemCall.presentsIncomingCalls = true;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();
      }

      Future<void> replaceAccount() async {
        controller.forget(firstSite);
        callRequests
          ..forget(firstSite)
          ..apiKeys[firstSite] = 'replacement-key';
        await controller.ensureLoaded(firstSite);
      }

      for (final invalidation in ['forget', 'replace', 'dispose']) {
        test('stops after CallKit answer when $invalidation occurs', () async {
          await offerCall();
          final gate = Completer<void>();
          systemCall.incomingAnswerGate = gate;
          final accepting = controller.acceptIncomingCall();
          expect(systemCall.incomingAnswers, 1);
          expect(await controller.acceptIncomingCall(), isNull);

          switch (invalidation) {
            case 'forget':
              await replaceAccount();
            case 'replace':
              callRequests
                ..forget(firstSite)
                ..apiKeys[firstSite] = 'replacement-key';
            case 'dispose':
              controller.dispose();
          }
          gate.complete();
          final accepted = await accepting;

          expect(
            callTransport.pluginGets,
            isNot(contains('/voice/rooms/call-1a2b.json')),
          );
          expect(accepted, isNull);
          expect(controller.room(firstSite, 9), isNull);
          expect(mediaFactory.sessions, isEmpty);
          expect(systemCall.failures, 0);
          if (invalidation != 'dispose') {
            await controller.join(
              siteUrl: firstSite,
              siteName: 'Replacement',
              room: VoiceRoom.fromJson(callRoom()),
            );
            expect(
              transport.writes
                  .singleWhere((write) => write.path.endsWith('/join.json'))
                  .body['invited_by'],
              isNull,
            );
          }
        });
      }

      test(
        'keeps the original session while room capability is pending',
        () async {
          await offerCall();
          final gate = Completer<bool?>();
          capabilityGate = gate;
          final accepting = controller.acceptIncomingCall(fromSystem: true);
          await pumpEventQueue();
          capabilityGate = null;
          await replaceAccount();

          gate.complete(true);
          expect(await accepting, isNull);
          expect(
            callTransport.pluginGets,
            isNot(contains('/voice/rooms/call-1a2b.json')),
          );
          expect(controller.room(firstSite, 9), isNull);
        },
      );

      for (final failure in [false, true]) {
        test(
          'ignores a stale room ${failure ? 'failure' : 'response'} without failing a newer call',
          () async {
            await offerCall();
            callTransport.heldPluginPaths.add('/voice/rooms/call-1a2b.json');
            systemCall.send(VoiceSystemCallAction.answer);
            await pumpEventQueue();
            final pending = callTransport.pendingPluginGets.single;
            await replaceAccount();
            await controller.join(
              siteUrl: firstSite,
              siteName: 'Replacement',
              room: controller.room(firstSite, 7)!,
            );
            final newerMedia = controller.call!.media;

            if (failure) {
              pending.response.completeError(
                StateError('old room unavailable'),
              );
            } else {
              pending.response.complete(callRoom());
            }
            await pumpEventQueue();

            expect(systemCall.failures, 0);
            expect(systemCall.ends, 0);
            expect(answeredRooms, isEmpty);
            expect(controller.call?.media, same(newerMedia));
            expect(controller.room(firstSite, 9), isNull);
          },
        );
      }

      test('rechecks the session after room observers run', () async {
        await offerCall();
        controller.addListener(() {
          if (controller.room(firstSite, 9) != null) {
            controller.forget(firstSite);
          }
        });

        expect(await controller.acceptIncomingCall(), isNull);
        expect(controller.room(firstSite, 9), isNull);
      });

      test('account retirement keeps duplicate system answers inert', () async {
        await offerCall();
        callTransport.heldPluginPaths.add('/voice/rooms/call-1a2b.json');
        systemCall.send(VoiceSystemCallAction.answer);
        await pumpEventQueue();
        final pending = callTransport.pendingPluginGets.single;

        await replaceAccount();
        systemCall.send(VoiceSystemCallAction.answer);
        await pumpEventQueue();
        pending.response.complete(callRoom());
        await pumpEventQueue();

        expect(systemCall.failures, 0);
        expect(answeredRooms, isEmpty);
        expect(controller.call, isNull);
        expect(controller.room(firstSite, 9), isNull);
      });

      for (final invalidation in [
        'forget',
        'dispose',
        'new ring',
        'join',
        'end',
      ]) {
        test(
          'stops the system answer after privacy read and $invalidation',
          () async {
            meshPrivacyWarning = true;
            transport.responses['GET /voice/rooms/call-1a2b.json'] = {
              ...callRoom(),
              'expected_transport': 'mesh',
            };
            await offerCall();
            final started = Completer<void>();
            final gate = Completer<void>();
            preferences
              ..meshPrivacyReadStarted = started
              ..meshPrivacyReadGate = gate;
            final notices = <VoiceNotice>[];
            controller.notices.listen(notices.add);
            systemCall.send(VoiceSystemCallAction.answer);
            await started.future;

            switch (invalidation) {
              case 'forget':
                await replaceAccount();
              case 'dispose':
                controller.dispose();
              case 'new ring':
                firstTracker.deliver(
                  '/voice/call-ring/1',
                  ring(sentAt: 1786204815),
                );
                await pumpEventQueue();
              case 'join':
                await controller.join(
                  siteUrl: firstSite,
                  siteName: 'One',
                  room: controller.room(firstSite, 7)!,
                );
              case 'end':
                systemCall.send(VoiceSystemCallAction.end);
                await pumpEventQueue();
            }
            gate.complete();
            await pumpEventQueue();

            expect(answeredRooms, isEmpty);
            expect(notices, isEmpty);
            expect(
              transport.writes.where(
                (write) => write.path == '/voice/rooms/9/join.json',
              ),
              isEmpty,
            );
            expect(systemCall.failures, 0);
            expect(systemCall.ends, 0);
            if (invalidation == 'join') expect(controller.call?.room.id, 7);
            if (invalidation == 'new ring') {
              expect(
                controller.incomingCall?.sentAt,
                DateTime.utc(2026, 8, 8, 16, 0, 15),
              );
            }
          },
        );
      }

      for (final callback in ['navigation', 'privacy flag', 'site name']) {
        test('rechecks the lifetime after the $callback callback', () async {
          await offerCall();
          void invalidate() => controller.forget(firstSite);
          switch (callback) {
            case 'navigation':
              onAnswer = invalidate;
            case 'privacy flag':
              onPrivacyFlag = invalidate;
            case 'site name':
              onSiteName = invalidate;
          }

          systemCall.send(VoiceSystemCallAction.answer);
          await pumpEventQueue();

          expect(mediaFactory.sessions, isEmpty);
          expect(transport.writes, isEmpty);
          expect(systemCall.failures, 0);
        });
      }

      test(
        'an unresolved current answer still fails the system call',
        () async {
          await offerCall();
          callTransport.heldPluginPaths.add('/voice/rooms/call-1a2b.json');
          systemCall.send(VoiceSystemCallAction.answer);
          await pumpEventQueue();

          callTransport.pendingPluginGets.single.response.completeError(
            StateError('room unavailable'),
          );
          await pumpEventQueue();

          expect(systemCall.failures, 1);
          expect(answeredRooms, isEmpty);
          expect(mediaFactory.sessions, isEmpty);
        },
      );

      test(
        'duplicate system answers do not fail or toggle the accepted call',
        () async {
          await offerCall();
          callTransport.heldPluginPaths.add('/voice/rooms/call-1a2b.json');
          systemCall.send(VoiceSystemCallAction.answer);
          await pumpEventQueue();
          systemCall.send(VoiceSystemCallAction.answer);
          await pumpEventQueue();
          expect(systemCall.failures, 0);
          expect(callTransport.pendingPluginGets, hasLength(1));

          callTransport.pendingPluginGets.single.response.complete(callRoom());
          await pumpEventQueue();
          systemCall.send(VoiceSystemCallAction.answer);
          await pumpEventQueue();

          expect(systemCall.failures, 0);
          expect(systemCall.ends, 0);
          expect(controller.call?.room.id, 9);
          expect(mediaFactory.sessions, hasLength(1));
          expect(answeredRooms, [(siteUrl: firstSite, roomId: 9)]);
        },
      );
    });

    test('calling someone holds and subscribes the call room', () async {
      await controller.ensureLoaded(firstSite);

      final outgoing = (await controller.callUser(firstSite, 'kim'))!;
      final room = outgoing.room;

      final request = transport.writes.singleWhere(
        (write) => write.path == '/voice/calls.json',
      );
      expect(request.method, 'POST');
      expect(request.body, {'username': 'kim'});
      expect(outgoing.siteUrl, firstSite);
      expect(outgoing.isCurrent, isTrue);
      expect(room.ephemeral, isTrue);
      expect(controller.room(firstSite, 9)?.slug, 'call-1a2b');
      expect(firstTracker.subscriberCount('/voice/rooms/9'), 1);
      expect(room.activeRingingAt(now).map((entry) => entry.user.username), [
        'sam',
      ]);
    });

    test(
      "keeps the call room's Chat when the site's directory first loads",
      () async {
        transport.responses['GET /voice/rooms/9/chat_session.json'] = fixture(
          'chat',
        );
        final outgoing = (await controller.callUser(firstSite, 'kim'))!;
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: outgoing.room,
        );
        await controller.openChat(firstSite, 9);
        final conversation = chatConversations.find(
          siteUrl: firstSite,
          channelId: 42,
          threadId: 99,
        )!;

        await controller.ensureLoaded(firstSite);

        expect(controller.call?.room.id, 9);
        expect(
          controller.chat(firstSite, 9)?.messages.map((message) => message.id),
          [10],
        );
        expect(conversation.closeCalls, 0);
        expect(firstTracker.subscriberCount('/voice/rooms/9/chat'), 1);
      },
    );

    test("a refused call propagates the server's reason", () async {
      transport.failures['POST /voice/calls.json'] = const WriteException(
        WriteFailure.forbidden,
        statusCode: 403,
        errors: ['Sorry, you cannot call that user.'],
      );

      await expectLater(
        controller.callUser(firstSite, 'kim'),
        throwsA(
          isA<WriteException>().having(
            (error) => error.message,
            'message',
            'Sorry, you cannot call that user.',
          ),
        ),
      );
      expect(controller.room(firstSite, 9), isNull);
    });

    group('through the system call UI', () {
      test('a ring is offered to the system by username and site', () async {
        await controller.ensureLoaded(firstSite);

        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();

        expect(systemCall.reportedIncomingCalls, [
          (
            callerName: '@kim · one.example.com',
            roomName: '📞 kim + sam',
            handle: 'kim@one.example.com',
          ),
        ]);
        expect(controller.incomingCallHandledBySystem, isFalse);
        expect(controller.incomingCall, isNotNull);
      });

      test("the app's own banner yields to a system presentation", () async {
        systemCall.presentsIncomingCalls = true;
        await controller.ensureLoaded(firstSite);
        var notifications = 0;
        controller.addListener(() => notifications++);

        firstTracker.deliver('/voice/call-ring/1', ring());
        expect(controller.incomingCallHandledBySystem, isFalse);
        await pumpEventQueue();

        expect(controller.incomingCallHandledBySystem, isTrue);
        expect(notifications, 2);

        scheduler.advance(const Duration(seconds: 50));
        expect(controller.incomingCall, isNull);
        expect(systemCall.incomingEnds, [
          VoiceIncomingCallEndReason.unanswered,
        ]);
      });

      test("a system refusal keeps the app's banner", () async {
        systemCall.reportIncomingFailure = StateError('CallKit unavailable');
        await controller.ensureLoaded(firstSite);

        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();

        expect(controller.incomingCall, isNotNull);
        expect(controller.incomingCallHandledBySystem, isFalse);
      });

      test('a ring that ends before the system answers is withdrawn', () async {
        systemCall
          ..presentsIncomingCalls = true
          ..reportIncomingGate = Completer<void>();
        await controller.ensureLoaded(firstSite);

        firstTracker.deliver('/voice/call-ring/1', ring());
        controller.declineIncomingCall();
        systemCall.reportIncomingGate!.complete();
        await pumpEventQueue();

        expect(controller.incomingCallHandledBySystem, isFalse);
        expect(systemCall.incomingDeclines, 0);
        expect(systemCall.incomingEnds, [
          VoiceIncomingCallEndReason.unanswered,
        ]);
      });

      test('expiry withdraws a presentation that completes late', () async {
        final presentation = Completer<void>();
        systemCall
          ..presentsIncomingCalls = true
          ..reportIncomingGate = presentation;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());

        scheduler.advance(const Duration(seconds: 50));
        expect(controller.incomingCall, isNull);
        expect(scheduler.activeTimerCount, 0);
        presentation.complete();
        await pumpEventQueue();

        expect(controller.incomingCallHandledBySystem, isFalse);
        expect(systemCall.incomingEnds, [
          VoiceIncomingCallEndReason.unanswered,
        ]);
      });

      test('late presentation leaves the replacement ring intact', () async {
        final previousPresentation = Completer<void>();
        systemCall
          ..presentsIncomingCalls = true
          ..reportIncomingGate = previousPresentation;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());

        final nextPresentation = Completer<void>();
        systemCall.reportIncomingGate = nextPresentation;
        firstTracker.deliver('/voice/call-ring/1', ring(sentAt: 1786204815));
        previousPresentation.complete();
        await pumpEventQueue();

        expect(
          controller.incomingCall?.sentAt,
          ringSentAt.add(const Duration(seconds: 15)),
        );
        expect(controller.incomingCallHandledBySystem, isFalse);
        expect(scheduler.activeTimerCount, 1);
        expect(systemCall.incomingEnds, [
          VoiceIncomingCallEndReason.unanswered,
        ]);

        nextPresentation.complete();
        await pumpEventQueue();
        expect(controller.incomingCallHandledBySystem, isTrue);
        scheduler.advance(const Duration(seconds: 50));
        expect(controller.incomingCall, isNotNull);
        scheduler.advance(const Duration(seconds: 15));
        expect(controller.incomingCall, isNull);
        expect(systemCall.incomingEnds, [
          VoiceIncomingCallEndReason.unanswered,
          VoiceIncomingCallEndReason.unanswered,
        ]);
      });

      test('close does not wait for a pending presentation', () async {
        final presentation = Completer<void>();
        systemCall
          ..presentsIncomingCalls = true
          ..reportIncomingGate = presentation;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());

        await controller.close();

        expect(presentation.isCompleted, isFalse);
        expect(controller.incomingCall, isNull);
        expect(scheduler.activeTimerCount, 0);
        expect(systemCall.disposeCount, 1);
        presentation.complete();
        await pumpEventQueue();
        expect(systemCall.incomingEnds, isEmpty);
      });

      test('declining in the app declines the system call', () async {
        systemCall.presentsIncomingCalls = true;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();

        controller.declineIncomingCall();
        await pumpEventQueue();

        expect(controller.incomingCall, isNull);
        expect(systemCall.incomingDeclines, 1);
        expect(systemCall.incomingEnds, isEmpty);
      });

      test('a decline from the system is not echoed back', () async {
        systemCall.presentsIncomingCalls = true;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();

        systemCall.send(VoiceSystemCallAction.decline);
        await pumpEventQueue();

        expect(controller.incomingCall, isNull);
        expect(systemCall.incomingDeclines, 0);
        expect(systemCall.incomingEnds, isEmpty);
      });

      test('answering in the app answers the system call first', () async {
        systemCall.presentsIncomingCalls = true;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();

        final accepted = await controller.acceptIncomingCall();

        expect(accepted?.room.id, 9);
        expect(systemCall.incomingAnswers, 1);
        expect(systemCall.incomingEnds, isEmpty);
      });

      Future<List<VoiceNotice>> answerFromSystem({
        required String expectedTransport,
      }) async {
        systemCall.presentsIncomingCalls = true;
        transport.responses['GET /voice/rooms/call-1a2b.json'] = {
          ...callRoom(),
          'expected_transport': expectedTransport,
        };
        await controller.ensureLoaded(firstSite);
        final notices = <VoiceNotice>[];
        controller.notices.listen(notices.add);
        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();

        systemCall.send(VoiceSystemCallAction.answer);
        await pumpEventQueue();
        await pumpEventQueue();
        return notices;
      }

      Iterable<PluginTransportRequest> joinWrites() => transport.writes.where(
        (write) => write.path == '/voice/rooms/9/join.json',
      );

      test(
        'an answer from the system waits for the privacy warning in the app',
        () async {
          meshPrivacyWarning = true;
          final notices = await answerFromSystem(expectedTransport: 'mesh');

          expect(answeredRooms, [(siteUrl: firstSite, roomId: 9)]);
          expect(controller.answeredCallAwaitingConfirmation?.room.id, 9);
          expect(controller.call, isNull);
          expect(joinWrites(), isEmpty);
          expect(systemCall.starts, 0);
          expect(notices, isEmpty);

          await controller.join(
            siteUrl: firstSite,
            siteName: 'One',
            room: controller.answeredCallAwaitingConfirmation!.room,
          );

          expect(controller.call?.room.id, 9);
          expect(controller.answeredCallAwaitingConfirmation, isNull);
          expect(systemCall.starts, 1);
          expect(joinWrites().single.body['invited_by'], 'kim');
          scheduler.advance(voiceAnswerConfirmationWindow);
          await pumpEventQueue();
          expect(systemCall.failures, 0);
          expect(systemCall.ends, 0);
        },
      );

      for (final reason in ['acknowledged', 'disabled', 'not mesh']) {
        test('an answer from the system joins directly when the warning is '
            '$reason', () async {
          meshPrivacyWarning = reason != 'disabled';
          preferences.meshPrivacyAcknowledged = reason == 'acknowledged';
          final notices = await answerFromSystem(
            expectedTransport: reason == 'not mesh' ? 'livekit' : 'mesh',
          );

          expect(controller.call?.room.id, 9);
          expect(controller.call?.siteName, 'One');
          expect(controller.answeredCallAwaitingConfirmation, isNull);
          expect(answeredRooms, [(siteUrl: firstSite, roomId: 9)]);
          expect(systemCall.incomingAnswers, 0);
          expect(systemCall.starts, 1);
          expect(systemCall.incomingEnds, isEmpty);
          expect(joinWrites().single.body['invited_by'], 'kim');
          expect(notices, isEmpty);
        });
      }

      for (final waiting in ['the warning', 'the join request']) {
        for (final unmuteAfter in [false, true]) {
          final pressed = unmuteAfter ? 'muted then unmuted' : 'muted';
          test('a system call $pressed while waiting for $waiting joins '
              '${unmuteAfter ? 'unmuted' : 'muted'}', () async {
            final throughWarning = waiting == 'the warning';
            meshPrivacyWarning = throughWarning;
            callTransport.heldPluginWritePaths.add('/voice/rooms/9/join.json');
            await answerFromSystem(expectedTransport: 'mesh');
            Future<void> press() {
              systemCall.send(VoiceSystemCallAction.mute);
              if (unmuteAfter) systemCall.send(VoiceSystemCallAction.unmute);
              return pumpEventQueue();
            }

            Future<void>? joining;
            if (throughWarning) {
              await press();
              joining = controller.join(
                siteUrl: firstSite,
                siteName: 'One',
                room: controller.answeredCallAwaitingConfirmation!.room,
              );
            }
            await callTransport.waitForPendingPluginWrites(1);
            if (!throughWarning) await press();
            callTransport.pendingPluginWrites.single.response.complete({
              ...fixture('join_mesh'),
              'room': callRoom(),
            });
            await joining;
            await pumpEventQueue();

            expect(controller.call?.status, VoiceCallStatus.connected);
            expect(controller.call?.muted, !unmuteAfter);
            expect(mediaFactory.sessions.single.muted, !unmuteAfter);
            expect(systemCall.systemMuted, unmuteAfter ? isNull : isTrue);
          });
        }
      }

      test('a system call muted before its join failed leaves the next join '
          'unmuted', () async {
        callTransport.heldPluginWritePaths.add('/voice/rooms/9/join.json');
        await answerFromSystem(expectedTransport: 'mesh');
        await callTransport.waitForPendingPluginWrites(1);
        systemCall.send(VoiceSystemCallAction.mute);
        await pumpEventQueue();
        callTransport.pendingPluginWrites
            .removeAt(0)
            .response
            .completeError(const WriteException(WriteFailure.forbidden));
        await pumpEventQueue();
        expect(controller.call, isNull);
        expect(systemCall.failures, 1);

        final room = await controller.resolveRoom(firstSite, 'call-1a2b');
        final rejoining = controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: room!,
        );
        await callTransport.waitForPendingPluginWrites(1);
        callTransport.pendingPluginWrites.single.response.complete({
          ...fixture('join_mesh'),
          'room': callRoom(),
        });
        await rejoining;

        expect(controller.call?.status, VoiceCallStatus.connected);
        expect(controller.call?.muted, isFalse);
        expect(mediaFactory.sessions.last.muted, isFalse);
      });

      for (final hangUp in ['the system', 'the app']) {
        test('hanging up from $hangUp while waiting joins nothing', () async {
          meshPrivacyWarning = true;
          await answerFromSystem(expectedTransport: 'mesh');
          expect(controller.answeredCallAwaitingConfirmation, isNotNull);

          if (hangUp == 'the system') {
            systemCall.send(VoiceSystemCallAction.end);
          } else {
            controller.cancelAnsweredCall();
          }
          await pumpEventQueue();

          expect(controller.answeredCallAwaitingConfirmation, isNull);
          expect(systemCall.ends, hangUp == 'the app' ? 1 : 0);
          scheduler.advance(voiceAnswerConfirmationWindow);
          await pumpEventQueue();
          expect(systemCall.failures, 0);
          expect(controller.call, isNull);
          expect(joinWrites(), isEmpty);
        });
      }

      test(
        'a system answer with nothing ringing fails the system call',
        () async {
          await controller.ensureLoaded(firstSite);

          systemCall.send(VoiceSystemCallAction.answer);
          await pumpEventQueue();

          expect(systemCall.failures, 1);
          expect(controller.call, isNull);
        },
      );

      test('joining the ringing room another way tells the system', () async {
        systemCall.presentsIncomingCalls = true;
        await controller.ensureLoaded(firstSite);
        firstTracker.deliver('/voice/call-ring/1', ring());
        await pumpEventQueue();

        final room = await controller.resolveRoom(firstSite, 'call-1a2b');
        await controller.join(siteUrl: firstSite, siteName: 'One', room: room!);

        expect(controller.incomingCall, isNull);
        expect(systemCall.incomingEnds, [
          VoiceIncomingCallEndReason.answeredElsewhere,
        ]);
      });
    });
  });

  group('invites', () {
    const invitePath = '/voice/rooms/7/invites.json';
    const suggestionsPath = '/voice/rooms/7/invites/suggestions.json';

    VoiceUserInvitationSession invitation() {
      final session = controller.userInvitation(firstSite, 7);
      addTearDown(session.dispose);
      return session;
    }

    test(
      'reports accepted and skipped usernames and preserves refusal',
      () async {
        transport.responses['POST $invitePath'] = {
          'invited_usernames': ['kim'],
          'skipped_usernames': ['bot'],
        };
        final session = invitation();
        final outcome = await session.submit(['kim', 'bot']);
        expect(outcome, isA<VoiceUserInvitationAccepted>());
        final result = (outcome as VoiceUserInvitationAccepted).result;
        expect(result.invitedUsernames, ['kim']);
        expect(result.skippedUsernames, ['bot']);
        expect(session.invitedUsernames, {'kim'});
        expect(transport.writes.single.body, {
          'usernames': ['kim', 'bot'],
        });
        const refusal = WriteException(
          WriteFailure.rateLimited,
          statusCode: 429,
          errors: ['Too many invites.'],
        );
        transport.failures['POST $invitePath'] = refusal;
        final refused = await session.submit(['lee']);
        expect(refused, isA<VoiceUserInvitationRefused>());
        expect((refused as VoiceUserInvitationRefused).error, same(refusal));
        expect(session.invitedUsernames, {'kim'});
        expect(session.available, isTrue);
      },
    );

    test('an unavailable shortlist is empty and can be reloaded', () async {
      final session = invitation();
      transport.failures['GET $suggestionsPath'] = const SiteLookupException(
        SiteLookupFailure.unreachable,
        'one',
      );
      await session.loadSuggestions();
      expect(session.suggestions, isEmpty);
      transport.responses['GET $suggestionsPath'] = {
        'suggestions': [
          {'id': 3, 'username': 'kim', 'total_seconds': 120},
        ],
      };
      await session.loadSuggestions();
      expect(session.suggestions!.map((s) => s.user.username), ['kim']);
    });

    test(
      'snapshots normalized names and admits one submission at a time',
      () async {
        final gate = Completer<void>();
        requests = _GatedRequestHost(credentialsGate: gate);
        useTransport(transport);
        transport.responses['POST $invitePath'] = {
          'invited_usernames': ['lee'],
        };
        final session = invitation();
        final names = [' @lee ', '  '];
        final pending = session.submit(names);
        names
          ..clear()
          ..add('replacement');
        expect(await session.submit(['other']), VoiceUserInvitationStatus.busy);
        expect(session.sending, isTrue);
        gate.complete();
        expect(await pending, isA<VoiceUserInvitationAccepted>());
        expect(transport.writes.single.body['usernames'], ['lee']);
        expect(session.invitedUsernames, {'lee'});
        expect(session.sending, isFalse);
        expect(
          await session.submit(['other']),
          isA<VoiceUserInvitationAccepted>(),
        );
        expect(transport.writes.last.body['usernames'], ['other']);
      },
    );

    test('empty input makes no request', () async {
      final session = invitation();
      expect(await session.submit([' ', '']), VoiceUserInvitationStatus.empty);
      expect(transport.writes, isEmpty);
      expect(session.available, isTrue);
    });

    test(
      'a notification may retire admission before credential acquisition',
      () async {
        final counting = _CountingRequestHost();
        requests = counting;
        useTransport(transport);
        final session = invitation();
        session.addListener(session.retire);
        expect(
          await session.submit(['lee']),
          VoiceUserInvitationStatus.retired,
        );
        expect(counting.credentialCalls, 0);
        expect(transport.writes, isEmpty);
      },
    );

    for (final submitting in [false, true]) {
      test(
        '${submitting ? 'invite' : 'suggestions'} retires during credentials',
        () async {
          final gate = Completer<void>();
          requests = _GatedRequestHost(credentialsGate: gate);
          useTransport(transport);
          final session = invitation();
          final pending = submitting
              ? session.submit(['lee'])
              : session.loadSuggestions().then<Object?>((_) => null);
          await pumpEventQueue();
          controller.forget(firstSite);
          gate.complete();
          final result = await pending;
          if (submitting) expect(result, VoiceUserInvitationStatus.retired);
          expect(transport.writes, isEmpty);
          expect(transport.reads, isEmpty);
          expect(session.suggestions, isNull);
          expect(session.invitedUsernames, isEmpty);
        },
      );
    }

    for (final failure in [false, true]) {
      for (final retirement in ['route', 'dispose', 'account']) {
        test(
          'late ${failure ? 'refusal' : 'success'} retires after $retirement',
          () async {
            final host = PluginTestRequestHost(apiKeys: {firstSite: 'key'});
            requests = host;
            final controlled = _ControlledVoiceTransport()
              ..heldPluginWritePaths.add(invitePath);
            useTransport(controlled);
            final session = controller.userInvitation(firstSite, 7);
            if (retirement != 'dispose') addTearDown(session.dispose);
            final pending = session.submit(['lee']);
            await controlled.waitForPendingPluginWrites(1);
            switch (retirement) {
              case 'route':
                session.retire();
              case 'dispose':
                session.dispose();
              case 'account':
                host.forget(firstSite);
            }
            final response = controlled.pendingPluginWrites.single.response;
            if (failure) {
              response.completeError(
                const WriteException(WriteFailure.forbidden),
              );
            } else {
              response.complete({
                'invited_usernames': ['lee'],
                'skipped_usernames': ['bot'],
              });
            }
            expect(await pending, VoiceUserInvitationStatus.retired);
            expect(session.invitedUsernames, isEmpty);
            expect(session.available, isFalse);
            if (retirement == 'account') {
              controlled.heldPluginWritePaths.clear();
              controlled.responses['POST $invitePath'] = {
                'invited_usernames': ['fresh'],
              };
              final fresh = invitation();
              expect(
                await fresh.submit(['fresh']),
                isA<VoiceUserInvitationAccepted>(),
              );
              expect(fresh.invitedUsernames, {'fresh'});
            }
          },
        );
      }
    }

    test('late suggestions cannot publish after disposal', () async {
      final controlled = _ControlledVoiceTransport()
        ..heldPluginPaths.add(suggestionsPath);
      useTransport(controlled);
      final session = controller.userInvitation(firstSite, 7);
      final pending = session.loadSuggestions();
      await pumpEventQueue();
      session.dispose();
      controlled.pendingPluginGets.single.response.complete({
        'suggestions': [
          {'id': 3, 'username': 'kim', 'total_seconds': 120},
        ],
      });
      await pending;
      expect(session.suggestions, isNull);
    });

    for (final submitting in [false, true]) {
      test(
        '${submitting ? 'invite' : 'suggestions'} rechecks deferred dispatch',
        () async {
          final deferred = _DeferredRequestHost()..deferNextRun = true;
          requests = deferred;
          useTransport(transport);
          final session = invitation();
          final pending = submitting
              ? session.submit(['lee'])
              : session.loadSuggestions().then<Object?>((_) => null);
          await deferred.runStarted.future;
          session.retire();
          deferred.runGate.complete();
          final result = await pending;
          if (submitting) expect(result, VoiceUserInvitationStatus.retired);
          expect(transport.writes, isEmpty);
          expect(transport.reads, isEmpty);
        },
      );
    }

    test(
      'retains the credential execution scope for shortlist and submit',
      () async {
        requests = _ScopedRequestHost();
        useTransport(transport);
        final scopes = <Object?>[];
        transport.responders['GET $suggestionsPath'] = (_) {
          scopes.add(Zone.current[_ScopedRequestHost.scope]);
          return {'suggestions': <Object?>[]};
        };
        transport.responders['POST $invitePath'] = (_) {
          scopes.add(Zone.current[_ScopedRequestHost.scope]);
          return {
            'invited_usernames': ['lee'],
          };
        };
        final session = invitation();
        await session.loadSuggestions();
        expect(
          await session.submit(['lee']),
          isA<VoiceUserInvitationAccepted>(),
        );
        expect(scopes, ['full', 'full']);
      },
    );
  });

  group('room Chat live session', () {
    test('a current site is followed on its Live channels', () async {
      useTransport(
        RecordingPluginTransport(
          responses: {
            'GET /live/rooms.json': fixture('directory'),
            'GET /live/rooms/7/chat_session.json': fixture('chat'),
          },
        ),
        namespaceFor: (_) => VoiceNamespace.live,
      );
      await controller.ensureLoaded(firstSite);
      await controller.openChat(firstSite, 7);

      expect(
        firstTracker.channels,
        unorderedEquals([
          '/live/rooms/index',
          '/live/call-ring/1',
          '/live/rooms/7',
          '/live/rooms/7/chat',
        ]),
      );

      transport.responses['GET /live/rooms/7/chat_session.json'] = {
        'channel_id': 42,
        'thread_id': 100,
      };
      firstTracker.deliver('/live/rooms/7/chat', {'type': 'updated'});
      await pumpEventQueue();

      expect(controller.chat(firstSite, 7)?.session.threadId, 100);
      expect(
        transport.reads.map((read) => read.path),
        everyElement(startsWith('/live/')),
      );
    });

    test('the call ring moves to the namespace the site settles on', () async {
      var namespace = VoiceNamespace.voice;
      useTransport(
        RecordingPluginTransport(
          responses: {'GET /live/rooms.json': fixture('directory')},
        ),
        namespaceFor: (_) => namespace,
      );
      // The shell attaches a site's tracker before it fetches the site's
      // settings, so the stored config names the namespace at first.
      controller.attachTracker(firstSite, firstTracker);
      expect(firstTracker.subscriberCount('/voice/call-ring/1'), 1);

      namespace = VoiceNamespace.live;
      await controller.ensureLoaded(firstSite);

      expect(firstTracker.subscriberCount('/voice/call-ring/1'), 0);
      expect(firstTracker.subscriberCount('/live/call-ring/1'), 1);
    });

    test('follows the thread the server rolls the session over to', () async {
      await controller.ensureLoaded(firstSite);
      await controller.openChat(firstSite, 7);
      expect(firstTracker.subscriberCount('/voice/rooms/7/chat'), 1);
      expect(controller.chat(firstSite, 7)?.session.threadId, 99);
      final readsBefore = transport.reads
          .where((read) => read.path.endsWith('/chat_session.json'))
          .length;

      transport.responses['GET /voice/rooms/7/chat_session.json'] = {
        'channel_id': 42,
        'thread_id': 100,
      };
      firstTracker.deliver('/voice/rooms/7/chat', {'type': 'updated'});
      await pumpEventQueue();

      expect(controller.chat(firstSite, 7)?.session.threadId, 100);
      expect(
        transport.reads
            .where((read) => read.path.endsWith('/chat_session.json'))
            .length,
        readsBefore + 1,
      );
      expect(
        chatConversations.opened.map((key) => key.threadId),
        containsAll([99, 100]),
      );
      expect(controller.chat(firstSite, 7)?.loading, isFalse);

      firstTracker.deliver('/voice/rooms/7/chat', {'type': 'noise'});
      await pumpEventQueue();
      expect(
        transport.reads
            .where((read) => read.path.endsWith('/chat_session.json'))
            .length,
        readsBefore + 1,
      );
    });

    test('a send through a thread followed after a failed first message '
        'answers for itself', () async {
      transport.responses['GET /voice/rooms/7/chat_session.json'] = {
        'channel_id': 42,
      };
      transport.failures['POST /voice/rooms/7/chat_message.json'] =
          const SiteLookupException(SiteLookupFailure.unreachable, 'one');
      await controller.ensureLoaded(firstSite);
      await controller.openChat(firstSite, 7);
      await controller.sendChatMessage(firstSite, 7, 'first');
      expect(controller.chat(firstSite, 7)?.error, 'Message not sent.');

      // Someone else's first message opened the thread meanwhile.
      transport.responses['GET /voice/rooms/7/chat_session.json'] = {
        'channel_id': 42,
        'thread_id': 99,
      };
      firstTracker.deliver('/voice/rooms/7/chat', {'type': 'updated'});
      await pumpEventQueue();
      final conversation = chatConversations.find(
        siteUrl: firstSite,
        channelId: 42,
        threadId: 99,
      )!;
      expect(conversation.refreshCalls, 1);

      await controller.sendChatMessage(firstSite, 7, 'first');

      expect(conversation.sentMessages, ['first']);
      expect(controller.chat(firstSite, 7)?.error, isNull);
    });

    test('stops watching when the panel closes', () async {
      await controller.ensureLoaded(firstSite);
      await controller.openChat(firstSite, 7);

      controller.closeChat(firstSite, 7);

      expect(firstTracker.subscriberCount('/voice/rooms/7/chat'), 0);
      final readsBefore = transport.reads.length;
      firstTracker.deliver('/voice/rooms/7/chat', {'type': 'updated'});
      await pumpEventQueue();
      expect(transport.reads.length, readsBefore);
    });

    test('moves the watch to a replacement tracker', () async {
      await controller.ensureLoaded(firstSite);
      await controller.openChat(firstSite, 7);
      final replacement = tracker(firstSite);

      controller.attachTracker(firstSite, replacement);

      expect(firstTracker.subscriberCount('/voice/rooms/7/chat'), 0);
      expect(replacement.subscriberCount('/voice/rooms/7/chat'), 1);
    });

    /// Opens room 7's Chat with its session read held, then has the server
    /// announce a session change while that read is still outstanding: the
    /// panel is already visible, so a tracker sync watches its channel before
    /// the open has read anything.
    Future<
      ({
        Future<void> open,
        _PendingPluginGet openRead,
        _PendingPluginGet updateRead,
      })
    >
    announceUpdateDuringOpen() async {
      final controlled = _ControlledVoiceTransport(
        responses: {'GET /voice/rooms.json': fixture('directory')},
      )..heldPluginPaths.add('/voice/rooms/7/chat_session.json');
      useTransport(controlled);
      chatConversations.seed(
        siteUrl: firstSite,
        channelId: 42,
        threadId: 100,
        snapshot: ChatConversationSnapshot(messages: _chatPage(20).messages),
      );
      await controller.ensureLoaded(firstSite);

      final open = controller.openChat(firstSite, 7);
      await pumpEventQueue();
      controller.attachTracker(firstSite);
      expect(firstTracker.subscriberCount('/voice/rooms/7/chat'), 1);
      firstTracker.deliver('/voice/rooms/7/chat', {'type': 'updated'});
      await pumpEventQueue();

      expect(controlled.pendingPluginGets, hasLength(2));
      return (
        open: open,
        openRead: controlled.pendingPluginGets[0],
        updateRead: controlled.pendingPluginGets[1],
      );
    }

    for (final updateAnswersFirst in [false, true]) {
      final order = updateAnswersFirst ? 'update' : 'open';
      test('an update during the open settles the panel on the newest session '
          '($order read answers first)', () async {
        final race = await announceUpdateDuringOpen();

        void answerOpen() => race.openRead.response.complete(fixture('chat'));
        void answerUpdate() => race.updateRead.response.complete({
          'channel_id': 42,
          'thread_id': 100,
        });
        if (updateAnswersFirst) {
          answerUpdate();
          await pumpEventQueue();
          answerOpen();
        } else {
          answerOpen();
          await pumpEventQueue();
          answerUpdate();
        }
        await race.open;
        await pumpEventQueue();

        final chat = controller.chat(firstSite, 7)!;
        expect(chat.loading, isFalse);
        expect(chat.error, isNull);
        expect(chat.session.threadId, 100);
        expect(chat.messages.map((message) => message.id), [20]);
        expect(chatConversations.opened.map((key) => key.threadId), [100]);
        expect(
          chatConversations
              .find(siteUrl: firstSite, channelId: 42, threadId: 100)!
              .refreshCalls,
          1,
        );
      });

      test('an update read that fails during the open shows the load error '
          '($order read answers first)', () async {
        final race = await announceUpdateDuringOpen();

        void answerOpen() => race.openRead.response.complete(fixture('chat'));
        void failUpdate() => race.updateRead.response.completeError(
          const SiteLookupException(SiteLookupFailure.unreachable, 'one'),
        );
        if (updateAnswersFirst) {
          failUpdate();
          await pumpEventQueue();
          answerOpen();
        } else {
          answerOpen();
          await pumpEventQueue();
          failUpdate();
        }
        await race.open;
        await pumpEventQueue();

        final chat = controller.chat(firstSite, 7)!;
        expect(chat.loading, isFalse);
        expect(chat.error, "Couldn't load room chat.");
        expect(chat.messages, isEmpty);
        expect(chatConversations.opened, isEmpty);
      });
    }
  });
}
