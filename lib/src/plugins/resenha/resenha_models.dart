import 'package:flutter/foundation.dart';

import '../../models/json.dart';

enum ResenhaRoomType {
  open,
  stage;

  static ResenhaRoomType parse(Object? value) => switch (value) {
    'stage' => ResenhaRoomType.stage,
    _ => ResenhaRoomType.open,
  };

  String get wireName => this == ResenhaRoomType.stage ? 'stage' : 'open';
}

enum ResenhaRole {
  participant,
  speaker,
  moderator;

  static ResenhaRole parse(Object? value) => switch (value) {
    'speaker' => ResenhaRole.speaker,
    'moderator' => ResenhaRole.moderator,
    _ => ResenhaRole.participant,
  };

  String get wireName => name;
}

enum ResenhaQualityProfile {
  standard,
  high,
  maximum;

  static ResenhaQualityProfile parse(Object? value) => switch (value) {
    'standard' => ResenhaQualityProfile.standard,
    'high' => ResenhaQualityProfile.high,
    'maximum' => ResenhaQualityProfile.maximum,
    _ => ResenhaQualityProfile.maximum,
  };

  String get wireName => name;
}

enum ResenhaTransport {
  mesh,
  livekit;

  static ResenhaTransport? parse(Object? value) => switch (value) {
    'mesh' => ResenhaTransport.mesh,
    'livekit' => ResenhaTransport.livekit,
    _ => null,
  };
}

enum ResenhaIdleState {
  active,
  idle,
  afk;

  String get wireName => name;
}

@immutable
class ResenhaParticipant {
  const ResenhaParticipant({
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
    this.idleState = ResenhaIdleState.active,
    this.handRaisedAt,
  });

  factory ResenhaParticipant.fromJson(Map<String, dynamic> json) {
    final idle = jsonText(json['idle_state']);
    return ResenhaParticipant(
      id: jsonInt(json['id']),
      username: jsonText(json['username']) ?? '',
      name: jsonText(json['name']),
      avatarTemplate: jsonText(json['avatar_template']),
      role: ResenhaRole.parse(json['role']),
      muted: json['is_muted'] == true,
      deafened: json['is_deafened'] == true,
      videoOn: json['is_video_on'] == true,
      screenSharing: json['is_screen_sharing'] == true,
      watchingVideo: json['watching_video'] == true,
      idleState: switch (idle) {
        'idle' => ResenhaIdleState.idle,
        'afk' => ResenhaIdleState.afk,
        _ => ResenhaIdleState.active,
      },
      handRaisedAt: _resenhaDate(json['hand_raised_at']),
    );
  }

  final int id;
  final String username;
  final String? name;
  final String? avatarTemplate;
  final ResenhaRole role;
  final bool muted;
  final bool deafened;
  final bool videoOn;
  final bool screenSharing;
  final bool watchingVideo;
  final ResenhaIdleState idleState;
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
class ResenhaMembership {
  const ResenhaMembership({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    this.user,
  });

  factory ResenhaMembership.fromJson(Map<String, dynamic> json) {
    final user = jsonObject(json['user']);
    return ResenhaMembership(
      id: jsonInt(json['id']),
      roomId: jsonInt(json['room_id']),
      userId: jsonInt(json['user_id']),
      role: ResenhaRole.parse(json['role_name'] ?? json['role']),
      user: user.isEmpty ? null : ResenhaParticipant.fromJson(user),
    );
  }

  final int id;
  final int roomId;
  final int userId;
  final ResenhaRole role;
  final ResenhaParticipant? user;
}

@immutable
class ResenhaRecording {
  const ResenhaRecording({
    required this.active,
    this.startedAt,
    this.startedById,
  });

  factory ResenhaRecording.fromJson(Map<String, dynamic> json) =>
      ResenhaRecording(
        // Resenha only serializes this object while recording is active. A
        // stopped recording is represented by a null `recording` value.
        active: json['active'] != false,
        startedAt: _resenhaDate(json['started_at']),
        startedById:
            jsonIntOrNull(json['started_by_id']) ??
            jsonIntOrNull(jsonObject(json['started_by'])['id']),
      );

