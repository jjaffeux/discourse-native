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
import 'package:discourse_native/src/plugins/resenha/resenha_media.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_preferences.dart';
import 'package:flutter/foundation.dart';
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
  Completer<void>? nextConnectGate;

  @override
  ResenhaMediaSession create({
    required ResenhaJoinResponse join,
    required int localUserId,
    required ResenhaSignalSender sendSignal,
    required ResenhaLiveKitCredentialRefresher refreshLiveKitCredentials,
  }) {
    final session = FakeResenhaMediaSession(
      join.transport,
      connectGate: nextConnectGate,
    );
    nextConnectGate = null;
    sessions.add(session);
    return session;
  }
}

final class FakeResenhaMediaSession extends ChangeNotifier
    implements ResenhaMediaSession {
  FakeResenhaMediaSession(this.transport, {this.connectGate});

  @override
  final ResenhaTransport transport;
  final Completer<void>? connectGate;

  @override
  ResenhaMediaConnectionState get connectionState =>
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
    selectedAudioOutput = deviceId;
  }

  @override
  Future<void> selectAudioInput(String deviceId) async {
    selectedAudioInput = deviceId;
  }

  @override
  Future<void> setAudioPublishingAllowed(bool allowed) async {
    audioPublishingAllowed = allowed;
    if (audioPublishingFailure case final failure?) throw failure;
  }

  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {
    camera = enabled;
    if (deviceId != null) selectedCamera = deviceId;
  }

  @override
  Future<void> setDeafened(bool enabled) async => deafened = enabled;

  @override
  Future<void> setMuted(bool enabled) async {
    muted = enabled;
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

final class _PendingThreadMessages {
  _PendingThreadMessages({required this.before});

  final int? before;
  final Completer<ChatMessagePage> response = Completer();
}

final class _ControlledResenhaTransport extends FakeDiscourseApi {
  _ControlledResenhaTransport({super.pluginResponses, super.chatMessagesByKey});

  final Set<String> heldPluginPaths = {};
  final Set<String> heldPluginWritePaths = {};
  final List<String> pluginGets = [];
  final List<_PendingPluginGet> pendingPluginGets = [];
  final List<_PendingPluginWrite> pendingPluginWrites = [];
  final List<_PendingThreadMessages> pendingThreadMessages = [];
  bool holdThreadMessages = false;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String apiKey,
    String? clientId,
  }) {
    pluginGets.add(path);
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
        apiKey: apiKey,
        clientId: clientId,
      );
    }
    final pending = _PendingThreadMessages(before: before);
    pendingThreadMessages.add(pending);
    return pending.response.future;
  }
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
);

void main() {
  const firstSite = 'https://one.example.com';
  const secondSite = 'https://two.example.com';
  late FakeDiscourseApi transport;
  late ApiCredentialReader credentials;
  late FakeResenhaPreferences preferences;
  late FakeResenhaMediaFactory mediaFactory;
  late FakeResenhaSystemCall systemCall;
  late FakeSiteTracker firstTracker;
  late FakeSiteTracker secondTracker;
  late ResenhaController controller;

  void useTransport(FakeDiscourseApi value) {
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
      onCallSiteChanged: () {},
      mediaFactory: mediaFactory,
      systemCall: systemCall,
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
        ),
      },
    );
    credentials = FakeApiCredentialReader()
      ..keys[firstSite] = 'first-key'
      ..keys[secondSite] = 'second-key';
    preferences = FakeResenhaPreferences();
    mediaFactory = FakeResenhaMediaFactory();
    systemCall = FakeResenhaSystemCall();
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
        transport.pluginWrites.where(
          (write) => write.path.endsWith('/leave.json'),
        ),
        isEmpty,
      );
    },
  );

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
        'room': fixture('directory')['rooms'][0],
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
