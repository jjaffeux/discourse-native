import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_api.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_callkit.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_controller.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_media.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
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

  @override
  ResenhaMediaSession create({
    required ResenhaJoinResponse join,
    required int localUserId,
    required ResenhaSignalSender sendSignal,
    required ResenhaLiveKitCredentialRefresher refreshLiveKitCredentials,
  }) {
    final session = FakeResenhaMediaSession(join.transport);
    sessions.add(session);
    return session;
  }
}

final class FakeResenhaMediaSession extends ChangeNotifier
    implements ResenhaMediaSession {
  FakeResenhaMediaSession(this.transport);

  @override
  final ResenhaTransport transport;

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
  List<ResenhaParticipant> participants = const [];

  @override
  Object? get localVideoTrack => null;

  @override
  Set<int> get speakingParticipantIds => const {};

  @override
  Object? videoTrackFor(int participantId) => null;

  @override
  Future<void> connect() async => connectCount++;

  @override
  Future<List<rtc.MediaDeviceInfo>> devices() async => const [];

  @override
  Future<void> handleSignal(int senderId, Map<String, dynamic> data) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> selectAudioInput(String deviceId) async {}

  @override
  Future<void> setAudioPublishingAllowed(bool allowed) async {
    audioPublishingAllowed = allowed;
  }

  @override
  Future<void> setCameraEnabled(bool enabled, {String? deviceId}) async {
    camera = enabled;
  }

  @override
  Future<void> setDeafened(bool enabled) async => deafened = enabled;

  @override
  Future<void> setMuted(bool enabled) async => muted = enabled;

  @override
  Future<void> setParticipantVolume(int participantId, double volume) async {}

  @override
  Future<void> setScreenShareEnabled(bool enabled) async => screen = enabled;

  @override
  Future<void> syncParticipants(List<ResenhaParticipant> value) async {
    participants = value;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    super.dispose();
  }
}

final class FakeResenhaSystemCall implements ResenhaSystemCall {
  final StreamController<ResenhaSystemCallAction> controller =
      StreamController.broadcast();
  int starts = 0;
  int connectedCalls = 0;
  int ends = 0;
  bool? systemMuted;

  @override
  Stream<ResenhaSystemCallAction> get actions => controller.stream;

  void send(ResenhaSystemCallAction action) => controller.add(action);

  @override
  Future<void> connected() async => connectedCalls++;

  @override
  Future<void> dispose() => controller.close();

  @override
  Future<void> end() async => ends++;

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

void main() {
  const firstSite = 'https://one.example.com';
  const secondSite = 'https://two.example.com';
  late FakeDiscourseApi transport;
  late FakeApiCredentialReader credentials;
  late FakeResenhaMediaFactory mediaFactory;
  late FakeResenhaSystemCall systemCall;
  late FakeSiteTracker firstTracker;
  late FakeSiteTracker secondTracker;
  late ResenhaController controller;

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
      heartbeatInterval: const Duration(milliseconds: 15),
    );
  });

  tearDown(() => controller.dispose());

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
        'type': 'participants',
        'participants': [
          {'id': 1, 'username': 'sam', 'role': 'speaker'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      expect(media.audioPublishingAllowed, isTrue);
    },
  );

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
