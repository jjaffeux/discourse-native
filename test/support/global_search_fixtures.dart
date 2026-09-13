import 'dart:async';

import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';

import 'bundled_plugins.dart';
import 'fakes.dart';

const globalSearchFixtureSite = 'https://search-review.invalid';
const globalSearchFixtureOtherSite = 'https://community-review.invalid';

final globalSearchFixtureUser = DiscourseUser(
  id: 7,
  username: 'joffrey',
  name: 'Joffrey',
  admin: true,
  staff: true,
  whisperer: true,
  canSendPrivateMessages: true,
  groups: const ['design', 'team'],
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canChat: true),
  ),
);

final globalSearchFixtureSites = [
  DiscourseInstance(
    url: globalSearchFixtureSite,
    title: 'Discourse Meta',
    user: globalSearchFixtureUser,
    config: SiteConfig(
      plugins: PluginData.none.withValue(
        chatSettingsDataKey,
        const ChatSettings(searchEnabled: true),
      ),
    ),
  ),
  DiscourseInstance(
    url: globalSearchFixtureOtherSite,
    title: 'Community Forum',
    user: globalSearchFixtureUser,
    config: SiteConfig(
      plugins: PluginData.none.withValue(
        chatSettingsDataKey,
        const ChatSettings(chatEnabled: false),
      ),
    ),
  ),
];

const globalSearchFixtureCategories = [
  TopicCategory(id: 1, name: 'UX', slug: 'ux', color: 'A787CB'),
  TopicCategory(id: 2, name: 'Support', slug: 'support', color: 'DFB567'),
  TopicCategory(id: 3, name: 'Development', slug: 'dev', color: '53A7C5'),
];

const globalSearchFixtureTopics = [
  Topic(
    id: 1038,
    title: 'A calmer, more useful global search',
    slug: 'a-calmer-search',
    categoryId: 1,
    postsCount: 27,
    tags: [
      TopicTag(name: 'design'),
      TopicTag(name: 'search'),
    ],
    excerpt: 'One place to find topics, people, groups, and chat.',
  ),
  Topic(
    id: 1037,
    title: 'Keyboard search focus after switching categories',
    slug: 'keyboard-search-focus',
    categoryId: 2,
    postsCount: 10,
    tags: [
      TopicTag(name: 'keyboard'),
      TopicTag(name: 'search'),
    ],
    excerpt: 'Keep the cursor where you were working.',
  ),
];

