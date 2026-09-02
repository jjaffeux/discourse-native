import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://voice.example.com';
const _apiKey = 'api-key';
const _roomId = 7;
const _participantSessionId = 'participant-session';
const _roomDraft = VoiceRoomDraft(
  name: 'Conf Room 1',
  isPublic: false,
  type: VoiceRoomType.stage,
  maxQualityProfile: VoiceQualityProfile.high,
);

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

({VoiceApi api, RecordingPluginTransport transport}) _apiWithResponses(
  Map<String, Map<String, dynamic>> responses,
) {
  final transport = RecordingPluginTransport(responses: responses);
  return (api: VoiceApi(transport), transport: transport);
}

void _expectRequest(
  PluginTransportRequest request, {
  required String method,
  required String path,
  Map<String, Object?> body = const {},
}) {
  expect(request.siteUrl, _siteUrl);
  expect(request.apiKey, _apiKey);
  expect(request.clientId, isNull);
  expect(request.method, method);
  expect(request.path, path);
  expect(request.body, body);
  expect(request.expectsList, isFalse);
}

void main() {
  group('room discovery', () {
    test('lists rooms', () async {
      final (:api, :transport) = _apiWithResponses({
        'GET /voice/rooms.json': fixture('directory'),
      });

      final directory = await api.rooms(siteUrl: _siteUrl, apiKey: _apiKey);

      expect(directory.messageBusLastId, 144);
      expect(directory.canCreateRoom, isTrue);
      expect(directory.rooms.single.slug, 'conf-room-1');
      _expectRequest(
        transport.requests.single,
        method: 'GET',
        path: '/voice/rooms.json',
      );
    });

    test('reads a room by slug', () async {
      final (:api, :transport) = _apiWithResponses({
        'GET /voice/rooms/conf-room-1.json': {'room': fixture('room')},
      });

      final room = await api.room(
        siteUrl: _siteUrl,
        slug: 'conf-room-1',
        apiKey: _apiKey,
      );

      expect((room.id, room.slug), (_roomId, 'conf-room-1'));
      _expectRequest(
        transport.requests.single,
        method: 'GET',
        path: '/voice/rooms/conf-room-1.json',
      );
    });
  });

  group('participant session', () {
    test('joins a room', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/join.json': fixture('join_mesh'),
      });

      final join = await api.join(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        invitedBy: 'sam',
        participantSessionId: 'existing-participant-session',
      );

      expect(join.transport, VoiceTransport.mesh);
      expect(join.participantSessionId, 'mesh-participant-session');
      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/join.json',
        body: {
          'skip_status': null,
          'invited_by': 'sam',
          'participant_session_id': 'existing-participant-session',
        },
      );
    });

    test('sends a heartbeat', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/heartbeat.json': {},
      });

      await api.heartbeat(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        idle: VoiceIdleState.afk,
        participantSessionId: _participantSessionId,
      );

      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/heartbeat.json',
        body: {
          'idle_state': 'afk',
          'participant_session_id': _participantSessionId,
        },
      );
    });

    test('leaves a room', () async {
      final (:api, :transport) = _apiWithResponses({
        'DELETE /voice/rooms/7/leave.json': {},
      });

      await api.leave(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        participantSessionId: _participantSessionId,
      );

      _expectRequest(
        transport.requests.single,
        method: 'DELETE',
        path: '/voice/rooms/7/leave.json',
        body: {'participant_session_id': _participantSessionId},
      );
    });

    test('refreshes LiveKit credentials', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/livekit_token.json': {
          ...(fixture('join_livekit')['livekit'] as Map<String, dynamic>),
          'participant_session_id': 'rotated-participant-session',
        },
      });

      final credentials = await api.livekitToken(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
      );

      expect(credentials.url, 'wss://livekit.example.com');
      expect(credentials.token, 'redacted-fixture-token');
      expect(credentials.participantSessionId, 'rotated-participant-session');
      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/livekit_token.json',
      );
    });
  });

  group('participant media state', () {
    test('sends signaling payload', () async {
      const payload = <String, Object?>{
        'recipient_id': 2,
        'events': <Object?>[],
      };
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/signal.json': {},
      });

      await api.signal(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        payload: payload,
        participantSessionId: _participantSessionId,
      );

      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/signal.json',
        body: {
          'payload': payload,
          'participant_session_id': _participantSessionId,
        },
      );
    });

    test('updates participant state', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/state.json': {},
      });

      await api.state(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        muted: true,
        screen: false,
        participantSessionId: _participantSessionId,
      );

      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/state.json',
        body: {
          'muted': true,
          'deafened': null,
          'video': null,
          'screen': false,
          'watching': null,
          'participant_session_id': _participantSessionId,
        },
      );
    });
  });

  group('stage moderation', () {
    test('raises and lowers a hand', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/request_to_speak.json': {},
        'DELETE /voice/rooms/7/request_to_speak.json': {},
      });

      await api.requestToSpeak(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        participantSessionId: _participantSessionId,
      );
      await api.requestToSpeak(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        raised: false,
        userId: 2,
        participantSessionId: _participantSessionId,
      );

      expect(transport.requests, hasLength(2));
      _expectRequest(
        transport.requests[0],
        method: 'POST',
        path: '/voice/rooms/7/request_to_speak.json',
        body: {
          'user_id': null,
          'participant_session_id': _participantSessionId,
        },
      );
      _expectRequest(
        transport.requests[1],
        method: 'DELETE',
        path: '/voice/rooms/7/request_to_speak.json',
        body: {'user_id': 2, 'participant_session_id': _participantSessionId},
      );
    });

    test('kicks a participant', () async {
      final (:api, :transport) = _apiWithResponses({
        'DELETE /voice/rooms/7/kick.json': {},
      });

      await api.kick(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        userId: 2,
      );

      _expectRequest(
        transport.requests.single,
        method: 'DELETE',
        path: '/voice/rooms/7/kick.json',
        body: {'user_id': 2},
      );
    });

    test('flags a participant', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/flag.json': {},
      });

      await api.flag(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        userId: 2,
        flagTypeId: 7,
        message: 'Needs attention',
      );

      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/flag.json',
        body: {'user_id': 2, 'flag_type_id': 7, 'message': 'Needs attention'},
      );
    });

    test('finds the notify-moderators flag type', () async {
      final (:api, :transport) = _apiWithResponses({
        'GET /site.json': {
          'post_action_types': [
            {'id': 7, 'name_key': 'notify_moderators'},
          ],
        },
      });

      final flagTypeId = await api.notifyModeratorsFlagType(
        siteUrl: _siteUrl,
        apiKey: _apiKey,
      );

      expect(flagTypeId, 7);
      _expectRequest(
        transport.requests.single,
        method: 'GET',
        path: '/site.json',
      );
    });
  });

  group('recording', () {
    test('starts and stops a recording', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/recording.json': {
          'recording': fixture('room')['recording'],
        },
        'DELETE /voice/rooms/7/recording.json': {},
      });

      final started = await api.setRecording(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        active: true,
      );
      final stopped = await api.setRecording(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        active: false,
      );

      expect(started?.active, isTrue);
      expect(started?.startedById, 1);
      expect(stopped, isNull);
      expect(transport.requests, hasLength(2));
      _expectRequest(
        transport.requests[0],
        method: 'POST',
        path: '/voice/rooms/7/recording.json',
      );
      _expectRequest(
        transport.requests[1],
        method: 'DELETE',
        path: '/voice/rooms/7/recording.json',
      );
    });
  });

  group('room Chat', () {
    test('reads an existing chat session', () async {
      final (:api, :transport) = _apiWithResponses({
        'GET /voice/rooms/7/chat_session.json': fixture('chat'),
      });

      final session = await api.chatSession(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
      );

      expect((session.channelId, session.threadId), (42, 99));
      _expectRequest(
        transport.requests.single,
        method: 'GET',
        path: '/voice/rooms/7/chat_session.json',
      );
    });

    test('ensures a chat session exists', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/chat_session.json': fixture('chat'),
      });

      final session = await api.chatSession(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        ensure: true,
      );

      expect((session.channelId, session.threadId), (42, 99));
      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/chat_session.json',
      );
    });

    test('starts a chat with its first message', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/chat_message.json': fixture('chat'),
      });

      final session = await api.firstChatMessage(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        message: 'hello',
      );

      expect((session.channelId, session.threadId), (42, 99));
      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/chat_message.json',
        body: {'message': 'hello'},
      );
    });
  });

  group('room management', () {
    test('creates a room', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms.json': {'room': fixture('room')},
      });

      final room = await api.createRoom(
        siteUrl: _siteUrl,
        apiKey: _apiKey,
        draft: _roomDraft,
      );

      expect((room.id, room.type), (_roomId, VoiceRoomType.stage));
      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms.json',
        body: {'room': _roomDraft.toJson()},
      );
    });

    test('updates a room', () async {
      final (:api, :transport) = _apiWithResponses({
        'PUT /voice/rooms/7.json': {'room': fixture('room')},
      });

      final room = await api.updateRoom(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        draft: _roomDraft,
      );

      expect((room.id, room.type), (_roomId, VoiceRoomType.stage));
      _expectRequest(
        transport.requests.single,
        method: 'PUT',
        path: '/voice/rooms/7.json',
        body: {'room': _roomDraft.toJson()},
      );
    });

    test('deletes a room', () async {
      final (:api, :transport) = _apiWithResponses({
        'DELETE /voice/rooms/7.json': {},
      });

      await api.deleteRoom(siteUrl: _siteUrl, roomId: _roomId, apiKey: _apiKey);

      _expectRequest(
        transport.requests.single,
        method: 'DELETE',
        path: '/voice/rooms/7.json',
      );
    });
  });

  group('room membership API', () {
    test('lists memberships', () async {
      final (:api, :transport) = _apiWithResponses({
        'GET /voice/rooms/7/memberships.json': fixture('memberships'),
      });

      final memberships = await api.memberships(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
      );

      expect(memberships.map((membership) => membership.role), [
        VoiceRole.moderator,
        VoiceRole.speaker,
      ]);
      _expectRequest(
        transport.requests.single,
        method: 'GET',
        path: '/voice/rooms/7/memberships.json',
      );
    });

    test('adds a membership', () async {
      final (:api, :transport) = _apiWithResponses({
        'POST /voice/rooms/7/memberships.json': {},
      });

      await api.addMembership(
        siteUrl: _siteUrl,
        roomId: _roomId,
        apiKey: _apiKey,
        username: 'lee',
        role: VoiceRole.speaker,
      );

      _expectRequest(
        transport.requests.single,
        method: 'POST',
        path: '/voice/rooms/7/memberships.json',
        body: {'user_id': null, 'username': 'lee', 'role': 'speaker'},
      );
    });

    test('updates a membership', () async {
      final (:api, :transport) = _apiWithResponses({
        'PUT /voice/rooms/7/memberships/8.json': {},
      });

      await api.updateMembership(
        siteUrl: _siteUrl,
        roomId: _roomId,
        membershipId: 8,
        apiKey: _apiKey,
        role: VoiceRole.moderator,
      );

      _expectRequest(
        transport.requests.single,
        method: 'PUT',
        path: '/voice/rooms/7/memberships/8.json',
        body: {'role': 'moderator'},
      );
    });

    test('removes a membership', () async {
      final (:api, :transport) = _apiWithResponses({
        'DELETE /voice/rooms/7/memberships/8.json': {},
      });

      await api.removeMembership(
        siteUrl: _siteUrl,
        roomId: _roomId,
        membershipId: 8,
        apiKey: _apiKey,
      );

      _expectRequest(
        transport.requests.single,
        method: 'DELETE',
        path: '/voice/rooms/7/memberships/8.json',
      );
    });
  });
}
