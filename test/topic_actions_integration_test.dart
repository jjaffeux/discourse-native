import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_footer.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/finders.dart';

import 'support/shell_test_harness.dart';

void main() {
  _registerTopicLinkTests();
  _registerTopicModerationTests();
}

void _registerTopicLinkTests() {
  group('following links', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload linking(String href, String label) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [
        Post(
          id: 1,
          postNumber: 1,
          username: 'joffreyj',
          cooked: '<p><a href="$href">$label</a></p>',
        ),
      ],
      stream: const [1],
    );

    final landed = topicPayload(
      id: 9,
      title: 'The other one [solved]',
      posts: const [
        Post(
          id: 2,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>Other topic body</p>',
        ),
      ],
      stream: const [2],
    );

    Future<List<String>> openPostLinking(
      WidgetTester tester,
      FakeDiscourseApi api,
    ) async {
      final launched = watchBrowser(tester);
      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return launched;
    }

    testWidgets('a topic on the site being read opens here', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: linking(
            'https://meta.discourse.org/t/the-other-one/9',
            'the other one',
          ),
          9: landed,
        },
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the other one'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 9]);
      expect(renderedText('Other topic body'), findsOneWidget);
      expect(contentText('The other one [solved]'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a topic on another site in the rail switches to it', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: linking(
            'https://team.discourse.org/t/the-other-one/9',
            'over on team',
          ),
          9: landed,
        },
      );

      final launched = await openPostLinking(tester, api);
      expect(find.text('Discourse Meta'), findsOneWidget);

      await tester.tapOnText(find.textRange.ofSubstring('over on team'));
      await tester.pumpAndSettle();

      expect(find.text('Discourse Team'), findsOneWidget);
      expect(renderedText('Other topic body'), findsOneWidget);
      expect(launched, isEmpty);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.text('Discourse Team'), findsOneWidget);
    });

    testWidgets('a topic on a site not in the rail goes to the browser', (
      tester,
    ) async {
      const url = 'https://example.com/t/the-other-one/9';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'somewhere else'), 9: landed},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('somewhere else'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
      expect(api.topicsOpened, [7]);
      expect(renderedText('somewhere else'), findsOneWidget);
    });

    testWidgets('a page that is not a topic goes to the browser', (
      tester,
    ) async {
      const url = 'https://meta.discourse.org/faq';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'the faq')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the faq'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
      expect(api.topicsOpened, [7]);
    });

    testWidgets('a site-relative link is read as this site', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking('/t/the-other-one/9', 'the other one'), 9: landed},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the other one'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 9]);
      expect(renderedText('Other topic body'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a category link opens the list here', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/bug/5.json': [
            const Topic(id: 3, title: 'A bug report', slug: 'a-bug-report'),
          ],
        },
        topics: {7: linking('/c/bug/5', 'the bug category')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the bug category'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/c/bug/5.json'));
      expect(find.text('A bug report'), findsOneWidget);
      expect(launched, isEmpty);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      expect(renderedText('the bug category'), findsOneWidget);
    });

    testWidgets('a subcategory keeps its whole path', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/parent/child/12.json': [
            const Topic(id: 3, title: 'Nested topic', slug: 'nested-topic'),
          ],
        },
        topics: {7: linking('/c/parent/child/12', 'the nested one')},
      );

      await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the nested one'));
      await tester.pumpAndSettle();

      // `/c/child/12.json` would be a different category, and would 404.
      expect(api.feedPaths, contains('/c/parent/child/12.json'));
      expect(find.text('Nested topic'), findsOneWidget);
    });

    testWidgets('a tag link opens the list here', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/tag/ux/3.json': [
            const Topic(id: 4, title: 'A tagged topic', slug: 'a-tagged-topic'),
          ],
        },
        topics: {7: linking('/tag/ux/3', 'the ux tag')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the ux tag'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/tag/ux/3.json'));
      expect(find.text('A tagged topic'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a filtered category list goes to the browser', (tester) async {
      const url = 'https://meta.discourse.org/c/bug/5/l/top';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'the top of it')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the top of it'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
      expect(api.feedPaths, isNot(contains('/c/bug/5/l/top.json')));
    });

    testWidgets('a category on a site not in the rail goes to the browser', (
      tester,
    ) async {
      const url = 'https://example.com/c/bug/5';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'somewhere else')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('somewhere else'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
    });

    testWidgets('the same category is not stacked twice', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/bug/5.json': [
            const Topic(id: 3, title: 'A bug report', slug: 'a-bug-report'),
          ],
        },
        topics: {7: linking('/c/bug/5', 'the bug category')},
      );

      await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the bug category'));
      await tester.pumpAndSettle();

      final before = api.feedPaths.length;
      await tester.tap(find.text('A bug report'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(api.feedPaths.length, before);
      expect(find.text('A bug report'), findsOneWidget);
    });

    testWidgets('a cooked hashtag opens the list it names', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/bug/5.json': [
            const Topic(id: 3, title: 'A bug report', slug: 'a-bug-report'),
          ],
        },
        categoryList: const [
          TopicCategory(id: 5, name: 'Bug', color: '0088CC', slug: 'bug'),
        ],
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked:
                    '<p>filed under <a class="hashtag-cooked" href="/c/bug/5" '
                    'data-type="category" data-slug="bug" data-id="5" '
                    'data-style-type="square"><span '
                    'class="hashtag-icon-placeholder"></span>'
                    '<span>Bug</span></a></p>',
              ),
            ],
            stream: const [1],
          ),
        },
      );

      final launched = await openPostLinking(tester, api);
      expect(find.byType(HashtagPill), findsOneWidget);

      await tester.tap(find.byType(HashtagPill));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/c/bug/5.json'));
      expect(find.text('A bug report'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a mention opens the card', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked:
                    '<p>ask <a class="mention" href="/u/joffreyj">'
                    '@joffreyj</a> about it</p>',
              ),
            ],
            stream: const [1],
          ),
        },
        cards: {
          'joffreyj': UserCard(
            username: 'joffreyj',
            name: 'Joffrey',
            createdAt: DateTime.utc(2015, 3, 4),
          ),
        },
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('@joffreyj'));
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj']);
      expect(launched, isEmpty);
    });
  });
}