/// Real production search parsers receive local, wire-shaped responses.
///
/// No HTTP client is created. The short fixture corpus supports search/design/
/// keyboard queries; `missing` is empty and `failure` exercises the retry state.
class GlobalSearchFixtureApi extends FakeDiscourseApi
    implements PluginJsonQueryTransport {
  GlobalSearchFixtureApi()
    : super(
        user: globalSearchFixtureUser,
        totals: chatNotificationTotals(),
        chatChannelsBySite: {
          globalSearchFixtureSite: const ChatChannels(
            public: [
              ChatChannel(
                id: 2,
                title: 'Design chat',
                slug: 'design',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
              ),
            ],
            direct: [
              ChatChannel(
                id: 12,
                title: 'david, sam',
                kind: ChatChannelKind.directMessage,
                membership: ChatMembership(following: true),
              ),
            ],
          ),
        },
        chatMessagesByKey: {
          for (final channelId in [2, 12])
            for (final target in [null, channelId == 12 ? 3012 : 3001])
              FakeDiscourseApi.chatMessagesKey(
                channelId,
                targetMessageId: target,
              ): (
                messages: [
                  ChatMessage(
                    id: channelId == 12 ? 3012 : 3001,
                    channelId: channelId,
                    cooked:
                        '<p>The search design is ready for a keyboard review.</p>',
                    author: const ChatMessageAuthor(id: 8, username: 'mira'),
                    createdAt: DateTime.utc(2026, 9, 13, 10, 20),
                  ),
                ],
                canLoadMorePast: false,
                canLoadMoreFuture: false,
                targetMessageId: target,
              ),
        },
        feeds: {'/latest.json': globalSearchFixtureTopics},
        categoryList: globalSearchFixtureCategories,
        categorySiteTopTags: const [
          SidebarTag(id: 1, name: 'design', slug: 'design'),
          SidebarTag(id: 2, name: 'search', slug: 'search'),
          SidebarTag(id: 3, name: 'keyboard', slug: 'keyboard'),
        ],
        siteConfigs: {
          for (final site in globalSearchFixtureSites) site.url: site.config,
        },
      );

  final requests = <({String siteUrl, Uri uri})>[];
  Completer<void>? responseGate;
  bool failRequests = false;

  @override
  Future<Map<String, dynamic>> pluginQueryJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (path != '/categories/search.json') {
      throw StateError('Unexpected fixture query: $path');
    }
    final term = (body['term'] as String? ?? '').toLowerCase();
    if (term == 'failure') throw StateError('Offline category fixture');
    final categories = [
      for (final category in globalSearchFixtureCategories)
        {
          'id': category.id,
          'name': category.name,
          'slug': category.slug,
          'color': category.color,
        },
      {'id': 4, 'name': 'Discourse Native App', 'color': '9980BA'},
      {'id': 5, 'name': 'alerts', 'color': 'CC765B'},
      {
        'id': 6,
        'name': 'Bug reports',
        'parent_category_id': 4,
        'color': 'C27580',
      },
      {'id': 7, 'name': 'Design', 'parent_category_id': 4, 'color': 'B480A6'},
      for (var id = 8; id <= 32; id++)
        {'id': id, 'name': 'Community $id', 'color': '679CB1'},
    ];
    final matches = categories
        .where(
          (category) =>
              (category['name']! as String).toLowerCase().contains(term),
        )
        .toList();
    final page = body['page'] as int? ?? 1;
    return {
      'categories_count': matches.length,
      'categories': matches.skip((page - 1) * 25).take(25).toList(),
      'ancestors': [categories[3]],
    };
  }

  @override
  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const ['design', 'keyboard shortcuts', 'search category:support'];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    requests.add((siteUrl: siteUrl, uri: uri));
    final params = uri.queryParameters;
    final query =
        params['q'] ??
        params['term'] ??
        params['query'] ??
        params['name'] ??
        params['filter'] ??
        '';
    final otherSite = siteUrl == globalSearchFixtureOtherSite;
    switch (uri.path) {
      case '/site/settings.json':
        return {
          'chat_enabled': !otherSite,
          'chat_search_enabled': !otherSite,
          'solved_enabled': true,
          'assign_enabled': true,
          'poll_enabled': true,
          'topic_voting_enabled': true,
          'tagging_enabled': true,
          'enable_user_directory': true,
          'enable_group_directory': true,
          'allow_uncategorized_topics': true,
        };
      case '/session/current.json':
        return {
          'current_user': {
            'id': 7,
            'username': 'joffrey',
            'admin': true,
            'staff': true,
            'can_chat': !otherSite,
            'has_chat_enabled': !otherSite,
            'can_assign': true,
            'can_assign_globally': true,
            'can_see_unlisted_topics': true,
          },
        };
      case '/directory-columns.json':
        return {
          'directory_columns': [
            for (final name in [
              'likes_received',
              'likes_given',
              'topics_entered',
              'topic_count',
              'post_count',
              'posts_read',
              'days_visited',
            ])
              {'id': name, 'name': name, 'enabled': true},
          ],
        };
      case '/u/recent-searches.json':
        return {
          'recent_searches': const ['design', 'keyboard shortcuts'],
        };
      case '/u/search/users.json':
        return {
          'users': [
            _userJson,
            const {'id': 7, 'username': 'joffrey', 'name': 'Joffrey'},
          ],
        };
      case '/site.json':
        return {
          'categories': [
            for (final category in globalSearchFixtureCategories)
              {
                'id': category.id,
                'name': category.name,
                'slug': category.slug,
                'color': category.color,
              },
          ],
        };
      case '/tags/filter/search.json':
        return {
          'results': [
            for (final tag in ['design', 'search', 'keyboard']) {'name': tag},
          ],
        };
      case '/chat/api/channels.json':
        return {
          'channels': [
            const {'id': 2, 'name': 'Design chat', 'slug': 'design'},
          ],
        };
    }
    if ({
      '/search/query.json',
      '/search.json',
      '/directory_items.json',
      '/groups.json',
      '/chat/api/search.json',
    }.contains(uri.path)) {
      await responseGate?.future;
      if (failRequests || query.contains('failure')) {
        throw StateError(
          'The local search fixture is temporarily unavailable.',
        );
      }
    }
    final empty = query.contains('missing');
    switch (uri.path) {
      case '/search/query.json':
      case '/search.json':
        final categoryCondition = RegExp(
          r'(?:^|\s)categor(?:y|ies):([^\s]+)',
        ).firstMatch(query)?.group(1);
        final categories =
            categoryCondition
                ?.split(',')
                .map((value) => value.replaceFirst(RegExp(r'^='), ''))
                .toSet() ??
            const <String>{};
        final support =
            categories.contains('2') || categories.contains('support');
        final ux = categories.contains('1') || categories.contains('ux');
        final supportOnly = support && !ux;
        final uxOnly = ux && !support;
        return {
          'topics': [
            if (!empty && !supportOnly) _topicJson(1038, otherSite: otherSite),
            if (!empty && !uxOnly) _topicJson(1037, otherSite: otherSite),
          ],
          'posts': [
            if (!empty && !supportOnly) _postJson(1038),
            if (!empty && !uxOnly) _postJson(1037),
          ],
          'users': empty ? <Object>[] : [_userJson],
          'groups': empty ? <Object>[] : [_groupJson],
          'grouped_search_result': {
            'more_posts': false,
            'more_users': false,
            'more_groups': false,
            'search_log_id': 42,
          },
        };
      case '/directory_items.json':
        return {
          'directory_items': [
            if (!empty)
              {
                'id': 1,
                'user': _userJson,
                'likes_received': 48,
                'likes_given': 37,
                'topic_count': 9,
                'post_count': 64,
                'topics_entered': 120,
                'posts_read': 482,
                'days_visited': 28,
              },
          ],
          'total_rows_directory_items': empty ? 0 : 1,
          'meta': {'total_rows_directory_items': empty ? 0 : 1},
        };
      case '/groups.json':
        return {
          'groups': empty ? <Object>[] : [_groupJson],
          'total_rows_groups': empty ? 0 : 1,
          'extras': {'type_filters': <Object>[], 'can_see_members': true},
        };
      case '/chat/api/search.json':
        final channelId = int.tryParse(params['channel_id'] ?? '') ?? 2;
        final channelTitle = channelId == 12 ? 'david, sam' : 'Design chat';
        return {
          'messages': [
            if (!empty && !otherSite)
              {
                'id': channelId == 12 ? 3012 : 3001,
                'chat_channel_id': channelId,
                'message': 'The search design is ready for a keyboard review.',
                'cooked':
                    '<p>The search design is ready for a keyboard review.</p>',
                'excerpt': 'The search design is ready for a keyboard review.',
                'created_at': '2026-09-13T10:20:00Z',
                'user': _userJson,
                'channel': {
                  'id': channelId,
                  'title': channelTitle,
                  'name': channelTitle,
                  'slug': 'design',
                  'chatable_type': 'Category',
                  'chatable_id': 1,
                  'status': 'open',
                },
              },
          ],
          'meta': {'has_more': false, 'limit': 20, 'offset': 0},
        };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

Map<String, dynamic> _topicJson(int id, {required bool otherSite}) => {
  'id': id,
  'title': otherSite
      ? 'Community search feedback'
      : globalSearchFixtureTopics.firstWhere((topic) => topic.id == id).title,
  'slug': id == 1038 ? 'a-calmer-search' : 'keyboard-search-focus',
  'category_id': id == 1038 ? 1 : 2,
  'posts_count': id == 1038 ? 27 : 10,
  'like_count': id == 1038 ? 48 : 12,
  'tags': ['search', if (id == 1038) 'design' else 'keyboard'],
};

Map<String, dynamic> _postJson(int topicId) => {
  'id': topicId + 1000,
  'topic_id': topicId,
  'post_number': 1,
  'username': 'mira',
  'name': 'Mira Laurent',
  'created_at': '2026-09-12T10:00:00Z',
  'blurb': topicId == 1038
      ? 'A thoughtful design for search across topics, people, groups, and chat.'
      : 'Keyboard focus should stay predictable while search results update.',
};

const _userJson = {
  'id': 101,
  'username': 'mira',
  'name': 'Mira Laurent',
  'bio_excerpt': 'Product designer working on search and keyboard navigation.',
};

const _groupJson = {
  'id': 201,
  'name': 'design',
  'full_name': 'Design',
  'bio_excerpt': 'Thoughtful product design, search, and keyboard access.',
  'user_count': 24,
  'automatic': false,
  'visibility_level': 0,
  'members_visibility_level': 0,
  'is_group_user': true,
  'is_group_owner': true,
};

ShellController createGlobalSearchFixtureController({
  GlobalSearchFixtureApi? api,
}) => ShellController(
  plugins: installedPlugins,
  instanceStore: FakeInstanceStore(globalSearchFixtureSites),
  api: api ?? GlobalSearchFixtureApi(),
  authenticator: FakeAuthenticator()
    ..keys.addAll({
      globalSearchFixtureSite: 'local-fixture',
      globalSearchFixtureOtherSite: 'local-fixture',
    }),
  drafts: FakeDraftStore(),
  forumTabs: FakeForumTabStore(),
  forumTabsEnabled: false,
  trackers: FakeSiteTracker.reset(),
  updater: FakeUpdater(),
  updateStore: FakeUpdateStore(),
);
