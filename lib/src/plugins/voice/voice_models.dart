import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

enum VoiceRoomType {
  open,
  stage;

  static VoiceRoomType parse(Object? value) => switch (value) {
    'stage' => VoiceRoomType.stage,
    _ => VoiceRoomType.open,
  };

  String get wireName => this == VoiceRoomType.stage ? 'stage' : 'open';
}

enum VoiceRole {
  participant,
  speaker,
  moderator;

  static VoiceRole parse(Object? value) => switch (value) {
    'speaker' => VoiceRole.speaker,
    'moderator' => VoiceRole.moderator,
    _ => VoiceRole.participant,
  };

  String get wireName => name;
}

enum VoiceQualityProfile {
  standard,
  high,
  maximum;

  static VoiceQualityProfile parse(Object? value) => switch (value) {
    'standard' => VoiceQualityProfile.standard,
    'high' => VoiceQualityProfile.high,
    'maximum' => VoiceQualityProfile.maximum,
    _ => VoiceQualityProfile.maximum,
  };

  String get wireName => name;
}

enum VoiceTransport {
  mesh,
  livekit;

  static VoiceTransport? parse(Object? value) => switch (value) {
    'mesh' => VoiceTransport.mesh,
    'livekit' => VoiceTransport.livekit,
    _ => null,
  };
}

enum VoiceIdleState {
  active,
  idle,
  afk;

  String get wireName => name;
}

@immutable
class VoiceParticipant {
  const VoiceParticipant({
    required this.id,
    required this.username,
    required this.role,
    this.name,
    this.avatarTemplate,
    this.muted = false,
    this.deafened = false,
    this.videoOn = false,
    this.screenSharing = false,
    this.watchingVideo = false,
    this.idleState = VoiceIdleState.active,
    this.handRaisedAt,
  });

  factory VoiceParticipant.fromJson(Map<String, dynamic> json) {
    final idle = jsonText(json['idle_state']);
    return VoiceParticipant(
      id: jsonInt(json['id']),
      username: jsonText(json['username']) ?? '',
      name: jsonText(json['name']),
      avatarTemplate: jsonText(json['avatar_template']),
      role: VoiceRole.parse(json['role']),
      muted: json['is_muted'] == true,
      deafened: json['is_deafened'] == true,
      videoOn: json['is_video_on'] == true,
      screenSharing: json['is_screen_sharing'] == true,
      watchingVideo: json['watching_video'] == true,
      idleState: switch (idle) {
        'idle' => VoiceIdleState.idle,
        'afk' => VoiceIdleState.afk,
        _ => VoiceIdleState.active,
      },
      handRaisedAt: _voiceDate(json['hand_raised_at']),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final VoiceRole role;
  final bool muted;
  final bool deafened;
  final bool videoOn;
  final bool screenSharing;
  final bool watchingVideo;
  final VoiceIdleState idleState;
  final DateTime? handRaisedAt;

  String avatarUrl(String siteUrl, {int size = 96}) {
    final template = avatarTemplate;
    if (template == null) return '';
    final path = template.replaceAll('{size}', '$size');
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('//')) return 'https:$path';
    return '$siteUrl${path.startsWith('/') ? '' : '/'}$path';
  }
}

@immutable
class VoiceMembership {
  const VoiceMembership({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    this.user,
  });

  factory VoiceMembership.fromJson(Map<String, dynamic> json) {
    final user = jsonObject(json['user']);
    return VoiceMembership(
      id: jsonInt(json['id']),
      roomId: jsonInt(json['room_id']),
      userId: jsonInt(json['user_id']),
      role: VoiceRole.parse(json['role_name'] ?? json['role']),
      user: user.isEmpty ? null : VoiceParticipant.fromJson(user),
    );
  }

  final int id;
  final int roomId;
  final int userId;
  final VoiceRole role;
  final VoiceParticipant? user;
}

/// How long a direct call rings before giving up. Mirrors the server's
/// `Voice::RoomInviter::RING_SECONDS`; ring payloads carry their own
/// `ring_seconds`, so this is the fallback and the cap for local timers.
const voiceRingDuration = Duration(seconds: 60);

/// Someone an ephemeral call room is still reaching out to: rung, and stamped
/// with when the ring went out so a client can stop showing them once it has
/// run out.
@immutable
class VoiceRingingEntry {
  const VoiceRingingEntry({required this.user, required this.notifiedAt});

