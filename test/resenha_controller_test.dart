import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_api.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_callkit.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_controller.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_media.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'support/fakes.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/resenha/$name.json').readAsStringSync())
        as Map<String, dynamic>;

FakeSiteTracker tracker(String siteUrl) => FakeSiteTracker(
  siteUrl: siteUrl,
  onIncomingTopics: () {},
  onNotifications: (_) {},
  onReviewableCounts: (_) {},
  userId: 1,
  apiKey: 'key',
);

final class FakeResenhaMediaFactory implements ResenhaMediaFactory {
  final List<FakeResenhaMediaSession> sessions = [];
  final List<String> correlationIds = [];
  final List<ResenhaDiagnosticsRecorder> diagnosticsRecorders = [];
  Completer<void>? nextConnectGate;
  Object? nextAudioInputFailure;
  Object? nextAudioOutputFailure;
  Object? nextCameraFailure;

  @override
  ResenhaMediaSession create({
    required ResenhaJoinResponse join,
    required int localUserId,
    required ResenhaSignalSender sendSignal,
    required ResenhaLiveKitCredentialRefresher refreshLiveKitCredentials,
    ResenhaDiagnosticsRecorder diagnostics =
        const NoopResenhaDiagnosticsRecorder(),
    String correlationId = 'uncorrelated',
  }) {
    final session =
        FakeResenhaMediaSession(join.transport, connectGate: nextConnectGate)
          ..audioInputFailure = nextAudioInputFailure
          ..audioOutputFailure = nextAudioOutputFailure
          ..cameraFailure = nextCameraFailure;
    nextConnectGate = null;
    nextAudioInputFailure = null;
    nextAudioOutputFailure = null;
    nextCameraFailure = null;
    correlationIds.add(correlationId);
    diagnosticsRecorders.add(diagnostics);
    sessions.add(session);
    return session;
  }
}

typedef RecordedResenhaDiagnostic = ({
  String event,
  String component,
  DiagnosticSeverity severity,
  String? correlationId,
  String? message,
  Map<String, Object?> data,
});

final class FakeResenhaDiagnosticsRecorder
    implements ResenhaDiagnosticsRecorder {
  @override
  bool captureEnabled = false;

  final List<RecordedResenhaDiagnostic> records = [];
  final List<RecordedResenhaDiagnostic> rawRecords = [];

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
}

final class FakeResenhaMediaSession extends ChangeNotifier
    implements ResenhaMediaSession {
  FakeResenhaMediaSession(this.transport, {this.connectGate});

  @override
  final ResenhaTransport transport;
  final Completer<void>? connectGate;

  @override
  ResenhaMediaConnectionState connectionState =
      ResenhaMediaConnectionState.connected;
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
  Object? audioInputFailure;
  Object? audioOutputFailure;
  Object? cameraFailure;
  Completer<void>? muteGate;
  String? selectedAudioInput;
  String? selectedAudioOutput;
  String? selectedCamera;
  final Map<int, double> participantVolumes = {};
  List<ResenhaParticipant> participants = const [];

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
    await connectGate?.future;
  }

  @override
  Future<List<rtc.MediaDeviceInfo>> devices() async => const [];

  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {
    if (signalFailure case final failure?) throw failure;
  }

  @override
  Future<void> selectAudioOutput(String deviceId) async {
    if (audioOutputFailure case final failure?) throw failure;
    selectedAudioOutput = deviceId;
  }

  @override
  Future<void> selectAudioInput(String deviceId) async {
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
  Future<void> syncParticipants(List<ResenhaParticipant> value) async {
    participants = value;
    if (participantSyncFailure case final failure?) throw failure;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    if (disposeFailure case final failure?) throw failure;
    super.dispose();
  }
}

final class FakeResenhaPreferences implements ResenhaPreferences {
  ResenhaDevicePreferences devices = const ResenhaDevicePreferences();
  bool rejectWrites = false;
  bool rejectVolumeReads = false;
  Completer<void>? deviceWriteStarted;
  Completer<void>? deviceWriteGate;
  final List<String> writes = [];
  final Map<(String, int, int), double> volumes = {};

  @override
  Future<ResenhaDevicePreferences> readDevices() async => devices;

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
    ResenhaDevicePreference preference,
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

final class _GatedCredentialReader implements ApiCredentialReader {
  _GatedCredentialReader({required this.apiKeyGate});

  final Completer<void> apiKeyGate;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    await apiKeyGate.future;
    return 'key';
  }

  @override
  Future<String> clientId() async => 'client';
}

final class _NextGatedCredentialReader implements ApiCredentialReader {
  bool gateNextRead = false;
  Completer<void> readStarted = Completer<void>();
  Completer<void> readGate = Completer<void>();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (gateNextRead) {
      gateNextRead = false;
      if (!readStarted.isCompleted) readStarted.complete();
      await readGate.future;
    }
    return 'key';
  }

  @override
  Future<String> clientId() async => 'client';
}

final class _FailingCredentialReader implements ApiCredentialReader {
  Object? failure;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (failure case final failure?) throw failure;
    return 'key';
  }

  @override
  Future<String> clientId() async => 'client';
}

final class _CountingCredentialReader implements ApiCredentialReader {
  int apiKeyCalls = 0;
  int clientIdCalls = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    apiKeyCalls++;
    return 'key';
  }

  @override
  Future<String> clientId() async {
    clientIdCalls++;
    return 'client';
  }
}

