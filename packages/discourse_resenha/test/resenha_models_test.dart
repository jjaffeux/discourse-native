import 'dart:convert';
import 'dart:io';

import 'package:discourse_resenha/src/resenha_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/resenha/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('Resenha protocol models', () {
    test('parses the complete room snapshot from the pinned contract', () {
      final room = ResenhaRoom.fromJson(fixture('room'));

      expect(room.id, 7);
      expect(room.type, ResenhaRoomType.stage);
      expect(room.maxQualityProfile, ResenhaQualityProfile.high);
      expect(room.membership?.role, ResenhaRole.moderator);
      expect(room.participants, hasLength(2));
      expect(room.participants.last.handRaisedAt, isNotNull);
      expect(room.recording?.active, isTrue);
      expect(room.recording?.startedById, 1);
      expect(room.recording?.startedAt?.isUtc, isTrue);
    });

    test('parses directory and both pinned transports', () {
      final directory = ResenhaDirectory.fromJson(fixture('directory'));
      final mesh = ResenhaJoinResponse.fromJson(fixture('join_mesh'));
      final livekit = ResenhaJoinResponse.fromJson(fixture('join_livekit'));

      expect(directory.canCreateRoom, isTrue);
      expect(directory.messageBusLastId, 144);
      expect(directory.rooms.single.messageBusLastId, 91);
      expect(mesh.transport, ResenhaTransport.mesh);
      expect(mesh.ice.relayOnly, isTrue);
      expect(mesh.ice.servers, hasLength(2));
      expect(mesh.ice.servers.last.urls, [
        'turn:turn.example.com:3478?transport=udp',
      ]);
      expect(livekit.transport, ResenhaTransport.livekit);
      expect(livekit.livekit?.url, 'wss://livekit.example.com');
    });

    test('fails a join safely when the transport is unknown', () {
      final payload = fixture('join_mesh')..['transport'] = 'future-sfu';

      expect(
        () => ResenhaJoinResponse.fromJson(payload),
        throwsA(isA<FormatException>()),
      );
    });

    test('ignores unknown events and parses stage and recording events', () {
      final events =
          (jsonDecode(
                    File(
                      'test/fixtures/resenha/events.json',
                    ).readAsStringSync(),
                  )
                  as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map(ResenhaRoomEvent.fromJson)
              .toList();

      expect(events[0], isA<ResenhaParticipantsEvent>());
      expect(events[1], isA<ResenhaKickedEvent>());
      expect(events[2], isA<ResenhaRoleChangedEvent>());
      expect(events[3], isA<ResenhaHandRaiseEvent>());
      expect((events[4] as ResenhaRecordingEvent).recording?.active, isTrue);
      expect((events[5] as ResenhaRecordingEvent).recording, isNull);
      expect(events[6], isNull);
    });

    test('parses chat, membership, and malformed optional payloads', () {
      final chat = ResenhaChatSession.fromJson(fixture('chat'));
      final memberships = [
        for (final value in fixture('memberships')['memberships'] as List)
          ResenhaMembership.fromJson(value as Map<String, dynamic>),
      ];
      final malformed = ResenhaDirectory.fromJson(fixture('malformed'));

      expect((chat.channelId, chat.threadId), (42, 99));
      expect(memberships.map((value) => value.role), [
        ResenhaRole.moderator,
        ResenhaRole.speaker,
      ]);
      expect(malformed.rooms, hasLength(1));
      expect(malformed.rooms.single.id, 7);
      expect(malformed.rooms.single.name, 'Voice room');
      expect(malformed.rooms.single.participants.single.id, 2);
      expect(malformed.canCreateRoom, isFalse);
      expect(malformed.messageBusLastId, isNull);
    });

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

    test('serializes server room type and quality names', () {
      const draft = ResenhaRoomDraft(
        name: 'Open room',
        isPublic: true,
        type: ResenhaRoomType.open,
        maxQualityProfile: ResenhaQualityProfile.maximum,
      );

      expect(draft.toJson()['room_type'], 'open');
      expect(draft.toJson()['max_quality_profile'], 'maximum');
    });
  });
}
