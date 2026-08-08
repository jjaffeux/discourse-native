import 'package:discourse_native/src/plugins/resenha/resenha_media.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_models.dart';
import 'package:flutter_test/flutter_test.dart';

ResenhaJoinResponse join({
  required ResenhaRoomType roomType,
  required ResenhaRole role,
}) => ResenhaJoinResponse(
  transport: ResenhaTransport.mesh,
  ice: const ResenhaIceConfiguration(servers: [], relayOnly: false),
  room: ResenhaRoom(
    id: 1,
    name: 'Room',
    slug: 'room',
    isPublic: true,
    ephemeral: false,
    type: roomType,
    participants: [ResenhaParticipant(id: 10, username: 'sam', role: role)],
  ),
);

void main() {
  test('stage listeners do not acquire an outgoing audio publication', () {
    final media = const NativeResenhaMediaFactory().create(
      join: join(
        roomType: ResenhaRoomType.stage,
        role: ResenhaRole.participant,
      ),
      localUserId: 10,
      sendSignal: (_, _) async {},
      refreshLiveKitCredentials: () async =>
          const ResenhaLiveKitCredentials(url: '', token: ''),
    );

    expect((media as MeshResenhaMediaSession).audioPublishingAllowed, isFalse);
  });

  test('stage speakers and open-room participants may publish audio', () {
    for (final response in [
      join(roomType: ResenhaRoomType.stage, role: ResenhaRole.speaker),
      join(roomType: ResenhaRoomType.open, role: ResenhaRole.participant),
    ]) {
      final media = const NativeResenhaMediaFactory().create(
        join: response,
        localUserId: 10,
        sendSignal: (_, _) async {},
        refreshLiveKitCredentials: () async =>
            const ResenhaLiveKitCredentials(url: '', token: ''),
      );

      expect((media as MeshResenhaMediaSession).audioPublishingAllowed, isTrue);
    }
  });
}