  static VoiceRingingEntry? fromJson(Map<String, dynamic> json) {
    final user = jsonObject(json['user']);
    final notifiedAt = _voiceDate(json['notified_at']);
    if (user.isEmpty || notifiedAt == null) return null;
    final participant = VoiceParticipant.fromJson(user);
    if (participant.id <= 0) return null;
    return VoiceRingingEntry(user: participant, notifiedAt: notifiedAt);
  }

  final VoiceParticipant user;
  final DateTime notifiedAt;

  DateTime get expiresAt => notifiedAt.add(voiceRingDuration);

  bool isActiveAt(DateTime now) => now.isBefore(expiresAt);
}

/// A direct call ringing this user, as published on the per-user ring
/// channel when someone invites them into an ephemeral call room. Carries
/// its own window so a ring replayed from a message-bus backlog can be
/// discarded once it has run out.
@immutable
class VoiceIncomingCall {
  const VoiceIncomingCall({
    required this.roomId,
    required this.roomSlug,
    required this.roomName,
    required this.caller,
    required this.sentAt,
    this.ringDuration = voiceRingDuration,
  });

  static VoiceIncomingCall? fromJson(Map<String, dynamic> json) {
    final roomId = jsonIntOrNull(json['room_id']);
    final roomSlug = jsonText(json['room_slug']);
    final callerUsername = jsonText(json['caller_username']);
    final sentAt = _voiceDate(json['sent_at']);
    if (roomId == null ||
        roomId <= 0 ||
        roomSlug == null ||
        callerUsername == null ||
        sentAt == null) {
      return null;
    }
    final ringSeconds = jsonIntOrNull(json['ring_seconds']);
    return VoiceIncomingCall(
      roomId: roomId,
      roomSlug: roomSlug,
      roomName: jsonText(json['room_name']) ?? 'Voice call',
      caller: VoiceParticipant(
        id: jsonInt(json['caller_id']),
        username: callerUsername,
        name: jsonText(json['caller_name']),
        avatarTemplate: jsonText(json['caller_avatar_template']),
        role: VoiceRole.participant,
      ),
      sentAt: sentAt,
      ringDuration: ringSeconds == null || ringSeconds <= 0
          ? voiceRingDuration
          : Duration(seconds: ringSeconds),
    );
  }

  final int roomId;
  final String roomSlug;
  final String roomName;
  final VoiceParticipant caller;
  final DateTime sentAt;
  final Duration ringDuration;

  DateTime get expiresAt => sentAt.add(ringDuration);

  Duration remainingAt(DateTime now) => expiresAt.difference(now);

  /// Identifies one ring across replays: the same invite re-published from
  /// a backlog carries the same stamp.
  String get key =>
      '$roomId-${caller.username}-${sentAt.millisecondsSinceEpoch}';
}

@immutable
class VoiceRecording {
  const VoiceRecording({
    required this.active,
    this.startedAt,
    this.startedById,
    this.startedByUsername,
  });

  factory VoiceRecording.fromJson(Map<String, dynamic> json) => VoiceRecording(
    // Voice only serializes this object while recording is active. A
    // stopped recording is represented by a null `recording` value.
    active: json['active'] != false,
    startedAt: _voiceDate(json['started_at']),
    startedById:
        jsonIntOrNull(json['started_by_id']) ??
        jsonIntOrNull(jsonObject(json['started_by'])['id']),
    startedByUsername: jsonText(jsonObject(json['started_by'])['username']),
  );

  final bool active;
  final DateTime? startedAt;
  final int? startedById;
  final String? startedByUsername;
}

@immutable
class VoiceRoom {
  const VoiceRoom({
    required this.id,
    required this.name,
    required this.slug,
    required this.isPublic,
    required this.ephemeral,
    required this.type,
    required this.participants,
    this.description,
    this.cookedDescription,
    this.maxParticipants,
    this.memberCount = 0,
    this.messageBusLastId,
    this.creatorId,
    this.canManage = false,
    this.videoEnabled = false,
    this.videoAllowed = false,
    this.chatAvailable = false,
    this.chatChannelId,
    this.chatIdleMinutes,
    this.livekitEnabled,
    this.maxQualityProfile = VoiceQualityProfile.maximum,
    this.membership,
    this.recording,
    this.descriptionExcerpt,
    this.canInvite = false,
    this.expectedTransport,
    this.ringing = const [],
  });

