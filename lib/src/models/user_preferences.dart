import 'package:flutter/foundation.dart';

import 'bookmark.dart';
import 'json.dart';
import 'notification_schedule.dart';
import 'sidebar_tag.dart';

/// Core sections have fixed identities; plugins declare their own namespace.
@immutable
final class PreferenceSection {
  const PreferenceSection.plugin({required this.owner, required this.name});
  const PreferenceSection._core(this.name) : owner = 'core';

  static const profile = PreferenceSection._core('profile');

  /// The bio has its own transaction: free text waits for an explicit save,
  /// while the rest of the profile tab saves each choice as it is made.
  static const about = PreferenceSection._core('about');
  static const notifications = PreferenceSection._core('notifications');
  static const notificationSchedule = PreferenceSection._core(
    'notificationSchedule',
  );
  static const tracking = PreferenceSection._core('tracking');
  static const sidebarCategories = PreferenceSection._core('sidebarCategories');
  static const sidebarTags = PreferenceSection._core('sidebarTags');
  static const interface = PreferenceSection._core('interface');

  /// The people this account has muted. Ignoring someone is a separate write
  /// with its own owner, so it is not part of this section's draft.
  static const users = PreferenceSection._core('users');
  static const values = [profile, notifications, tracking, interface, users];

  final String owner;
  final String name;
  String get id => '$owner/$name';
  String get keyName => owner == 'core' ? name : id;

  @override
  bool operator ==(Object other) =>
      other is PreferenceSection && other.owner == owner && other.name == name;
  @override
  int get hashCode => Object.hash(owner, name);
}

/// An opaque, immutable value whose wire schema belongs to its contributor.
abstract interface class UserPreferenceValues {
  Map<String, Object?> get payload;
}

@immutable
final class UserPreferences {
  static const Set<String> coreFields = {
    'sidebar_category_ids',
    'sidebar_tag_names',
    'timezone',
    'bio_raw',
    'like_notification_frequency',
    'notify_on_linked_posts',
    'new_topic_duration_minutes',
    'auto_track_topics_after_msecs',
    'notification_level_when_replying',
    'bookmark_auto_delete_preference',
    'user_notification_schedule',
    'muted_usernames',
  };

  /// Core response identities are reserved even when they are not editable.
  static const coreWireFields = {
    ...coreFields,
    'username',
    'can_edit',
    'can_change_bio',
    'can_edit_avatar',
    'can_upload_avatar',
    'uploaded_avatar_id',
    'can_change_tracking_preferences',
    'can_mute_users',
    'user_option',
    'sidebar_tags',
  };

  const UserPreferences({
    this.sidebarCategoryIds = const [],
    this.sidebarTags = const [],
    this.username = '',
    this.timezone = '',
    this.bioRaw = '',
    this.likeNotificationFrequency = 1,
    this.notifyOnLinkedPosts = true,
    this.notificationSchedule,
    this.newTopicDurationMinutes = 2880,
    this.autoTrackTopicsAfterMsecs = 300000,
    this.notificationLevelWhenReplying = 2,
    this.bookmarkAutoDeletePreference =
        BookmarkAutoDeletePreference.clearReminder,
    this.pluginValues = const {},
    this.canEdit = false,
    this.canChangeBio = true,
    this.canEditAvatar = false,
    this.canUploadAvatar = false,
    this.uploadedAvatarId,
    this.canChangeTrackingPreferences = false,
    this.mutedUsernames = const [],
    this.canMuteUsers = false,
  });