void _registerTopicModerationTests() {
  group('editing and deleting', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    Post mine({
      bool canEdit = true,
      bool canDelete = true,
      bool canRecover = false,
      bool wiki = false,
      bool canWiki = false,
      DateTime? deletedAt,
    }) => Post(
      id: 1,
      postNumber: 1,
      username: 'joffreyj',
      cooked: '<p>First post body</p>',
      canEdit: canEdit,
      canDelete: canDelete,
      canRecover: canRecover,
      wiki: wiki,
      canWiki: canWiki,
      deletedAt: deletedAt,
    );

    TopicPayload detail(Post post) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [post],
      stream: const [1],
      postsCount: 1,
      canCreatePost: true,
    );

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required Post post,
      Map<int, Post> postsById = const {},
      WriteException? writeFailure,
    }) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(post)},
        postsById: postsById,
        writeFailure: writeFailure,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('a post nobody may touch offers nothing but a reply', (
      tester,
    ) async {
      await openTopic(tester, post: mine(canEdit: false, canDelete: false));

      await hoverPost(tester);

      // can_edit and can_delete are the whole question: the guardian behind
      // them has already weighed ownership, staff, the edit window and the
      // state of the topic.
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
      expect(find.byTooltip('Edit this post'), findsNothing);
      expect(find.byTooltip('Delete this post'), findsNothing);
    });

    testWidgets('editing a post sends the markdown, not the HTML', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        post: mine(),
        // The stream carries cooked HTML, so the raw has to be fetched before
        // there is anything to edit.
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            raw: 'First **post** body',
          ),
        },
      );

      await hoverPost(tester);
      expect(find.byTooltip('Edit this post'), findsOneWidget);
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      expect(find.text('Edit post #1'), findsOneWidget);
      expect(find.text('First **post** body'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'First **post** body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(api.updated.single['postId'], 1);
      expect(api.updated.single['raw'], 'First **post** body!');
      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('First **post** body!'), findsOneWidget);
    });

    testWidgets('an edit nobody has changed cannot be saved', (tester) async {
      await openTopic(
        tester,
        post: mine(),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            raw: 'First post body',
          ),
        },
      );

      await hoverPost(tester);
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      // Not a rule of ours — the site refuses an unchanged edit — but there is
      // no reason to spend a request finding that out.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('closing a changed edit asks before discarding it', (
      tester,
    ) async {
      await openTopic(
        tester,
        post: mine(),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            raw: 'First post body',
          ),
        },
      );

      await hoverPost(tester);
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Changed post body');
      await tester.pumpAndSettle();

      expect(find.text('Cancel edit'), findsOneWidget);
      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();

      expect(find.text('Do you want to discard your changes?'), findsOneWidget);
      expect(find.text('Discard changes'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Changed post body'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('an edit never saves over a post it could not read', (
      tester,
    ) async {
      await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('re-reads a soft-deleted post and offers undo', (tester) async {
      final api = await openTopic(
        tester,
        post: mine(),
        // Staff get a soft delete: the post is still there, and still theirs
        // to put back.
        postsById: {
          1: Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            canRecover: true,
            deletedAt: DateTime(2026),
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tapPostAction(tester, 'Delete this post');
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(find.text('deleted'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('More actions'), findsOneWidget);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Undelete'), findsOneWidget);
      expect(find.byTooltip('Put this post back'), findsNothing);
      expect(find.byTooltip('Delete this post'), findsNothing);
    });

    testWidgets('a guardian-authorized post can become and stop being a wiki', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        post: mine(canWiki: true),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            wiki: true,
            canWiki: true,
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tapPostAction(tester, 'Allow community members to edit this post');
      await tester.pumpAndSettle();

      expect(api.postWikiUpdates, const [(postId: 1, wiki: true)]);
      expect(find.text('wiki'), findsOneWidget);

      api.postsById[1] = const Post(
        id: 1,
        postNumber: 1,
        username: 'joffreyj',
        cooked: '<p>First post body</p>',
        wiki: false,
        canWiki: true,
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Return this to ordinary post editing');
      await tester.pumpAndSettle();

      expect(api.postWikiUpdates, const [
        (postId: 1, wiki: true),
        (postId: 1, wiki: false),
      ]);
      expect(find.text('wiki'), findsNothing);
    });

    testWidgets('staff can lock and unlock an authored post', (tester) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final refreshed = <int, Post>{
        1: const Post(
          id: 1,
          postNumber: 1,
          userId: 7,
          username: 'joffreyj',
          cooked: '<p>Lockable body</p>',
          locked: true,
        ),
      };
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Lockable body</p>',
              ),
            ],
          ),
        },
        postsById: refreshed,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final gesture = await hoverPost(tester, body: 'Lockable body');
      await tapPostAction(tester, 'Prevent further edits to this post');
      await tester.pumpAndSettle();
      expect(api.postLockUpdates, const [(postId: 1, locked: true)]);
      expect(find.text('locked'), findsOneWidget);

      refreshed[1] = const Post(
        id: 1,
        postNumber: 1,
        userId: 7,
        username: 'joffreyj',
        cooked: '<p>Lockable body</p>',
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('Lockable body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Allow this post to be edited again');
      await tester.pumpAndSettle();

      expect(api.postLockUpdates, const [
        (postId: 1, locked: true),
        (postId: 1, locked: false),
      ]);
      expect(find.text('locked'), findsNothing);
    });

    testWidgets('staff can restore a flagged-hidden post', (tester) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Hidden body</p>',
                hidden: true,
              ),
            ],
          ),
        },
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            userId: 7,
            username: 'joffreyj',
            cooked: '<p>Visible body</p>',
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);
      await hoverPost(tester, body: 'Hidden body');
      await tapPostAction(tester, 'Restore this hidden post');
      await tester.pumpAndSettle();

      expect(api.postsUnhidden, [1]);
      expect(find.text('hidden'), findsNothing);
      expect(renderedText('Visible body'), findsOneWidget);
    });

    testWidgets('staff can convert and revert a moderator post', (
      tester,
    ) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final refreshed = <int, Post>{
        1: const Post(
          id: 1,
          postNumber: 1,
          userId: 7,
          username: 'joffreyj',
          cooked: '<p>Official body</p>',
          postType: Post.moderatorPostType,
        ),
      };
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Official body</p>',
              ),
            ],
          ),
        },
        postsById: refreshed,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final gesture = await hoverPost(tester, body: 'Official body');
      await tapPostAction(tester, 'Mark this as an official moderator post');
      await tester.pumpAndSettle();
      expect(api.postTypeUpdates, const [
        (postId: 1, postType: Post.moderatorPostType),
      ]);
      expect(find.text('moderator'), findsOneWidget);

      refreshed[1] = const Post(
        id: 1,
        postNumber: 1,
        userId: 7,
        username: 'joffreyj',
        cooked: '<p>Official body</p>',
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('Official body')));
      await tester.pumpAndSettle();
      await tapPostAction(
        tester,
        'Remove the moderator styling from this post',
      );
      await tester.pumpAndSettle();

      expect(api.postTypeUpdates, const [
        (postId: 1, postType: Post.moderatorPostType),
        (postId: 1, postType: Post.regularPostType),
      ]);
      expect(find.text('moderator'), findsNothing);
    });

    testWidgets('staff-note guardians can add and remove a post notice', (
      tester,
    ) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final refreshed = <int, Post>{
        1: const Post(
          id: 1,
          postNumber: 1,
          userId: 7,
          username: 'joffreyj',
          cooked: '<p>Noticeable body</p>',
          notice: PostNotice(
            type: 'custom',
            raw: 'Please read this carefully.',
            cooked: '<p>Please <strong>read</strong> this carefully.</p>',
          ),
        ),
      };
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Noticeable body</p>',
              ),
            ],
            canEditStaffNotes: true,
          ),
        },
        postsById: refreshed,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final gesture = await hoverPost(tester, body: 'Noticeable body');
      await tapPostAction(tester, 'Add a staff notice above this post');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('post-notice-text')),
        '  Please read this carefully.  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-notice-save')));
      await tester.pumpAndSettle();

      expect(api.postNoticeUpdates, const [
        (postId: 1, notice: 'Please read this carefully.'),
      ]);
      expect(find.byKey(const ValueKey('post-notice-1')), findsOneWidget);
      expect(renderedText('Please read this carefully.'), findsOneWidget);

      refreshed[1] = const Post(
        id: 1,
        postNumber: 1,
        userId: 7,
        username: 'joffreyj',
        cooked: '<p>Noticeable body</p>',
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('Noticeable body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Change or remove the staff notice');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-notice-delete')));
      await tester.pumpAndSettle();

      expect(api.postNoticeUpdates, const [
        (postId: 1, notice: 'Please read this carefully.'),
        (postId: 1, notice: null),
      ]);
      expect(find.byKey(const ValueKey('post-notice-1')), findsNothing);
    });

    testWidgets('post-owner guardians can reassign one post directly', (
      tester,
    ) async {
      const ownerGuardian = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        canChangePostOwner: true,
      );
      final api = FakeDiscourseApi(
        user: ownerGuardian,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Owned body</p>',
              ),
            ],
          ),
        },
        userSearches: const {
          'kris': [FoundUser(username: 'kris', name: 'Kris')],
        },
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            userId: 12,
            username: 'kris',
            name: 'Kris',
            cooked: '<p>Owned body</p>',
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Meta',
          ).copyWith(user: ownerGuardian),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await hoverPost(tester, body: 'Owned body');
      await tapPostAction(tester, 'Assign this post to another account');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-change-owner-search')),
        'kris',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-change-owner-submit')));
      await tester.pumpAndSettle();

      expect(api.postOwnersChanged, hasLength(1));
      expect(api.postOwnersChanged.single.topicId, 7);
      expect(api.postOwnersChanged.single.postIds, [1]);
      expect(api.postOwnersChanged.single.username, 'kris');
      expect(find.text('Kris'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );
    });

    testWidgets('admins can permanently delete a reply after preflight', (
      tester,
    ) async {
      final deletedReply = Post(
        id: 2,
        postNumber: 2,
        username: 'sam',
        cooked: '<p>Deleted reply body</p>',
        deletedAt: DateTime.utc(2026, 8, 25),
        canRecover: true,
        canPermanentlyDelete: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              const Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked: '<p>First permanent body</p>',
              ),
              deletedReply,
            ],
          ),
        },
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First permanent body</p>',
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await hoverPost(tester, body: 'Deleted reply body');
      await tapPostAction(tester, 'Permanently delete this post');
      await tester.pumpAndSettle();
      expect(api.permanentDeletionChecks, [2]);
      expect(
        find.byKey(const ValueKey('post-permanent-delete-dialog')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('post-permanent-delete-confirmation')),
        'PERMANENTLY DELETE',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('post-permanent-delete-submit')),
      );
      await tester.pumpAndSettle();

      expect(api.postsPermanentlyDeleted, const [(topicId: 7, postId: 2)]);
      expect(renderedText('Deleted reply body'), findsNothing);
      expect(renderedText('First permanent body'), findsOneWidget);
    });

    testWidgets('permanent-delete preflight surfaces the server refusal', (
      tester,
    ) async {
      final deletedReply = Post(
        id: 2,
        postNumber: 2,
        username: 'sam',
        cooked: '<p>Cooldown reply body</p>',
        deletedAt: DateTime.utc(2026, 8, 25),
        canPermanentlyDelete: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(id: 7, title: 'A real topic', posts: [deletedReply]),
        },
        permanentDeletionAllowed: false,
        permanentDeletionReason: 'Wait five minutes or use another admin.',
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await hoverPost(tester, body: 'Cooldown reply body');
      await tapPostAction(tester, 'Permanently delete this post');
      await tester.pumpAndSettle();

      expect(api.permanentDeletionChecks, [2]);
      expect(
        find.text('Wait five minutes or use another admin.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('post-permanent-delete-dialog')),
        findsNothing,
      );
      expect(api.postsPermanentlyDeleted, isEmpty);
    });

    testWidgets('permanently deleting the opening post removes the topic', (
      tester,
    ) async {
      final openingPost = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>Deleted opening body</p>',
        deletedAt: DateTime.utc(2026, 8, 25),
        canRecover: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [openingPost],
            deletedAt: DateTime.utc(2026, 8, 25),
            canRecoverTopic: true,
            canPermanentlyDelete: true,
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await hoverPost(tester, body: 'Deleted opening body');
      await tapPostAction(tester, 'Permanently delete this post');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('post-permanent-delete-confirmation')),
        'permanently delete',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('post-permanent-delete-submit')),
      );
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.permanentDeletionChecks, [1]);
      expect(api.topicsPermanentlyDeleted, [7]);
      expect(shell.currentContent?.topicId, isNull);
      expect(find.byType(TopicView), findsNothing);
      expect(renderedText('Deleted opening body'), findsNothing);
    });

    testWidgets('selects, merges, and bulk-deletes guardian-authorized posts', (
      tester,
    ) async {
      const first = Post(
        id: 1,
        postNumber: 1,
        username: 'joffreyj',
        cooked: '<p>First selected body</p>',
        canDelete: true,
      );
      const second = Post(
        id: 2,
        postNumber: 2,
        username: 'joffreyj',
        cooked: '<p>Second selected body</p>',
        canDelete: true,
      );
      const third = Post(
        id: 3,
        postNumber: 3,
        username: 'sam',
        cooked: '<p>Third selected body</p>',
        canDelete: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [first, second, third],
            canSplitMergeTopic: true,
          ),
        },
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>Merged selected body</p>',
            canDelete: true,
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('topic-post-select-1')));
      await tester.tap(find.byKey(const ValueKey('topic-post-select-2')));
      await tester.pumpAndSettle();
      expect(find.text('2 posts selected'), findsOneWidget);

      final mergeAction = find.byKey(
        const ValueKey('topic-selected-posts-merge'),
      );
      await tester.ensureVisible(mergeAction);
      await tester.tap(mergeAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topic-selected-merge-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.merged, const [
        [1, 2],
      ]);
      expect(renderedText('Merged selected body'), findsOneWidget);
      expect(renderedText('Second selected body'), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-post-select-3')));
      await tester.pumpAndSettle();
      final deleteAction = find.byKey(
        const ValueKey('topic-selected-posts-delete'),
      );
      await tester.ensureVisible(deleteAction);
      await tester.tap(deleteAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topic-selected-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.bulkDeleted, const [
        [3],
      ]);
      expect(renderedText('Third selected body'), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );
    });

    testWidgets('moves selected posts to a searched existing topic', (
      tester,
    ) async {
      const sourcePosts = [
        Post(
          id: 1,
          postNumber: 1,
          username: 'joffreyj',
          cooked: '<p>Move this body</p>',
        ),
        Post(
          id: 2,
          postNumber: 2,
          username: 'sam',
          cooked: '<p>Leave this body</p>',
        ),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: sourcePosts,
            canMovePosts: true,
          ),
          99: topicPayload(
            id: 99,
            title: 'Destination topic',
            posts: const [
              Post(
                id: 99,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>Destination body</p>',
              ),
            ],
          ),
        },
        searchResults: const {
          'Destination': SearchResults(
            hits: [
              SearchPostHit(
                postId: 99,
                topicId: 99,
                postNumber: 1,
                topicTitle: 'Destination topic',
                topicSlug: 'destination-topic',
                username: 'sam',
                excerpt: SearchExcerpt([]),
              ),
            ],
          ),
        },
      );
      api.topicMoveUrl = '/t/destination-topic/99';
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-post-select-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-selected-posts-move')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Existing topic'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-move-posts-search')),
        'Destination',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Destination topic'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('topic-move-posts-chronological')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('topic-move-posts-submit')));
      await tester.pumpAndSettle();

      expect(api.movedTopicPosts, hasLength(1));
      expect(api.movedTopicPosts.single.topicId, 7);
      expect(api.movedTopicPosts.single.postIds, [1]);
      expect(api.movedTopicPosts.single.destinationTopicId, 99);
      expect(api.movedTopicPosts.single.chronologicalOrder, isTrue);
      expect(renderedText('Destination body'), findsOneWidget);
      expect(api.topicsOpened, contains(99));
    });

    testWidgets('changes the owner of same-author selected posts', (
      tester,
    ) async {
      const first = Post(
        id: 1,
        postNumber: 1,
        username: 'joffreyj',
        cooked: '<p>First owner body</p>',
      );
      const second = Post(
        id: 2,
        postNumber: 2,
        username: 'joffreyj',
        cooked: '<p>Second owner body</p>',
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [first, second],
            canSplitMergeTopic: true,
          ),
        },
        userSearches: const {
          'kris': [FoundUser(username: 'kris', name: 'Kris')],
        },
        user: const DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          canChangePostOwner: true,
        ),
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            username: 'kris',
            name: 'Kris',
            cooked: '<p>First owner body</p>',
          ),
          2: Post(
            id: 2,
            postNumber: 2,
            username: 'kris',
            name: 'Kris',
            cooked: '<p>Second owner body</p>',
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(
            user: const DiscourseUser(
              username: 'joffreyj',
              name: 'Joffrey',
              canChangePostOwner: true,
            ),
          ),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-post-select-1')));
      await tester.tap(find.byKey(const ValueKey('topic-post-select-2')));
      await tester.pumpAndSettle();
      final action = find.byKey(
        const ValueKey('topic-selected-posts-change-owner'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('topic-change-owner-search')),
        'kris',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Kris'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-change-owner-submit')));
      await tester.pumpAndSettle();

      expect(api.postOwnersChanged, hasLength(1));
      expect(api.postOwnersChanged.single.topicId, 7);
      expect(api.postOwnersChanged.single.postIds, [1, 2]);
      expect(api.postOwnersChanged.single.username, 'kris');
      expect(find.text('Kris'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );
    });

    testWidgets('a post that is really gone stops being drawn', (tester) async {
      // Nothing comes back for the id, which is the site saying it is no
      // longer there — or no longer ours to see.
      final api = await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tapPostAction(tester, 'Delete this post');
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(renderedText('First post body'), findsNothing);
    });

    testWidgets('recovering puts the post back', (tester) async {
      final api = await openTopic(
        tester,
        post: mine(
          canDelete: false,
          canRecover: true,
          deletedAt: DateTime(2026),
        ),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            canDelete: true,
          ),
        },
      );

      await hoverPost(tester);
      await tapPostAction(tester, 'Put this post back');
      await tester.pumpAndSettle();

      expect(api.recovered, [1]);
      expect(find.text('deleted'), findsNothing);
    });

    testWidgets('a refused delete says why and leaves the post alone', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        post: mine(),
        writeFailure: const WriteException(WriteFailure.forbidden),
      );

      await hoverPost(tester);
      await tapPostAction(tester, 'Delete this post');
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(find.textContaining("You can't post that here"), findsOneWidget);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('on a touch screen the same actions arrive as a sheet', (
      tester,
    ) async {
      await openTopic(tester, post: mine());

      await tester.longPress(find.text('joffreyj'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Delete'), findsOneWidget);
    });
  });

  group('optional site features', () {
    const site = 'https://meta.discourse.org';

    final reactionsOn = installedPlugins.models.siteConfig(const {
      'emoji_set': 'apple',
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_enabled_reactions': '+1|clap',
    }, site);

    ShellController controllerWith(
      WidgetTester tester,
      FakeDiscourseApi api, {
      FakeInstanceStore? store,
    }) {
      final controller = ShellController(
        instanceStore:
            store ?? FakeInstanceStore([instance('meta.discourse.org')]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        plugins: installedPlugins,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    FakeDiscourseApi serving({Map<String, SiteConfig> configs = const {}}) =>
        FakeDiscourseApi(
          feeds: {'/latest.json': const []},
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A real topic',
              posts: [
                const Post(
                  id: 1,
                  postNumber: 1,
                  username: 'sam',
                  cooked: '<p>First post body</p>',
                ),
              ],
              stream: const [1],
            ),
          },
          siteConfigs: configs,
        );

    testWidgets('site settings load with category navigation and are reused', (
      tester,
    ) async {
      final api = serving(configs: {site: reactionsOn});
      final controller = controllerWith(tester, api);
      await controller.load();
      await tester.pump();

      expect(api.siteConfigsRequested, [site]);
      expect(controller.siteConfigFor(site).emojiSet, 'apple');
      expect(controller.siteConfigFor(site).mainReaction, 'heart');

      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();

      expect(api.siteConfigsRequested, [site]);
    });

    testWidgets('a site is only asked once', (tester) async {
      final api = serving(configs: {site: reactionsOn});
      final controller = controllerWith(tester, api);
      await controller.load();

      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();
      await controller.loadTopic(7, 'a-real-topic', force: true);
      await tester.pump();

      expect(api.siteConfigsRequested, [site]);
    });

    testWidgets('the answer is remembered between launches', (tester) async {
      final store = FakeInstanceStore([instance('meta.discourse.org')]);
      final controller = controllerWith(
        tester,
        serving(configs: {site: reactionsOn}),
        store: store,
      );
      await controller.load();
      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();

      final stored = await store.load();
      expect(stored.single.config, reactionsOn);
    });

    testWidgets('a stored answer stands until this session has its own', (
      tester,
    ) async {
      final controller = controllerWith(
        tester,
        serving(),
        store: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(config: reactionsOn),
        ]),
      );
      await controller.load();

      expect(controller.siteConfigFor(site).emojiSet, 'apple');
    });

    testWidgets('a site that will not answer is drawn as plain core', (
      tester,
    ) async {
      final controller = controllerWith(tester, serving());
      await controller.load();
      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();

      expect(controller.siteConfigFor(site), const SiteConfig.unknown());
    });

    testWidgets('a site that will not answer is given up on, not hammered', (
      tester,
    ) async {
      final api = serving();
      final controller = controllerWith(tester, api);
      await controller.load();

      for (var i = 0; i < 6; i++) {
        await controller.loadTopic(7, 'a-real-topic', force: true);
        await tester.pump();
      }

      expect(api.siteConfigsRequested, hasLength(3));
    });

    testWidgets('signing out forgets what the site said', (tester) async {
      // On a login_required site the settings were only readable as that
      // account, so keeping an answer that can no longer be refreshed would
      // leave the shell drawing something it cannot correct.
      final api = serving(configs: {site: reactionsOn});
      final controller = controllerWith(
        tester,
        api,
        store: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(username: 'joffreyj')),
        ]),
      );
      await controller.load();
      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();
      expect(controller.siteConfigFor(site), reactionsOn);

      await controller.disconnectCurrentInstance();

      expect(controller.siteConfigFor(site), const SiteConfig.unknown());
    });

    testWidgets('a post no feature claims keeps the core footer', (
      tester,
    ) async {
      await pumpShell(
        tester,
        desktop,
        api: FakeDiscourseApi(
          feeds: {
            '/latest.json': [
              const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
            ],
          },
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A real topic',
              posts: [
                const Post(
                  id: 1,
                  postNumber: 1,
                  username: 'sam',
                  cooked: '<p>First post body</p>',
                  likeCount: 2,
                ),
              ],
              stream: const [1],
            ),
          },
        ),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byType(PostFooter), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PostFooter),
          matching: find.byType(PostLikes),
        ),
        findsOneWidget,
      );
    });
  });
}
