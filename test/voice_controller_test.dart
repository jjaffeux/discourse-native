import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_test.dart'
    show RecordingPluginLiveChannels;
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugins/chat/chat_contract.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_callkit.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_media.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_preferences.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'support/voice_fake_chat_conversations.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

RecordingPluginLiveChannels tracker(String _) => RecordingPluginLiveChannels();

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
  final List<String> correlationIds = [];
  final List<VoiceDiagnosticsRecorder> diagnosticsRecorders = [];
  Completer<void>? nextConnectGate;
  Completer<void>? nextConnectStarted;
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
    VoiceDiagnosticsRecorder diagnostics = const NoopVoiceDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  }) {
    final session =
        FakeVoiceMediaSession(
            join.transport,
            sendSignal: sendSignal,
            refreshLiveKitCredentials: refreshLiveKitCredentials,
            connectGate: nextConnectGate,
            connectStarted: nextConnectStarted,
          )
          ..audioInputFailure = nextAudioInputFailure
          ..audioOutputFailure = nextAudioOutputFailure
          ..onSelectAudioInput = nextAudioInputSelection
          ..onSelectAudioOutput = nextAudioOutputSelection
          ..cameraFailure = nextCameraFailure;
    nextConnectGate = null;
    nextConnectStarted = null;
    nextAudioInputFailure = null;
    nextAudioOutputFailure = null;
    nextAudioInputSelection = null;
    nextAudioOutputSelection = null;
    nextCameraFailure = null;
    correlationIds.add(correlationId);
    diagnosticsRecorders.add(diagnostics);
    sessions.add(session);
    return session;
  }
}

typedef RecordedVoiceDiagnostic = ({
  String event,
  String component,
  DiagnosticSeverity severity,
  String? correlationId,
  String? message,
  Map<String, Object?> data,
});