  factory VoiceRoom.fromJson(Map<String, dynamic> json) => VoiceRoom(
    id: jsonInt(json['id']),
    name: jsonText(json['name']) ?? 'Voice room',
    slug: jsonText(json['slug']) ?? '',
    description: jsonText(json['description']),
    cookedDescription: jsonText(json['cooked_description']),
    descriptionExcerpt: jsonText(json['description_excerpt']),
    isPublic: json['public'] == true,
    ephemeral: json['ephemeral'] == true,
    type: VoiceRoomType.parse(json['room_type']),
    maxParticipants: jsonIntOrNull(json['max_participants']),
    memberCount: jsonInt(json['member_count']),
    messageBusLastId: jsonIntOrNull(json['message_bus_last_id']),
    participants: canonicalVoiceParticipants([
      for (final entry in jsonObjects(json['active_participants']))
        VoiceParticipant.fromJson(entry),
    ]),
    creatorId: jsonIntOrNull(json['creator_id']),
    canManage: json['can_manage'] == true,
    canInvite: json['can_invite'] == true,
    expectedTransport: VoiceTransport.parse(json['expected_transport']),
    ringing: List.unmodifiable([
      for (final entry in jsonObjects(json['ringing']))
        ?VoiceRingingEntry.fromJson(entry),
    ]),
    videoEnabled: json['video_enabled'] == true,
    videoAllowed: json['video_allowed'] == true,
    chatAvailable: json['chat_available'] == true,
    chatChannelId: jsonIntOrNull(json['chat_channel_id']),
    chatIdleMinutes: jsonIntOrNull(json['chat_idle_minutes']),
    livekitEnabled: json.containsKey('livekit_enabled')
        ? json['livekit_enabled'] == true
        : null,
    maxQualityProfile: VoiceQualityProfile.parse(json['max_quality_profile']),
    membership: jsonObject(json['membership']).isEmpty
        ? null
        : VoiceMembership.fromJson(jsonObject(json['membership'])),
    recording: jsonObject(json['recording']).isEmpty
        ? null
        : VoiceRecording.fromJson(jsonObject(json['recording'])),
  );

  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? cookedDescription;
  final bool isPublic;
  final bool ephemeral;
  final VoiceRoomType type;
  final int? maxParticipants;
  final int memberCount;
  final int? messageBusLastId;
  final List<VoiceParticipant> participants;
  final int? creatorId;
  final bool canManage;
  final bool videoEnabled;
  final bool videoAllowed;
  final bool chatAvailable;
  final int? chatChannelId;
  final int? chatIdleMinutes;
  final bool? livekitEnabled;
  final VoiceQualityProfile maxQualityProfile;
  final VoiceMembership? membership;
  final VoiceRecording? recording;
  final String? descriptionExcerpt;
  final bool canInvite;

  /// The server's best guess at the transport a join would resolve to right
  /// now; the pin set at join stays authoritative. Only used to warn about a
  /// peer-to-peer room's IP exposure before joining.
  final VoiceTransport? expectedTransport;

  /// Only ephemeral call rooms carry this. Entries are never pruned here: the
  /// display filters out people already present and rings that have run out.
  final List<VoiceRingingEntry> ringing;

  /// People this call is still reaching out to at [now]: rung, not present,
  /// and within the ring window.
  List<VoiceRingingEntry> activeRingingAt(DateTime now) {
    if (!ephemeral || ringing.isEmpty) return const [];
    final present = {for (final participant in participants) participant.id};
    return List.unmodifiable([
      for (final entry in ringing)
        if (!present.contains(entry.user.id) && entry.isActiveAt(now)) entry,
    ]);
  }

  VoiceRoom copyWith({
    int? messageBusLastId,
    List<VoiceParticipant>? participants,
    bool? canManage,
    bool? chatAvailable,
    int? chatChannelId,
    int? chatIdleMinutes,
    bool? livekitEnabled,
    VoiceMembership? membership,
    VoiceRecording? recording,
    bool clearRecording = false,
    List<VoiceRingingEntry>? ringing,
  }) => VoiceRoom(
    id: id,
    name: name,
    slug: slug,
    description: description,
    cookedDescription: cookedDescription,
    isPublic: isPublic,
    ephemeral: ephemeral,
    type: type,
    maxParticipants: maxParticipants,
    memberCount: memberCount,
    messageBusLastId: messageBusLastId ?? this.messageBusLastId,
    participants: participants ?? this.participants,
    creatorId: creatorId,
    canManage: canManage ?? this.canManage,
    videoEnabled: videoEnabled,
    videoAllowed: videoAllowed,
    chatAvailable: chatAvailable ?? this.chatAvailable,
    chatChannelId: chatChannelId ?? this.chatChannelId,
    chatIdleMinutes: chatIdleMinutes ?? this.chatIdleMinutes,
    livekitEnabled: livekitEnabled ?? this.livekitEnabled,
    maxQualityProfile: maxQualityProfile,
    membership: membership ?? this.membership,
    recording: clearRecording ? null : (recording ?? this.recording),
    descriptionExcerpt: descriptionExcerpt,
    canInvite: canInvite,
    expectedTransport: expectedTransport,
    ringing: ringing ?? this.ringing,
  );