  final bool active;
  final DateTime? startedAt;
  final int? startedById;
}

@immutable
class ResenhaRoom {
  const ResenhaRoom({
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
    this.chatThreadTitleTemplate,
    this.livekitEnabled,
    this.maxQualityProfile = ResenhaQualityProfile.maximum,
    this.membership,
    this.recording,
  });

  factory ResenhaRoom.fromJson(Map<String, dynamic> json) => ResenhaRoom(
    id: jsonInt(json['id']),
    name: jsonText(json['name']) ?? 'Voice room',
    slug: jsonText(json['slug']) ?? '',
    description: jsonText(json['description']),
    cookedDescription: jsonText(json['cooked_description']),
    isPublic: json['public'] == true,
    ephemeral: json['ephemeral'] == true,
    type: ResenhaRoomType.parse(json['room_type']),
    maxParticipants: jsonIntOrNull(json['max_participants']),
    memberCount: jsonInt(json['member_count']),
    messageBusLastId: jsonIntOrNull(json['message_bus_last_id']),
    participants: List.unmodifiable([
      for (final entry in jsonObjects(json['active_participants']))
        ResenhaParticipant.fromJson(entry),
    ]),
    creatorId: jsonIntOrNull(json['creator_id']),
    canManage: json['can_manage'] == true,
    videoEnabled: json['video_enabled'] == true,
    videoAllowed: json['video_allowed'] == true,
    chatAvailable: json['chat_available'] == true,
    chatChannelId: jsonIntOrNull(json['chat_channel_id']),
    chatIdleMinutes: jsonIntOrNull(json['chat_idle_minutes']),
    chatThreadTitleTemplate: jsonText(json['chat_thread_title_template']),
    livekitEnabled: json.containsKey('livekit_enabled')
        ? json['livekit_enabled'] == true
        : null,
    maxQualityProfile: ResenhaQualityProfile.parse(json['max_quality_profile']),
    membership: jsonObject(json['membership']).isEmpty
        ? null
        : ResenhaMembership.fromJson(jsonObject(json['membership'])),
    recording: jsonObject(json['recording']).isEmpty
        ? null
        : ResenhaRecording.fromJson(jsonObject(json['recording'])),
  );

  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? cookedDescription;
  final bool isPublic;
  final bool ephemeral;
  final ResenhaRoomType type;
  final int? maxParticipants;
  final int memberCount;
  final int? messageBusLastId;
  final List<ResenhaParticipant> participants;
  final int? creatorId;
  final bool canManage;
  final bool videoEnabled;
  final bool videoAllowed;
  final bool chatAvailable;
  final int? chatChannelId;
  final int? chatIdleMinutes;
  final String? chatThreadTitleTemplate;
  final bool? livekitEnabled;
  final ResenhaQualityProfile maxQualityProfile;
  final ResenhaMembership? membership;
  final ResenhaRecording? recording;

  /// The fields anything here replaces, over the twenty-odd it does not.
  ///
  /// Written once. Three callers used to spell the whole record out, so a
  /// field added to [ResenhaRoom] was a field one of them silently dropped.
  /// Nulling follows the shape `DiscourseInstance.copyWith` uses: a null
  /// argument means "unchanged", and the one field anything actually clears
  /// says so with a flag.
  ResenhaRoom copyWith({
    List<ResenhaParticipant>? participants,
    bool? canManage,
    bool? chatAvailable,
    int? chatChannelId,
    int? chatIdleMinutes,
    String? chatThreadTitleTemplate,
    bool? livekitEnabled,
    ResenhaMembership? membership,
    ResenhaRecording? recording,
    bool clearRecording = false,
  }) => ResenhaRoom(
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
    messageBusLastId: messageBusLastId,
    participants: participants ?? this.participants,
    creatorId: creatorId,
    canManage: canManage ?? this.canManage,
    videoEnabled: videoEnabled,
    videoAllowed: videoAllowed,
    chatAvailable: chatAvailable ?? this.chatAvailable,
    chatChannelId: chatChannelId ?? this.chatChannelId,
    chatIdleMinutes: chatIdleMinutes ?? this.chatIdleMinutes,
    chatThreadTitleTemplate:
        chatThreadTitleTemplate ?? this.chatThreadTitleTemplate,
    livekitEnabled: livekitEnabled ?? this.livekitEnabled,
    maxQualityProfile: maxQualityProfile,
    membership: membership ?? this.membership,
    recording: clearRecording ? null : (recording ?? this.recording),
  );

