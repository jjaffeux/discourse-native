import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/plugins/resenha/resenha_api.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/resenha/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  const site = 'https://voice.example.com';
  const key = 'api-key';

  test('uses the directory/show/join contract routes', () async {
    final fake = FakeDiscourseApi(
      pluginResponses: {
        'GET /resenha/rooms.json': fixture('directory'),
        'GET /resenha/rooms/conf-room-1.json': {'room': fixture('room')},
        'POST /resenha/rooms/7/join.json': fixture('join_mesh'),
      },
    );
    final api = ResenhaApi(fake);

    final directory = await api.rooms(siteUrl: site, apiKey: key);
    final room = await api.room(
      siteUrl: site,
      slug: 'conf-room-1',
      apiKey: key,
    );
    final join = await api.join(
      siteUrl: site,
      roomId: 7,
      apiKey: key,
      participantSessionId: 'existing-participant-session',
    );

    expect(directory.messageBusLastId, 144);
    expect(room.slug, 'conf-room-1');
    expect(join.transport, ResenhaTransport.mesh);
    expect(join.participantSessionId, 'mesh-participant-session');
    expect(fake.pluginWrites.single.path, '/resenha/rooms/7/join.json');
    expect(
      fake.pluginWrites.single.body['participant_session_id'],
      'existing-participant-session',
    );
  });

  test(
    'maps state, signaling, stage, moderation, and recording writes',
    () async {
      final responses = <String, Map<String, dynamic>>{
        for (final key in [
          'POST /resenha/rooms/7/signal.json',
          'POST /resenha/rooms/7/state.json',
          'POST /resenha/rooms/7/request_to_speak.json',
          'DELETE /resenha/rooms/7/request_to_speak.json',
          'DELETE /resenha/rooms/7/kick.json',
          'POST /resenha/rooms/7/flag.json',
          'DELETE /resenha/rooms/7/recording.json',
        ])
          key: <String, dynamic>{},
        'POST /resenha/rooms/7/recording.json': {
          'recording': fixture('room')['recording'],
        },
        'GET /site.json': {
          'post_action_types': [
            {'id': 7, 'name_key': 'notify_moderators'},
          ],
        },
      };
      final fake = FakeDiscourseApi(pluginResponses: responses);
      final api = ResenhaApi(fake);

      await api.signal(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        payload: {'recipient_id': 2, 'events': const []},
        participantSessionId: 'participant-session',
      );
      await api.state(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        muted: true,
        screen: false,
        participantSessionId: 'participant-session',
      );
      await api.requestToSpeak(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        participantSessionId: 'participant-session',
      );
      await api.requestToSpeak(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        raised: false,
        userId: 2,
        participantSessionId: 'participant-session',
      );
      await api.kick(siteUrl: site, roomId: 7, apiKey: key, userId: 2);
      await api.flag(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        userId: 2,
        flagTypeId: 7,
        message: 'Needs attention',
      );
      final recording = await api.setRecording(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        active: true,
      );
      await api.setRecording(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        active: false,
      );
      expect(await api.notifyModeratorsFlagType(siteUrl: site, apiKey: key), 7);

      expect(
        fake.pluginWrites.map((write) => '${write.method} ${write.path}'),
        [
          'POST /resenha/rooms/7/signal.json',
          'POST /resenha/rooms/7/state.json',
          'POST /resenha/rooms/7/request_to_speak.json',
          'DELETE /resenha/rooms/7/request_to_speak.json',
          'DELETE /resenha/rooms/7/kick.json',
          'POST /resenha/rooms/7/flag.json',
          'POST /resenha/rooms/7/recording.json',
          'DELETE /resenha/rooms/7/recording.json',
        ],
      );
      expect(recording?.active, isTrue);
      for (final write in fake.pluginWrites.take(4)) {
        expect(
          write.body['participant_session_id'],
          'participant-session',
          reason: write.path,
        );
      }
    },
  );

  test(
    'maps chat, room CRUD, memberships, heartbeat and LiveKit token',
    () async {
      final room = fixture('room');
      final responses = <String, Map<String, dynamic>>{
        'POST /resenha/rooms/7/heartbeat.json': {},
        'DELETE /resenha/rooms/7/leave.json': {},
        'POST /resenha/rooms/7/livekit_token.json': {
          ...(fixture('join_livekit')['livekit'] as Map<String, dynamic>),
          'participant_session_id': 'rotated-participant-session',
        },
        'GET /resenha/rooms/7/chat_session.json': fixture('chat'),
        'POST /resenha/rooms/7/chat_session.json': fixture('chat'),
        'POST /resenha/rooms/7/chat_message.json': fixture('chat'),
        'POST /resenha/rooms.json': {'room': room},
        'PUT /resenha/rooms/7.json': {'room': room},
        'DELETE /resenha/rooms/7.json': {},
        'GET /resenha/rooms/7/memberships.json': fixture('memberships'),
        'POST /resenha/rooms/7/memberships.json': {},
        'PUT /resenha/rooms/7/memberships/8.json': {},
        'DELETE /resenha/rooms/7/memberships/8.json': {},
      };
      final fake = FakeDiscourseApi(pluginResponses: responses);
      final api = ResenhaApi(fake);
      const draft = ResenhaRoomDraft(
        name: 'Conf Room 1',
        isPublic: false,
        type: ResenhaRoomType.stage,
        maxQualityProfile: ResenhaQualityProfile.high,
      );

      await api.heartbeat(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        participantSessionId: 'participant-session',
      );
      await api.leave(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        participantSessionId: 'participant-session',
      );
      final livekit = await api.livekitToken(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
      );
      expect(livekit.token, 'redacted-fixture-token');
      expect(livekit.participantSessionId, 'rotated-participant-session');
      expect(
        (await api.chatSession(siteUrl: site, roomId: 7, apiKey: key)).threadId,
        99,
      );
      expect(
        (await api.chatSession(
          siteUrl: site,
          roomId: 7,
          apiKey: key,
          ensure: true,
        )).threadId,
        99,
      );
      await api.firstChatMessage(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        message: 'hello',
      );
      await api.createRoom(siteUrl: site, apiKey: key, draft: draft);
      await api.updateRoom(siteUrl: site, roomId: 7, apiKey: key, draft: draft);
      await api.deleteRoom(siteUrl: site, roomId: 7, apiKey: key);
      expect(
        await api.memberships(siteUrl: site, roomId: 7, apiKey: key),
        hasLength(2),
      );
      await api.addMembership(
        siteUrl: site,
        roomId: 7,
        apiKey: key,
        username: 'lee',
        role: ResenhaRole.speaker,
      );
      await api.updateMembership(
        siteUrl: site,
        roomId: 7,
        membershipId: 8,
        apiKey: key,
        role: ResenhaRole.moderator,
      );
      await api.removeMembership(
        siteUrl: site,
        roomId: 7,
        membershipId: 8,
        apiKey: key,
      );

      for (final path in [
        '/resenha/rooms/7/heartbeat.json',
        '/resenha/rooms/7/leave.json',
      ]) {
        expect(
          fake.pluginWrites
              .singleWhere((write) => write.path == path)
              .body['participant_session_id'],
          'participant-session',
        );
      }

      final create = fake.pluginWrites.firstWhere(
        (write) => write.path == '/resenha/rooms.json',
      );
      expect(
        (create.body['room'] as Map<String, Object?>)['room_type'],
        'stage',
      );
      expect(
        (create.body['room'] as Map<String, Object?>)['max_quality_profile'],
        'high',
      );
    },
  );
}