  VoiceRoom withParticipants(List<VoiceParticipant> value) =>
      copyWith(participants: canonicalVoiceParticipants(value));

  VoiceRoom withRecording(VoiceRecording? value) =>
      copyWith(recording: value, clearRecording: value == null);

  /// Records that someone started ringing [entry]'s user. A repeat ring for
  /// the same user replaces their entry, restarting the ring window.
  VoiceRoom withRinging(VoiceRingingEntry entry) => copyWith(
    ringing: List.unmodifiable([
      for (final held in ringing)
        if (held.user.id != entry.user.id) held,
      entry,
    ]),
  );
}

/// Participant broadcasts arrive in arbitrary database order, so every list
/// that reaches the UI is normalized to one canonical order — otherwise
/// sidebar rows and tiles reshuffle on each broadcast. Mirrors the web
/// client's `sortParticipants`: username, then id.
List<VoiceParticipant> canonicalVoiceParticipants(
  Iterable<VoiceParticipant> participants,
) {
  final sorted = participants.toList()
    ..sort((a, b) {
      final byName = a.username.toLowerCase().compareTo(
        b.username.toLowerCase(),
      );
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
  return List.unmodifiable(sorted);
}

@immutable
class VoiceDirectory {
  const VoiceDirectory({
    required this.rooms,
    required this.canCreateRoom,
    this.messageBusLastId,
  });

  factory VoiceDirectory.fromJson(Map<String, dynamic> json) => VoiceDirectory(
    rooms: List.unmodifiable([
      for (final room in jsonObjects(json['rooms'])) VoiceRoom.fromJson(room),
    ]),
    canCreateRoom: json['can_create_room'] == true,
    messageBusLastId: jsonIntOrNull(json['index_message_bus_last_id']),
  );

  final List<VoiceRoom> rooms;
  final bool canCreateRoom;
  final int? messageBusLastId;
}

@immutable
class VoiceIceServer {
  const VoiceIceServer({required this.urls, this.username, this.credential});

  factory VoiceIceServer.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['urls'];
    return VoiceIceServer(
      urls: List.unmodifiable(
        rawUrls is List
            ? rawUrls.whereType<String>()
            : rawUrls is String
            ? [rawUrls]
            : const <String>[],
      ),
      username: jsonText(json['username']),
      credential: jsonText(json['credential']),
    );
  }

  final List<String> urls;
  final String? username;
  final String? credential;
}

@immutable
class VoiceIceConfiguration {
  const VoiceIceConfiguration({required this.servers, required this.relayOnly});

  factory VoiceIceConfiguration.fromJson(Map<String, dynamic> json) =>
      VoiceIceConfiguration(
        servers: List.unmodifiable([
          for (final server in jsonObjects(json['servers']))
            VoiceIceServer.fromJson(server),
        ]),
        relayOnly: json['transport_policy'] == 'relay',
      );

  final List<VoiceIceServer> servers;
  final bool relayOnly;
}

@immutable
class VoiceLiveKitCredentials {
  const VoiceLiveKitCredentials({
    required this.url,
    required this.token,
    this.participantSessionId,
  });

  factory VoiceLiveKitCredentials.fromJson(Map<String, dynamic> json) =>
      VoiceLiveKitCredentials(
        url: jsonText(json['url']) ?? '',
        token: jsonText(json['token']) ?? '',
        participantSessionId: jsonText(json['participant_session_id']),
      );

  final String url;
  final String token;
  final String? participantSessionId;
}

@immutable
class VoiceJoinResponse {
  const VoiceJoinResponse({
    required this.transport,
    required this.ice,
    required this.room,
    this.participantSessionId,
    this.livekit,
  });

  factory VoiceJoinResponse.fromJson(Map<String, dynamic> json) {
    final transport = VoiceTransport.parse(json['transport']);
    if (transport == null) {
      throw const FormatException('Unsupported Voice transport');
    }
    final roomJson = jsonObject(json['room']);
    if (roomJson.isEmpty) throw const FormatException('Missing Voice room');
    final livekitJson = jsonObject(json['livekit']);
    return VoiceJoinResponse(
      transport: transport,
      ice: VoiceIceConfiguration.fromJson(jsonObject(json['ice'])),
      room: VoiceRoom.fromJson(roomJson),
      participantSessionId: jsonText(json['participant_session_id']),
      livekit: livekitJson.isEmpty
          ? null
          : VoiceLiveKitCredentials.fromJson(livekitJson),
    );
  }

  final VoiceTransport transport;
  final VoiceIceConfiguration ice;
  final VoiceRoom room;
  final String? participantSessionId;
  final VoiceLiveKitCredentials? livekit;
}

@immutable
class VoiceChatSession {
  const VoiceChatSession({this.channelId, this.threadId});

  factory VoiceChatSession.fromJson(Map<String, dynamic> json) =>
      VoiceChatSession(
        channelId: jsonIntOrNull(json['channel_id']),
        threadId: jsonIntOrNull(json['thread_id']),
      );

  final int? channelId;
  final int? threadId;
}

@immutable
class VoiceRoomDraft {
  const VoiceRoomDraft({
    required this.name,
    required this.isPublic,
    required this.type,
    this.description,
    this.maxParticipants,
    this.videoEnabled = false,
    this.chatChannelId,
    this.chatIdleMinutes,
    this.livekitEnabled,
    this.maxQualityProfile,
  });

  final String name;
  final String? description;
  final bool isPublic;
  final VoiceRoomType type;
  final int? maxParticipants;
  final bool videoEnabled;
  final int? chatChannelId;
  final int? chatIdleMinutes;
  final bool? livekitEnabled;
  final VoiceQualityProfile? maxQualityProfile;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'public': isPublic,
    'room_type': type.wireName,
    'max_participants': maxParticipants,
    'video_enabled': videoEnabled,
    'chat_channel_id': chatChannelId,
    'chat_idle_minutes': chatIdleMinutes,
    'livekit_enabled': livekitEnabled,
    'max_quality_profile': maxQualityProfile?.wireName,
  };
}

DateTime? _voiceDate(Object? value) => switch (value) {
  final num seconds when seconds.isFinite =>
    DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true),
  _ => jsonDate(value),
};

