import 'package:discourse_native/discourse_plugin_sdk.dart';

const userNotesPluginId = PluginId('discourse-user-notes');
const userNotesSettingsKey = PluginDataKey<UserNotesSettings>(
  owner: 'discourse-user-notes',
  name: 'settings',
);
const userNotesCountKey = PluginDataKey<UserNotesCount>(
  owner: 'discourse-user-notes',
  name: 'count',
);

enum UserNotesPlacement { name, avatar }

final class UserNotesSettings {
  const UserNotesSettings({
    this.enabled = false,
    this.placement = UserNotesPlacement.name,
    this.maximumLength,
  });
  final bool enabled;
  final UserNotesPlacement placement;
  final int? maximumLength;
  @override
  bool operator ==(Object other) =>
      other is UserNotesSettings &&
      enabled == other.enabled &&
      placement == other.placement &&
      maximumLength == other.maximumLength;

  @override
  int get hashCode => Object.hash(enabled, placement, maximumLength);

  factory UserNotesSettings.read(Map<String, dynamic> json) =>
      UserNotesSettings(
        enabled: json['user_notes_enabled'] == true,
        placement: json['user_notes_icon_placement'] == 'avatar'
            ? UserNotesPlacement.avatar
            : UserNotesPlacement.name,
        maximumLength: userNotePositiveId(json['max_post_length']),
      );
}

final class UserNotesSettingsCodec
    extends PluginDataPersistenceCodec<UserNotesSettings> {
  const UserNotesSettingsCodec();
  @override
  PluginDataKey<UserNotesSettings> get key => userNotesSettingsKey;
  @override
  UserNotesSettings? decode(Object? value) => value is Map
      ? UserNotesSettings.read(Map<String, dynamic>.from(value))
      : null;
  @override
  Object encode(UserNotesSettings value) => {
    'user_notes_enabled': value.enabled,
    'user_notes_icon_placement': value.placement.name,
    if (value.maximumLength != null) 'max_post_length': value.maximumLength,
  };
}

final class UserNotesCount {
  const UserNotesCount(this.value);
  final int value;
  @override
  bool operator ==(Object other) =>
      other is UserNotesCount && value == other.value;
  @override
  int get hashCode => value.hashCode;

  static UserNotesCount? read(Map<String, dynamic> json, {bool post = false}) {
    final fields = json[post ? 'user_custom_fields' : 'custom_fields'];
    final raw = !post && json['user_notes_count'] != null
        ? json['user_notes_count']
        : fields is Map
        ? fields['user_notes_count']
        : null;
    final count = userNoteInteger(raw);
    return count != null && count >= 0 ? UserNotesCount(count) : null;
  }
}

int? userNoteInteger(Object? value) {
  if (value is int) return value;
  return value is String && RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)
      ? int.tryParse(value)
      : null;
}

int? userNotePositiveId(Object? value) {
  final id = userNoteInteger(value);
  return id != null && id > 0 ? id : null;
}

final class UserNoteAuthor {
  const UserNoteAuthor({
    required this.id,
    required this.username,
    this.avatarTemplate,
  });
  final int id;
  final String username;
  final String? avatarTemplate;
  static UserNoteAuthor? read(Object? value) {
    if (value is! Map ||
        value['id'] is! int ||
        value['username'] is! String ||
        (value['username'] as String).isEmpty) {
      return null;
    }
    return UserNoteAuthor(
      id: value['id'] as int,
      username: value['username'] as String,
      avatarTemplate: value['avatar_template'] is String
          ? value['avatar_template'] as String
          : null,
    );
  }
}

final class UserNotePost {
  const UserNotePost({required this.id, required this.url, this.title});
  final int id;
  final String url;
  final String? title;
}

final class UserNote {
  const UserNote({
    required this.id,
    required this.userId,
    required this.raw,
    required this.createdAt,
    required this.canDelete,
    this.author,
    this.post,
    this.reviewableId,
  });
  final String id;
  final int userId;
  final String raw;
  final DateTime createdAt;
  final bool canDelete;
  final UserNoteAuthor? author;
  final UserNotePost? post;
  final int? reviewableId;

  factory UserNote.read(Map<String, dynamic> json, {required int userId}) {
    final id = json['id'], raw = json['raw'], timestamp = json['created_at'];
    final createdAt = timestamp is String ? DateTime.tryParse(timestamp) : null;
    if (id is! String ||
        id.trim().isEmpty ||
        raw is! String ||
        createdAt == null ||
        userNoteInteger(json['user_id']) != userId) {
      throw const FormatException('Invalid user note record');
    }
    final postId = userNotePositiveId(json['post_id']), url = json['post_url'];
    return UserNote(
      id: id,
      userId: userId,
      raw: raw,
      createdAt: createdAt,
      canDelete: json['can_delete'] == true,
      author: UserNoteAuthor.read(json['created_by']),
      post: postId != null && url is String && url.isNotEmpty
          ? UserNotePost(
              id: postId,
              url: url,
              title: json['post_title'] is String
                  ? json['post_title'] as String
                  : null,
            )
          : null,
      reviewableId: userNotePositiveId(json['reviewable_id']),
    );
  }
}

final class UserNotesList {
  UserNotesList({required this.username, required Iterable<UserNote> notes})
    : notes = List.unmodifiable(notes);
  final String username;
  final List<UserNote> notes;
}