final class FakeVoiceDiagnosticsRecorder
    implements VoiceDiagnosticsRecorder, VoiceDiagnosticsFlusher {
  @override
  bool captureEnabled = false;

  final List<RecordedVoiceDiagnostic> records = [];
  final List<RecordedVoiceDiagnostic> rawRecords = [];
  Completer<void>? flushStarted;
  Completer<void>? flushGate;
  Object? flushFailure;
  int flushCount = 0;

  @override
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {
    records.add((
      event: event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      message: null,
      data: data,
    ));
  }

  @override
  void recordRaw(
    String event, {
    String component = 'sdk',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  }) {
    rawRecords.add((
      event: event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      message: message,
      data: data,
    ));
  }

  @override
  Future<void> flushDiagnostics() async {
    flushCount++;
    flushStarted?.complete();
    await flushGate?.future;
    if (flushFailure case final failure?) throw failure;
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
  int connectCount = 0;
  int disposeCount = 0;
  bool muted = false;
  bool deafened = false;
  bool camera = false;
  bool screen = false;
  bool audioPublishingAllowed = true;
  Object? signalFailure;
  Object? audioPublishingFailure;
  Object? muteFailure;
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
  Completer<void>? muteGate;
  String? selectedAudioInput;
  String? selectedAudioOutput;
  String? selectedCamera;
  final Map<int, double> participantVolumes = {};
  List<VoiceParticipant> participants = const [];
  final List<(int, Map<String, dynamic>)> signals = [];

  @override
  Object? get localVideoTrack => null;

  @override
  bool get screenSharing => screen;

  @override
  Set<int> get speakingParticipantIds => const {};

  @override
  Object? videoTrackFor(int participantId) => null;

  @override
  Future<void> connect() async {
    connectCount++;
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
    if (audioPublishingFailure case final failure?) throw failure;
  }

  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {
    if (cameraFailure case final failure?) throw failure;
    camera = enabled;
    if (deviceId != null) selectedCamera = deviceId;
  }

  @override
  Future<void> setDeafened(bool enabled) async => deafened = enabled;

  @override
  Future<void> setMuted(bool enabled) async {
    muted = enabled;
    await muteGate?.future;
    if (muteFailure case final failure?) throw failure;
  }

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {
    participantVolumes[participantId] = volume;
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async => screen = enabled;

  @override
  Future<void> syncParticipants(List<VoiceParticipant> value) async {
    participants = value;
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

  @override
  Future<VoiceDevicePreferences> readDevices() async => devices;

  @override
  Future<double?> readParticipantVolume(
    String siteUrl,
    int roomId,
    int userId,
  ) async {
    if (rejectVolumeReads) throw StateError('volume storage unavailable');
    return volumes[(siteUrl, roomId, userId)];
  }

  @override
  Future<void> writeDevice(
    VoiceDevicePreference preference,
    String value,
  ) async {
    writes.add('device:${preference.name}:$value');
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
    if (rejectWrites) throw StateError('push-to-talk write rejected');
  }
}

abstract class _RequestHostBase implements PluginRequestHost {
  @override
  PluginSiteLease capture(String siteUrl) => const _CurrentSiteLease();

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    final credentials = await credentialsFor(siteUrl);
    return (
      apiKey: credentials.apiKey,
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
  Future<void> failed() async {}

  @override
  Future<void> setMuted(bool muted) async => systemMuted = muted;

  @override
  Future<void> start({
    required String roomName,
    required String siteName,
  }) async {
    starts++;
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

typedef _TransportDiagnosticContext = ({
  String path,
  String? operation,
  String? correlationId,
});

final class _ControlledVoiceTransport extends RecordingPluginTransport {
  _ControlledVoiceTransport({super.responses});

  final Set<String> heldPluginPaths = {};
  final Set<String> heldPluginWritePaths = {};
  final Map<String, SiteLookupException> pluginGetFailures = {};
  final List<String> pluginGets = [];
  final List<_PendingPluginGet> pendingPluginGets = [];
  final List<_PendingPluginWrite> pendingPluginWrites = [];
  final List<({int count, Completer<void> completer})> _writeWaiters = [];
  final List<_TransportDiagnosticContext> diagnosticContexts = [];
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
    diagnosticContexts.add((
      path: path,
      operation: DiagnosticsSink.currentOperation,
      correlationId: DiagnosticsSink.currentCorrelationId,
    ));
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
  late FakeVoiceDiagnosticsRecorder diagnostics;
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
    FakeChatConversationCapability? conversations,
    Duration heartbeatInterval = const Duration(days: 1),
  }) {
    controller.dispose();
    transport = value;
    chatConversations = conversations ?? seededChatConversations();
    mediaFactory = FakeVoiceMediaFactory();
    systemCall = FakeVoiceSystemCall();
    controller = VoiceController(
      api: VoiceApi(transport),
      chatConversations: chatConversations,
      requests: requests,
      trackerFor: (siteUrl) => siteUrl == firstSite
          ? firstTracker
          : siteUrl == secondSite
          ? secondTracker
          : null,
      userIdFor: (_) => 1,
      capabilityEnabledFor: capabilityEnabledFor,
      onCallSiteChanged: () {},
      mediaFactory: mediaFactory,
      systemCall: systemCall,
      reporter: const PluginDiagnosticsReporter.ambient(),
      diagnostics: diagnostics,
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
    diagnostics = FakeVoiceDiagnosticsRecorder();
    firstTracker = tracker(firstSite);
    secondTracker = tracker(secondSite);
    chatConversations = seededChatConversations();
    controller = VoiceController(
      api: VoiceApi(transport),
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
      reporter: const PluginDiagnosticsReporter.ambient(),
      diagnostics: diagnostics,
      preferences: preferences,
      heartbeatInterval: const Duration(days: 1),
      signalBatchDelay: Duration.zero,
    );
  });

  tearDown(() => controller.dispose());

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

  group('directory loading', () {
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
      expect(
        diagnostics.records.map((record) => record.event),
        contains('room.directory.skipped'),
      );
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

        controller.forget(firstSite);
        gate.complete();
        await joining;

        expect(controlled.writes, isEmpty);
        expect(controller.call, isNull);
        expect(mediaFactory.sessions, isEmpty);
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
      test(
        'prevent stale ${action.name} when the site is forgotten during credential lookup',
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
          final writesBefore = controlled.writes.length;
          final getsBefore = controlled.pluginGets.length;

          gated.gateNextRead = true;
          final operation = action.begin(controller);
          await gated.readStarted.future;
          controller.forget(firstSite);
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

    for (final action
        in <
          ({
            String name,
            String path,
            Future<void> Function(VoiceController controller) begin,
          })
        >[
          (
            name: 'membership read',
            path: '/voice/rooms/7/memberships.json',
            begin: (controller) async {
              await controller.memberships(firstSite, 7);
            },
          ),
          (
            name: 'membership add',
            path: '/voice/rooms/7/memberships.json',
            begin: (controller) => controller.addMember(
              firstSite,
              7,
              'lee',
              VoiceRole.participant,
            ),
          ),
          (
            name: 'membership update',
            path: '/voice/rooms/7/memberships/9.json',
            begin: (controller) =>
                controller.updateMember(firstSite, 7, 9, VoiceRole.speaker),
          ),
          (
            name: 'membership removal',
            path: '/voice/rooms/7/memberships/9.json',
            begin: (controller) => controller.removeMember(firstSite, 7, 9),
          ),
        ]) {
      test(
        'prevent stale ${action.name} when the site is forgotten during credential lookup',
        () async {
          final gated = _NextGatedRequestHost()..gateNextRead = true;
          requests = gated;
          final controlled = privilegedTransport();
          useTransport(controlled);

          final operation = action.begin(controller);
          await gated.readStarted.future;
          controller.forget(firstSite);
          gated.readGate.complete();
          await operation;

          expect(
            controlled.writes.where((write) => write.path == action.path),
            isEmpty,
          );
          expect(
            controlled.pluginGets.where((path) => path == action.path),
            isEmpty,
          );
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
        final ordinaryDiagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'voice-public-credentials',
        );
        final binding = DiagnosticsSink.install(ordinaryDiagnostics);
        addTearDown(() async {
          binding.close();
          await ordinaryDiagnostics.close();
        });
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
        const operations = {'voice.directory', 'voice.join', 'voice.chat.load'};
        expect(
          diagnostics.records
              .where((record) => record.event == 'runtime.error')
              .map((record) => record.data['operation'])
              .toSet(),
          containsAll(operations),
        );
        final reportedOperations = diagnostics.records
            .where((record) => record.event == 'runtime.error')
            .map((record) => record.data['operation']);
        expect(reportedOperations, isNot(contains('voice.chat.page')));
        expect(reportedOperations, isNot(contains('voice.chat.send')));
        expect(
          ordinaryDiagnostics.events
              .whereType<ErrorDiagnosticEvent>()
              .map((event) => event.operation)
              .toSet(),
          containsAll(operations),
        );
        expect(diagnostics.rawRecords, isEmpty);
        expect(
          ordinaryDiagnostics.buildJsonReport(),
          isNot(contains(privateCause)),
        );
      },
    );

    test(
      'contain ignored admin failures behind the safe diagnostics boundary',
      () async {
        const privateCause =
            'admin-private-user membership-987654321 203.0.113.131';
        final controlled = privilegedTransport();
        useTransport(controlled);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: VoiceRoom.fromJson(fixture('room')),
        );
        final ordinaryDiagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'voice-public-admin',
        );
        final binding = DiagnosticsSink.install(ordinaryDiagnostics);
        addTearDown(() async {
          binding.close();
          await ordinaryDiagnostics.close();
        });
        controlled.operationFailure = PlatformException(
          code: 'admin_operation',
          message: privateCause,
          details: {'userId': 987654321},
        );
        final actions = <Future<void> Function()>[
          () => controller.requestToSpeak(),
          () => controller.kick(2),
          () async {
            await controller.flagParticipant(2, 'Please review');
          },
          () => controller.setRecording(true),
          () async {
            await controller.memberships(firstSite, 7);
          },
          () => controller.addMember(
            firstSite,
            7,
            'admin-private-user',
            VoiceRole.participant,
          ),
          () => controller.updateMember(
            firstSite,
            7,
            987654321,
            VoiceRole.speaker,
          ),
          () => controller.removeMember(firstSite, 7, 987654321),
        ];

        final uncaught = await _captureUncaught(() async {
          for (final action in actions) {
            unawaited(action());
          }
          for (var index = 0; index < 8; index++) {
            await pumpEventQueue();
          }
        });

        expect(uncaught, isEmpty);
        const operations = {
          'voice.requestToSpeak',
          'voice.kick',
          'voice.flag',
          'voice.recording',
          'voice.memberships',
          'voice.membership.add',
          'voice.membership.update',
          'voice.membership.remove',
        };
        expect(
          diagnostics.records
              .where((record) => record.event == 'runtime.error')
              .map((record) => record.data['operation'])
              .toSet(),
          containsAll(operations),
        );
        expect(
          ordinaryDiagnostics.events
              .whereType<ErrorDiagnosticEvent>()
              .map((event) => event.operation)
              .toSet(),
          containsAll(operations),
        );
        expect(diagnostics.rawRecords, isEmpty);
        final ordinaryExport = ordinaryDiagnostics.buildJsonReport();
        expect(ordinaryExport, isNot(contains(privateCause)));
        expect(ordinaryExport, isNot(contains('admin-private-user')));
        expect(ordinaryExport, isNot(contains('987654321')));
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
        final fallback = diagnostics.records.singleWhere(
          (record) =>
              record.event == 'media.device_selection.succeeded' &&
              record.data['origin'] == 'saved_join_fallback',
        );
        expect(fallback.data['kind'], kind);
        expect(fallback.correlationId, mediaFactory.correlationIds.single);
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
        final diagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'voice-preferences',
        );
        final binding = DiagnosticsSink.install(diagnostics);
        addTearDown(() async {
          binding.close();
          await diagnostics.close();
        });
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
        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().map(
            (event) => event.operation,
          ),
          containsAll({
            'voice.preferences.audioInput',
            'voice.preferences.audioOutput',
            'voice.preferences.pushToTalk',
            'voice.preferences.writeVolume',
            'voice.preferences.readVolume',
          }),
        );
      },
    );

    for (final captureEnabled in [false, true]) {
      test('keep stale saved-device failures private with deep capture '
          '${captureEnabled ? 'on' : 'off'}', () async {
        const deviceId = 'private-stale-microphone';
        const sentinelUsername = 'private-participant-name';
        const sentinelUserId = '987654321';
        const sentinelTrackId = 'private-track-id';
        const sentinelStreamId = 'private-stream-id';
        const sentinelIp = '203.0.113.77';
        final ordinaryDiagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'voice-stale-device-$captureEnabled',
        );
        final binding = DiagnosticsSink.install(ordinaryDiagnostics);
        addTearDown(() async {
          binding.close();
          await ordinaryDiagnostics.close();
        });
        preferences.devices = const VoiceDevicePreferences(
          audioInputDeviceId: deviceId,
        );
        diagnostics.captureEnabled = captureEnabled;
        useTransport(transport);
        mediaFactory.nextAudioInputFailure = StateError(
          '$sentinelUsername $sentinelUserId $deviceId $sentinelTrackId '
          '$sentinelStreamId $sentinelIp',
        );
        await pumpEventQueue();

        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );

        final failure = diagnostics.records.singleWhere(
          (record) => record.event == 'media.device_selection.failed',
        );
        expect(failure.data['kind'], 'audio_input');
        expect(failure.data['origin'], 'saved_join');
        expect(failure.data['errorType'], 'StateError');
        expect(failure.correlationId, mediaFactory.correlationIds.single);

        final safeExport = jsonEncode([
          for (final record in diagnostics.records)
            {
              'event': record.event,
              'correlationId': record.correlationId,
              'data': record.data,
            },
        ]);
        expect(safeExport, isNot(contains(deviceId)));
        expect(safeExport, isNot(contains(sentinelUsername)));
        expect(safeExport, isNot(contains(sentinelUserId)));
        expect(safeExport, isNot(contains(sentinelTrackId)));
        expect(safeExport, isNot(contains(sentinelStreamId)));
        expect(safeExport, isNot(contains(sentinelIp)));

        final rawExport = jsonEncode([
          for (final record in diagnostics.rawRecords)
            {
              'event': record.event,
              'message': record.message,
              'data': record.data,
            },
        ]);
        expect(
          rawExport.contains(deviceId),
          captureEnabled,
          reason: 'Device IDs belong only to explicit deep capture.',
        );
        final ordinaryExport = ordinaryDiagnostics.buildJsonReport();
        for (final sentinel in [
          deviceId,
          sentinelUsername,
          sentinelUserId,
          sentinelTrackId,
          sentinelStreamId,
          sentinelIp,
        ]) {
          expect(ordinaryExport, isNot(contains(sentinel)));
        }
        expect(ordinaryExport, contains('StateError'));
        expect(ordinaryExport, contains('voice.join'));
      });
    }

    test(
      'trace saved input and output selection with the call correlation',
      () async {
        preferences.devices = const VoiceDevicePreferences(
          audioInputDeviceId: 'saved-input',
          audioOutputDeviceId: 'saved-output',
        );
        diagnostics.captureEnabled = true;
        useTransport(transport);
        await pumpEventQueue();

        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );

        final saved = diagnostics.records
            .where(
              (record) =>
                  record.event.startsWith('media.device_selection.') &&
                  record.data['origin'] == 'saved_join',
            )
            .toList();
        expect(saved, hasLength(4));
        expect(saved.map((record) => record.data['kind']).toSet(), {
          'audio_input',
          'audio_output',
        });
        expect(
          saved.every(
            (record) =>
                record.correlationId == mediaFactory.correlationIds.single,
          ),
          isTrue,
        );
        final raw = jsonEncode([
          for (final record in diagnostics.rawRecords)
            {'event': record.event, 'data': record.data},
        ]);
        expect(raw, contains('saved-input'));
        expect(raw, contains('saved-output'));
      },
    );

    test('trace explicit input, output, and camera selections', () async {
      diagnostics.captureEnabled = true;
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      await controller.setCameraEnabled(true);

      await controller.selectAudioInput('user-input');
      await controller.selectAudioOutput('user-output');
      await controller.selectCamera('user-camera');

      final explicit = diagnostics.records
          .where(
            (record) =>
                record.event.startsWith('media.device_selection.') &&
                record.data['origin'] == 'user',
          )
          .toList();
      expect(explicit, hasLength(6));
      expect(explicit.map((record) => record.data['kind']).toSet(), {
        'audio_input',
        'audio_output',
        'camera',
      });
      expect(
        explicit.every(
          (record) =>
              record.correlationId == mediaFactory.correlationIds.single,
        ),
        isTrue,
      );
      final raw = jsonEncode([
        for (final record in diagnostics.rawRecords)
          {'event': record.event, 'data': record.data},
      ]);
      expect(raw, contains('user-input'));
      expect(raw, contains('user-output'));
      expect(raw, contains('user-camera'));
    });

    test(
      'contain ignored device PlatformExceptions behind the safe diagnostics boundary',
      () async {
        const privateCause = 'device-private-user track-private 203.0.113.132';
        const inputId = 'private-input-device';
        const outputId = 'private-output-device';
        const cameraId = 'private-camera-device';
        await controller.ensureLoaded(firstSite);
        await controller.join(
          siteUrl: firstSite,
          siteName: 'One',
          room: controller.room(firstSite, 7)!,
        );
        await controller.setCameraEnabled(true);
        final media = mediaFactory.sessions.single;
        final failure = PlatformException(
          code: 'device_selection',
          message: privateCause,
          details: {'deviceId': inputId, 'trackId': 'track-private'},
        );
        media
          ..audioInputFailure = failure
          ..audioOutputFailure = failure
          ..cameraFailure = failure;
        final ordinaryDiagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'voice-public-devices',
        );
        final binding = DiagnosticsSink.install(ordinaryDiagnostics);
        addTearDown(() async {
          binding.close();
          await ordinaryDiagnostics.close();
        });

        final uncaught = await _captureUncaught(() async {
          unawaited(controller.selectAudioInput(inputId));
          unawaited(controller.selectAudioOutput(outputId));
          unawaited(controller.selectCamera(cameraId));
          for (var index = 0; index < 8; index++) {
            await pumpEventQueue();
          }
        });

        expect(uncaught, isEmpty);
        expect(
          diagnostics.records
              .where(
                (record) => record.event == 'media.device_selection.failed',
              )
              .map((record) => record.data['kind'])
              .toSet(),
          {'audio_input', 'audio_output', 'camera'},
        );
        const operations = {
          'voice.media.selectAudioInput',
          'voice.media.selectAudioOutput',
          'voice.media.selectCamera',
        };
        expect(
          ordinaryDiagnostics.events
              .whereType<ErrorDiagnosticEvent>()
              .map((event) => event.operation)
              .toSet(),
          containsAll(operations),
        );
        expect(diagnostics.rawRecords, isEmpty);
        final ordinaryExport = ordinaryDiagnostics.buildJsonReport();
        for (final sentinel in [
          privateCause,
          inputId,
          outputId,
          cameraId,
          'track-private',
        ]) {
          expect(ordinaryExport, isNot(contains(sentinel)));
        }
      },
    );

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
          '/voice/rooms/7': 1,
        });

        await controller.ensureLoaded(firstSite, force: true);
        expect(counting.subscribeCounts, {
          '/voice/rooms/index': 1,
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

    test('report asynchronous signal and roster-media failures', () async {
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'voice-room-events',
      );
      final binding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        binding.close();
        await diagnostics.close();
      });
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
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().map(
          (event) => event.operation,
        ),
        containsAll({
          'voice.media.signal',
          'voice.media.audioPublishing',
          'voice.media.rosterMute',
          'voice.media.participants',
        }),
      );
    });

    test(
      'preserve batched signal order and admit an early open-room sender',
      () async {
        final joinPayload = fixture('join_mesh');
        final room = joinPayload['room']! as Map<String, dynamic>;
        room['room_type'] = 'open';
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

        firstTracker.deliver('/voice/rooms/7', {
          'type': 'signal',
          'sender_id': 2,
          'sender': {'id': 2, 'username': 'early'},
          'events': [
            {'type': 'offer', 'sdp': 'offer'},
            {
              'type': 'candidate',
              'candidate': {'candidate': 'candidate:first'},
            },
          ],
        });
        await pumpEventQueue();

        final media = mediaFactory.sessions.single;
        expect(media.participants.map((participant) => participant.id), [2, 1]);
        expect(media.signals.map((signal) => signal.$2['type']), [
          'offer',
          'candidate',
        ]);
        expect(controller.call?.room.participants.first.username, 'early');
      },
    );
  });

  group('participant session propagation', () {
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
        expect(conversation.sentMessages, ['hello room']);
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

    test('propagates one correlation ID into media and join HTTP', () async {
      final controlled = privilegedTransport();
      useTransport(controlled);

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: VoiceRoom.fromJson(fixture('room')),
      );

      final correlationId = mediaFactory.correlationIds.single;
      final joinContext = controlled.diagnosticContexts.singleWhere(
        (context) => context.path.endsWith('/join.json'),
      );
      expect(correlationId, startsWith('voice-call-'));
      expect(joinContext.operation, 'voice.join');
      expect(joinContext.correlationId, correlationId);
      expect(mediaFactory.diagnosticsRecorders.single, same(diagnostics));
    });

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

    test('records an ordered correlated join-and-leave lifecycle', () async {
      diagnostics.captureEnabled = true;
      await controller.ensureLoaded(firstSite);

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final correlationId = mediaFactory.correlationIds.single;
      await controller.leave();

      final events = diagnostics.records
          .where((record) => record.correlationId == correlationId)
          .map((record) => record.event)
          .toList();
      int index(String event) => events.indexOf(event);
      expect(
        index('call.join.requested'),
        lessThan(index('call.join.started')),
      );
      expect(
        index('call.join.started'),
        lessThan(index('call.join.completed')),
      );
      expect(
        index('call.join.completed'),
        lessThan(index('call.leave.started')),
      );
      expect(
        index('call.leave.started'),
        lessThan(index('call.leave.completed')),
      );
      final leave = diagnostics.records.singleWhere(
        (record) =>
            record.correlationId == correlationId &&
            record.event == 'call.leave.started',
      );
      expect(leave.data['reason'], 'user');
      final roster = diagnostics.rawRecords.singleWhere(
        (record) =>
            record.correlationId == correlationId &&
            record.event == 'call.join.initial_roster',
      );
      final participants = roster.data['participants']! as List<Object?>;
      expect(
        (participants.first! as Map<String, Object?>)['username'],
        isNotEmpty,
      );
    });

    test('captures raw signaling only while deep capture is enabled', () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      void deliver(String sdp) {
        firstTracker.deliver('/voice/rooms/7', {
          'type': 'signal',
          'sender_id': 2,
          'data': {'type': 'offer', 'sdp': sdp},
        });
      }

      deliver('capture-off');
      await pumpEventQueue();
      expect(
        diagnostics.rawRecords.where(
          (record) => record.event == 'signaling.received.raw',
        ),
        isEmpty,
      );

      diagnostics.captureEnabled = true;
      deliver('capture-on');
      await pumpEventQueue();
      final rawSignal = diagnostics.rawRecords.singleWhere(
        (record) => record.event == 'signaling.received.raw',
      );
      final capturedSignals = rawSignal.data['signals']! as List<Object?>;
      expect(
        (capturedSignals.single! as Map<String, dynamic>)['sdp'],
        'capture-on',
      );
    });

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
          diagnostics.records
              .singleWhere((record) => record.event == 'call.leave.started')
              .data['reason'],
          'rosterRemoval',
        );
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
        expect(
          diagnostics.records.where(
            (record) => record.event == 'call.leave.started',
          ),
          isEmpty,
        );
      },
    );

    test(
      'awaits leave, media, subscriptions, CallKit, and diagnostics during session close',
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
        final diagnosticsFlushStarted = Completer<void>();
        final diagnosticsFlushGate = Completer<void>();
        diagnostics
          ..flushCount = 0
          ..flushStarted = diagnosticsFlushStarted
          ..flushGate = diagnosticsFlushGate;

        var completed = false;
        final closing = controller.close();
        unawaited(closing.then((_) => completed = true));
        expect(controller.close(), same(closing));
        await awaitableTracker.firstCancellationStarted.future;
        expect(awaitableTracker.channels, isEmpty);
        expect(completed, isFalse);

        await controlled.waitForPendingPluginWrites(1);
        expect(media.disposeCount, 0);
        controlled.pendingPluginWrites.single.response.complete({});
        await mediaDisposeStarted.future;
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
        await diagnosticsFlushStarted.future;
        expect(completed, isFalse);

        diagnosticsFlushGate.complete();
        await closing;

        expect(completed, isTrue);
        expect(media.disposeCount, 1);
        expect(systemCall.disposeCount, 1);
        expect(diagnostics.flushCount, 1);
        expect(
          diagnostics.records
              .singleWhere((record) => record.event == 'call.leave.started')
              .data['reason'],
          'sessionClose',
        );
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
        diagnostics.flushFailure = StateError('diagnostics flush rejected');

        await controller.close().timeout(const Duration(seconds: 1));

        expect(controller.call, isNull);
        expect(media.disposeCount, 1);
        expect(systemCall.ends, 1);
        expect(systemCall.disposeCount, 1);
        expect(diagnostics.flushCount, 1);
        expect(
          diagnostics.records.where(
            (record) => record.event == 'session.close.completed',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'keeps leave terminal and idempotent when native teardown fails',
      () async {
        final diagnostics = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'voice-leave',
        );
        final binding = DiagnosticsSink.install(diagnostics);
        addTearDown(() async {
          binding.close();
          await diagnostics.close();
        });
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
        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().map(
            (event) => event.operation,
          ),
          containsAll({'voice.media.dispose', 'voice.systemCall.end'}),
        );
      },
    );

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
    }) async {
      final payload = fixture('join_mesh');
      final room = payload['room'] as Map<String, dynamic>;
      room['room_type'] = 'stage';
      room['can_manage'] = true;
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
          'reason': 'dismissed',
        });
        await pumpEventQueue();
        expect(notices.last.message, 'Your request to speak was dismissed.');
      },
    );

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
}
