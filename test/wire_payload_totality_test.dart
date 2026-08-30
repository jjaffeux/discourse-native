import 'dart:io';
import 'dart:math';

import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/post_revision.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/models/topic_link.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/plugins/assign/assign_data.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_data.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keys taken from the payloads these parsers actually read, so the generator
/// spends its budget on fields with code behind them rather than on names
/// nothing looks up.
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
  'archetype',
  'site_settings',
  'primary_group_name',
  'flair_url',
  'chat_notifications',
  'ignored_users',
  'topic_tracking',
  'unread_notifications',
  'type',
  'ref',
  'relative_url',
  'description',
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
  'user_summary',
  'topic_ids',
  'most_liked_by_users',
  'most_liked_users',
  'most_replied_to_users',
  'top_categories',
  'badge_id',
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
];

Object? _value(Random random, int depth) => switch (random.nextInt(
  depth > 2 ? 8 : 11,
)) {
  0 => null,
  1 => random.nextBool(),
  2 => random.nextInt(1 << 32) - (1 << 31),
  3 => random.nextDouble() * 1e9,
  4 => '',
  5 => _keys[random.nextInt(_keys.length)],
  6 => '9' * (random.nextInt(40) + 1),
  7 => const [
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
  8 => [for (var i = random.nextInt(3); i > 0; i--) _value(random, depth + 1)],
  9 => _object(random, depth + 1),
  _ => <String, dynamic>{},
};

Map<String, dynamic> _object(Random random, int depth) => {
  for (var i = random.nextInt(6); i > 0; i--)
    _keys[random.nextInt(_keys.length)]: _value(random, depth),
};

void main() {
  // `json.dart` states the rule the whole model layer is written to: "Every
  // parser answers that with a default rather than a throw — a field the site
  // did not send is a field left at its default." Nothing pinned it, and a
  // parser that throws does not degrade one field, it takes down whatever
  // screen was reading the payload.
  //
  // Deliberately absent, because they read this app's own storage rather than
  // a site and their callers are written around the throw: `ContentRoute`,
  // `ForumTabAnchor` and `ResolvedSitePalette` raise FormatException on an
  // unusable record, and `DiscourseInstance`/`DiscourseUser` cast, which
  // `InstanceStore` catches per entry so one damaged site cannot erase the
  // rail. `ResenhaJoinResponse` is the one wire parser that joins them: a join
  // answered with a transport this client cannot speak is a failed join rather
  // than a degraded one, and `ResenhaController` turns the throw into the
  // call's error state.
  test('no wire parser throws on a payload it did not expect', () {
    final random = Random(20260823);
    const site = 'https://example.com';
    final failures = <String, String>{};

    void probe(String label, void Function() body, Object? json) {
      try {
        body();
      } catch (error) {
        failures.putIfAbsent(label, () => '$label threw $error on $json');
      }
    }

    for (var run = 0; run < 4000; run++) {
      final json = _object(random, 0);
      final loose = _value(random, 0);

      probe('Bookmark', () => Bookmark.fromJson(json), json);
      probe('ComposerDraft', () => ComposerDraft.fromJson(json), json);
      probe('FoundGroup', () => FoundGroup.fromJson(json, site), json);
      probe('FoundHashtag', () => FoundHashtag.fromJson(json), json);
      probe('FoundUser', () => FoundUser.fromJson(json, site), json);
      probe(
        'DiscourseNotification',
        () => DiscourseNotification.fromJson(json),
        json,
      );
      probe(
        'NotificationTotals',
        () => NotificationTotals.fromJson(json),
        json,
      );
      probe('Post', () => Post.fromJson(json, site), json);
      probe('PostNotice', () => PostNotice.fromJson(loose), loose);
      probe('PostInboundLink', () => PostInboundLink.fromJson(json), json);
      probe(
        'PostRevisionChange',
        () => PostRevisionChange.fromJson(
          loose,
          (value) => value is String ? value : null,
        ),
        loose,
      );
      probe('PostRevisionDiff', () => PostRevisionDiff.fromJson(loose), loose);
      probe(
        'PostRevisionUser',
        () => PostRevisionUser.fromJson(loose, site),
        loose,
      );
      probe(
        'PostRevisionReplyTarget',
        () => PostRevisionReplyTarget.fromJson(loose),
        loose,
      );
      probe('PostRevision', () => PostRevision.fromJson(json, site), json);
      probe('PostCreation', () => PostCreation.fromJson(json, site), json);
      probe(
        'SitePostActionCatalog',
        () => SitePostActionCatalog.fromJson(json),
        json,
      );
      probe('PostActionSummary', () => PostActionSummary.fromJson(json), json);
      probe('PostLiker', () => PostLiker.fromJson(json, site), json);
      probe('SearchResults', () => SearchResults.fromJson(json, site), json);
      probe('SearchCategoryHit', () => SearchCategoryHit.fromJson(json), json);
      probe('SearchTagHit', () => SearchTagHit.fromJson(json), json);
      probe('SearchUserHit', () => SearchUserHit.fromJson(json, site), json);
      probe('SearchGroupHit', () => SearchGroupHit.fromJson(json, site), json);
      probe('SiteAppearance', () => SiteAppearance.fromJson(json), json);
      probe('SiteConfig', () => SiteConfig.fromJson(json), json);
      probe('AssignSettings', () => AssignSettings.fromWire(json), json);
      probe('AssignCurrentUser', () => AssignCurrentUser.fromWire(json), json);
      probe(
        'AssignedGroupMember',
        () => AssignedGroupMember.fromJson(json, site),
        json,
      );
      probe(
        'AssignedGroupMembersPage',
        () =>
            AssignedGroupMembersPage.fromJson(json, site, offset: 0, limit: 50),
        json,
      );
      probe('ChatSettings', () => ChatSettings.fromSettings(json), json);
      probe(
        'ChatCurrentUser',
        () => ChatCurrentUser.fromCurrentUser(json),
        json,
      );
      probe('GifsSettings', () => GifsSettings.fromSiteSettings(json), json);
      probe(
        'LocalDatesSettings',
        () => LocalDatesSettings.fromSiteSettings(json),
        json,
      );
      probe('PollSettings', () => PollSettings.fromWire(json), json);
      probe('PollCurrentUser', () => PollCurrentUser.fromWire(json), json);
      probe(
        'ReactionsSettings',
        () => ReactionsSettings.fromSiteSettings(json),
        json,
      );
      probe(
        'TopicFilterModifier',
        () => TopicFilterModifier.fromJson(json),
        json,
      );
      probe('UserCard', () => UserCard.fromJson(json, site), json);
      probe(
        'UserActivityItem',
        () => UserActivityItem.fromJson(json, site),
        json,
      );
      probe(
        'UserActivityPage',
        () => UserActivityPage.fromJson(json, site),
        json,
      );
      probe('UserDraft', () => UserDraft.fromJson(json), json);
      probe('UserPreferences', () => UserPreferences.fromJson(json), json);
      probe('UserStatus', () => UserStatus.fromJson(json), json);
      probe('UserSummary', () => UserSummary.fromJson(json, site), json);
      probe('Topic', () => Topic.fromJson(json, const {}, site), json);
      probe(
        'TopicParticipant',
        () => TopicParticipant.fromJson(json, site),
        json,
      );
      probe('TopicMapLink', () => TopicMapLink.fromJson(json), json);
      probe('TopicDetail', () => TopicDetail.parse(json, site), json);
      probe('TopicList', () => TopicList.fromJson(json, site), json);
      probe(
        'TopicRecommendations',
        () => TopicRecommendations.fromJson(json, site),
        json,
      );
      probe(
        'CategoryFeaturedTopic',
        () => CategoryFeaturedTopic.fromJson(json),
        json,
      );
      probe('TopicCategory', () => TopicCategory.fromJson(json), json);
      probe(
        'TopicTrackingState',
        () => TopicTrackingState.fromJson(loose),
        loose,
      );
      probe(
        'TrackedTopicState',
        () => TrackedTopicState.fromJson(json),
        json,
      );
      probe(
        'TopicComposerCapabilities',
        () => TopicComposerCapabilities.fromJson(json),
        json,
      );
      probe('TopicTagSearch', () => TopicTagSearch.fromJson(json), json);
      probe('TopicTag', () => TopicTag.parse(loose), loose);
      probe('SidebarTag', () => SidebarTag.fromJson(loose), loose);
      probe(
        'TopicNotificationLevel',
        () => TopicNotificationLevel.fromJson(loose),
        loose,
      );

      probe('ChatUser', () => ChatUser.fromJson(json, site), json);
      probe('ChatMembership', () => ChatMembership.fromJson(loose), loose);
      probe('ChatTracking', () => ChatTracking.fromJson(json), json);
      probe('ChatPresence', () => ChatPresence.fromJson(loose), loose);
      probe(
        'ChatChannelMessageBusState',
        () => ChatChannelMessageBusState.fromJson(loose),
        loose,
      );
      probe('ChatChannel', () => ChatChannel.fromJson(json, site), json);
      probe(
        'ChatDirectMessageUser',
        () => ChatDirectMessageUser.fromJson(json, site),
        json,
      );
      probe(
        'ChatDirectMessageChannel',
        () => ChatDirectMessageChannel.fromJson(json, site),
        json,
      );
      probe(
        'ChatDirectMessageGroup',
        () => ChatDirectMessageGroup.fromJson(json),
        json,
      );
      probe(
        'ChatDirectMessageSearchResults',
        () => ChatDirectMessageSearchResults.fromJson(json, site),
        json,
      );
      probe(
        'ChatChannelBrowsePage',
        () => ChatChannelBrowsePage.fromJson(json, site),
        json,
      );
      probe(
        'ChatMessageAuthor',
        () => ChatMessageAuthor.fromJson(loose, site),
        loose,
      );
      probe('ChatReaction', () => ChatReaction.fromJson(json), json);
      probe('ChatUpload', () => ChatUpload.fromJson(json), json);
      probe('ChatReplyTo', () => ChatReplyTo.fromJson(json, site), json);
      probe(
        'ChatThreadPreview',
        () => ChatThreadPreview.fromJson(loose, site),
        loose,
      );
      probe('ChatMessage', () => ChatMessage.fromJson(json, site), json);
      probe('ChatPin', () => ChatPin.fromJson(json, site), json);
      probe('ChatSearchPage', () => ChatSearchPage.fromJson(json, site), json);
      probe(
        'ChatThreadMembership',
        () => ChatThreadMembership.fromJson(loose),
        loose,
      );
      probe(
        'ChatThreadOriginalMessage',
        () => ChatThreadOriginalMessage.fromJson(loose, site),
        loose,
      );
      probe('ChatThread', () => ChatThread.fromJson(json, site), json);
      probe('ChatThreadPage', () => ChatThreadPage.fromJson(json, site), json);
      probe(
        'ChatThreadNotificationLevel',
        () => ChatThreadNotificationLevel.fromJson(loose),
        loose,
      );

      probe(
        'AssignmentSuggestions',
        () => AssignmentSuggestions.fromJson(json, site),
        json,
      );
      probe('GifCategory', () => GifCategory.fromJson(loose), loose);
      probe(
        'GifResult',
        () => GifResult.fromJson(loose, fileDetail: 'gif'),
        loose,
      );
      probe(
        'GifSearchPage',
        () => GifSearchPage.fromJson(json, fileDetail: 'gif'),
        json,
      );
      probe('PollOption', () => PollOption.fromJson(loose), loose);
      probe(
        'PollSelection',
        () => PollSelection.fromJson(loose, type: PollType.regular),
        loose,
      );
      probe(
        'PollRankedCandidate',
        () => PollRankedCandidate.fromJson(loose),
        loose,
      );
      probe('PollRankedRound', () => PollRankedRound.fromJson(loose), loose);
      probe(
        'RankedChoiceOutcome',
        () => RankedChoiceOutcome.fromJson(loose),
        loose,
      );
      probe('PollClosedBy', () => PollClosedBy.fromJson(loose, site), loose);
      probe('Poll', () => Poll.fromJson(loose, site), loose);
      probe('Polls', () => Polls.fromJson(json, site), json);
      probe('PostReactor', () => PostReactor.fromJson(json, site), json);
      probe('ChatReactor', () => ChatReactor.fromJson(json, site), json);
      probe('Reaction', () => Reaction.fromJson(loose), loose);
      probe('Reactions', () => Reactions.fromJson(json), json);

      probe(
        'AiSummaryAvailability',
        () => AiSummaryAvailability.fromJson(json),
        json,
      );
      probe('AiTopicSummary', () => AiTopicSummary.fromJson(json), json);

      probe('TopicLink', () => TopicLink.parse('$loose'), loose);
      probe('ListLink', () => ListLink.parse('$loose'), loose);
    }

    expect(failures.values, isEmpty);
  });
  // The instruction above — add every new wire parser here — is only as good
  // as somebody remembering it, and the parser it is forgotten for is the one
  // nothing else covers either. So it is checked against the source rather
  // than asked for: every type in `lib/` declaring a `fromJson` is either
  // probed above or named below with why it is not a site payload.
  test('every parser that reads a payload is in the corpus', () {
    const notSitePayloads = {
      // This app's own storage. Their callers are written around the throw:
      // `InstanceStore` catches per entry so one damaged site cannot erase
      // the rail, and a workspace with an unreadable anchor keeps its tabs.
      'ContentRoute',
      'GroupRoute',
      'DiscourseInstance',
      'DiscourseUser',
      'ForumTabAnchor',
      'ResolvedSitePalette',
      'ComposerGeometryPreference',
      // The diagnostics store reading back what it wrote.
      'DiagnosticEvent',
      'DiagnosticLogEvent',
      'DiagnosticRedirect',
      'DiagnosticSessionEvent',
      'ErrorDiagnosticEvent',
      'HttpDiagnosticEvent',
      '_CommonFields',
    };

    final declaring = <String, String>{};
    final declaration = RegExp(
      r'^\s*(?:@\w+\s+)*'
      r'(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
      r'(?:class|enum)\s+(\w+)',
    );
    final parser = RegExp(
      r'factory\s+\w+\.fromJson|\bstatic\s+.*\bfromJson\s*\(',
    );
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      String? enclosing;
      for (final line in entity.readAsLinesSync()) {
        final declared = declaration.firstMatch(line);
        if (declared != null) enclosing = declared.group(1);
        if (enclosing != null && parser.hasMatch(line)) {
          declaring.putIfAbsent(enclosing, () => entity.path);
        }
      }
    }
    // The scan is a heuristic over source text, so a corpus it stopped finding
    // parsers in would pass while checking nothing.
    expect(declaring.length, greaterThan(60));

    final probed = RegExp(r"probe\(\s*'(\w+)'")
        .allMatches(
          File('test/wire_payload_totality_test.dart').readAsStringSync(),
        )
        .map((match) => match.group(1)!)
        .toSet();

    final unaccounted = {
      for (final entry in declaring.entries)
        if (!probed.contains(entry.key) && !notSitePayloads.contains(entry.key))
          entry.key: entry.value,
    };
    expect(
      unaccounted,
      isEmpty,
      reason: 'add these to the probes above, or to notSitePayloads with why',
    );

    // The other direction: an exemption for a type that no longer declares a
    // parser is a claim nobody is checking any more.
    expect(
      notSitePayloads.difference(declaring.keys.toSet()),
      isEmpty,
      reason: 'these no longer declare a fromJson',
    );
  });
}