final class FakeResenhaSystemCall implements ResenhaSystemCall {
  final StreamController<ResenhaSystemCallAction> controller =
      StreamController.broadcast();
  int starts = 0;
  int connectedCalls = 0;
  int ends = 0;
  bool? systemMuted;
  Object? endFailure;

  @override
  Stream<ResenhaSystemCallAction> get actions => controller.stream;

  void send(ResenhaSystemCallAction action) => controller.add(action);

  @override
  Future<void> connected() async => connectedCalls++;

  @override
  Future<void> dispose() => controller.close();

  @override
  Future<void> end() async {
    ends++;
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

final class _PendingThreadMessages {
  _PendingThreadMessages({required this.before});

  final int? before;
  final Completer<ChatMessagePage> response = Completer();
}

final class _ControlledResenhaTransport extends FakeDiscourseApi {
  _ControlledResenhaTransport({super.pluginResponses, super.chatMessagesByKey});

  final Set<String> heldPluginPaths = {};
  final Set<String> heldPluginWritePaths = {};
  final Map<String, SiteLookupException> pluginGetFailures = {};
  final List<String> pluginGets = [];
  final List<_PendingPluginGet> pendingPluginGets = [];
  final List<_PendingPluginWrite> pendingPluginWrites = [];
  final List<_TransportDiagnosticContext> diagnosticContexts = [];
  final List<_PendingThreadMessages> pendingThreadMessages = [];
  bool holdThreadMessages = false;
  Object? chatThreadReadFailure;
  Object? operationFailure;
  int chatThreadReadCalls = 0;

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
    return pending.response.future;
  }

  @override
  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    int? targetMessageId,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) {
    if (!holdThreadMessages) {
      return super.chatThreadMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        threadId: threadId,
        before: before,
        after: after,
        targetMessageId: targetMessageId,
        pageSize: pageSize,
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    final pending = _PendingThreadMessages(before: before);
    pendingThreadMessages.add(pending);
    return pending.response.future;
  }

  @override
  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  }) async {
    chatThreadReadCalls++;
    if (chatThreadReadFailure case final failure?) throw failure;
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
  late FakeDiscourseApi transport;
  late ApiCredentialReader credentials;
  late FakeResenhaPreferences preferences;
  late FakeResenhaMediaFactory mediaFactory;
  late FakeResenhaSystemCall systemCall;
  late FakeResenhaDiagnosticsRecorder diagnostics;
  late FakeSiteTracker firstTracker;
  late FakeSiteTracker secondTracker;
  late ResenhaController controller;

  void useTransport(
    FakeDiscourseApi value, {
    ResenhaCapabilityResolver? capabilityEnabledFor,
  }) {
    controller.dispose();
    transport = value;
    mediaFactory = FakeResenhaMediaFactory();
    systemCall = FakeResenhaSystemCall();
    controller = ResenhaController(
      api: ResenhaApi(transport),
      chatApi: transport,
      credentials: credentials,
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
      diagnostics: diagnostics,
      preferences: preferences,
      heartbeatInterval: const Duration(milliseconds: 15),
    );
  }

  setUp(() {
    final joinPayload = fixture('join_mesh');
    (joinPayload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
    transport = FakeDiscourseApi(
      pluginResponses: {
        'GET /resenha/rooms.json': fixture('directory'),
        'POST /resenha/rooms/7/join.json': joinPayload,
        'POST /resenha/rooms/7/heartbeat.json': {},
        'DELETE /resenha/rooms/7/leave.json': {},
        'POST /resenha/rooms/7/state.json': {},
        'GET /resenha/rooms/7/chat_session.json': fixture('chat'),
      },
      chatMessagesByKey: {
        'thread-42-99': (
          messages: const [
            ChatMessage(
              id: 10,
              channelId: 42,
              cooked: '<p>newer</p>',
              author: ChatMessageAuthor(id: 1, username: 'sam'),
            ),
          ],
          canLoadMorePast: true,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
        'thread-42-99~past~10': (
          messages: const [
            ChatMessage(
              id: 5,
              channelId: 42,
              cooked: '<p>older</p>',
              author: ChatMessageAuthor(id: 2, username: 'lee'),
            ),
          ],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
    );
    credentials = FakeApiCredentialReader()
      ..keys[firstSite] = 'first-key'
      ..keys[secondSite] = 'second-key';
    preferences = FakeResenhaPreferences();
    mediaFactory = FakeResenhaMediaFactory();
    systemCall = FakeResenhaSystemCall();
    diagnostics = FakeResenhaDiagnosticsRecorder();
    firstTracker = tracker(firstSite);
    secondTracker = tracker(secondSite);
    controller = ResenhaController(
      api: ResenhaApi(transport),
      chatApi: transport,
      credentials: credentials,
      trackerFor: (siteUrl) => siteUrl == firstSite
          ? firstTracker
          : siteUrl == secondSite
          ? secondTracker
          : null,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
      mediaFactory: mediaFactory,
      systemCall: systemCall,
      diagnostics: diagnostics,
      preferences: preferences,
      heartbeatInterval: const Duration(milliseconds: 15),
    );
  });

  tearDown(() => controller.dispose());

  _ControlledResenhaTransport privilegedTransport() {
    final joinPayload = fixture('join_mesh');
    (joinPayload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
    return _ControlledResenhaTransport(
      pluginResponses: {
        'POST /resenha/rooms/7/join.json': joinPayload,
        'DELETE /resenha/rooms/7/leave.json': <String, dynamic>{},
        'POST /resenha/rooms/7/heartbeat.json': <String, dynamic>{},
        'POST /resenha/rooms/7/state.json': <String, dynamic>{},
        'POST /resenha/rooms/7/request_to_speak.json': <String, dynamic>{},
        'DELETE /resenha/rooms/7/kick.json': <String, dynamic>{},
        'GET /site.json': {
          'post_action_types': [
            {'name_key': 'notify_moderators', 'id': 3},
          ],
        },
        'POST /resenha/rooms/7/flag.json': <String, dynamic>{},
        'POST /resenha/rooms/7/recording.json': <String, dynamic>{},
        'GET /resenha/rooms/7/memberships.json': {'memberships': <Object?>[]},
        'POST /resenha/rooms/7/memberships.json': <String, dynamic>{},
        'PUT /resenha/rooms/7/memberships/9.json': <String, dynamic>{},
        'DELETE /resenha/rooms/7/memberships/9.json': <String, dynamic>{},
      },
    );
  }

  test(
    'caches a missing or unsupported plugin until the site is forgotten',
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
        final controlled = _ControlledResenhaTransport()
          ..pluginGetFailures['/resenha/rooms.json'] = failure;
        useTransport(controlled);

        await controller.ensureLoaded(firstSite);
        await controller.ensureLoaded(firstSite);
        await controller.ensureLoaded(firstSite, force: true);

        expect(
          controlled.pluginGets,
          ['/resenha/rooms.json'],
          reason:
              'a confirmed unavailable capability is stable for the session',
        );

        controller.forget(firstSite);
        await controller.ensureLoaded(firstSite);

        expect(
          controlled.pluginGets,
          ['/resenha/rooms.json', '/resenha/rooms.json'],
          reason: 'forget starts a new site session and clears the capability',
        );
      }
    },
  );

  test(
    'does not probe room routes when site settings disable Resenha',
    () async {
      final controlled = _ControlledResenhaTransport(
        pluginResponses: {'GET /resenha/rooms.json': fixture('directory')},
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
    },
  );

  test('still probes when site settings could not be resolved', () async {
    final controlled = _ControlledResenhaTransport(
      pluginResponses: {'GET /resenha/rooms.json': fixture('directory')},
    );
    useTransport(controlled, capabilityEnabledFor: (_) async => null);

    await controller.ensureLoaded(firstSite);

    expect(controlled.pluginGets, ['/resenha/rooms.json']);
    expect(controller.directory(firstSite), isNotNull);
  });

  test('an unreachable directory remains retryable', () async {
    final controlled =
        _ControlledResenhaTransport(
            pluginResponses: {'GET /resenha/rooms.json': fixture('directory')},
          )
          ..pluginGetFailures['/resenha/rooms.json'] =
              const SiteLookupException(
                SiteLookupFailure.unreachable,
                firstSite,
                statusCode: HttpStatus.serviceUnavailable,
              );
    useTransport(controlled);

    await controller.ensureLoaded(firstSite);
    controlled.pluginGetFailures.remove('/resenha/rooms.json');
    await controller.ensureLoaded(firstSite);

    expect(controlled.pluginGets, [
      '/resenha/rooms.json',
      '/resenha/rooms.json',
    ]);
    expect(controller.directory(firstSite), isNotNull);
  });

  test(
    'directory publication rechecks ownership before credential work',
    () async {
      final counting = _CountingCredentialReader();
      final controlled = _ControlledResenhaTransport(
        pluginResponses: {'GET /resenha/rooms.json': fixture('directory')},
      );
      credentials = counting;
      useTransport(controlled);
      controller.addListener(() {
        if (controller.isLoading(firstSite)) controller.forget(firstSite);
      });

      await controller.ensureLoaded(firstSite);

      expect(counting.apiKeyCalls, 1);
      expect(counting.clientIdCalls, 0);
      expect(controlled.pluginGets, isEmpty);
    },
  );

  test(
    'forget prevents a credential-gated join from reaching the server',
    () async {
      final gate = Completer<void>();
      credentials = _GatedCredentialReader(apiKeyGate: gate);
      final controlled = _ControlledResenhaTransport();
      useTransport(controlled);

      final joining = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(fixture('room')),
      );
      await pumpEventQueue();

      controller.forget(firstSite);
      gate.complete();
      await joining;

      expect(controlled.pluginWrites, isEmpty);
      expect(controller.call, isNull);
      expect(mediaFactory.sessions, isEmpty);
    },
  );

  test(
    'forget prevents an in-flight join response from creating media',
    () async {
      final controlled = _ControlledResenhaTransport()
        ..heldPluginWritePaths.add('/resenha/rooms/7/join.json');
      useTransport(controlled);

      final joining = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(fixture('room')),
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

  test(
    'joining publication rechecks ownership before the system call',
    () async {
      controller.addListener(() {
        if (controller.call?.status == ResenhaCallStatus.joining) {
          controller.forget(firstSite);
        }
      });

      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(fixture('room')),
      );
      await pumpEventQueue();

      expect(systemCall.starts, 0);
      expect(mediaFactory.sessions.single.disposeCount, 1);
    },
  );

  for (final action
      in <
        ({
          String name,
          Set<String> paths,
          Future<void> Function(ResenhaController controller) begin,
        })
      >[
        (
          name: 'raise-hand write',
          paths: {'/resenha/rooms/7/request_to_speak.json'},
          begin: (controller) => controller.requestToSpeak(),
        ),
        (
          name: 'kick write',
          paths: {'/resenha/rooms/7/kick.json'},
          begin: (controller) => controller.kick(2),
        ),
        (
          name: 'participant flag',
          paths: {'/site.json', '/resenha/rooms/7/flag.json'},
          begin: (controller) async {
            await controller.flagParticipant(2, 'Please review');
          },
        ),
        (
          name: 'recording write',
          paths: {'/resenha/rooms/7/recording.json'},
          begin: (controller) => controller.setRecording(true),
        ),
        (
          name: 'state write',
          paths: {'/resenha/rooms/7/state.json'},
          begin: (controller) => controller.setMuted(true),
        ),
        (
          name: 'heartbeat write',
          paths: {'/resenha/rooms/7/heartbeat.json'},
          begin: (controller) async {
            controller.setForeground(false);
            await pumpEventQueue();
          },
        ),
      ]) {
    test('forget during credentials prevents stale ${action.name}', () async {
      final gated = _NextGatedCredentialReader();
      credentials = gated;
      final controlled = privilegedTransport();
      useTransport(controlled);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(fixture('room')),
      );
      final writesBefore = controlled.pluginWrites.length;
      final getsBefore = controlled.pluginGets.length;

      gated.gateNextRead = true;
      final operation = action.begin(controller);
      await gated.readStarted.future;
      controller.forget(firstSite);
      gated.readGate.complete();
      await operation;
      await pumpEventQueue();

      final paths = <String>{
        for (final write in controlled.pluginWrites.skip(writesBefore))
          write.path,
        ...controlled.pluginGets.skip(getsBefore),
      };
      expect(paths.intersection(action.paths), isEmpty);
    });
  }

  for (final action
      in <
        ({
          String name,
          String path,
          Future<void> Function(ResenhaController controller) begin,
        })
      >[
        (
          name: 'membership read',
          path: '/resenha/rooms/7/memberships.json',
          begin: (controller) async {
            await controller.memberships(firstSite, 7);
          },
        ),
        (
          name: 'membership add',
          path: '/resenha/rooms/7/memberships.json',
          begin: (controller) => controller.addMember(
            firstSite,
            7,
            'lee',
            ResenhaRole.participant,
          ),
        ),
        (
          name: 'membership update',
          path: '/resenha/rooms/7/memberships/9.json',
          begin: (controller) =>
              controller.updateMember(firstSite, 7, 9, ResenhaRole.speaker),
        ),
        (
          name: 'membership removal',
          path: '/resenha/rooms/7/memberships/9.json',
          begin: (controller) => controller.removeMember(firstSite, 7, 9),
        ),
      ]) {
    test('forget during credentials prevents stale ${action.name}', () async {
      final gated = _NextGatedCredentialReader()..gateNextRead = true;
      credentials = gated;
      final controlled = privilegedTransport();
      useTransport(controlled);

      final operation = action.begin(controller);
      await gated.readStarted.future;
      controller.forget(firstSite);
      gated.readGate.complete();
      await operation;

      expect(
        controlled.pluginWrites.where((write) => write.path == action.path),
        isEmpty,
      );
      expect(
        controlled.pluginGets.where((path) => path == action.path),
        isEmpty,
      );
    });
  }

  test(
    'contains secure-store failures across detached public entry points',
    () async {
      const privateCause =
          'credential-private-user device-private 203.0.113.130';
      final failingCredentials = _FailingCredentialReader();
      credentials = failingCredentials;
      useTransport(transport);
      await controller.openChat(firstSite, 7);
      final ordinaryDiagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-public-credentials',
      );
      final binding = DiagnosticsSink.install(ordinaryDiagnostics);
      addTearDown(() async {
        binding.close();
        await ordinaryDiagnostics.close();
      });
      failingCredentials.failure = PlatformException(
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
            room: ResenhaRoom.fromJson(fixture('room')),
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
      const operations = {
        'resenha.directory',
        'resenha.join',
        'resenha.chat.load',
        'resenha.chat.page',
        'resenha.chat.send',
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
      expect(
        ordinaryDiagnostics.buildJsonReport(),
        isNot(contains(privateCause)),
      );
    },
  );

  test(
    'contains ignored admin operation failures behind the safe boundary',
    () async {
      const privateCause =
          'admin-private-user membership-987654321 203.0.113.131';
      final controlled = privilegedTransport();
      useTransport(controlled);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(fixture('room')),
      );
      final ordinaryDiagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-public-admin',
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
          ResenhaRole.participant,
        ),
        () => controller.updateMember(
          firstSite,
          7,
          987654321,
          ResenhaRole.speaker,
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
        'resenha.requestToSpeak',
        'resenha.kick',
        'resenha.flag',
        'resenha.recording',
        'resenha.memberships',
        'resenha.membership.add',
        'resenha.membership.update',
        'resenha.membership.remove',
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

  test('rejected media preferences do not block live call controls', () async {
    final diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'resenha-preferences',
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
        'resenha.preferences.audioInput',
        'resenha.preferences.audioOutput',
        'resenha.preferences.pushToTalk',
        'resenha.preferences.writeVolume',
        'resenha.preferences.readVolume',
      }),
    );
  });

  for (final captureEnabled in [false, true]) {
    test('saved stale device failure is privacy-safe with capture '
        '${captureEnabled ? 'on' : 'off'}', () async {
      const deviceId = 'private-stale-microphone';
      const sentinelUsername = 'private-participant-name';
      const sentinelUserId = '987654321';
      const sentinelTrackId = 'private-track-id';
      const sentinelStreamId = 'private-stream-id';
      const sentinelIp = '203.0.113.77';
      final ordinaryDiagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-stale-device-$captureEnabled',
      );
      final binding = DiagnosticsSink.install(ordinaryDiagnostics);
      addTearDown(() async {
        binding.close();
        await ordinaryDiagnostics.close();
      });
      preferences.devices = const ResenhaDevicePreferences(
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
      expect(ordinaryExport, contains('resenha.join'));
    });
  }

  test(
    'traces saved input and output selection with call correlation',
    () async {
      preferences.devices = const ResenhaDevicePreferences(
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

  test('traces explicit input output and camera selections', () async {
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
        (record) => record.correlationId == mediaFactory.correlationIds.single,
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
    'contains ignored device PlatformExceptions behind the safe boundary',
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
        sessionId: 'resenha-public-devices',
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
            .where((record) => record.event == 'media.device_selection.failed')
            .map((record) => record.data['kind'])
            .toSet(),
        {'audio_input', 'audio_output', 'camera'},
      );
      const operations = {
        'resenha.media.selectAudioInput',
        'resenha.media.selectAudioOutput',
        'resenha.media.selectCamera',
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
    'device selection stops at a pending preference write after disposal',
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

  test(
    'a forgotten site cannot be restored by a late directory response',
    () async {
      final controlled = _ControlledResenhaTransport()
        ..heldPluginPaths.add('/resenha/rooms.json');
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
      expect(firstTracker.pluginChannelLastIds, isEmpty);
    },
  );

  test('a forgotten site cannot retain a late linked-room lookup', () async {
    final controlled = _ControlledResenhaTransport()
      ..heldPluginPaths.add('/resenha/rooms/conf-room-1.json');
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
  });

  test(
    'a forgotten site cannot be restored by a late room-chat response',
    () async {
      final controlled = _ControlledResenhaTransport(
        chatMessagesByKey: {'thread-42-99': _chatPage(10)},
      )..heldPluginPaths.add('/resenha/rooms/7/chat_session.json');
      useTransport(controlled);

      final load = controller.openChat(firstSite, 7);
      await pumpEventQueue();
      expect(controlled.pendingPluginGets, hasLength(1));

      controller.forget(firstSite);
      controlled.pendingPluginGets.single.response.complete(fixture('chat'));
      await load;

      expect(controller.chat(firstSite, 7), isNull);
      expect(firstTracker.pluginChannelLastIds, isEmpty);
    },
  );

  test('a late room save cannot restore a forgotten site', () async {
    final controlled = _ControlledResenhaTransport(
      pluginResponses: {'GET /resenha/rooms.json': fixture('directory')},
    )..heldPluginWritePaths.add('/resenha/rooms.json');
    useTransport(controlled);

    final save = controller.saveRoom(
      siteUrl: firstSite,
      draft: const ResenhaRoomDraft(
        name: 'Late room',
        isPublic: true,
        type: ResenhaRoomType.open,
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

  test('a late chat send cannot restore a forgotten site', () async {
    final controlled = _ControlledResenhaTransport()
      ..heldPluginWritePaths.add('/resenha/rooms/7/chat_session.json');
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

  test(
    'an older forced chat refresh cannot replace a newer response',
    () async {
      final controlled = _ControlledResenhaTransport()
        ..heldPluginPaths.add('/resenha/rooms/7/chat_session.json')
        ..holdThreadMessages = true;
      useTransport(controlled);

      final older = controller.openChat(firstSite, 7, force: true);
      await pumpEventQueue();
      controlled.pendingPluginGets[0].response.complete(fixture('chat'));
      await pumpEventQueue();
      expect(controlled.pendingThreadMessages, hasLength(1));

      final newer = controller.openChat(firstSite, 7, force: true);
      await pumpEventQueue();
      controlled.pendingPluginGets[1].response.complete(fixture('chat'));
      await pumpEventQueue();
      expect(controlled.pendingThreadMessages, hasLength(2));

      controlled.pendingThreadMessages[1].response.complete(_chatPage(20));
      await newer;
      controlled.pendingThreadMessages[0].response.complete(_chatPage(10));
      await older;

      expect(
        controller.chat(firstSite, 7)?.messages.map((message) => message.id),
        [20],
      );
    },
  );

  test('an older chat page cannot replace a newer forced refresh', () async {
    final controlled = _ControlledResenhaTransport(
      pluginResponses: {
        'GET /resenha/rooms/7/chat_session.json': fixture('chat'),
      },
      chatMessagesByKey: {'thread-42-99': _chatPage(10, canLoadMorePast: true)},
    );
    useTransport(controlled);
    await controller.openChat(firstSite, 7);
    controlled.holdThreadMessages = true;

    final page = controller.loadOlderChat(firstSite, 7);
    await pumpEventQueue();
    expect(controlled.pendingThreadMessages.single.before, 10);

    final refresh = controller.openChat(firstSite, 7, force: true);
    await pumpEventQueue();
    expect(controlled.pendingThreadMessages, hasLength(2));
    expect(controlled.pendingThreadMessages[1].before, isNull);

    controlled.pendingThreadMessages[1].response.complete(_chatPage(20));
    await refresh;
    controlled.pendingThreadMessages[0].response.complete(_chatPage(5));
    await page;

    expect(
      controller.chat(firstSite, 7)?.messages.map((message) => message.id),
      [20],
    );
  });

  test(
    'subscribes from both snapshot cursors and applies live rosters',
    () async {
      await controller.ensureLoaded(firstSite);

      expect(firstTracker.pluginChannelLastIds['/resenha/rooms/index'], 144);
      expect(firstTracker.pluginChannelLastIds['/resenha/rooms/7'], 91);

      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
        'type': 'participants',
        'participants': [
          {'id': 2, 'username': 'lee', 'role': 'speaker'},
        ],
      });
      expect(
        controller.room(firstSite, 7)?.participants.single.username,
        'lee',
      );

      firstTracker.deliverPluginMessage('/resenha/rooms/index', {
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
    'stage role changes acquire and release microphone publication',
    () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;

      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
        'type': 'participants',
        'participants': [
          {'id': 1, 'username': 'sam', 'role': 'participant'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      expect(media.audioPublishingAllowed, isFalse);

      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
        'type': 'role_change',
        'user_id': 1,
        'role': 'speaker',
      });
      await Future<void>.delayed(Duration.zero);
      expect(media.audioPublishingAllowed, isTrue);

      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
        'type': 'participants',
        'participants': [
          {'id': 1, 'username': 'sam', 'role': 'speaker'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      expect(media.audioPublishingAllowed, isTrue);
    },
  );

  test('room video watching is reference counted across a join', () async {
    controller.watchRoomVideo(siteUrl: firstSite, roomId: 7);
    controller.watchRoomVideo(siteUrl: firstSite, roomId: 7);

    expect(
      transport.pluginWrites.where(
        (write) => write.path.endsWith('/state.json'),
      ),
      isEmpty,
    );

    await controller.ensureLoaded(firstSite);
    await controller.join(
      siteUrl: firstSite,
      siteName: 'One',
      room: controller.room(firstSite, 7)!,
    );
    await pumpEventQueue();

    var stateWrites = transport.pluginWrites
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
    stateWrites = transport.pluginWrites
        .where((write) => write.path.endsWith('/state.json'))
        .toList();
    expect(stateWrites.last.body['watching'], isTrue);

    controller.stopWatchingRoomVideo(siteUrl: firstSite, roomId: 7);
    await pumpEventQueue();
    expect(
      transport.pluginWrites.where(
        (write) => write.path.endsWith('/state.json'),
      ),
      hasLength(stateWrites.length),
    );

    controller.stopWatchingRoomVideo(siteUrl: firstSite, roomId: 7);
    await pumpEventQueue();
    stateWrites = transport.pluginWrites
        .where((write) => write.path.endsWith('/state.json'))
        .toList();
    expect(stateWrites.last.body['watching'], isFalse);
    expect(
      stateWrites.every((write) => write.body.containsKey('watching')),
      isTrue,
    );
  });

  test('reports asynchronous signal and roster media failures', () async {
    final diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'resenha-room-events',
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

    firstTracker.deliverPluginMessage('/resenha/rooms/7', {
      'type': 'signal',
      'sender_id': 2,
      'data': {'type': 'offer'},
    });
    firstTracker.deliverPluginMessage('/resenha/rooms/7', {
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
        'resenha.media.signal',
        'resenha.media.audioPublishing',
        'resenha.media.rosterMute',
        'resenha.media.participants',
      }),
    );
  });

  test('loads and pages the associated Discourse Chat thread', () async {
    await controller.openChat(firstSite, 7);
    expect(
      controller.chat(firstSite, 7)?.messages.map((message) => message.id),
      [10],
    );
    expect(controller.chat(firstSite, 7)?.canLoadMorePast, isTrue);

    await controller.loadOlderChat(firstSite, 7);
    expect(
      controller.chat(firstSite, 7)?.messages.map((message) => message.id),
      [5, 10],
    );
    expect(controller.chat(firstSite, 7)?.canLoadMorePast, isFalse);
  });

  test(
    'contains detached chat mark-read failures without forwarding raw cause',
    () async {
      const privateCause = 'chat-private-user device-private 203.0.113.122';
      final controlled = _ControlledResenhaTransport(
        pluginResponses: {
          'GET /resenha/rooms/7/chat_session.json': fixture('chat'),
        },
        chatMessagesByKey: {'thread-42-99': _chatPage(10)},
      )..chatThreadReadFailure = StateError(privateCause);
      useTransport(controlled);
      final ordinaryDiagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-chat-mark-read',
      );
      final binding = DiagnosticsSink.install(ordinaryDiagnostics);
      addTearDown(() async {
        binding.close();
        await ordinaryDiagnostics.close();
      });
      final uncaught = <Object>[];

      final operation = runZonedGuarded<Future<void>>(() async {
        await controller.openChat(firstSite, 7);
        await pumpEventQueue();
        await pumpEventQueue();
      }, (error, _) => uncaught.add(error));
      await operation;

      expect(uncaught, isEmpty);
      expect(controlled.chatThreadReadCalls, 1);
      final safeRecord = diagnostics.records.singleWhere(
        (record) =>
            record.event == 'runtime.error' &&
            record.data['operation'] == 'resenha.chat.markRead',
      );
      expect(safeRecord.data['errorType'], 'StateError');
      expect(diagnostics.rawRecords, isEmpty);
      final globalRecord = ordinaryDiagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .singleWhere((event) => event.operation == 'resenha.chat.markRead');
      expect(globalRecord.message, contains('resenha.chat.markRead'));
      expect(globalRecord.message, isNot(contains(privateCause)));
      expect(
        ordinaryDiagnostics.buildJsonReport(),
        isNot(contains(privateCause)),
      );
    },
  );

  test('enforces one call globally while switching sites', () async {
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
      transport.pluginWrites
          .where((write) => write.path.endsWith('/leave.json'))
          .single
          .siteUrl,
      firstSite,
    );
  });

  test('waits out a rate-limited room join and retries it once', () async {
    transport.pluginWriteFailures['POST /resenha/rooms/7/join.json'] =
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
    expect(controller.call?.status, ResenhaCallStatus.connected);
    expect(
      transport.pluginWrites.where(
        (write) => write.path.endsWith('/join.json'),
      ),
      hasLength(2),
    );
    expect(controller.errorFor(firstSite), isNull);
  });

  test('propagates one call correlation into media and join HTTP', () async {
    final controlled = privilegedTransport();
    useTransport(controlled);

    await controller.join(
      siteUrl: firstSite,
      siteName: 'One',
      room: ResenhaRoom.fromJson(fixture('room')),
    );

    final correlationId = mediaFactory.correlationIds.single;
    final joinContext = controlled.diagnosticContexts.singleWhere(
      (context) => context.path.endsWith('/join.json'),
    );
    expect(correlationId, startsWith('resenha-call-'));
    expect(joinContext.operation, 'resenha.join');
    expect(joinContext.correlationId, correlationId);
    expect(mediaFactory.diagnosticsRecorders.single, same(diagnostics));
  });

  test('records an ordered correlated join and leave lifecycle', () async {
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
    expect(index('call.join.requested'), lessThan(index('call.join.started')));
    expect(index('call.join.started'), lessThan(index('call.join.completed')));
    expect(index('call.join.completed'), lessThan(index('call.leave.started')));
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
      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
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
    expect(
      (rawSignal.data['signal']! as Map<String, dynamic>)['sdp'],
      'capture-on',
    );
  });

  test('dispose during a failing connect tears media down only once', () async {
    final connectGate = Completer<void>();
    mediaFactory.nextConnectGate = connectGate;

    final joining = controller.join(
      siteUrl: firstSite,
      siteName: 'One',
      room: ResenhaRoom.fromJson(fixture('room')),
    );
    while (mediaFactory.sessions.isEmpty ||
        mediaFactory.sessions.single.connectCount == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final media = mediaFactory.sessions.single;

    controller.dispose();
    connectGate.completeError(StateError('connection closed by teardown'));
    await joining;
    await pumpEventQueue();

    expect(media.disposeCount, 1);
  });

  test(
    'dispose during a media setting skips roster and system synchronization',
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
      final stateWritesBefore = transport.pluginWrites
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
        transport.pluginWrites.where(
          (write) => write.path.endsWith('/state.json'),
        ),
        hasLength(stateWritesBefore),
      );
    },
  );

  test('switches rooms when the old room echoes the explicit leave', () async {
    final secondJoinPayload = fixture('join_mesh');
    final secondRoomJson = secondJoinPayload['room'] as Map<String, dynamic>;
    secondRoomJson
      ..['id'] = 8
      ..['name'] = 'Breakroom'
      ..['slug'] = 'breakroom';
    transport.pluginResponses['POST /resenha/rooms/8/join.json'] =
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
      room: ResenhaRoom.fromJson(secondRoomJson),
    );
    firstTracker.deliverPluginMessage('/resenha/rooms/7', {
      'type': 'participants',
      'participants': const <Object?>[],
    });
    await switching;

    expect(controller.call?.room.id, 8);
    expect(controller.call?.room.name, 'Breakroom');
    expect(firstMedia.disposeCount, 1);
    expect(systemCall.ends, 1);
    expect(mediaFactory.sessions, hasLength(2));
  });

  test(
    'serializes another room switch while the first is connecting',
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
      transport.pluginResponses
        ..['POST /resenha/rooms/8/join.json'] = breakroom
        ..['DELETE /resenha/rooms/8/leave.json'] = <String, dynamic>{}
        ..['POST /resenha/rooms/9/join.json'] = kitchen;

      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );

      final connectGate = Completer<void>();
      mediaFactory.nextConnectGate = connectGate;
      final firstSwitch = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(breakroom['room'] as Map<String, dynamic>),
      );
      while (mediaFactory.sessions.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }

      final secondSwitch = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(kitchen['room'] as Map<String, dynamic>),
      );
      final duplicateSecondSwitch = controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: ResenhaRoom.fromJson(kitchen['room'] as Map<String, dynamic>),
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

  test(
    'heartbeats, synchronizes call controls, and responds to CallKit',
    () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      await controller.setMuted(true);
      await controller.setDeafened(true);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(controller.call?.muted, isTrue);
      expect(controller.call?.deafened, isTrue);
      expect(mediaFactory.sessions.single.muted, isTrue);
      expect(systemCall.systemMuted, isTrue);
      expect(
        transport.pluginWrites.where(
          (write) => write.path.endsWith('/heartbeat.json'),
        ),
        isNotEmpty,
      );

      systemCall.send(ResenhaSystemCallAction.unmute);
      await Future<void>.delayed(Duration.zero);
      expect(controller.call?.muted, isFalse);

      systemCall.send(ResenhaSystemCallAction.end);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.call, isNull);
    },
  );

  test('a slow heartbeat has only one request in flight', () async {
    final joinPayload = fixture('join_mesh');
    (joinPayload['room'] as Map<String, dynamic>)['room_type'] = 'stage';
    final controlled = _ControlledResenhaTransport(
      pluginResponses: {
        'GET /resenha/rooms.json': fixture('directory'),
        'POST /resenha/rooms/7/join.json': joinPayload,
        'POST /resenha/rooms/7/heartbeat.json': <String, dynamic>{},
        'DELETE /resenha/rooms/7/leave.json': <String, dynamic>{},
        'POST /resenha/rooms/7/state.json': <String, dynamic>{},
        'GET /resenha/rooms/7/chat_session.json': fixture('chat'),
      },
    )..heldPluginWritePaths.add('/resenha/rooms/7/heartbeat.json');
    useTransport(controlled);

    Future<void> waitForHeartbeatCount(int count) async {
      for (var attempt = 0; attempt < 40; attempt++) {
        if (controlled.pendingPluginWrites.length >= count) return;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    await controller.ensureLoaded(firstSite);
    await controller.join(
      siteUrl: firstSite,
      siteName: 'One',
      room: controller.room(firstSite, 7)!,
    );
    expect(controller.call?.status, ResenhaCallStatus.connected);
    controller.setForeground(false);
    await waitForHeartbeatCount(1);
    expect(controlled.pendingPluginWrites, hasLength(1));

    controller.setForeground(true);
    controller.setForeground(false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controlled.pendingPluginWrites, hasLength(1));

    controlled.pendingPluginWrites[0].response.complete({});
    await waitForHeartbeatCount(2);
    expect(controlled.pendingPluginWrites, hasLength(2));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controlled.pendingPluginWrites, hasLength(2));

    controlled.pendingPluginWrites[1].response.complete({});
    await controller.leave();
  });

  test('heartbeats resume after a media reconnection', () async {
    await controller.ensureLoaded(firstSite);
    await controller.join(
      siteUrl: firstSite,
      siteName: 'One',
      room: controller.room(firstSite, 7)!,
    );
    final media = mediaFactory.sessions.single;

    media.connectionState = ResenhaMediaConnectionState.reconnecting;
    media.notifyListeners();
    expect(controller.call?.status, ResenhaCallStatus.reconnecting);
    // Long enough for any scheduled heartbeat to fire while the call is away
    // from connected, which is the moment the chain historically died.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final heartbeatsBefore = transport.pluginWrites
        .where((write) => write.path.endsWith('/heartbeat.json'))
        .length;

    media.connectionState = ResenhaMediaConnectionState.connected;
    media.notifyListeners();
    expect(controller.call?.status, ResenhaCallStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      transport.pluginWrites
          .where((write) => write.path.endsWith('/heartbeat.json'))
          .length,
      greaterThan(heartbeatsBefore),
    );
  });

  test(
    'keeps a local media setting when roster state is rate limited',
    () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final stateWritesBefore = transport.pluginWrites
          .where((write) => write.path.endsWith('/state.json'))
          .length;
      transport.pluginWriteFailures['POST /resenha/rooms/7/state.json'] =
          const WriteException(
            WriteFailure.rateLimited,
            statusCode: 429,
            retryAfter: Duration.zero,
          );

      await controller.setCameraEnabled(true);

      expect(controller.call?.cameraEnabled, isTrue);
      expect(controller.call?.error, isNull);
      expect(mediaFactory.sessions.single.camera, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        transport.pluginWrites.where(
          (write) => write.path.endsWith('/state.json'),
        ),
        hasLength(stateWritesBefore + 2),
      );
    },
  );

  test(
    'a failed media toggle keeps roster updates that landed while in flight',
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
      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
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

  test('an externally ended screen share updates roster state', () async {
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
    final stateWrites = transport.pluginWrites
        .where((write) => write.path.endsWith('/state.json'))
        .toList();
    expect(stateWrites.last.body['screen'], isFalse);
  });

  test(
    'a roster removal from another client tears the local call down',
    () async {
      await controller.ensureLoaded(firstSite);
      await controller.join(
        siteUrl: firstSite,
        siteName: 'One',
        room: controller.room(firstSite, 7)!,
      );
      final media = mediaFactory.sessions.single;

      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
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
        transport.pluginWrites.where(
          (write) => write.path.endsWith('/leave.json'),
        ),
        isEmpty,
      );
    },
  );

  test('a stale roster without the local user does not abort a join', () async {
    await controller.ensureLoaded(firstSite);
    final connectGate = Completer<void>();
    mediaFactory.nextConnectGate = connectGate;

    final joining = controller.join(
      siteUrl: firstSite,
      siteName: 'One',
      room: controller.room(firstSite, 7)!,
    );
    while (mediaFactory.sessions.isEmpty ||
        mediaFactory.sessions.single.connectCount == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.call?.status, ResenhaCallStatus.joining);

    firstTracker.deliverPluginMessage('/resenha/rooms/7', {
      'type': 'participants',
      'participants': const <Object?>[],
    });
    await Future<void>.delayed(Duration.zero);
    connectGate.complete();
    await joining;

    expect(controller.call?.status, ResenhaCallStatus.connected);
    expect(mediaFactory.sessions.single.disposeCount, 0);
    expect(
      diagnostics.records.where(
        (record) => record.event == 'call.leave.started',
      ),
      isEmpty,
    );
  });

  test(
    'leave remains terminal and idempotent when native teardown fails',
    () async {
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'resenha-leave',
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
        containsAll({'resenha.media.dispose', 'resenha.systemCall.end'}),
      );
    },
  );

  test(
    'kicks, room destruction, and account removal tear media down',
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
      firstTracker.deliverPluginMessage('/resenha/rooms/7', {
        'type': 'kicked',
        'room_id': 7,
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.call, isNull);
      expect(
        transport.pluginWrites.where(
          (write) => write.path.endsWith('/leave.json'),
        ),
        isEmpty,
      );

      await join();
      firstTracker.deliverPluginMessage('/resenha/rooms/index', {
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
}
