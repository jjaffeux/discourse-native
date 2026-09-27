import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/models/badge.dart';
import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discover_site.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/models/invite.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/post_revision.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/models/topic_link.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/models/user_flair.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/plugin_api/notification_counters.dart';
import 'package:discourse_native/src/plugins/assign/assign_data.dart';
import 'package:discourse_native/src/plugins/assign/assign_group_data.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_proofreading_data.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/topic_calendar_data.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_data.dart';
import 'package:discourse_native/src/plugins/prometheus_alert_receiver/alert_links.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:discourse_native/src/plugins/voice/voice_agents.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

const _keys = [
  'id',
  'name',
  'title',
  'fancy_title',
  'slug',
  'username',
  'url',
  'user',
  'created_at',
  'updated_at',
  'bumped_at',
  'last_posted_at',
  'posts_count',
  'reply_count',
  'like_count',
  'cooked',
  'raw',
  'post_number',
  'post_id',
  'topic_id',
  'category_id',
  'highest_post_number',
  'last_read_post_number',
  'notification_level',
  'created_in_new_period',
  'is_seen',
  'is_category_topic',
  'tags',
  'posters',
  'users',
  'topic_list',
  'topics',
  'avatar_template',
  'notification_type',
  'data',
  'read',
  'unread',
  'actions_summary',
  'post_action_types',
  'is_flag',
  'name_key',
  'short_description',
  'require_message',
  'enabled',
  'applies_to',
  'system',
  'can_act',
  'can_undo',
  'acted',
  'count',
  'topic_count',
  'pm_count',
  'pm_only',
  'pmOnly',
  'color',
  'text_color',
  'bookmarkable_url',
  'bookmarkable_id',
  'bookmarkable_type',
  'bookmarked',
  'bookmarks',
  'bookmark_id',
  'bookmark_name',
  'bookmark_reminder_at',
  'bookmark_auto_delete_preference',
  'reminder_at',
  'auto_delete_preference',
  'more_topics_url',
  'user_bookmark_list',
  'more_bookmarks_url',
  'archetype',
  'site_settings',
  'primary_group_name',
  'flair_url',
  'flair_group_id',
  'flair_name',
  'flair_color',
  'flair_bg_color',
  'chat_notifications',
  'ignored_users',
  'topic_tracking',
  'unread_notifications',
  'type',
  'ref',
  'relative_url',
  'description',
  'topic_template',
  'group',
  'grouped_search_result',
  'posts',
  'categories',
  'user_actions',
  'action_type',
  'excerpt',
  'closed',
  'archived',
  'deleted',
  'hidden',
  'sequence',
  'draft_key',
  'results',
  'suggestions',
  'options',
  'votes',
  'chatable',
  'chatable_type',
  'last_message',
  'meta',
  'thread',
  'threads',
  'memberships',
  'reactions',
  'uploads',
  'in_reply_to',
  'chat_message',
  'rooms',
  'participants',
  'ice_servers',
  'livekit',
  'recording',
  'writerId',
  'timestampUtc',
  'captureId',
  'event',
  'next',
  'suggested_topics',
  'related_topics',
  'emoji',
  'status',
  'ends_at',
  'message_bus_last_id',
  'assigned_to_user',
  'ranked_choice',
  'link_counts',
  'reflection',
  'root_domain',
  'word_count',
  'summarizable',
  'has_cached_summary',
  'ai_topic_summary',
  'summarized_text',
  'ai_helper_enabled_features',
  'ai_helper_prompts',
  'can_use_assistant',
  'user_summary',
  'topic_ids',
  'most_liked_by_users',
  'most_liked_users',
  'most_replied_to_users',
  'top_categories',
  'badge_id',
  'badges',
  'badge_groupings',
  'badge_type_id',
  'badge_grouping_id',
  'grant_count',
  'has_badge',
  'long_description',
  'multiple_grant',
  'allow_title',
  'image_url',
  'icon',
  'position',
  'user_badge_info',
  'user_badges',
  'granted_at',
  'user_id',
  'listable',
  'likes_given',
  'likes_received',
  'topics_entered',
  'posts_read_count',
  'days_visited',
  'time_read',
  'recent_time_read',
  'bookmark_count',
  'can_see_summary_stats',
  'can_see_user_actions',
  'user_option',
  'identifier',
  'match_quality',
  'has_chat_enabled',
  'can_chat',
  'chat_enabled_user_count',
  'full_name',
  'timezone',
  'like_notification_frequency',
  'notify_on_linked_posts',
  'new_topic_duration_minutes',
  'auto_track_topics_after_msecs',
  'notification_level_when_replying',
  'bookmark_auto_delete_preference',
  'can_edit',
  'can_change_tracking_preferences',
  'version',
  'can_view_edit_history',
  'current_revision',
  'previous_revision',
  'next_revision',
  'version_count',
  'body_changes',
  'title_changes',
  'previous',
  'current',
  'channels',
  'channel',
  'channel_id',
  'chat_channel_id',
  'thread_id',
  'messages',
  'pinned_messages',
  'membership',
  'model',
  'invites',
  'counts',
  'email',
  'link',
  'groups',
  'members',
  'owners',
  'extras',
  'logs',
  'usernames',
  'skipped_usernames',
  'directory_items',
  'directory_columns',
  'user_fields',
  'post_action_users',
  'post_stream',
  'total_rows',
  'grouped_unread_notifications',
  'links',
  'calendar_details',
  'alert_data',
];

Object? _value(Random random, int depth) => switch (random.nextInt(
  depth > 2 ? 9 : 12,
)) {
  0 => null,
  1 => random.nextBool(),
  2 => random.nextInt(1 << 32) - (1 << 31),
  // Levels, kinds and post numbers are small, and a random 32-bit value never
  // lands on the one a parser dispatches on.
  3 => random.nextInt(6) - 1,
  4 => random.nextDouble() * 1e9,
  5 => '',
  6 => _keys[random.nextInt(_keys.length)],
  7 => '9' * (random.nextInt(40) + 1),
  8 => const [
    '2020-01-01T00:00:00Z',
    'not-a-date',
    '#abc',
    'ff0000',
    '/t/x/1',
    '{size}/a.png',
    '-1',
    '1e400',
    '😀',
  ][random.nextInt(9)],
  9 => [for (var i = random.nextInt(3); i > 0; i--) _value(random, depth + 1)],
  10 => _object(random, depth + 1),
  _ => <String, dynamic>{},
};

Map<String, dynamic> _object(Random random, int depth) => {
  for (var i = random.nextInt(6); i > 0; i--)
    _keys[random.nextInt(_keys.length)]: _value(random, depth),
};

void _recordCorpusShapes(Object? value, Set<String> reached) {
  switch (value) {
    case null:
      reached.add('null');
    case bool():
      reached.add('boolean');
    case int():
      reached.add('integer');
    case double():
      reached.add('double');
    case String():
      reached.add(value.isEmpty ? 'empty string' : 'non-empty string');
    case List<Object?>():
      reached.add(value.isEmpty ? 'empty list' : 'non-empty list');
      if (value.any((item) => item is List || item is Map)) {
        reached.add('list with nested collection');
      }
      for (final item in value) {
        _recordCorpusShapes(item, reached);
      }
    case Map<Object?, Object?>():
      reached.add(value.isEmpty ? 'empty object' : 'non-empty object');
      if (value.values.any((item) => item is List || item is Map)) {
        reached.add('object with nested collection');
      }
      for (final item in value.values) {
        _recordCorpusShapes(item, reached);
      }
    default:
      reached.add('other');
  }
}

