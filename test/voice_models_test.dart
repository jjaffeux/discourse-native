import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> fixtureList(String name) =>
    (jsonDecode(File('test/fixtures/voice/$name.json').readAsStringSync())
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

const _callRoomJson = <String, Object?>{
  'id': 9,
  'name': '📞 sam + kim',
  'slug': 'call-1a2b',
  'public': false,
  'room_type': 'open',
  'active_participants': [
    {'id': 1, 'username': 'sam', 'role': 'moderator'},
  ],
  'ringing': [
    {
      'user': {'id': 3, 'username': 'kim'},
      'notified_at': 1786204800,
    },
    {
      'user': {'id': 1, 'username': 'sam'},
      'notified_at': 1786204800,
    },
    {
      'user': {'id': 0, 'username': 'ghost'},
      'notified_at': 1786204800,
    },
    {'user': <String, Object?>{}, 'notified_at': 1786204800},
    {
      'user': {'id': 4, 'username': 'undated'},
    },
  ],
};

void main() {
  group('room snapshots', () {
    test('parse the complete room snapshot from the pinned contract', () {
      final room = VoiceRoom.fromJson(fixture('room'));

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
          type: VoiceRoomType.stage,
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
          maxQualityProfile: VoiceQualityProfile.high,
        ),
      );
      expect(
        (
          chatAvailable: room.chatAvailable,
          chatChannelId: room.chatChannelId,
          chatIdleMinutes: room.chatIdleMinutes,
          livekitEnabled: room.livekitEnabled,
          canInvite: room.canInvite,
          expectedTransport: room.expectedTransport,
          descriptionExcerpt: room.descriptionExcerpt,
        ),
        (
          chatAvailable: true,
          chatChannelId: 42,
          chatIdleMinutes: 15,
          livekitEnabled: true,
          canInvite: true,
          expectedTransport: VoiceTransport.livekit,
          descriptionExcerpt: 'Daily engineering room',
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
            id: 2,
            username: 'lee',
            name: null,
            avatarTemplate: null,
            role: VoiceRole.participant,
            muted: true,
            deafened: false,
            videoOn: false,
            screenSharing: false,
            watchingVideo: false,
            idleState: VoiceIdleState.active,
            handRaisedAt: DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
          ),
          (
            id: 1,
            username: 'sam',
            name: 'Sam Example',
            avatarTemplate: '/user_avatar/example.com/sam/{size}/1_2.png',
            role: VoiceRole.moderator,
            muted: false,
            deafened: false,
            videoOn: true,
            screenSharing: false,
            watchingVideo: true,
            idleState: VoiceIdleState.active,
            handRaisedAt: null,
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
          role: VoiceRole.moderator,
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

  group('call room ringing', () {
    VoiceRoom callRoom({bool ephemeral = true}) =>
        VoiceRoom.fromJson({..._callRoomJson, 'ephemeral': ephemeral});

    test('keeps rung users that are absent and still within the window', () {
      final room = callRoom();
      final notifiedAt = DateTime.utc(2026, 8, 8, 16);

      expect(room.ringing.map((entry) => entry.user.id), [3, 1]);
      expect(
        room
            .activeRingingAt(notifiedAt.add(const Duration(seconds: 59)))
            .map((entry) => entry.user.username),
        ['kim'],
      );
      expect(
        room.activeRingingAt(notifiedAt.add(const Duration(seconds: 60))),
        isEmpty,
      );
    });

    test('never reports ringing for a persistent room', () {
      final room = callRoom(ephemeral: false);

      expect(room.activeRingingAt(DateTime.utc(2026, 8, 8, 16)), isEmpty);
    });

    test('a repeat ring replaces the earlier entry for the same user', () {
      final room = callRoom().withRinging(
        VoiceRingingEntry(
          user: const VoiceParticipant(
            id: 3,
            username: 'kim',
            role: VoiceRole.participant,
          ),
          notifiedAt: DateTime.utc(2026, 8, 8, 16, 5),
        ),
      );

      expect(room.ringing.map((entry) => (entry.user.id, entry.notifiedAt)), [
        (1, DateTime.utc(2026, 8, 8, 16)),
        (3, DateTime.utc(2026, 8, 8, 16, 5)),
      ]);
    });
  });

  group('participant ordering', () {
    test('normalizes rosters to username then id regardless of wire order', () {
      final participants = canonicalVoiceParticipants(const [
        VoiceParticipant(id: 9, username: 'Zed', role: VoiceRole.participant),
        VoiceParticipant(id: 5, username: 'amy', role: VoiceRole.participant),
        VoiceParticipant(id: 3, username: 'amy', role: VoiceRole.participant),
        VoiceParticipant(id: 7, username: 'Bob', role: VoiceRole.participant),
      ]);

      expect(participants.map((participant) => participant.id), [3, 5, 7, 9]);
      expect(
        () => participants.add(participants.first),
        throwsUnsupportedError,
      );
    });
  });

  group('directory snapshots', () {
    test('parse directory capabilities and message-bus cursors', () {
      final directory = VoiceDirectory.fromJson(fixture('directory'));

      expect(directory.canCreateRoom, isTrue);
      expect(directory.messageBusLastId, 144);
      expect(directory.rooms.single.messageBusLastId, 91);
    });

    test('keep valid rooms while defaulting malformed optional fields', () {
      final directory = VoiceDirectory.fromJson(fixture('malformed'));

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
      final mesh = VoiceJoinResponse.fromJson(fixture('join_mesh'));

      expect(mesh.transport, VoiceTransport.mesh);
      expect(mesh.ice.relayOnly, isTrue);
      expect(mesh.ice.servers, hasLength(2));
      expect(mesh.ice.servers.last.urls, [
        'turn:turn.example.com:3478?transport=udp',
      ]);
    });

    test('parse the pinned LiveKit transport', () {
      final livekit = VoiceJoinResponse.fromJson(fixture('join_livekit'));

      expect(livekit.transport, VoiceTransport.livekit);
      expect(livekit.livekit?.url, 'wss://livekit.example.com');
    });

    test('fail a join safely when the transport is unknown', () {
      final payload = fixture('join_mesh')..['transport'] = 'future-sfu';

      expect(
        () => VoiceJoinResponse.fromJson(payload),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('room events', () {
    test(
      'ignore unknown events and parse stage, recording, and ringing events',
      () {
        final events = fixtureList(
          'events',
        ).map(VoiceRoomEvent.fromJson).toList();

        final participants = events[0] as VoiceParticipantsEvent;
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
              id: 2,
              username: 'lee',
              role: VoiceRole.participant,
              handRaisedAt: DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
            ),
            (
              id: 1,
              username: 'sam',
              role: VoiceRole.moderator,
              handRaisedAt: null,
            ),
          ],
        );
        expect(events[1], isA<VoiceKickedEvent>());
        final roleChanged = events[2] as VoiceRoleChangedEvent;
        expect(
          (userId: roleChanged.userId, role: roleChanged.role),
          (userId: 2, role: VoiceRole.speaker),
        );
        final handRaise = events[3] as VoiceHandRaiseEvent;
        expect(
          (
            userId: handRaise.userId,
            raised: handRaise.raised,
            raisedAt: handRaise.raisedAt,
            reason: handRaise.reason,
          ),
          (
            userId: 2,
            raised: false,
            raisedAt: DateTime.utc(2026, 8, 8, 16, 0, 1, 500),
            reason: 'dismissed',
          ),
        );
        final recording = (events[4] as VoiceRecordingEvent).recording;
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
        expect((events[5] as VoiceRecordingEvent).recording, isNull);
        final ringing = (events[6] as VoiceRingingEvent).entry;
        expect(
          (
            userId: ringing.user.id,
            username: ringing.user.username,
            notifiedAt: ringing.notifiedAt,
          ),
          (
            userId: 3,
            username: 'kim',
            notifiedAt: DateTime.utc(2026, 8, 8, 16, 0, 10),
          ),
        );
        expect(events[7], isNull);
      },
    );
  });

  group('chat and membership snapshots', () {
    test('parse the associated chat identifiers', () {
      final chat = VoiceChatSession.fromJson(fixture('chat'));

      expect((chat.channelId, chat.threadId), (42, 99));
    });

    test('parse membership identities, roles, and users', () {
      final memberships = [
        for (final value in fixture('memberships')['memberships'] as List)
          VoiceMembership.fromJson(value as Map<String, dynamic>),
      ];

      expect(memberships.map((value) => value.id), [8, 9]);
      expect(memberships.map((value) => value.userId), [1, 2]);
      expect(memberships.map((value) => value.role), const [
        VoiceRole.moderator,
        VoiceRole.speaker,
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
        VoiceParticipant.fromJson(
          participant('2026-08-12T12:34:56Z'),
        ).handRaisedAt,
        DateTime.utc(2026, 8, 12, 12, 34, 56),
      );
      expect(
        VoiceParticipant.fromJson(participant('2' * 200000)).handRaisedAt,
        isNull,
      );
      expect(
        VoiceParticipant.fromJson(participant(double.nan)).handRaisedAt,
        isNull,
      );
      expect(
        VoiceParticipant.fromJson(participant(double.infinity)).handRaisedAt,
        isNull,
      );
    });
  });

  group('room drafts', () {
    test('serialize the complete server contract', () {
      const draft = VoiceRoomDraft(
        name: 'Open room',
        isPublic: true,
        type: VoiceRoomType.open,
        maxQualityProfile: VoiceQualityProfile.maximum,
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
        'livekit_enabled': null,
        'max_quality_profile': 'maximum',
      });
    });
  });
}