  ResenhaRoom withParticipants(List<ResenhaParticipant> value) =>
      copyWith(participants: List.unmodifiable(value));

  ResenhaRoom withRecording(ResenhaRecording? value) =>
      copyWith(recording: value, clearRecording: value == null);
}

@immutable
class ResenhaDirectory {
  const ResenhaDirectory({
    required this.rooms,
    required this.canCreateRoom,
    this.messageBusLastId,
  });

  factory ResenhaDirectory.fromJson(Map<String, dynamic> json) =>
      ResenhaDirectory(
        rooms: List.unmodifiable([
          for (final room in jsonObjects(json['rooms']))
            ResenhaRoom.fromJson(room),
        ]),
        canCreateRoom: json['can_create_room'] == true,
        messageBusLastId: jsonIntOrNull(json['index_message_bus_last_id']),
      );

  final List<ResenhaRoom> rooms;
  final bool canCreateRoom;
  final int? messageBusLastId;
}

@immutable
class ResenhaIceServer {
  const ResenhaIceServer({required this.urls, this.username, this.credential});

  factory ResenhaIceServer.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['urls'];
    return ResenhaIceServer(
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
class ResenhaIceConfiguration {
  const ResenhaIceConfiguration({
    required this.servers,
    required this.relayOnly,
  });

  factory ResenhaIceConfiguration.fromJson(Map<String, dynamic> json) =>
      ResenhaIceConfiguration(
        servers: List.unmodifiable([
          for (final server in jsonObjects(json['servers']))
            ResenhaIceServer.fromJson(server),
        ]),
        relayOnly: json['transport_policy'] == 'relay',
      );

  final List<ResenhaIceServer> servers;
  final bool relayOnly;
}

@immutable
class ResenhaLiveKitCredentials {
  const ResenhaLiveKitCredentials({
    required this.url,
    required this.token,
    this.participantSessionId,
  });

  factory ResenhaLiveKitCredentials.fromJson(Map<String, dynamic> json) =>
      ResenhaLiveKitCredentials(
        url: jsonText(json['url']) ?? '',
        token: jsonText(json['token']) ?? '',
        participantSessionId: jsonText(json['participant_session_id']),
      );

  final String url;
  final String token;
  final String? participantSessionId;
}

@immutable
class ResenhaJoinResponse {
  const ResenhaJoinResponse({
    required this.transport,
    required this.ice,
    required this.room,
    this.participantSessionId,
    this.livekit,
  });

  factory ResenhaJoinResponse.fromJson(Map<String, dynamic> json) {
    final transport = ResenhaTransport.parse(json['transport']);
    if (transport == null) {
      throw const FormatException('Unsupported Resenha transport');
    }
    final roomJson = jsonObject(json['room']);
    if (roomJson.isEmpty) throw const FormatException('Missing Resenha room');
    final livekitJson = jsonObject(json['livekit']);
    return ResenhaJoinResponse(
      transport: transport,
      ice: ResenhaIceConfiguration.fromJson(jsonObject(json['ice'])),
      room: ResenhaRoom.fromJson(roomJson),
      participantSessionId: jsonText(json['participant_session_id']),
      livekit: livekitJson.isEmpty
          ? null
          : ResenhaLiveKitCredentials.fromJson(livekitJson),
    );
  }

  final ResenhaTransport transport;
  final ResenhaIceConfiguration ice;
  final ResenhaRoom room;
  final String? participantSessionId;
  final ResenhaLiveKitCredentials? livekit;
}

@immutable
class ResenhaChatSession {
  const ResenhaChatSession({this.channelId, this.threadId});

  factory ResenhaChatSession.fromJson(Map<String, dynamic> json) =>
      ResenhaChatSession(
        channelId: jsonIntOrNull(json['channel_id']),
        threadId: jsonIntOrNull(json['thread_id']),
      );

  final int? channelId;
  final int? threadId;
}

@immutable
class ResenhaRoomDraft {
  const ResenhaRoomDraft({
    required this.name,
    required this.isPublic,
    required this.type,
    this.description,
    this.maxParticipants,
    this.videoEnabled = false,
    this.chatChannelId,
    this.chatIdleMinutes,
    this.chatThreadTitleTemplate,
    this.livekitEnabled,
    this.maxQualityProfile,
  });

  final String name;
  final String? description;
  final bool isPublic;
  final ResenhaRoomType type;
  final int? maxParticipants;
  final bool videoEnabled;
  final int? chatChannelId;
  final int? chatIdleMinutes;
  final String? chatThreadTitleTemplate;
  final bool? livekitEnabled;
  final ResenhaQualityProfile? maxQualityProfile;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'public': isPublic,
    'room_type': type.wireName,
    'max_participants': maxParticipants,
    'video_enabled': videoEnabled,
    'chat_channel_id': chatChannelId,
    'chat_idle_minutes': chatIdleMinutes,
    'chat_thread_title_template': chatThreadTitleTemplate,
    'livekit_enabled': livekitEnabled,
    'max_quality_profile': maxQualityProfile?.wireName,
  };
}

DateTime? _resenhaDate(Object? value) => switch (value) {
  final num seconds when seconds.isFinite =>
    DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true),
  _ => jsonDate(value),
};

sealed class ResenhaRoomEvent {
  const ResenhaRoomEvent();