sealed class VoiceRoomEvent {
  const VoiceRoomEvent();

  static VoiceRoomEvent? fromJson(Map<String, dynamic> json) =>
      switch (jsonText(json['type'])) {
        'participants' => VoiceParticipantsEvent(
          canonicalVoiceParticipants([
            for (final participant in jsonObjects(json['participants']))
              VoiceParticipant.fromJson(participant),
          ]),
        ),
        'kicked' => const VoiceKickedEvent(),
        'role_change' => VoiceRoleChangedEvent(
          userId: jsonInt(json['user_id']),
          role: VoiceRole.parse(json['role']),
        ),
        'hand_raise' => VoiceHandRaiseEvent(
          userId: jsonInt(json['user_id']),
          raised: json['raised'] == true,
          raisedAt: _voiceDate(json['raised_at']),
          reason: jsonText(json['reason']),
        ),
        'ringing' => switch (VoiceRingingEntry.fromJson(json)) {
          final entry? => VoiceRingingEvent(entry),
          null => null,
        },
        'recording' => VoiceRecordingEvent(
          recording: jsonObject(json['recording']).isEmpty
              ? null
              : VoiceRecording.fromJson(jsonObject(json['recording'])),
        ),
        _ => null,
      };
}

final class VoiceParticipantsEvent extends VoiceRoomEvent {
  const VoiceParticipantsEvent(this.participants);
  final List<VoiceParticipant> participants;
}

final class VoiceKickedEvent extends VoiceRoomEvent {
  const VoiceKickedEvent();
}

final class VoiceRoleChangedEvent extends VoiceRoomEvent {
  const VoiceRoleChangedEvent({required this.userId, required this.role});
  final int userId;
  final VoiceRole role;
}

final class VoiceHandRaiseEvent extends VoiceRoomEvent {
  const VoiceHandRaiseEvent({
    required this.userId,
    required this.raised,
    this.raisedAt,
    this.reason,
  });
  final int userId;
  final bool raised;

  /// Queue position is first-come: the server stamps a raise with when it was
  /// first recorded, so a client can order the queue without a roster.
  final DateTime? raisedAt;

  /// `raised`, `withdrawn` (own hand lowered) or `dismissed` (by a manager).
  final String? reason;
}

/// Someone in an ephemeral call room started ringing a user.
final class VoiceRingingEvent extends VoiceRoomEvent {
  const VoiceRingingEvent(this.entry);
  final VoiceRingingEntry entry;
}

final class VoiceRecordingEvent extends VoiceRoomEvent {
  const VoiceRecordingEvent({required this.recording});
  final VoiceRecording? recording;
}