/// Site parsers that refuse a payload with a [FormatException] on purpose,
/// and why their callers want the throw rather than a default.
const _rejectsOnPurpose = {
  'UserDirectoryColumn':
      'A column without a name has nothing to label or sort by; '
      'UserDirectoryMetadata.fromColumns drops that column and keeps the rest.',
  'UserDirectoryUser':
      'A directory row without a username cannot be shown or opened.',
  'UserDirectoryItem':
      'An item is only its user, so it refuses whatever the user refuses.',
  'UserDirectoryPage':
      'A page holding a row it cannot show is refused whole, as '
      'user_directory_model_test pins; UserDirectoryController reports it and '
      'keeps the rows it already held.',
  'VoiceJoinResponse':
      'A join answer without a room, or naming a transport this client cannot '
      'speak, connects nobody; the join fails instead, as voice_models_test '
      'pins.',
};

/// The parameter list that opens at [open], through its matching parenthesis.
String _parameters(String source, int open) {
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    switch (source[index]) {
      case '(':
        depth++;
      case ')':
        if (--depth == 0) return source.substring(open, index + 1);
    }
  }
  return source.substring(open);
}

void main() {
  test('no wire parser throws on a payload it did not expect', () {
    final random = Random(20260823);
    const site = 'https://example.com';
    final failures = <String, String>{};
    final reachedShapes = <String>{};
    final probed = <String>{};
    final produced = <String>{};
    final rejected = <String>{};

    for (var run = 0; run < 4000; run++) {
      final json = _object(random, 0);
      final loose = _value(random, 0);
      _recordCorpusShapes(json, reachedShapes);
      _recordCorpusShapes(loose, reachedShapes);

      // Every probe builds its input from this run's [json] and [loose], which
      // is what a failure reports. [reached] says the parse got past its
      // default: a row made it through a page's row path, or a field held
      // something the payload sent. A parser that only ever answers its
      // default is one the corpus never tested.
      void probe<T>(
        String label,
        T Function() parse,
        bool Function(T parsed) reached,
      ) {
        probed.add(label);
        try {
          if (reached(parse())) produced.add(label);
        } catch (error) {
          if (error is FormatException &&
              _rejectsOnPurpose.containsKey(label)) {
            rejected.add(label);
          } else {
            failures.putIfAbsent(
              label,
              () => '$label threw $error on $json, $loose',
            );
          }
        }
      }

      // This run's random object with [fields] on top: a probe sets only the
      // fields it needs, and every other field stays whatever the corpus drew.
      Map<String, dynamic> withFields(Map<String, Object?> fields) => {
        ...json,
        ...fields,
      };

      // What a probe needs a field to hold, such as a page's rows or an id a
      // row is dropped without: [valid] on even runs, so the parse reaches
      // past it, and [loose] on odd runs, so the parser meets garbage there.
      Object? gate(Object? valid) => run.isEven ? valid : loose;

      probe(
        'DiscourseBadge',
        () => DiscourseBadge.fromJson(withFields({'id': loose}), site),
        (badge) => badge.id != 0 || badge.description.isNotEmpty,
      );
      probe(
        'BadgeCatalog',
        () => BadgeCatalog.fromJson(
          withFields({
            'badges': gate([
              json,
              loose,
              withFields({'id': 1}),
            ]),
            'badge_groupings': gate([json, loose]),
          }),
          site,
        ),
        (catalog) => catalog.groups.isNotEmpty,
      );
      probe(
        'BadgeGrantPage',
        () => BadgeGrantPage.fromJson(
          withFields({
            'user_badge_info': gate({
              'user_badges': [
                json,
                loose,
                withFields({
                  'id': 1,
                  'user': withFields({'username': 'u'}),
                }),
              ],
            }),
            'users': gate([json, loose]),
            'topics': gate([json, loose]),
          }),
          site,
        ),
        (page) => page.grants.isNotEmpty,
      );
      probe(
        'Bookmark',
        () => Bookmark.fromJson(withFields({'id': loose})),
        (bookmark) =>
            bookmark.id != 0 ||
            bookmark.title.isNotEmpty ||
            bookmark.categoryId != null,
      );
      probe(
        'Bookmark.fromPostJson',
        () => Bookmark.fromPostJson(
          withFields({
            'bookmarked': gate(true),
            'bookmark_id': gate(1),
            'id': gate(1),
          }),
        ),
        (bookmark) => bookmark != null,
      );
      probe(
        'BookmarkListPage',
        () => BookmarkListPage.fromJson(
          withFields({
            'user_bookmark_list': gate({
              'bookmarks': [json, loose],
              'more_bookmarks_url': loose,
            }),
          }),
        ),
        (page) => page.bookmarks.isNotEmpty,
      );
      probe(
        'ComposerDraft',
        () => ComposerDraft.fromJson(withFields({'reply': loose})),
        (draft) =>
            draft.reply.isNotEmpty ||
            draft.title != null ||
            draft.tags.isNotEmpty,
      );
      probe(
        'ComposerDraft.decode',
        () => ComposerDraft.decode(gate(jsonEncode({'title': loose}))),
        (draft) => draft != null,
      );
      probe(
        'FoundGroup',
        () => FoundGroup.fromJson(withFields({'name': loose}), site),
        (group) => group.name.isNotEmpty || group.fullName != null,
      );
      probe(
        'FoundHashtag',
        () => FoundHashtag.fromJson(
          withFields({'type': loose, 'ref': gate('r')}),
        ),
        (hashtag) => hashtag != null,
      );
      probe(
        'FoundUser',
        () => FoundUser.fromJson(withFields({'username': loose}), site),
        (user) =>
            user.username.isNotEmpty || user.id != null || user.name != null,
      );
      probe(
        'DiscourseNotification',
        () => DiscourseNotification.fromJson(withFields({'id': loose})),
        (notification) =>
            notification.id != 0 ||
            notification.read ||
            notification.topicId != null ||
            notification.slug.isNotEmpty,
      );
      probe(
        'NotificationTotals',
        () => NotificationTotals.fromJson(
          withFields({'unread_notifications': loose}),
        ),
        (totals) => totals.unreadNotifications != 0 || totals.username != null,
      );
      probe(
        'NotificationTypeCounts',
        () => NotificationTypeCounts.fromWire(gate(withFields({'1': loose}))),
        (counts) => counts.totalExcluding(const []) != 0,
      );
      probe(
        'PluginNotificationCounters',
        () => PluginNotificationCounters.fromLive(const [
          chatNotificationCounter,
        ], withFields({chatNotificationCounter.wireName: loose})),
        (counters) => counters.isAvailable(chatNotificationCounter.id),
      );
      probe(
        'Post',
        () => Post.fromJson(withFields({'id': loose}), site),
        (post) =>
            post.id != 0 || post.username.isNotEmpty || post.cooked.isNotEmpty,
      );
      probe(
        'PostNotice',
        () => PostNotice.fromJson(gate(withFields({'type': loose}))),
        (notice) => notice != null,
      );
      probe(
        'PostLinkCount',
        () => PostLinkCount.fromJson(
          withFields({'url': loose, 'clicks': gate(1)}),
        ),
        (link) => link != null,
      );
      probe(
        'PostInboundLink',
        () => PostInboundLink.fromJson(
          withFields({
            'internal': gate(true),
            'reflection': gate(true),
            'url': gate('u'),
            'title': loose,
          }),
        ),
        (link) => link != null,
      );
      probe(
        'PostRevisionChange',
        () => PostRevisionChange.fromJson(
          gate(withFields({'current': loose})),
          (value) => value is String ? value : null,
        ),
        (change) => change != null,
      );
      probe(
        'PostRevisionDiff',
        () => PostRevisionDiff.fromJson(gate(withFields({'inline': loose}))),
        (diff) => diff != null,
      );
      probe(
        'PostRevisionUser',
        () => PostRevisionUser.fromJson(
          gate(withFields({'username': loose})),
          site,
        ),
        (user) => user != null,
      );
      probe(
        'PostRevisionReplyTarget',
        () => PostRevisionReplyTarget.fromJson(
          gate(withFields({'post_number': loose})),
        ),
        (target) => target != null,
      );
      probe(
        'PostRevision',
        () => PostRevision.fromJson(withFields({'post_id': loose}), site),
        (revision) =>
            revision.postId != 0 ||
            revision.username.isNotEmpty ||
            revision.currentRevision != 0,
      );
      probe(
        'PostCreation',
        () => PostCreation.fromJson(withFields({'topic_id': loose}), site),
        (creation) => creation.post != null || creation.topicId != null,
      );
      probe(
        'SitePostActionCatalog',
        () => SitePostActionCatalog.fromJson(
          withFields({
            'post_action_types': gate([
              json,
              loose,
              withFields({
                'is_flag': true,
                'id': 1,
                'name_key': 'k',
                'name': 'n',
              }),
            ]),
            'topic_flag_types': gate([json, loose]),
          }),
        ),
        (catalog) => catalog.postFlags.isNotEmpty,
      );
      probe(
        'PostFlagType',
        () => PostFlagType.tryParse(
          withFields({
            'is_flag': gate(true),
            'id': gate(1),
            'name_key': gate('k'),
            'name': loose,
          }),
        ),
        (flag) => flag != null,
      );
      probe(
        'PostActionSummary',
        () => PostActionSummary.fromJson(withFields({'id': loose})),
        (summary) =>
            summary.id != 0 ||
            summary.count != 0 ||
            summary.acted ||
            summary.canAct ||
            summary.canUndo,
      );
      probe(
        'PostLiker',
        () => PostLiker.fromJson(withFields({'id': loose}), site),
        (liker) =>
            liker.id != 0 || liker.username.isNotEmpty || liker.name != null,
      );
      probe(
        'PostLikers',
        () => PostLikers.parse(
          withFields({
            'post_action_users': gate([json, loose]),
          }),
          postId: 1,
          siteUrl: site,
        ),
        (likers) => likers.likers.isNotEmpty,
      );
      probe(
        'SearchResults',
        () => SearchResults.fromJson(
          withFields({
            'topics': gate([
              json,
              loose,
              withFields({'id': 1}),
            ]),
            'posts': gate([
              json,
              loose,
              withFields({'id': 1, 'topic_id': 1, 'post_number': 1}),
            ]),
            'categories': gate([json, loose]),
            'users': gate([json, loose]),
          }),
          site,
        ),
        (results) => results.hits.isNotEmpty,
      );
      probe(
        'SearchCategoryHit',
        () => SearchCategoryHit.fromJson(
          withFields({'id': gate(1), 'name': loose}),
        ),
        (hit) => hit != null,
      );
      probe(
        'SearchTagHit',
        () => SearchTagHit.fromJson(withFields({'name': loose})),
        (hit) => hit != null,
      );
      probe(
        'SearchUserHit',
        () => SearchUserHit.fromJson(withFields({'username': loose}), site),
        (hit) => hit != null,
      );
      probe(
        'SearchGroupHit',
        () => SearchGroupHit.fromJson(
          withFields({'id': gate(1), 'name': loose}),
          site,
        ),
        (hit) => hit != null,
      );
      probe(
        'SiteAppearance',
        () => SiteAppearance.fromJson(
          withFields({'mode': gate('alternate'), 'base': loose, 'dark': json}),
        ),
        (appearance) => appearance.mode != SiteAppearanceMode.followSystem,
      );
      probe(
        'SiteConfig',
        () => SiteConfig.fromJson(withFields({'emojiSet': loose})),
        (config) => config.emojiSet != SiteConfig.defaultEmojiSet,
      );
      probe(
        'SiteConfig.fromSettings',
        () => SiteConfig.fromSettings(
          withFields({'emoji_set': loose}),
          siteUrl: site,
        ),
        (config) => config.emojiSet != SiteConfig.defaultEmojiSet,
      );
      probe(
        'InviteSettings',
        () =>
            InviteSettings.fromJson(withFields({'invite_expiry_days': loose})),
        (settings) => settings.expiryDays != 90,
      );
      probe(
        'ComposerImageOptimization',
        () => ComposerImageOptimization.fromJson(
          withFields({'composer_media_optimization_image_enabled': loose}),
        ),
        (optimization) => !optimization.enabled,
      );
      probe(
        'DiscourseInvite',
        () => DiscourseInvite.fromJson(withFields({'id': loose})),
        (invite) =>
            invite.id != 0 ||
            invite.email != null ||
            invite.link != null ||
            invite.description != null,
      );
      probe(
        'InvitePage',
        () => InvitePage.fromJson(
          withFields({
            'invites': gate([
              json,
              loose,
              withFields({'id': 1}),
            ]),
            'counts': gate(
              withFields({
                for (final filter in InviteFilter.values) filter.name: loose,
              }),
            ),
          }),
        ),
        (page) =>
            page.invites.isNotEmpty &&
            page.counts.values.any((count) => count > 0),
      );
      probe(
        'AssignSettings',
        () => AssignSettings.fromWire(
          withFields({
            'enable_assign_status': gate(true),
            'assign_statuses': loose,
          }),
        ),
        (settings) => settings.statuses.isNotEmpty,
      );
      probe('AssignCurrentUser', () {
        AssignCurrentUser.fromWire(json);
        return AssignCurrentUser.fromWire(withFields({'can_assign': loose}));
      }, (user) => user?.canAssign == true);
      probe('AssignGroupData', () {
        AssignGroupData.fromWire(json);
        return AssignGroupData.fromWire(
          withFields({'assignment_count': loose}),
        );
      }, (group) => group?.assignmentCount != null);
      probe(
        'AssignedGroupMember',
        () => AssignedGroupMember.fromJson(
          withFields({'id': gate(1), 'username': loose}),
          site,
        ),
        (member) => member != null,
      );
      probe(
        'AssignedGroupMembersPage',
        () => AssignedGroupMembersPage.fromJson(
          withFields({
            'members': gate([
              json,
              loose,
              withFields({'id': 1, 'username': 'u'}),
            ]),
          }),
          site,
          offset: 0,
          limit: 50,
        ),
        (page) => page.members.isNotEmpty,
      );
      probe(
        'ChatSettings',
        () => ChatSettings.fromSettings(withFields({'chat_enabled': loose})),
        (settings) => !settings.chatEnabled,
      );
      probe(
        'ChatCurrentUser',
        () => ChatCurrentUser.fromCurrentUser(withFields({'can_chat': loose})),
        (user) => user.canChat == true,
      );
      probe(
        'GifsSettings',
        () => GifsSettings.fromSiteSettings(withFields({'enable_gifs': loose})),
        (settings) => settings.enabled,
      );
      probe(
        'LocalDatesSettings',
        () => LocalDatesSettings.fromSiteSettings(
          withFields({'discourse_local_dates_enabled': loose}),
        ),
        (settings) => settings.enabled,
      );
      probe(
        'PollSettings',
        () => PollSettings.fromWire(withFields({'poll_enabled': loose})),
        (settings) => !settings.enabled,
      );
      probe('PollCurrentUser', () {
        PollCurrentUser.fromWire(json);
        return PollCurrentUser.fromWire(withFields({'can_create_poll': loose}));
      }, (user) => user?.canCreatePoll == true);
      probe(
        'ReactionsSettings',
        () => ReactionsSettings.fromSiteSettings(
          withFields({
            'discourse_reactions_enabled': gate(true),
            'discourse_reactions_reaction_for_like': loose,
          }),
        ),
        (settings) => settings.mainReaction != null,
      );
      probe(
        'TopicFilterModifier',
        () => TopicFilterModifier.fromJson(withFields({'name': loose})),
        (modifier) => modifier.name.isNotEmpty || modifier.description != null,
      );
      probe(
        'TopicFilterOption',
        () => TopicFilterOption.parse(
          gate(
            withFields({
              'name': 'n',
              'delimiters': [
                json,
                loose,
                withFields({'name': 'd'}),
              ],
            }),
          ),
        ),
        (option) => option != null && option.delimiters.isNotEmpty,
      );
      probe(
        'UserCard',
        () => UserCard.fromJson(withFields({'username': loose}), site),
        (card) =>
            card.username.isNotEmpty ||
            card.id != null ||
            card.name != null ||
            card.title != null,
      );
      probe(
        'UserActivityItem',
        () => UserActivityItem.fromJson(withFields({'topic_id': loose}), site),
        (item) =>
            item.topicId != 0 ||
            item.title.isNotEmpty ||
            item.username.isNotEmpty,
      );
      probe(
        'UserActivityPage',
        () => UserActivityPage.fromJson(
          withFields({
            'user_actions': gate([
              json,
              loose,
              withFields({
                'action_type': UserActivityItem.replyActionType,
                'topic_id': 1,
                'post_number': 1,
                'title': 't',
              }),
            ]),
            'categories': gate([json, loose]),
          }),
          site,
        ),
        (page) => page.items.isNotEmpty,
      );
      probe(
        'UserDraft',
        () => UserDraft.fromJson(withFields({'draft_key': loose})),
        (draft) =>
            draft.key.isNotEmpty ||
            draft.sequence != 0 ||
            draft.title != null ||
            draft.topicId != null,
      );
      probe(
        'UserPreferences',
        () => UserPreferences.fromJson(withFields({'username': loose})),
        (preferences) => preferences.username.isNotEmpty || preferences.canEdit,
      );
      probe(
        'UserStatus',
        () => UserStatus.fromJson(
          withFields({'description': loose, 'emoji': gate('e')}),
        ),
        (status) => status != null,
      );
      probe(
        'UserSummary',
        () => UserSummary.fromJson(
          withFields({
            'user_summary': gate(
              withFields({
                'topic_ids': [loose, 1],
              }),
            ),
            'topics': gate([
              json,
              loose,
              withFields({'id': 1}),
            ]),
          }),
          site,
        ),
        (summary) => summary.topics.isNotEmpty,
      );
      probe(
        'UserDirectoryColumn',
        () => UserDirectoryColumn.fromWire(withFields({'name': loose})),
        (column) => column.name.isNotEmpty,
      );
      probe(
        'UserDirectoryUser',
        () => UserDirectoryUser.fromWire(
          withFields({
            'username': loose,
            'user_fields': {
              '1': withFields({
                'value': [loose, 'v'],
              }),
            },
          }),
          site,
        ),
        (user) => user.userFields.isNotEmpty,
      );
      probe(
        'UserDirectoryItem',
        () => UserDirectoryItem.fromWire(
          withFields({
            'user': withFields({'username': loose}),
          }),
          site,
        ),
        (item) => item.values.isNotEmpty,
      );
      probe(
        'UserDirectoryPage',
        () => UserDirectoryPage.fromWire(
          withFields({
            'directory_items': [
              loose,
              withFields({
                'user': withFields({'username': 'u'}),
              }),
            ],
          }),
          site,
        ),
        (page) => page.items.isNotEmpty,
      );
      probe(
        'UserDirectoryMetadata',
        () => UserDirectoryMetadata.fromColumns(
          withFields({
            'directory_columns': gate([
              json,
              loose,
              withFields({'name': 'n'}),
            ]),
          }),
          groupNames: [if (loose is String) loose, 'g'],
          editable: run % 4 < 2,
        ),
        (metadata) => metadata.availableColumns.isNotEmpty,
      );
      probe(
        'Group',
        () => Group.fromWire(withFields({'id': loose}), site),
        (group) =>
            group.id != 0 || group.name.isNotEmpty || group.fullName != null,
      );
      probe(
        'GroupUserReference',
        () => GroupUserReference.fromWire(
          gate(withFields({'username': loose})),
          site,
        ),
        (user) => user != null,
      );
      probe(
        'GroupDirectoryPage',
        () => GroupDirectoryPage.fromWire(
          withFields({
            'groups': gate([json, loose]),
            'extras': gate(
              withFields({
                'type_filters': [loose, 'f'],
              }),
            ),
          }),
          site,
        ),
        (page) => page.groups.isNotEmpty,
      );
      probe(
        'GroupDetail',
        () => GroupDetail.fromWire(
          withFields({
            'group': gate(withFields({'name': loose})),
          }),
          site,
        ),
        (detail) => detail.group.name.isNotEmpty,
      );
      probe(
        'GroupMember',
        () => GroupMember.fromWire(
          withFields({'id': loose}),
          site,
          groupName: 'g',
        ),
        (member) =>
            member.id != 0 || member.username.isNotEmpty || member.name != null,
      );
      probe(
        'GroupMembersPage',
        () => GroupMembersPage.fromWire(
          withFields({
            'members': gate([json, loose]),
            'owners': gate([json, loose]),
          }),
          site,
          groupName: 'g',
        ),
        (page) => page.members.isNotEmpty,
      );
      probe(
        'GroupRequester',
        () => GroupRequester.fromWire(withFields({'id': loose}), site),
        (requester) =>
            requester.id != 0 ||
            requester.username.isNotEmpty ||
            requester.name != null,
      );
      probe(
        'GroupRequestersPage',
        () => GroupRequestersPage.fromWire(
          withFields({
            'members': gate([json, loose]),
          }),
          site,
        ),
        (page) => page.requesters.isNotEmpty,
      );
      probe(
        'GroupActivityPost',
        () => GroupActivityPost.fromWire(withFields({'id': loose}), site),
        (post) =>
            post.id != 0 || post.topicId != 0 || post.topicTitle.isNotEmpty,
      );
      probe(
        'GroupActivityPage',
        () => GroupActivityPage.fromWire(
          withFields({
            'posts': gate([json, loose]),
            'categories': gate([json, loose]),
          }),
          site,
        ),
        (page) => page.posts.isNotEmpty && page.categories.isNotEmpty,
      );
      probe(
        'GroupPermission',
        () => GroupPermission.fromWire(
          withFields({
            'category': gate(withFields({'id': 1})),
          }),
        ),
        (permission) => permission.category.id > 0,
      );
      probe(
        'GroupLogEntry',
        () => GroupLogEntry.fromWire(
          withFields({
            'acting_user': gate(withFields({'username': loose})),
          }),
          site,
        ),
        (entry) => entry.actingUser != null,
      );
      probe(
        'GroupLogsPage',
        () => GroupLogsPage.fromWire(
          withFields({
            'logs': gate([json, loose]),
          }),
          site,
        ),
        (page) => page.logs.isNotEmpty,
      );
      probe(
        'GroupMembershipMutationResult',
        () => GroupMembershipMutationResult.fromWire(
          withFields({
            'usernames': gate([loose, json]),
          }),
        ),
        (result) => result.usernames.isNotEmpty,
      );
      probe(
        'GroupInvite',
        () => GroupInvite.fromWire(withFields({'id': loose})),
        (invite) =>
            invite.id != 0 || invite.link != null || invite.email != null,
      );
      probe(
        'Topic',
        () => Topic.fromJson(withFields({'id': loose}), const {}, site),
        (topic) =>
            topic.id != 0 || topic.title.isNotEmpty || topic.slug.isNotEmpty,
      );
      probe(
        'Topic.fromRecommendationJson',
        () => Topic.fromRecommendationJson(
          withFields({
            'posters': gate([
              json,
              loose,
              withFields({
                'user_id': 1,
                'user': withFields({'id': 1, 'avatar_template': loose}),
              }),
            ]),
          }),
          site,
        ),
        (topic) => topic.posterAvatars.isNotEmpty,
      );
      probe(
        'TopicParticipant',
        () => TopicParticipant.fromJson(withFields({'username': loose}), site),
        (participant) => participant != null,
      );
      probe(
        'TopicMapLink',
        () => TopicMapLink.fromJson(withFields({'url': loose})),
        (link) => link != null,
      );
      probe(
        'TopicDetail',
        () => TopicDetail.parse(
          withFields({
            'post_stream': gate(
              withFields({
                'posts': [json, loose],
              }),
            ),
          }),
          site,
        ),
        (payload) => payload.posts.isNotEmpty,
      );
      probe(
        'TopicList',
        () => TopicList.fromJson(
          withFields({
            'topic_list': gate(
              withFields({
                'topics': [json, loose],
                'categories': [json, loose],
              }),
            ),
            'users': gate([json, loose]),
          }),
          site,
        ),
        (list) => list.topics.isNotEmpty && list.categories.isNotEmpty,
      );
      probe(
        'TopicRecommendations',
        () => TopicRecommendations.fromJson(
          withFields({
            'suggested_topics': gate([json, loose]),
          }),
          site,
        ),
        (recommendations) =>
            recommendations != null &&
            recommendations.sources.any((source) => source.topics.isNotEmpty),
      );
      probe(
        'CategoryFeaturedTopic',
        () => CategoryFeaturedTopic.fromJson(withFields({'id': loose})),
        (topic) =>
            topic.id != 0 || topic.title.isNotEmpty || topic.slug.isNotEmpty,
      );
      probe(
        'TopicCategory',
        () => TopicCategory.fromJson(
          withFields({
            'topics': gate([
              json,
              loose,
              withFields({'id': 1}),
            ]),
          }),
        ),
        (category) => category.featuredTopics.isNotEmpty,
      );
      probe(
        'TopicTrackingState',
        () => TopicTrackingState.fromJson(
          gate([
            json,
            loose,
            withFields({'topic_id': 1}),
          ]),
        ),
        (state) => state.topics.isNotEmpty,
      );
      probe(
        'TrackedTopicState',
        () => TrackedTopicState.fromJson(withFields({'topic_id': gate(1)})),
        (state) => state != null,
      );
      probe(
        'TrackedTopicState.fromMessage',
        () => TrackedTopicState.fromMessage(
          topicId: 1,
          payload: withFields({'highest_post_number': loose}),
          previous: run.isEven
              ? null
              : TrackedTopicState.fromJson(withFields({'topic_id': 1})),
          unread: run % 4 < 2,
        ),
        (state) =>
            state.highestPostNumber > 0 ||
            state.lastReadPostNumber != null ||
            state.categoryId != null ||
            state.tagIds.isNotEmpty,
      );
      probe(
        'TopicComposerCapabilities',
        () => TopicComposerCapabilities.fromJson(
          withFields({'max_tag_length': loose}),
        ),
        (capabilities) => capabilities.maxTagLength != null,
      );
      probe(
        'TopicTagSearch',
        () => TopicTagSearch.fromJson(
          withFields({
            'results': gate([
              json,
              loose,
              withFields({'name': 'n'}),
            ]),
          }),
        ),
        (search) => search.tags.isNotEmpty,
      );
      probe(
        'TopicUpdate',
        () => TopicUpdate.fromJson(
          withFields({
            'basic_topic': gate(withFields({'title': loose})),
          }),
        ),
        (update) => update.title != null,
      );
      probe(
        'TopicTag',
        () => TopicTag.parse(gate(withFields({'name': loose}))),
        (tag) => tag != null,
      );
      probe(
        'SidebarTag',
        () => SidebarTag.fromJson(gate(withFields({'id': 1, 'name': loose}))),
        (tag) => tag != null,
      );
      probe(
        'SidebarSection',
        () => SidebarSection.customFromJson(
          withFields({
            'section_type': gate(null),
            'title': gate('t'),
            'links': gate([
              json,
              loose,
              withFields({'name': 'n', 'value': 'v'}),
            ]),
          }),
          index: 0,
        ),
        (section) => section != null && section.destinations.isNotEmpty,
      );
      probe(
        'CategoryNotificationLevel',
        () => CategoryNotificationLevel.fromJson(loose),
        (level) => level != CategoryNotificationLevel.normal,
      );
      probe(
        'TopicNotificationLevel',
        () => TopicNotificationLevel.fromJson(loose),
        (level) => level != TopicNotificationLevel.normal,
      );
      probe(
        'DiscoverSite',
        () => DiscoverSite.tryParse(
          withFields({
            'featured_link': gate(site),
            'title': loose,
            'discover_entry_logo_url': loose,
          }),
        ),
        (discovered) => discovered != null,
      );

      probe(
        'ChatUser',
        () => ChatUser.fromJson(withFields({'id': loose}), site),
        (user) => user.id != 0 || user.username.isNotEmpty || user.name != null,
      );
      probe(
        'ChatMembership',
        () => ChatMembership.fromJson(
          gate(withFields({'last_read_message_id': loose})),
        ),
        (membership) => membership.lastReadMessageId != null,
      );
      probe(
        'ChatTracking',
        () => ChatTracking.fromJson(withFields({'unread_count': loose})),
        (tracking) => tracking.unreadCount != 0,
      );
      probe(
        'ChatPresence',
        () => ChatPresence.fromJson(
          gate(
            withFields({
              'users': [
                json,
                loose,
                withFields({'id': 1}),
              ],
            }),
          ),
        ),
        (presence) => presence.userIds.isNotEmpty,
      );
      probe(
        'ChatChannelMessageBusState',
        () => ChatChannelMessageBusState.fromJson(
          gate(withFields({'new_messages': loose})),
        ),
        (state) => state.newMessages != null,
      );
      probe(
        'ChatChannel',
        () => ChatChannel.fromJson(withFields({'id': loose}), site),
        (channel) =>
            channel.id != 0 || channel.title.isNotEmpty || channel.slug != null,
      );
      probe(
        'ChatChannel.parse',
        () => ChatChannel.parse(
          withFields({
            'public_channels': gate([json, loose]),
            'direct_message_channels': gate([json, loose]),
          }),
          site,
        ),
        (channels) => channels.public.isNotEmpty && channels.direct.isNotEmpty,
      );
      probe(
        'ChatDirectMessageUser',
        () => ChatDirectMessageUser.fromJson(
          withFields({
            'model': gate(withFields({'username': loose})),
          }),
          site,
        ),
        (user) => user.username.isNotEmpty,
      );
      probe(
        'ChatDirectMessageChannel',
        () => ChatDirectMessageChannel.fromJson(
          withFields({
            'model': gate(withFields({'id': 1})),
          }),
          site,
        ),
        (channel) => channel.channel.id > 0,
      );
      probe(
        'ChatDirectMessageGroup',
        () => ChatDirectMessageGroup.fromJson(
          withFields({
            'model': gate(withFields({'name': loose})),
          }),
        ),
        (group) => group.name.isNotEmpty,
      );
      probe(
        'ChatDirectMessageSearchResults',
        () => ChatDirectMessageSearchResults.fromJson(
          withFields({
            'users': gate([
              json,
              loose,
              withFields({
                'model': withFields({'username': 'u'}),
              }),
            ]),
            'direct_message_channels': gate([json, loose]),
            'category_channels': gate([json, loose]),
            'groups': gate([json, loose]),
          }),
          site,
        ),
        (results) => results.items.isNotEmpty,
      );
      probe(
        'ChatChannelBrowsePage',
        () => ChatChannelBrowsePage.fromJson(
          withFields({
            'channels': gate([json, loose]),
          }),
          site,
        ),
        (page) => page.channels.isNotEmpty,
      );
      probe(
        'ChatMessageAuthor',
        () => ChatMessageAuthor.fromJson(gate(withFields({'id': loose})), site),
        (author) =>
            author.id != 0 || author.username.isNotEmpty || author.name != null,
      );
      probe(
        'ChatReaction',
        () => ChatReaction.fromJson(withFields({'emoji': loose})),
        (reaction) =>
            reaction.emoji.isNotEmpty ||
            reaction.count != 0 ||
            reaction.reactorIds.isNotEmpty,
      );
      probe(
        'UserFlair',
        () => UserFlair.fromJson(
          gate(withFields({'flair_group_id': 1, 'flair_bg_color': loose})),
          site,
        ),
        (flair) => flair != null,
      );
      probe(
        'ChatUpload',
        () => ChatUpload.fromJson(withFields({'id': loose})),
        (upload) => upload.id != 0 || upload.url.isNotEmpty,
      );
      probe(
        'ChatReplyTo',
        () => ChatReplyTo.fromJson(withFields({'id': loose}), site),
        (reply) =>
            reply.id != 0 ||
            reply.excerpt.isNotEmpty ||
            reply.username.isNotEmpty,
      );
      probe(
        'ChatThreadPreview',
        () => ChatThreadPreview.fromJson(
          gate(
            withFields({
              'preview': withFields({
                'participant_users': [json, loose],
              }),
            }),
          ),
          site,
        ),
        (preview) => preview != null && preview.participantUsers.isNotEmpty,
      );
      probe(
        'ChatMessage',
        () => ChatMessage.fromJson(withFields({'id': loose}), site),
        (message) =>
            message.id != 0 ||
            message.cooked.isNotEmpty ||
            message.raw.isNotEmpty,
      );
      probe(
        'ChatMessage.parsePage',
        () => ChatMessage.parsePage(
          withFields({
            'messages': gate([json, loose]),
          }),
          site,
        ),
        (page) => page.messages.isNotEmpty,
      );
      probe(
        'ChatPin',
        () => ChatPin.fromJson(withFields({'id': loose}), site),
        (pin) => pin.id != 0 || pin.excerpt.isNotEmpty,
      );
      probe(
        'ChatPin.parse',
        () => ChatPin.parse(
          withFields({
            'pinned_messages': gate([json, loose]),
            'membership': gate(json),
          }),
          site,
        ),
        (pins) => pins.pins.isNotEmpty && pins.membership != null,
      );
      probe(
        'ChatSearchPage',
        () => ChatSearchPage.fromJson(
          withFields({
            'messages': gate([
              json,
              loose,
              withFields({
                'id': 1,
                'chat_channel_id': 1,
                'channel': withFields({'id': 1}),
              }),
            ]),
          }),
          site,
        ),
        (page) => page.hits.isNotEmpty,
      );
      probe(
        'ChatThreadMembership',
        () => ChatThreadMembership.fromJson(
          gate(withFields({'last_read_message_id': loose})),
        ),
        (membership) => membership?.lastReadMessageId != null,
      );
      probe(
        'ChatThreadOriginalMessage',
        () => ChatThreadOriginalMessage.fromJson(
          gate(withFields({'id': loose})),
          site,
        ),
        (message) =>
            message != null &&
            (message.id != 0 ||
                message.cooked != null ||
                message.excerpt != null),
      );
      probe(
        'ChatThread',
        () => ChatThread.fromJson(withFields({'id': loose}), site),
        (thread) =>
            thread.id != 0 || thread.title != null || thread.replyCount != 0,
      );
      probe(
        'ChatThreadPage',
        () => ChatThreadPage.fromJson(
          withFields({
            'threads': gate([
              json,
              loose,
              withFields({
                'id': 1,
                'channel_id': 1,
                'channel': withFields({'id': 1}),
              }),
            ]),
          }),
          site,
        ),
        (page) => page.threads.isNotEmpty && page.channels.isNotEmpty,
      );
      probe(
        'ChatThreadNotificationLevel',
        () => ChatThreadNotificationLevel.fromJson(loose),
        (level) => level != ChatThreadNotificationLevel.normal,
      );

      probe(
        'AssignmentSuggestions',
        () => AssignmentSuggestions.fromJson(
          withFields({
            'suggestions': gate([
              json,
              loose,
              withFields({'username': 'u'}),
            ]),
            'assign_allowed_on_groups': gate([loose, 'g']),
          }),
          site,
        ),
        (suggestions) => suggestions.users.isNotEmpty,
      );
      probe(
        'Assignments.fromTopicJson',
        () => Assignments.fromTopicJson(
          withFields({
            'indirectly_assigned_to': gate({
              '1': withFields({
                'assigned_to': withFields({'username': 'u'}),
              }),
            }),
          }),
          site,
        ),
        (assignments) =>
            assignments != null && assignments.postAssignments.isNotEmpty,
      );
      probe(
        'Assignments.fromPostJson',
        () => Assignments.fromPostJson(
          withFields({
            'assigned_to_user': gate(withFields({'username': 'u'})),
          }),
          site,
        ),
        (assignments) => assignments?.direct != null,
      );
      probe(
        'GifCategory',
        () => GifCategory.fromJson(
          withFields({
            'name': 'n',
            'image': gate('$site/a.gif'),
            'searchterm': loose,
          }),
        ),
        (category) => category != null,
      );
      final gif = withFields({
        'media_formats': {
          'gif': withFields({
            'url': gate('$site/a.gif'),
            'dims': [1, 1],
          }),
        },
      });
      probe(
        'GifResult',
        () => GifResult.fromJson(gif, fileDetail: 'gif'),
        (result) => result != null,
      );
      probe(
        'GifSearchPage',
        () => GifSearchPage.fromJson(
          withFields({
            'results': gate([json, loose, gif]),
          }),
          fileDetail: 'gif',
        ),
        (page) => page.results.isNotEmpty,
      );
      probe(
        'PollOption',
        () => PollOption.fromJson(gate(withFields({'id': 'o', 'html': loose}))),
        (option) => option != null,
      );
      probe('PollSelection', () {
        PollSelection.fromJson(gate([loose, 'o']), type: PollType.regular);
        return PollSelection.fromJson(
          gate([
            json,
            loose,
            withFields({'digest': 'd', 'rank': loose}),
          ]),
          type: PollType.rankedChoice,
        );
      }, (selection) => selection.rankedChoices.isNotEmpty);
      probe(
        'PollType',
        () => PollType.fromValue(loose),
        (type) => type != PollType.regular,
      );
      probe(
        'PollStatus',
        () => PollStatus.fromValue(loose),
        (status) => status != PollStatus.open,
      );
      probe(
        'PollResults',
        () => PollResults.fromValue(loose),
        (results) => results != PollResults.always,
      );
      probe(
        'PollChartType',
        () => PollChartType.fromValue(loose),
        (chart) => chart != PollChartType.bar,
      );
      probe(
        'PollRankedCandidate',
        () => PollRankedCandidate.fromJson(
          gate(withFields({'digest': 'd', 'html': loose})),
        ),
        (candidate) => candidate != null,
      );
      probe(
        'PollRankedRound',
        () => PollRankedRound.fromJson(
          gate(
            withFields({
              'round': 1,
              'eliminated': [
                json,
                loose,
                withFields({'digest': 'd', 'html': loose}),
              ],
            }),
          ),
        ),
        (round) => round != null && round.eliminated.isNotEmpty,
      );
      probe(
        'RankedChoiceOutcome',
        () => RankedChoiceOutcome.fromJson(
          gate(
            withFields({
              'round_activity': [
                json,
                loose,
                withFields({'round': 1}),
              ],
            }),
          ),
        ),
        (outcome) => outcome != null && outcome.rounds.isNotEmpty,
      );
      probe(
        'PollClosedBy',
        () => PollClosedBy.fromJson(
          gate(withFields({'id': 1, 'username': loose})),
          site,
        ),
        (closedBy) => closedBy != null,
      );
      probe(
        'Poll',
        () => Poll.fromJson(
          gate(
            withFields({
              'name': 'p',
              'options': [
                json,
                loose,
                withFields({'id': 'o', 'html': loose}),
              ],
            }),
          ),
          site,
          selection: loose,
        ),
        (poll) => poll != null && poll.options.isNotEmpty,
      );
      probe(
        'Polls',
        () => Polls.fromJson(
          withFields({
            'polls': gate([
              json,
              loose,
              withFields({'name': 'p'}),
            ]),
          }),
          site,
        ),
        (polls) => polls != null && polls.byName.isNotEmpty,
      );
      probe(
        'PostReactor',
        () => PostReactor.fromJson(withFields({'id': loose}), site),
        (reactor) =>
            reactor.id != 0 ||
            reactor.username.isNotEmpty ||
            reactor.name != null,
      );
      probe(
        'PostReactors',
        () => PostReactors.parse(
          withFields({
            'users': gate([json, loose]),
          }),
          postId: 1,
          siteUrl: site,
        ),
        (reactors) => reactors.reactors.isNotEmpty,
      );
      probe(
        'ChatReactor',
        () => ChatReactor.fromJson(withFields({'id': loose}), site),
        (reactor) =>
            reactor.id != 0 ||
            reactor.username.isNotEmpty ||
            reactor.name != null,
      );
      probe(
        'ChatMessageReactors',
        () => ChatMessageReactors.parse(
          withFields({
            'users': gate([json, loose]),
          }),
          channelId: 1,
          messageId: 1,
          siteUrl: site,
        ),
        (reactors) => reactors.reactors.isNotEmpty,
      );
      probe(
        'Reaction',
        () => Reaction.fromJson(gate(withFields({'id': loose}))),
        (reaction) => reaction != null,
      );
      probe(
        'Reactions',
        () => Reactions.fromJson(
          withFields({
            'reactions': gate([
              json,
              loose,
              withFields({'id': 'r'}),
            ]),
          }),
        ),
        (reactions) => reactions != null && reactions.entries.isNotEmpty,
      );

      probe(
        'AiSummaryAvailability',
        () => AiSummaryAvailability.fromJson(
          run.isEven ? withFields({'summarizable': loose}) : json,
        ),
        (availability) => availability != null,
      );
      probe(
        'AiTopicSummary',
        () => AiTopicSummary.fromJson(
          withFields({
            'ai_topic_summary': gate(withFields({'summarized_text': loose})),
          }),
        ),
        (summary) => summary != null,
      );
      probe(
        'AiSummaryStreamFailure',
        () =>
            AiSummaryStreamFailure.fromJson(withFields({'error_type': loose})),
        (failure) => failure != null,
      );
      probe(
        'DiscourseAiSettings',
        () => DiscourseAiSettings.fromWire(
          withFields({'discourse_ai_enabled': loose}),
        ),
        (settings) => settings.enabled,
      );
      probe('DiscourseAiCurrentUser', () {
        DiscourseAiCurrentUser.fromWire(json);
        return DiscourseAiCurrentUser.fromWire(
          withFields({'can_use_assistant': loose}),
        );
      }, (user) => user?.canUseAssistant == true);

      probe(
        'EventSettings',
        () => EventSettings.decode(
          withFields({'discourse_events_enabled': loose}),
        ),
        (settings) => settings.eventsEnabled,
      );
      probe(
        'EventUserPermissions',
        () => EventUserPermissions.decode(
          withFields({'can_create_discourse_post_event': loose}),
        ),
        (permissions) => permissions != null,
      );
      probe(
        'PostEvent',
        () => PostEvent.decode(gate(withFields({'id': 1})), topicId: 1),
        (event) => event != null,
      );
      probe(
        'EventPerson',
        () => EventPerson.decode(gate(withFields({'username': loose}))),
        (person) => person != null,
      );
      probe(
        'EventInvitee',
        () => EventInvitee.decode(
          gate(
            withFields({
              'user': withFields({'username': 'u'}),
            }),
          ),
        ),
        (invitee) => invitee != null,
      );
      probe(
        'EventPostData',
        () => EventPostData.decode(
          withFields({
            'event': gate(withFields({'id': 1})),
            'event_oneboxes': gate({
              '1': loose,
              '2': withFields({'id': 2}),
            }),
          }),
        ),
        (data) => data?.event != null,
      );
      probe(
        'EventTopicData',
        () => EventTopicData.decode(withFields({'event_starts_at': loose})),
        (data) => data != null,
      );
      probe(
        'TopicCalendarData',
        () => TopicCalendarData.decode(
          withFields({
            'post_number': gate(1),
            'topic_id': gate(1),
            'calendar_details': gate([json, loose]),
          }),
        ),
        (calendar) => calendar != null && calendar.details.isNotEmpty,
      );
      probe(
        'TopicCalendarSettings',
        () => TopicCalendarSettings.decode(
          withFields({'calendar_first_day_of_week': loose}),
        ),
        (settings) => settings.firstDay != 1,
      );
      probe(
        'AlertData',
        () => AlertData.decode(
          withFields({
            'alert_data': gate([
              json,
              loose,
              withFields({'status': 'firing'}),
            ]),
          }),
        ),
        (data) => data != null && data.alerts.isNotEmpty,
      );
      probe(
        'PrometheusAlert',
        () => PrometheusAlert.decode(gate(withFields({'status': 'stale'}))),
        (alert) => alert != null,
      );
      probe(
        'AlertLinkSettings',
        () => AlertLinkSettings.decode(
          withFields({'prometheus_alert_receiver_grafana_regex': loose}),
        ),
        (settings) => settings.grafana.isNotEmpty,
      );

      probe(
        'VoiceClientConfig',
        () => VoiceClientConfig.fromJson(withFields({'enabled': loose})),
        (config) => config.enabled,
      );
      probe(
        'VoiceClientConfig.fromSettings',
        () => VoiceClientConfig.fromSettings(
          withFields({'voice_enabled': loose}),
        ),
        (config) => config.enabled,
      );
      probe(
        'VoiceAgentPermission',
        () => VoiceAgentPermission.read(
          withFields({'voice_livekit_agent_bot_id': loose}),
        ),
        (permission) => permission.botId != null,
      );
      probe(
        'VoiceDiagnosticRecord',
        () => VoiceDiagnosticRecord.fromJson(
          gate(
            withFields({
              'sequence': 1,
              'timestampUtc': '2020-01-01T00:00:00Z',
              'captureId': 'c',
              'event': 'e',
              'component': 'x',
              'severity': DiagnosticSeverity.info.name,
              'message': loose,
              'data': {'value': loose},
              'truncated': false,
            }),
          ),
        ),
        (record) => record != null,
      );
      probe(
        'VoiceParticipant',
        () => VoiceParticipant.fromJson(withFields({'id': loose})),
        (participant) =>
            participant.id != 0 ||
            participant.username.isNotEmpty ||
            participant.name != null,
      );
      probe(
        'VoiceMembership',
        () => VoiceMembership.fromJson(withFields({'id': loose})),
        (membership) =>
            membership.id != 0 ||
            membership.userId != 0 ||
            membership.user != null,
      );
      probe(
        'VoiceRecording',
        () => VoiceRecording.fromJson(withFields({'active': loose})),
        (recording) =>
            !recording.active ||
            recording.startedAt != null ||
            recording.startedById != null,
      );
      probe(
        'VoiceRingingEntry',
        () => VoiceRingingEntry.fromJson(
          withFields({
            'user': gate(withFields({'id': 1})),
            'notified_at': gate('2020-01-01T00:00:00Z'),
          }),
        ),
        (entry) => entry != null,
      );
      probe(
        'VoiceIncomingCall',
        () => VoiceIncomingCall.fromJson(
          withFields({
            'room_id': gate(1),
            'room_slug': gate('s'),
            'caller_username': loose,
            'sent_at': gate('2020-01-01T00:00:00Z'),
          }),
        ),
        (call) => call != null,
      );
      probe(
        'VoiceInviteResult',
        () => VoiceInviteResult.fromJson(
          withFields({
            'invited_usernames': gate([loose, json]),
          }),
        ),
        (result) => result.invitedUsernames.isNotEmpty,
      );
      probe(
        'VoiceInviteSuggestion',
        () => VoiceInviteSuggestion.fromJson(
          withFields({'id': gate(1), 'username': loose}),
        ),
        (suggestion) => suggestion != null,
      );
      probe(
        'VoiceRoom',
        () => VoiceRoom.fromJson(withFields({'slug': loose})),
        (room) => room.id != 0 || room.slug.isNotEmpty,
      );
      probe(
        'VoiceDirectory',
        () => VoiceDirectory.fromJson(
          withFields({
            'rooms': gate([json, loose]),
          }),
        ),
        (directory) => directory.rooms.isNotEmpty,
      );
      probe(
        'VoiceIceServer',
        () => VoiceIceServer.fromJson(withFields({'urls': loose})),
        (server) => server.urls.isNotEmpty || server.username != null,
      );
      probe(
        'VoiceIceConfiguration',
        () => VoiceIceConfiguration.fromJson(
          withFields({
            'servers': gate([json, loose]),
          }),
        ),
        (configuration) => configuration.servers.isNotEmpty,
      );
      probe(
        'VoiceLiveKitCredentials',
        () => VoiceLiveKitCredentials.fromJson(withFields({'url': loose})),
        (credentials) => credentials.url.isNotEmpty,
      );
      probe(
        'VoiceJoinResponse',
        () => VoiceJoinResponse.fromJson(
          withFields({
            'transport': gate('mesh'),
            'room': run % 3 == 0 ? loose : withFields({'_corpus_probe': true}),
            'ice': json,
            'livekit': json,
          }),
        ),
        (response) => response.livekit != null,
      );
      probe(
        'VoiceChatSession',
        () => VoiceChatSession.fromJson(withFields({'channel_id': loose})),
        (session) => session.channelId != null || session.threadId != null,
      );
      probe(
        'VoiceRoomEvent',
        () => VoiceRoomEvent.fromJson(
          withFields({
            'type': gate(
              const [
                'participants',
                'kicked',
                'role_change',
                'hand_raise',
                'ringing',
                'recording',
              ][run ~/ 2 % 6],
            ),
          }),
        ),
        (event) => event != null,
      );

      probe(
        'TopicLink',
        () => TopicLink.parse(run.isEven ? '/t/$loose/1' : '$loose'),
        (link) => link != null,
      );
      probe(
        'BadgeRoute',
        () => BadgeRoute.parse(
          run.isEven ? '/badges/$loose' : '$loose',
          siteUrl: site,
        ),
        (route) => route != null,
      );
      probe(
        'ListLink',
        () => ListLink.parse(run.isEven ? '/c/$loose/1' : '$loose'),
        (link) => link != null,
      );
    }

    expect(failures.values, isEmpty);
    expect(
      probed.difference(produced),
      isEmpty,
      reason:
          'the corpus never took these past their default: give _keys the '
          'fields they read, or give the probe the rows they keep',
    );
    expect(
      _rejectsOnPurpose.keys.toSet().difference(rejected),
      isEmpty,
      reason:
          'these no longer reject anything: drop them from '
          '_rejectsOnPurpose',
    );
    expect(reachedShapes, {
      'null',
      'boolean',
      'integer',
      'double',
      'empty string',
      'non-empty string',
      'empty list',
      'non-empty list',
      'empty object',
      'non-empty object',
      'list with nested collection',
      'object with nested collection',
    }, reason: 'the fixed-seed corpus must reach every intended JSON shape');
  });
  test('every parser that reads a payload is in the corpus', () {
    // A class name covers each of its parsers; `Class.member` covers one.
    const notSitePayloads = {
      // This app's own storage. Their callers are written around the throw:
      // `InstanceStore` catches per entry so one damaged site cannot erase
      // the rail, and a workspace with an unreadable anchor keeps its tabs.
      'ContentRoute',
      'GroupRoute',
      'BadgeRoute',
      'DiscourseInstance',
      'DiscourseUser',
      'ForumTabAnchor',
      // This app's own storage, read back by codecs that answer null or a
      // default for a value they cannot read.
      'AggregateTabPreferences',
      'ForumTab',
      'ForumTabLocation',
      'ForumWorkspace',
      '_RecentDestinations',
      'ChatCurrentUser.fromStored',
      'ChatSettings.fromStored',
      'GifsSettings.fromStored',
      'LocalDatesSettings.fromStored',
      'ReactionsSettings.fromStored',
      'NotificationTotals.fromStoredJson',
      'UserStatus.fromStoredJson',
      'PluginNotificationCounters.fromStored',
      // Local theme imports, preferences and the draft file validate their own
      // versioned format.
      '_DraftFileState',
      'ForumBackground',
      'ForumTheme',
      'ForumThemePreferences',
      'SharedAppearance',
      'ResolvedSitePalette',
      'ComposerLayoutPreference',
      // UI questionnaire drafts serialize local answers, not site payloads.
      'DQuestionnaireAnswer',
      'DQuestionnaireSavedState',
      // The diagram renderer's own reply, posted by the page this app loads.
      '_MermaidImage',
      // The diagnostics store reading back what it wrote.
      'DiagnosticEvent',
      'DiagnosticLogEvent',
      'DiagnosticRedirect',
      'DiagnosticSessionEvent',
      'ErrorDiagnosticEvent',
      'HttpDiagnosticEvent',
      '_CommonFields',
      // Scrubs a diagnostics map on its way out; it reads no payload.
      'VoiceDiagnosticsRedactor',
    };

    // A parser is a factory or static member of a class that is named
    // `fromJson`, that takes a JSON map, or that is named like a parser and
    // takes an untyped value. An enum's parser maps one scalar onto its own
    // cases; the payload parser that holds the scalar is what gets probed.
    final declaration = RegExp(
      r'^[ \t]*(?:@\w+\s+)*'
      r'(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
      r'(class|enum|mixin|extension(?:\s+type)?)\s+(\w+)',
      multiLine: true,
    );
    final member = RegExp(
      r'\bfactory\s+\w+\.(\w+)\s*\(|\bstatic\s+[\w<>?,.\s]*?\b(\w+)\s*\(',
    );
    final jsonMap = RegExp(r'Map<String,\s*(?:dynamic|Object\?)>');
    final untyped = RegExp(
      r'(?:^|[(,{\s])(?:required\s+)?(?:Object\?|dynamic)\s+\w+\s*[,)}=]',
    );
    final parserName = RegExp(
      r'^(?:from[A-Z]\w*|parse\w*|decode\w*|try[A-Z]\w*)$',
    );
    final declaring = <String, String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final declarations = declaration.allMatches(source).toList();
      for (final match in member.allMatches(source)) {
        final name = match.group(1) ?? match.group(2)!;
        if (name.startsWith('_')) continue;
        RegExpMatch? enclosing;
        for (final candidate in declarations) {
          if (candidate.start > match.start) break;
          enclosing = candidate;
        }
        if (enclosing == null || enclosing.group(1) == 'enum') continue;
        final parameters = _parameters(source, match.end - 1);
        if (name == 'fromJson' ||
            jsonMap.hasMatch(parameters) ||
            (parserName.hasMatch(name) && untyped.hasMatch(parameters))) {
          declaring.putIfAbsent(
            '${enclosing.group(2)}.$name',
            () => entity.path,
          );
        }
      }
    }
    // The scan is a heuristic over source text, so a corpus it stopped finding
    // parsers in would pass while checking nothing.
    expect(declaring.length, greaterThan(150));

    final called = {
      for (final match in RegExp(r'\b(\w+)\.(\w+)\s*\(').allMatches(
        File('test/wire_payload_totality_test.dart').readAsStringSync(),
      ))
        '${match.group(1)}.${match.group(2)}',
    };
    final unaccounted = {
      for (final entry in declaring.entries)
        if (!called.contains(entry.key) &&
            !notSitePayloads.contains(entry.key) &&
            !notSitePayloads.contains(entry.key.split('.').first))
          entry.key: entry.value,
    };
    expect(
      unaccounted,
      isEmpty,
      reason: 'add these to the probes above, or to notSitePayloads with why',
    );

    expect(
      notSitePayloads.difference({
        ...declaring.keys,
        for (final key in declaring.keys) key.split('.').first,
      }),
      isEmpty,
      reason: 'these no longer declare a parser',
    );
  });
}
