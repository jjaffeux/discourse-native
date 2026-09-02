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

@immutable
class VoiceRecording {
  const VoiceRecording({
    required this.active,
    this.startedAt,
    this.startedById,
  });

  factory VoiceRecording.fromJson(Map<String, dynamic> json) => VoiceRecording(
    // Voice only serializes this object while recording is active. A
    // stopped recording is represented by a null `recording` value.
    active: json['active'] != false,
    startedAt: _voiceDate(json['started_at']),
    startedById:
        jsonIntOrNull(json['started_by_id']) ??
        jsonIntOrNull(jsonObject(json['started_by'])['id']),
  );

  final bool active;
  final DateTime? startedAt;
  final int? startedById;
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
  });

  factory VoiceRoom.fromJson(Map<String, dynamic> json) => VoiceRoom(
    id: jsonInt(json['id']),
    name: jsonText(json['name']) ?? 'Voice room',
    slug: jsonText(json['slug']) ?? '',
    description: jsonText(json['description']),
    cookedDescription: jsonText(json['cooked_description']),
    isPublic: json['public'] == true,
    ephemeral: json['ephemeral'] == true,
    type: VoiceRoomType.parse(json['room_type']),
    maxParticipants: jsonIntOrNull(json['max_participants']),
    memberCount: jsonInt(json['member_count']),
    messageBusLastId: jsonIntOrNull(json['message_bus_last_id']),
    participants: List.unmodifiable([
      for (final entry in jsonObjects(json['active_participants']))
        VoiceParticipant.fromJson(entry),
    ]),
    creatorId: jsonIntOrNull(json['creator_id']),
    canManage: json['can_manage'] == true,
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
  );

  VoiceRoom withParticipants(List<VoiceParticipant> value) =>
      copyWith(participants: List.unmodifiable(value));

  VoiceRoom withRecording(VoiceRecording? value) =>
      copyWith(recording: value, clearRecording: value == null);
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
          List.unmodifiable([
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
          reason: jsonText(json['reason']),
        ),
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
    this.reason,
  });
  final int userId;
  final bool raised;
  final String? reason;
}

final class VoiceRecordingEvent extends VoiceRoomEvent {
  const VoiceRecordingEvent({required this.recording});
  final VoiceRecording? recording;
}
