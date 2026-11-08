import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const userCardActivitySite = 'https://meta.example';
const userCardActivityCategoryId = 7;

const _viewer = DiscourseUser(id: 1, username: 'reader');

const userCardActivityProfile = UserCard(
  username: 'sam',
  name: 'Sam Example',
  title: 'Community guide',
  bioExcerpt:
      '<p>Builds things with the community, writes about <em>moderation</em> '
      'and <a href="https://example.com/">software</a> most evenings.</p>',
  location: 'Paris',
  timeRead: 86400,
  badgeCount: 12,
);

const _excerpt =
    'A reply long enough to fill both of the preview lines the activity row '
    'allows, which is what a real forum post looks like once it is excerpted&hellip;';

/// Rows as the site serves them, across [count] entries of a person's history.
List<UserActivityItem> userCardActivityRows(int count) => [
  for (var index = 0; index < count; index++)
    UserActivityItem(
      actionType: index % 7 == 0
          ? UserActivityItem.topicActionType
          : index % 5 == 0
          ? UserActivityItem.likeActionType
          : UserActivityItem.replyActionType,
      topicId: 1000 + index,
      postNumber: 2 + index,
      postId: 5000 + index,
      title:
          'Discussion $index about how a long running community works :tada:',
      slug: 'discussion-$index',
      username: 'sam',
      excerpt: _excerpt,
      categoryId: userCardActivityCategoryId,
      createdAt: DateTime.now().subtract(Duration(hours: 2 + index * 5)),
    ),
];

/// Topic-list metadata for the rows a reader has already seen, which is the
/// costlier row: it carries the footer, avatars and tags.
Topic _cachedTopic(UserActivityItem row) => Topic(
  id: row.topicId,
  title: row.title,
  slug: row.slug,
  postsCount: 48,
  likeCount: 19,
  tags: const [
    TopicTag(name: 'design'),
    TopicTag(name: 'mobile'),
  ],
  posters: const [
    TopicPoster(userId: 2, username: 'alice'),
    TopicPoster(userId: 3, username: 'bob', latest: true),
  ],
);

class UserCardActivityFixture {
  UserCardActivityFixture(this.shell, this.api);

  final ShellController shell;
  final FakeDiscourseApi api;
}

class _PacedFeedApi extends FakeDiscourseApi {
  _PacedFeedApi({
    required this.beforePage,
    required super.user,
    required super.cards,
    required super.userActivityItems,
    required super.userActivityCategories,
  });

  final Future<void> Function()? beforePage;

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    await beforePage?.call();
    return super.userActivity(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
  }
}

UserCard _profileFor(String username) => UserCard(
  username: username,
  name: userCardActivityProfile.name,
  title: userCardActivityProfile.title,
  bioExcerpt: userCardActivityProfile.bioExcerpt,
  location: userCardActivityProfile.location,
  timeRead: userCardActivityProfile.timeRead,
  badgeCount: userCardActivityProfile.badgeCount,
);

/// A signed-in phone shell with a target that opens Sam's card and a history
/// of [items] rows, half of them topics already in the store. [beforePage]
/// runs ahead of every page of activity, so a caller decides when one lands.
Future<UserCardActivityFixture> pumpUserCardActivityFixture(
  WidgetTester tester, {
  int items = 90,
  List<String> people = const ['sam'],
  Future<void> Function()? beforePage,
}) async {
  final rows = userCardActivityRows(items);
  final api = _PacedFeedApi(
    beforePage: beforePage,
    user: _viewer,
    cards: {for (final person in people) person: _profileFor(person)},
    userActivityItems: rows,
    userActivityCategories: const [
      TopicCategory(
        id: userCardActivityCategoryId,
        name: 'Support',
        color: '0088CC',
        slug: 'support',
      ),
    ],
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: _viewer),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[userCardActivitySite] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  addTearDown(shell.dispose);
  for (final row in rows.where((row) => row.topicId.isEven)) {
    shell.store.put(userCardActivitySite, _cachedTopic(row));
  }
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: UserCardTarget(
              username: people.first,
              siteUrl: userCardActivitySite,
              child: const Text('Open card'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return UserCardActivityFixture(shell, api);
}
