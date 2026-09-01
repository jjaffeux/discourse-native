import 'package:flutter/foundation.dart';

import 'bookmark.dart';
import 'json.dart';

enum PreferenceSection { profile, notifications, tracking, interface, chat }

enum ChatSeparateSidebarPreference {
  siteDefault('default'),
  always('always'),
  fullscreen('fullscreen'),
  never('never');

  const ChatSeparateSidebarPreference(this.wireValue);

  final String wireValue;

  static ChatSeparateSidebarPreference read(
    Object? value,
    ChatSeparateSidebarPreference fallback,
  ) {
    for (final preference in values) {
      if (value == preference.wireValue) return preference;
    }
    return fallback;
  }
}

@immutable
final class UserPreferences {
  const UserPreferences({
    this.username = '',
    this.timezone = '',
    this.likeNotificationFrequency = 1,
    this.notifyOnLinkedPosts = true,
    this.newTopicDurationMinutes = 2880,
    this.autoTrackTopicsAfterMsecs = 300000,
    this.notificationLevelWhenReplying = 2,
    this.bookmarkAutoDeletePreference =
        BookmarkAutoDeletePreference.clearReminder,
    this.chatSeparateSidebarMode = ChatSeparateSidebarPreference.siteDefault,
    this.canEdit = false,
    this.canChangeTrackingPreferences = false,
  });

  factory UserPreferences.fromJson(
    Map<String, dynamic> json, {
    UserPreferences fallback = const UserPreferences(),
  }) {
    final options = jsonObject(json['user_option']);

    return UserPreferences(
      username: _string(json, 'username', fallback.username),
      timezone: _string(options, 'timezone', fallback.timezone),
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
      chatSeparateSidebarMode: ChatSeparateSidebarPreference.read(
        options['chat_separate_sidebar_mode'],
        fallback.chatSeparateSidebarMode,
      ),
      canEdit: _boolean(json, 'can_edit', fallback.canEdit),
      canChangeTrackingPreferences: _boolean(
        json,
        'can_change_tracking_preferences',
        fallback.canChangeTrackingPreferences,
      ),
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

  final String username;
  final String timezone;

  final int likeNotificationFrequency;
  final bool notifyOnLinkedPosts;

  final int newTopicDurationMinutes;
  final int autoTrackTopicsAfterMsecs;
  final int notificationLevelWhenReplying;

  final BookmarkAutoDeletePreference bookmarkAutoDeletePreference;
  final ChatSeparateSidebarPreference chatSeparateSidebarMode;

  final bool canEdit;
  final bool canChangeTrackingPreferences;

  Map<String, Object?> payloadFor(PreferenceSection section) =>
      Map.unmodifiable(switch (section) {
        PreferenceSection.profile => {'timezone': timezone},
        PreferenceSection.notifications => {
          'like_notification_frequency': likeNotificationFrequency,
          'notify_on_linked_posts': notifyOnLinkedPosts,
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
        PreferenceSection.chat => {
          'chat_separate_sidebar_mode': chatSeparateSidebarMode.wireValue,
        },
      });

  UserPreferences withSectionFrom(
    PreferenceSection section,
    UserPreferences confirmed,
  ) => switch (section) {
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
    PreferenceSection.interface => copyWith(
      bookmarkAutoDeletePreference: confirmed.bookmarkAutoDeletePreference,
    ),
    PreferenceSection.chat => copyWith(
      chatSeparateSidebarMode: confirmed.chatSeparateSidebarMode,
    ),
  };

  UserPreferences copyWith({
    String? username,
    String? timezone,
    int? likeNotificationFrequency,
    bool? notifyOnLinkedPosts,
    int? newTopicDurationMinutes,
    int? autoTrackTopicsAfterMsecs,
    int? notificationLevelWhenReplying,
    BookmarkAutoDeletePreference? bookmarkAutoDeletePreference,
    ChatSeparateSidebarPreference? chatSeparateSidebarMode,
    bool? canEdit,
    bool? canChangeTrackingPreferences,
  }) => UserPreferences(
    username: username ?? this.username,
    timezone: timezone ?? this.timezone,
    likeNotificationFrequency:
        likeNotificationFrequency ?? this.likeNotificationFrequency,
    notifyOnLinkedPosts: notifyOnLinkedPosts ?? this.notifyOnLinkedPosts,
    newTopicDurationMinutes:
        newTopicDurationMinutes ?? this.newTopicDurationMinutes,
    autoTrackTopicsAfterMsecs:
        autoTrackTopicsAfterMsecs ?? this.autoTrackTopicsAfterMsecs,
    notificationLevelWhenReplying:
        notificationLevelWhenReplying ?? this.notificationLevelWhenReplying,
    bookmarkAutoDeletePreference:
        bookmarkAutoDeletePreference ?? this.bookmarkAutoDeletePreference,
    chatSeparateSidebarMode:
        chatSeparateSidebarMode ?? this.chatSeparateSidebarMode,
    canEdit: canEdit ?? this.canEdit,
    canChangeTrackingPreferences:
        canChangeTrackingPreferences ?? this.canChangeTrackingPreferences,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreferences &&
          other.username == username &&
          other.timezone == timezone &&
          other.likeNotificationFrequency == likeNotificationFrequency &&
          other.notifyOnLinkedPosts == notifyOnLinkedPosts &&
          other.newTopicDurationMinutes == newTopicDurationMinutes &&
          other.autoTrackTopicsAfterMsecs == autoTrackTopicsAfterMsecs &&
          other.notificationLevelWhenReplying ==
              notificationLevelWhenReplying &&
          other.bookmarkAutoDeletePreference == bookmarkAutoDeletePreference &&
          other.chatSeparateSidebarMode == chatSeparateSidebarMode &&
          other.canEdit == canEdit &&
          other.canChangeTrackingPreferences == canChangeTrackingPreferences;

  @override
  int get hashCode => Object.hash(
    username,
    timezone,
    likeNotificationFrequency,
    notifyOnLinkedPosts,
    newTopicDurationMinutes,
    autoTrackTopicsAfterMsecs,
    notificationLevelWhenReplying,
    bookmarkAutoDeletePreference,
    chatSeparateSidebarMode,
    canEdit,
    canChangeTrackingPreferences,
  );
}

String _string(Map<String, dynamic> json, String key, String fallback) =>
    json[key] is String ? jsonString(json[key]) : fallback;

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
