import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_preferences.dart';
import 'package:discourse_native/src/plugins/policy/policy_email_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';

void main() {
  test(
    'sidebar sections parse top-level server fields and merge independently',
    () {
      final value = UserPreferences.fromJson(const {
        'username': 'reader',
        'can_edit': true,
        'sidebar_category_ids': [3, 8],
        'sidebar_tags': [
          {'id': 7, 'name': 'release', 'slug': 'release', 'count': 10},
        ],
      });
      expect(value.payloadFor(PreferenceSection.sidebarCategories), {
        'sidebar_category_ids': [3, 8],
      });
      expect(value.payloadFor(PreferenceSection.sidebarTags), {
        'sidebar_tag_names': ['release'],
      });
      final changed = value.copyWith(
        sidebarCategoryIds: const [],
        sidebarTags: const [],
      );
      expect(
        changed
            .withSectionFrom(PreferenceSection.sidebarCategories, value)
            .sidebarTags,
        isEmpty,
      );
      expect(
        changed
            .withSectionFrom(PreferenceSection.sidebarCategories, value)
            .sidebarCategoryIds,
        [3, 8],
      );
      expect(UserPreferences.fromJson(const {}, fallback: value), value);
    },
  );

  test(
    'channel-list wire values round trip independently and preserve absence',
    () {
      for (final section in ChatChannelListSection.values) {
        for (final filter in ChatChannelListFilter.values) {
          for (final sort in ChatChannelListSort.values) {
            final fields = {
              section.filterField: filter.wireValue,
              section.sortField: sort.wireValue,
            };
            final value = installedPlugins.models.userPreferences({
              'user_option': fields,
            });
            expect(value.chatPreferences.channelList.wireValues, fields);
            expect(
              value.chatPreferences.channelList.filterFor(section),
              filter,
            );
            expect(value.chatPreferences.channelList.sortFor(section), sort);
            expect(
              installedPlugins.models.userPreferences(
                const {},
                fallback: value,
              ),
              value,
            );
            expect(value.copyWith().hashCode, value.hashCode);
          }
        }
      }
      final missing = installedPlugins.models.userPreferences(const {});
      expect(missing.chatPreferences.channelList.wireValues, isEmpty);
      final unknown = installedPlugins.models
          .userPreferences({
            'user_option': {
              for (final section in ChatChannelListSection.values) ...{
                section.filterField: ['invalid'],
                section.sortField: 999,
              },
            },
          })
          .chatPreferences
          .channelList;
      expect(unknown.wireValues, {
        for (final section in ChatChannelListSection.values) ...{
          section.filterField: 'all',
          section.sortField: 'alphabetical',
        },
      });
      expect(
        installedPlugins.models
            .userPreferences(const {
              'user_option': {'chat_channel_list_sort_dms': 'priority'},
            })
            .chatPreferences
            .channelList
            .sortFor(ChatChannelListSection.directMessages),
        ChatChannelListSort.priority,
      );
    },
  );

  test('reads identity, permissions, and nested user-option fields', () {
    final preferences = installedPlugins.models.userPreferences(const {
      'username': 'sam',
      'can_edit': true,
      'can_change_tracking_preferences': true,
      'user_option': {
        'timezone': 'Europe/Paris',
        'like_notification_frequency': 3,
        'notify_on_linked_posts': false,
        'new_topic_duration_minutes': -2,
        'auto_track_topics_after_msecs': 60000,
        'notification_level_when_replying': 3,
        'bookmark_auto_delete_preference': 1,
        'chat_separate_sidebar_mode': 'fullscreen',
      },
    });

    expect(
      preferences,
      const UserPreferences(
        username: 'sam',
        timezone: 'Europe/Paris',
        likeNotificationFrequency: 3,
        notifyOnLinkedPosts: false,
        newTopicDurationMinutes: -2,
        autoTrackTopicsAfterMsecs: 60000,
        notificationLevelWhenReplying: 3,
        bookmarkAutoDeletePreference:
            BookmarkAutoDeletePreference.whenReminderSent,
        canEdit: true,
        canChangeTrackingPreferences: true,
        pluginValues: {
          'discourse-cakeday/birthday': CakedayPreferences.unavailable(),
          'discourse-policy/emails': PolicyEmailPreferences(
            PolicyEmailFrequency.never,
          ),
          'chat/preferences': ChatUserPreferences(
            separateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
          ),
        },
      ),
    );
  });

  test('uses safe defaults for malformed values', () {
    final preferences = installedPlugins.models.userPreferences(const {
      'username': 12,
      'can_edit': 'true',
      'can_change_tracking_preferences': 1,
      'user_option': {
        'timezone': false,
        'like_notification_frequency': 99,
        'notify_on_linked_posts': 'false',
        'new_topic_duration_minutes': 42,
        'auto_track_topics_after_msecs': double.infinity,
        'notification_level_when_replying': 0,
        'bookmark_auto_delete_preference': 99,
        'chat_separate_sidebar_mode': 'unsupported',
      },
    });

    expect(
      preferences,
      const UserPreferences(
        pluginValues: {
          'discourse-cakeday/birthday': CakedayPreferences.unavailable(),
          'discourse-policy/emails': PolicyEmailPreferences(
            PolicyEmailFrequency.never,
          ),
          'chat/preferences': ChatUserPreferences(),
        },
      ),
    );
  });

  test('merges a partial user response over the confirmed fallback', () {
    const fallback = UserPreferences(
      username: 'sam',
      timezone: 'UTC',
      likeNotificationFrequency: 1,
      notifyOnLinkedPosts: false,
      newTopicDurationMinutes: 10080,
      autoTrackTopicsAfterMsecs: 120000,
      notificationLevelWhenReplying: 2,
      bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.never,
      canEdit: true,
      canChangeTrackingPreferences: true,
      pluginValues: {
        'discourse-cakeday/birthday': CakedayPreferences.unavailable(),
        'discourse-policy/emails': PolicyEmailPreferences(
          PolicyEmailFrequency.never,
        ),
        'chat/preferences': ChatUserPreferences(
          separateSidebarMode: ChatSeparateSidebarPreference.always,
        ),
      },
    );

    final updated = installedPlugins.models.userPreferences(const {
      'user_option': {'like_notification_frequency': 2},
    }, fallback: fallback);

    expect(updated, fallback.copyWith(likeNotificationFrequency: 2));
  });

  test('reads the bio beside the options and keeps it across a partial '
      'response', () {
    final loaded = UserPreferences.fromJson(const {
      'username': 'sam',
      'bio_raw': 'I like **boats**.',
      'can_change_bio': false,
      'user_option': {'bio_raw': 'never read from the options'},
    });
    expect(loaded.bioRaw, 'I like **boats**.');
    expect(loaded.canChangeBio, isFalse);

    final empty = UserPreferences.fromJson(const {'bio_raw': null});
    expect(empty.bioRaw, '');
    expect(empty.canChangeBio, isTrue);

    final partial = UserPreferences.fromJson(const {
      'user_option': {'timezone': 'Europe/Paris'},
    }, fallback: loaded);
    expect(partial.bioRaw, 'I like **boats**.');
    expect(partial.canChangeBio, isFalse);
    expect(
      UserPreferences.fromJson(const {'bio_raw': 7}, fallback: loaded).bioRaw,
      'I like **boats**.',
    );
  });

  test('reads what the account may do with its picture', () {
    final loaded = UserPreferences.fromJson(const {
      'can_edit_avatar': true,
      'can_upload_avatar': true,
      'uploaded_avatar_id': 42,
    });
    expect(loaded.canEditAvatar, isTrue);
    expect(loaded.canUploadAvatar, isTrue);
    expect(loaded.uploadedAvatarId, 42);

    const none = UserPreferences();
    expect(none.canEditAvatar, isFalse);
    expect(none.canUploadAvatar, isFalse);
    expect(none.uploadedAvatarId, isNull);

    expect(
      UserPreferences.fromJson(const {
        'user_option': <String, Object?>{},
      }, fallback: loaded),
      loaded,
    );
    final letter = UserPreferences.fromJson(const {
      'uploaded_avatar_id': null,
      'can_upload_avatar': 'yes',
    }, fallback: loaded);
    expect(letter.uploadedAvatarId, isNull);
    expect(letter.canUploadAvatar, isTrue);
    expect(loaded.copyWith(uploadedAvatarId: null).uploadedAvatarId, isNull);
    expect(loaded.copyWith(timezone: 'Etc/UTC').uploadedAvatarId, 42);
    for (final section in [
      ...PreferenceSection.values,
      PreferenceSection.about,
    ]) {
      expect(
        loaded.payloadFor(section).keys.where((key) => key.contains('avatar')),
        isEmpty,
      );
    }
  });

  test('the bio is its own section, apart from the timezone', () {
    const confirmed = UserPreferences(timezone: 'Etc/UTC', bioRaw: 'Before');
    final draft = confirmed.copyWith(timezone: 'Asia/Tokyo', bioRaw: 'After');

    expect(draft.payloadFor(PreferenceSection.about), {'bio_raw': 'After'});
    expect(draft.payloadFor(PreferenceSection.profile), {
      'timezone': 'Asia/Tokyo',
    });
    expect(
      draft.withSectionFrom(PreferenceSection.about, confirmed),
      confirmed.copyWith(timezone: 'Asia/Tokyo'),
    );
    expect(
      draft.withSectionFrom(PreferenceSection.profile, confirmed),
      confirmed.copyWith(bioRaw: 'After'),
    );
    expect(draft == confirmed.copyWith(timezone: 'Asia/Tokyo'), isFalse);
    expect(UserPreferences.coreFields, contains('bio_raw'));
  });

  test('reads the muted list and whether the account may mute', () {
    final loaded = UserPreferences.fromJson(const {
      'muted_usernames': ['sam', ' Robin ', 'sam', '', 7, null],
      'can_mute_users': true,
    });
    expect(loaded.mutedUsernames, ['sam', 'Robin']);
    expect(loaded.canMuteUsers, isTrue);
    expect(() => loaded.mutedUsernames.add('x'), throwsUnsupportedError);

    for (final malformed in <Object?>[
      'sam,robin',
      4,
      null,
      {'a': 1},
    ]) {
      final kept = UserPreferences.fromJson({
        'muted_usernames': malformed,
        'can_mute_users': 'yes',
      }, fallback: loaded);
      expect(kept.mutedUsernames, ['sam', 'Robin']);
      expect(kept.canMuteUsers, isTrue);
    }
    expect(
      UserPreferences.fromJson(const {
        'muted_usernames': <Object?>[],
      }, fallback: loaded).mutedUsernames,
      isEmpty,
    );
    expect(const UserPreferences().canMuteUsers, isFalse);
  });

  test('the muted list is sent whole, as core reads it', () {
    const confirmed = UserPreferences(
      timezone: 'Etc/UTC',
      mutedUsernames: ['sam', 'robin'],
    );
    final draft = confirmed.copyWith(
      timezone: 'Asia/Tokyo',
      mutedUsernames: ['robin', 'sam', 'alex'],
    );

    expect(draft.payloadFor(PreferenceSection.users), {
      'muted_usernames': 'alex,robin,sam',
    });
    expect(
      confirmed
          .copyWith(mutedUsernames: const [])
          .payloadFor(PreferenceSection.users),
      {'muted_usernames': ''},
    );
    expect(
      confirmed
          .copyWith(mutedUsernames: ['robin', 'sam'])
          .payloadFor(PreferenceSection.users),
      confirmed.payloadFor(PreferenceSection.users),
    );
    expect(
      draft.withSectionFrom(PreferenceSection.users, confirmed),
      confirmed.copyWith(timezone: 'Asia/Tokyo'),
    );
    expect(
      draft.withSectionFrom(PreferenceSection.profile, confirmed),
      confirmed.copyWith(mutedUsernames: ['robin', 'sam', 'alex']),
    );
    expect(draft == confirmed.copyWith(timezone: 'Asia/Tokyo'), isFalse);
    expect(UserPreferences.coreFields, contains('muted_usernames'));
  });

  test('writes each section with exact flat web field names', () {
    const preferences = UserPreferences(
      timezone: 'Asia/Tokyo',
      likeNotificationFrequency: 0,
      notifyOnLinkedPosts: false,
      newTopicDurationMinutes: -1,
      autoTrackTopicsAfterMsecs: 30000,
      notificationLevelWhenReplying: 1,
      bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.onOwnerReply,
      pluginValues: {
        'chat/preferences': ChatUserPreferences(
          separateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
        ),
      },
    );

    expect(preferences.payloadFor(PreferenceSection.notifications), {
      'like_notification_frequency': 0,
      'notify_on_linked_posts': false,
    });
    expect(preferences.payloadFor(PreferenceSection.tracking), {
      'new_topic_duration_minutes': -1,
      'auto_track_topics_after_msecs': 30000,
      'notification_level_when_replying': 1,
    });
    expect(preferences.payloadFor(PreferenceSection.profile), {
      'timezone': 'Asia/Tokyo',
    });
    expect(preferences.payloadFor(PreferenceSection.interface), {
      'bookmark_auto_delete_preference': 2,
    });
    expect(preferences.payloadFor(chatPreferenceSection), {
      'chat_separate_sidebar_mode': 'fullscreen',
    });
    expect(
      () => preferences.payloadFor(
        PreferenceSection.notifications,
      )['unexpected'] = true,
      throwsUnsupportedError,
    );
  });

  test('preserves the server default chat sidebar sentinel', () {
    final preferences = installedPlugins.models.userPreferences(const {
      'user_option': {'chat_separate_sidebar_mode': 'default'},
    });

    expect(
      preferences.chatPreferences.separateSidebarMode,
      ChatSeparateSidebarPreference.siteDefault,
    );
    expect(preferences.payloadFor(chatPreferenceSection), {
      'chat_separate_sidebar_mode': 'default',
    });
  });

  test('copyWith and value equality preserve confirmed/draft snapshots', () {
    const original = UserPreferences(username: 'sam', canEdit: true);
    final unchanged = original.copyWith();
    final changed = original.copyWith(timezone: '', notifyOnLinkedPosts: false);

    expect(unchanged, original);
    expect(unchanged.hashCode, original.hashCode);
    expect(changed, isNot(original));
    expect(changed.username, 'sam');
    expect(changed.timezone, '');
    expect(changed.notifyOnLinkedPosts, isFalse);
  });

  test('section merge never confirms unsent edits from another section', () {
    const confirmed = UserPreferences(
      timezone: 'UTC',
      likeNotificationFrequency: 1,
      notifyOnLinkedPosts: true,
      newTopicDurationMinutes: 2880,
    );
    const serverResponseUsingWholeDraftAsFallback = UserPreferences(
      timezone: 'Europe/Paris',
      likeNotificationFrequency: 3,
      notifyOnLinkedPosts: false,
      newTopicDurationMinutes: 10080,
    );

    final merged = confirmed.withSectionFrom(
      PreferenceSection.notifications,
      serverResponseUsingWholeDraftAsFallback,
    );

    expect(merged.likeNotificationFrequency, 3);
    expect(merged.notifyOnLinkedPosts, isFalse);
    expect(merged.timezone, 'UTC');
    expect(merged.newTopicDurationMinutes, 2880);
  });
}
