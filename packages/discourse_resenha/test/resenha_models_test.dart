import 'dart:convert';
import 'dart:io';

import 'package:discourse_resenha/src/resenha_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/resenha/$name.json').readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> fixtureList(String name) =>
    (jsonDecode(File('test/fixtures/resenha/$name.json').readAsStringSync())
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

void main() {
  group('room snapshots', () {
    test('parse the complete room snapshot from the pinned contract', () {
      final room = ResenhaRoom.fromJson(fixture('room'));

      expect(
        (
          id: room.id,
          name: room.name,
          slug: room.slug,
          description: room.description,
          cookedDescription: room.cookedDescription,
          isPublic: room.isPublic,
          ephemeral: room.ephemeral,
          type: room.type,
        ),
        (
          id: 7,
          name: 'Conf Room 1',
          slug: 'conf-room-1',
          description: 'Daily engineering room',
          cookedDescription: '<p>Daily engineering room</p>',
          isPublic: false,
          ephemeral: false,
          type: ResenhaRoomType.stage,
        ),
      );
      expect(
        (
          maxParticipants: room.maxParticipants,
          memberCount: room.memberCount,
          messageBusLastId: room.messageBusLastId,
          creatorId: room.creatorId,
          canManage: room.canManage,
          videoEnabled: room.videoEnabled,
          videoAllowed: room.videoAllowed,
          maxQualityProfile: room.maxQualityProfile,
        ),
        (
          maxParticipants: 20,
          memberCount: 4,
          messageBusLastId: 91,
          creatorId: 1,
          canManage: true,
          videoEnabled: true,
          videoAllowed: true,
          maxQualityProfile: ResenhaQualityProfile.high,
        ),
      );
      expect(
        (
          chatAvailable: room.chatAvailable,
          chatChannelId: room.chatChannelId,
          chatIdleMinutes: room.chatIdleMinutes,
          chatThreadTitleTemplate: room.chatThreadTitleTemplate,
          livekitEnabled: room.livekitEnabled,
        ),
        (
          chatAvailable: true,
          chatChannelId: 42,
          chatIdleMinutes: 15,
          chatThreadTitleTemplate: 'Team meeting at {time}',
          livekitEnabled: true,
        ),
      );
      expect(
        room.participants.map(
          (participant) => (
            id: participant.id,
            username: participant.username,
            name: participant.name,
            avatarTemplate: participant.avatarTemplate,
            role: participant.role,
            muted: participant.muted,
            deafened: participant.deafened,
            videoOn: participant.videoOn,
            screenSharing: participant.screenSharing,
            watchingVideo: participant.watchingVideo,
            idleState: participant.idleState,
            handRaisedAt: participant.handRaisedAt,
          ),
        ),
        [
          (
            id: 1,
            username: 'sam',
            name: 'Sam Example',
            avatarTemplate: '/user_avatar/example.com/sam/{size}/1_2.png',
            role: ResenhaRole.moderator,
            muted: false,
            deafened: false,
            videoOn: true,
            screenSharing: false,
            watchingVideo: true,
            idleState: ResenhaIdleState.active,
            handRaisedAt: null,
          ),
          (
            id: 2,
            username: 'lee',
            name: null,
            avatarTemplate: null,
            role: ResenhaRole.participant,
            muted: true,
            deafened: false,
            videoOn: false,
            screenSharing: false,
            watchingVideo: false,
            idleState: ResenhaIdleState.active,
            handRaisedAt: DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
          ),
        ],
      );
      expect(
        (
          id: room.membership?.id,
          roomId: room.membership?.roomId,
          userId: room.membership?.userId,
          role: room.membership?.role,
          username: room.membership?.user?.username,
        ),
        (
          id: 8,
          roomId: 7,
          userId: 1,
          role: ResenhaRole.moderator,
          username: 'sam',
        ),
      );
      expect(
        (
          active: room.recording?.active,
          startedById: room.recording?.startedById,
          startedAt: room.recording?.startedAt,
        ),
        (
          active: true,
          startedById: 1,
          startedAt: DateTime.utc(2026, 8, 8, 16, 0, 0, 250),
        ),
      );
    });
  });

  group('directory snapshots', () {
    test('parse directory capabilities and message-bus cursors', () {
      final directory = ResenhaDirectory.fromJson(fixture('directory'));

      expect(directory.canCreateRoom, isTrue);
      expect(directory.messageBusLastId, 144);
      expect(directory.rooms.single.messageBusLastId, 91);
    });

    test('keep valid rooms while defaulting malformed optional fields', () {
      final directory = ResenhaDirectory.fromJson(fixture('malformed'));

      expect(directory.rooms, hasLength(1));
      expect(directory.rooms.single.id, 7);
      expect(directory.rooms.single.name, 'Voice room');
      expect(directory.rooms.single.participants.single.id, 2);
      expect(directory.canCreateRoom, isFalse);
      expect(directory.messageBusLastId, isNull);
    });
  });

  group('join responses', () {
    test('parse the pinned mesh transport', () {
      final mesh = ResenhaJoinResponse.fromJson(fixture('join_mesh'));

      expect(mesh.transport, ResenhaTransport.mesh);
      expect(mesh.ice.relayOnly, isTrue);
      expect(mesh.ice.servers, hasLength(2));
      expect(mesh.ice.servers.last.urls, [
        'turn:turn.example.com:3478?transport=udp',
      ]);
    });

    test('parse the pinned LiveKit transport', () {
      final livekit = ResenhaJoinResponse.fromJson(fixture('join_livekit'));

      expect(livekit.transport, ResenhaTransport.livekit);
      expect(livekit.livekit?.url, 'wss://livekit.example.com');
    });

    test('fail a join safely when the transport is unknown', () {
      final payload = fixture('join_mesh')..['transport'] = 'future-sfu';

      expect(
        () => ResenhaJoinResponse.fromJson(payload),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('room events', () {
    test('ignore unknown events and parse stage and recording events', () {
      final events = fixtureList(
        'events',
      ).map(ResenhaRoomEvent.fromJson).toList();

      final participants = events[0] as ResenhaParticipantsEvent;
      expect(
        participants.participants.map(
          (participant) => (
            id: participant.id,
            username: participant.username,
            role: participant.role,
            handRaisedAt: participant.handRaisedAt,
          ),
        ),
        [
          (
            id: 1,
            username: 'sam',
            role: ResenhaRole.moderator,
            handRaisedAt: null,
          ),
          (
            id: 2,
            username: 'lee',
            role: ResenhaRole.participant,
            handRaisedAt: DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
          ),
        ],
      );
      expect(events[1], isA<ResenhaKickedEvent>());
      final roleChanged = events[2] as ResenhaRoleChangedEvent;
      expect(
        (userId: roleChanged.userId, role: roleChanged.role),
        (userId: 2, role: ResenhaRole.speaker),
      );
      final handRaise = events[3] as ResenhaHandRaiseEvent;
      expect(
        (
          userId: handRaise.userId,
          raised: handRaise.raised,
          reason: handRaise.reason,
        ),
        (userId: 2, raised: false, reason: 'dismissed'),
      );
      final recording = (events[4] as ResenhaRecordingEvent).recording;
      expect(
        (
          active: recording?.active,
          startedById: recording?.startedById,
          startedAt: recording?.startedAt,
        ),
        (
          active: true,
          startedById: 1,
          startedAt: DateTime.utc(2026, 8, 8, 16, 0, 0, 250),
        ),
      );
      expect((events[5] as ResenhaRecordingEvent).recording, isNull);
      expect(events[6], isNull);
    });
  });

  group('chat and membership snapshots', () {
    test('parse the associated chat identifiers', () {
      final chat = ResenhaChatSession.fromJson(fixture('chat'));

      expect((chat.channelId, chat.threadId), (42, 99));
    });

    test('parse membership identities, roles, and users', () {
      final memberships = [
        for (final value in fixture('memberships')['memberships'] as List)
          ResenhaMembership.fromJson(value as Map<String, dynamic>),
      ];

      expect(memberships.map((value) => value.id), [8, 9]);
      expect(memberships.map((value) => value.userId), [1, 2]);
      expect(memberships.map((value) => value.role), const [
        ResenhaRole.moderator,
        ResenhaRole.speaker,
      ]);
      expect(memberships.map((value) => value.user?.username), ['sam', 'lee']);
    });
  });

  group('participant timestamp parsing', () {
    test('bounds and safely ignores malformed hand-raise dates', () {
      Map<String, dynamic> participant(Object? handRaisedAt) => {
        'id': 1,
        'username': 'sam',
        'role': 'participant',
        'hand_raised_at': handRaisedAt,
      };

      expect(
        ResenhaParticipant.fromJson(
          participant('2026-08-12T12:34:56Z'),
        ).handRaisedAt,
        DateTime.utc(2026, 8, 12, 12, 34, 56),
      );
      expect(
        ResenhaParticipant.fromJson(participant('2' * 200000)).handRaisedAt,
        isNull,
      );
      expect(
        ResenhaParticipant.fromJson(participant(double.nan)).handRaisedAt,
        isNull,
      );
      expect(
        ResenhaParticipant.fromJson(participant(double.infinity)).handRaisedAt,
        isNull,
      );
    });
  });

  group('room drafts', () {
    test('serialize the complete server contract', () {
      const draft = ResenhaRoomDraft(
        name: 'Open room',
        isPublic: true,
        type: ResenhaRoomType.open,
        maxQualityProfile: ResenhaQualityProfile.maximum,
      );

      expect(draft.toJson(), {
        'name': 'Open room',
        'description': null,
        'public': true,
        'room_type': 'open',
        'max_participants': null,
        'video_enabled': false,
        'chat_channel_id': null,
        'chat_idle_minutes': null,
        'chat_thread_title_template': null,
        'livekit_enabled': null,
        'max_quality_profile': 'maximum',
      });
    });
  });
}