  factory UserPreferences.fromJson(
    Map<String, dynamic> json, {
    UserPreferences fallback = const UserPreferences(),
    Map<String, UserPreferenceValues>? pluginValues,
  }) {
    final options = jsonObject(json['user_option']);

    return UserPreferences(
      sidebarCategoryIds: json.containsKey('sidebar_category_ids')
          ? List.unmodifiable([
              for (final id in jsonArray(json['sidebar_category_ids']))
                ?jsonIntOrNull(id),
            ])
          : fallback.sidebarCategoryIds,
      sidebarTags: json.containsKey('sidebar_tags')
          ? List.unmodifiable([
              for (final tag in jsonArray(json['sidebar_tags']))
                ?SidebarTag.fromJson(tag),
            ])
          : fallback.sidebarTags,
      username: _string(json, 'username', fallback.username),
      timezone: _string(options, 'timezone', fallback.timezone),
      bioRaw: _string(json, 'bio_raw', fallback.bioRaw),
      notificationSchedule:
          NotificationSchedule.read(json['user_notification_schedule']) ??
          fallback.notificationSchedule,
      likeNotificationFrequency: _allowedInt(
        options,
        'like_notification_frequency',
        _likeNotificationFrequencies,
        fallback.likeNotificationFrequency,
      ),
      notifyOnLinkedPosts: _boolean(
        options,
        'notify_on_linked_posts',
        fallback.notifyOnLinkedPosts,
      ),
      newTopicDurationMinutes: _allowedInt(
        options,
        'new_topic_duration_minutes',
        _newTopicDurations,
        fallback.newTopicDurationMinutes,
      ),
      autoTrackTopicsAfterMsecs: _allowedInt(
        options,
        'auto_track_topics_after_msecs',
        _autoTrackDurations,
        fallback.autoTrackTopicsAfterMsecs,
      ),
      notificationLevelWhenReplying: _allowedInt(
        options,
        'notification_level_when_replying',
        _replyNotificationLevels,
        fallback.notificationLevelWhenReplying,
      ),
      bookmarkAutoDeletePreference: _bookmarkPreference(
        options,
        fallback.bookmarkAutoDeletePreference,
      ),
      pluginValues: Map.unmodifiable(pluginValues ?? fallback.pluginValues),
      canEdit: _boolean(json, 'can_edit', fallback.canEdit),
      canChangeBio: _boolean(json, 'can_change_bio', fallback.canChangeBio),
      canEditAvatar: _boolean(json, 'can_edit_avatar', fallback.canEditAvatar),
      canUploadAvatar: _boolean(
        json,
        'can_upload_avatar',
        fallback.canUploadAvatar,
      ),
      uploadedAvatarId: json.containsKey('uploaded_avatar_id')
          ? jsonIntOrNull(json['uploaded_avatar_id'])
          : fallback.uploadedAvatarId,
      canChangeTrackingPreferences: _boolean(
        json,
        'can_change_tracking_preferences',
        fallback.canChangeTrackingPreferences,
      ),
      mutedUsernames: _usernames(
        json,
        'muted_usernames',
        fallback.mutedUsernames,
      ),
      canMuteUsers: _boolean(json, 'can_mute_users', fallback.canMuteUsers),
    );
  }

  static const Set<int> _likeNotificationFrequencies = {0, 1, 2, 3};
  static const Set<int> _newTopicDurations = {-2, -1, 1440, 2880, 10080, 20160};
  static const Set<int> _autoTrackDurations = {
    -1,
    0,
    30000,
    60000,
    120000,
    180000,
    240000,
    300000,
    600000,
  };
  static const Set<int> _replyNotificationLevels = {1, 2, 3};

  final List<int> sidebarCategoryIds;
  final List<SidebarTag> sidebarTags;
  final String username;
  final String timezone;

  /// The markdown source of the profile's "About me".
  final String bioRaw;

  final int likeNotificationFrequency;
  final bool notifyOnLinkedPosts;
  final NotificationSchedule? notificationSchedule;

  final int newTopicDurationMinutes;
  final int autoTrackTopicsAfterMsecs;
  final int notificationLevelWhenReplying;

  final BookmarkAutoDeletePreference bookmarkAutoDeletePreference;
  final Map<String, UserPreferenceValues> pluginValues;

  final bool canEdit;

  /// False where single sign-on owns the bio; a site that predates the flag
  /// leaves the bio editable.
  final bool canChangeBio;

  /// False where single sign-on or another login provider owns the picture.
  final bool canEditAvatar;

  /// Whether this person may pick an image of their own, which the site
  /// grants by group.
  final bool canUploadAvatar;

  /// The upload this person's picture is drawn from. Null means the site
  /// draws its letter avatar.
  final int? uploadedAvatarId;
  final bool canChangeTrackingPreferences;

  /// The people whose posts and notifications this account has muted, as the
  /// site spells their usernames.
  final List<String> mutedUsernames;

  /// False below the trust level the site asks for before anyone may mute.
  final bool canMuteUsers;