  static ResenhaRoomEvent? fromJson(Map<String, dynamic> json) =>
      switch (jsonText(json['type'])) {
        'participants' => ResenhaParticipantsEvent(
          List.unmodifiable([
            for (final participant in jsonObjects(json['participants']))
              ResenhaParticipant.fromJson(participant),
          ]),
        ),
        'kicked' => const ResenhaKickedEvent(),
        'role_change' => ResenhaRoleChangedEvent(
          userId: jsonInt(json['user_id']),
          role: ResenhaRole.parse(json['role']),
        ),
        'hand_raise' => ResenhaHandRaiseEvent(
          userId: jsonInt(json['user_id']),
          raised: json['raised'] == true,
          reason: jsonText(json['reason']),
        ),
        'recording' => ResenhaRecordingEvent(
          recording: jsonObject(json['recording']).isEmpty
              ? null
              : ResenhaRecording.fromJson(jsonObject(json['recording'])),
        ),
        _ => null,
      };
}

final class ResenhaParticipantsEvent extends ResenhaRoomEvent {
  const ResenhaParticipantsEvent(this.participants);
  final List<ResenhaParticipant> participants;
}

final class ResenhaKickedEvent extends ResenhaRoomEvent {
  const ResenhaKickedEvent();
}

final class ResenhaRoleChangedEvent extends ResenhaRoomEvent {
  const ResenhaRoleChangedEvent({required this.userId, required this.role});
  final int userId;
  final ResenhaRole role;
}

final class ResenhaHandRaiseEvent extends ResenhaRoomEvent {
  const ResenhaHandRaiseEvent({
    required this.userId,
    required this.raised,
    this.reason,
  });
  final int userId;
  final bool raised;
  final String? reason;
}

final class ResenhaRecordingEvent extends ResenhaRoomEvent {
  const ResenhaRecordingEvent({required this.recording});
  final ResenhaRecording? recording;
}