  Map<String, Object?> payloadFor(PreferenceSection section) =>
      Map.unmodifiable(switch (section) {
        PreferenceSection.sidebarCategories => {
          'sidebar_category_ids': sidebarCategoryIds,
        },
        PreferenceSection.sidebarTags => {
          'sidebar_tag_names': [for (final tag in sidebarTags) tag.name],
        },
        PreferenceSection.profile => {'timezone': timezone},
        PreferenceSection.about => {'bio_raw': bioRaw},
        PreferenceSection.notifications => {
          'like_notification_frequency': likeNotificationFrequency,
          'notify_on_linked_posts': notifyOnLinkedPosts,
        },
        PreferenceSection.notificationSchedule => {
          if (notificationSchedule case final schedule?)
            'user_notification_schedule': schedule.wireValues,
        },
        PreferenceSection.tracking => {
          'new_topic_duration_minutes': newTopicDurationMinutes,
          'auto_track_topics_after_msecs': autoTrackTopicsAfterMsecs,
          'notification_level_when_replying': notificationLevelWhenReplying,
        },
        PreferenceSection.interface => {
          'bookmark_auto_delete_preference':
              bookmarkAutoDeletePreference.wireValue,
        },
        // Core takes the whole list as one comma-separated string and mutes
        // exactly those people. The order carries no meaning, so it is fixed
        // here and a list put back the way it was is not a change.
        PreferenceSection.users => {
          'muted_usernames': ([...mutedUsernames]..sort()).join(','),
        },
        _ => pluginValues[section.id]?.payload ?? const {},
      });

  UserPreferences withSectionFrom(
    PreferenceSection section,
    UserPreferences confirmed,
  ) => switch (section) {
    PreferenceSection.sidebarCategories => copyWith(
      sidebarCategoryIds: confirmed.sidebarCategoryIds,
    ),
    PreferenceSection.sidebarTags => copyWith(
      sidebarTags: confirmed.sidebarTags,
    ),
    PreferenceSection.notificationSchedule => copyWith(
      notificationSchedule: confirmed.notificationSchedule,
    ),
    PreferenceSection.notifications => copyWith(
      likeNotificationFrequency: confirmed.likeNotificationFrequency,
      notifyOnLinkedPosts: confirmed.notifyOnLinkedPosts,
    ),
    PreferenceSection.tracking => copyWith(
      newTopicDurationMinutes: confirmed.newTopicDurationMinutes,
      autoTrackTopicsAfterMsecs: confirmed.autoTrackTopicsAfterMsecs,
      notificationLevelWhenReplying: confirmed.notificationLevelWhenReplying,
    ),
    PreferenceSection.profile => copyWith(timezone: confirmed.timezone),
    PreferenceSection.about => copyWith(bioRaw: confirmed.bioRaw),
    PreferenceSection.interface => copyWith(
      bookmarkAutoDeletePreference: confirmed.bookmarkAutoDeletePreference,
    ),
    PreferenceSection.users => copyWith(
      mutedUsernames: confirmed.mutedUsernames,
    ),
    _ => copyWith(
      pluginValues: {
        ...pluginValues,
        section.id: ?confirmed.pluginValues[section.id],
      },
    ),
  };

  UserPreferences copyWith({
    List<int>? sidebarCategoryIds,
    List<SidebarTag>? sidebarTags,
    String? username,
    String? timezone,
    String? bioRaw,
    int? likeNotificationFrequency,
    bool? notifyOnLinkedPosts,
    Object? notificationSchedule = _unchanged,
    int? newTopicDurationMinutes,
    int? autoTrackTopicsAfterMsecs,
    int? notificationLevelWhenReplying,
    BookmarkAutoDeletePreference? bookmarkAutoDeletePreference,
    Map<String, UserPreferenceValues>? pluginValues,
    bool? canEdit,
    bool? canChangeBio,
    bool? canEditAvatar,
    bool? canUploadAvatar,
    Object? uploadedAvatarId = _unchanged,
    bool? canChangeTrackingPreferences,
    List<String>? mutedUsernames,
    bool? canMuteUsers,
  }) => UserPreferences(
    sidebarCategoryIds: List.unmodifiable(
      sidebarCategoryIds ?? this.sidebarCategoryIds,
    ),
    sidebarTags: List.unmodifiable(sidebarTags ?? this.sidebarTags),
    username: username ?? this.username,
    timezone: timezone ?? this.timezone,
    bioRaw: bioRaw ?? this.bioRaw,
    likeNotificationFrequency:
        likeNotificationFrequency ?? this.likeNotificationFrequency,
    notifyOnLinkedPosts: notifyOnLinkedPosts ?? this.notifyOnLinkedPosts,
    notificationSchedule: identical(notificationSchedule, _unchanged)
        ? this.notificationSchedule
        : notificationSchedule as NotificationSchedule?,
    newTopicDurationMinutes:
        newTopicDurationMinutes ?? this.newTopicDurationMinutes,
    autoTrackTopicsAfterMsecs:
        autoTrackTopicsAfterMsecs ?? this.autoTrackTopicsAfterMsecs,
    notificationLevelWhenReplying:
        notificationLevelWhenReplying ?? this.notificationLevelWhenReplying,
    bookmarkAutoDeletePreference:
        bookmarkAutoDeletePreference ?? this.bookmarkAutoDeletePreference,
    pluginValues: Map.unmodifiable(pluginValues ?? this.pluginValues),
    canEdit: canEdit ?? this.canEdit,
    canChangeBio: canChangeBio ?? this.canChangeBio,
    canEditAvatar: canEditAvatar ?? this.canEditAvatar,
    canUploadAvatar: canUploadAvatar ?? this.canUploadAvatar,
    uploadedAvatarId: identical(uploadedAvatarId, _unchanged)
        ? this.uploadedAvatarId
        : uploadedAvatarId as int?,
    canChangeTrackingPreferences:
        canChangeTrackingPreferences ?? this.canChangeTrackingPreferences,
    mutedUsernames: List.unmodifiable(mutedUsernames ?? this.mutedUsernames),
    canMuteUsers: canMuteUsers ?? this.canMuteUsers,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreferences &&
          listEquals(other.sidebarCategoryIds, sidebarCategoryIds) &&
          listEquals(other.sidebarTags, sidebarTags) &&
          other.username == username &&
          other.timezone == timezone &&
          other.bioRaw == bioRaw &&
          other.likeNotificationFrequency == likeNotificationFrequency &&
          other.notifyOnLinkedPosts == notifyOnLinkedPosts &&
          other.notificationSchedule == notificationSchedule &&
          other.newTopicDurationMinutes == newTopicDurationMinutes &&
          other.autoTrackTopicsAfterMsecs == autoTrackTopicsAfterMsecs &&
          other.notificationLevelWhenReplying ==
              notificationLevelWhenReplying &&
          other.bookmarkAutoDeletePreference == bookmarkAutoDeletePreference &&
          mapEquals(other.pluginValues, pluginValues) &&
          other.canEdit == canEdit &&
          other.canChangeBio == canChangeBio &&
          other.canEditAvatar == canEditAvatar &&
          other.canUploadAvatar == canUploadAvatar &&
          other.uploadedAvatarId == uploadedAvatarId &&
          other.canChangeTrackingPreferences == canChangeTrackingPreferences &&
          listEquals(other.mutedUsernames, mutedUsernames) &&
          other.canMuteUsers == canMuteUsers;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(sidebarCategoryIds),
    Object.hashAll(sidebarTags),
    username,
    timezone,
    bioRaw,
    likeNotificationFrequency,
    notifyOnLinkedPosts,
    notificationSchedule,
    newTopicDurationMinutes,
    autoTrackTopicsAfterMsecs,
    notificationLevelWhenReplying,
    bookmarkAutoDeletePreference,
    Object.hashAllUnordered(
      pluginValues.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    canEdit,
    canChangeBio,
    canEditAvatar,
    canUploadAvatar,
    uploadedAvatarId,
    canChangeTrackingPreferences,
    Object.hash(Object.hashAll(mutedUsernames), canMuteUsers),
  );

  static const _unchanged = Object();
}

String _string(Map<String, dynamic> json, String key, String fallback) =>
    json[key] is String ? jsonString(json[key]) : fallback;

/// The usernames under [key], without blanks or repeats. An absent or
/// malformed list keeps [fallback], as a write's answer may leave it out.
List<String> _usernames(
  Map<String, dynamic> json,
  String key,
  List<String> fallback,
) {
  if (json[key] is! List) return fallback;
  final seen = <String>{};
  return List.unmodifiable([
    for (final value in jsonArray(json[key]))
      if (value is String && value.trim().isNotEmpty && seen.add(value.trim()))
        value.trim(),
  ]);
}

bool _boolean(Map<String, dynamic> json, String key, bool fallback) =>
    json[key] is bool ? json[key] as bool : fallback;

int _allowedInt(
  Map<String, dynamic> json,
  String key,
  Set<int> allowed,
  int fallback,
) {
  final value = jsonIntOrNull(json[key]);
  return value != null && allowed.contains(value) ? value : fallback;
}

BookmarkAutoDeletePreference _bookmarkPreference(
  Map<String, dynamic> options,
  BookmarkAutoDeletePreference fallback,
) {
  final value = jsonIntOrNull(options['bookmark_auto_delete_preference']);
  for (final preference in BookmarkAutoDeletePreference.values) {
    if (preference.wireValue == value) return preference;
  }
  return fallback;
}
