import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/right_sidebar.dart';
import 'package:discourse_native/src/shell/user_bar.dart';

import 'support/fakes.dart';

/// Sizes chosen to sit either side of the shell's breakpoints (768 / 1200).
const Size phone = Size(390, 844);
const Size laptop = Size(1000, 800);
const Size desktop = Size(1440, 900);

final List<DiscourseInstance> twoSites = [
  instance('meta.discourse.org', title: 'Discourse Meta'),
  instance('team.discourse.org', title: 'Discourse Team'),
];

Future<void> pumpShell(
  WidgetTester tester,
  Size size, {
  List<DiscourseInstance>? instances,
  FakeDiscourseApi? api,
  FakeInstanceStore? store,
  FakeAuthenticator? authenticator,
  FakeDraftStore? drafts,
  Key? key,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    DiscourseApp(
      key: key,
      store: store ?? FakeInstanceStore(instances ?? twoSites),
      api: api ?? FakeDiscourseApi(),
      authenticator: authenticator ?? FakeAuthenticator(),
      drafts: drafts ?? FakeDraftStore(),
    ),
  );
  await tester.pumpAndSettle();
}

/// HtmlWidget renders into a bare RichText, which find.text and
/// find.textContaining both ignore.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  description: 'rendered text containing "$text"',
);

void main() {
  group('compact', () {
    testWidgets('shows the rail and the sidebar, but no main content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
      expect(find.byType(RightSidebar), findsNothing);
    });

    testWidgets('selecting a destination replaces the sidebar with content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();

      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      // The rail never goes away.
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('back returns from content to the sidebar', (tester) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
    });

    testWidgets('back unwinds the content stack before the sidebar', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace with deeper view'));
      await tester.pumpAndSettle();

      expect(find.text('Topic 1'), findsWidgets);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // First back pops the stack; the sidebar is still not showing.
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
    });

    testWidgets('the right sidebar is never used', (tester) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();

      expect(find.byType(RightSidebar), findsNothing);
    });

    testWidgets('the user bar card is inset further on iOS', (tester) async {
      await pumpShell(tester, phone, key: const ValueKey('default'));
      final byDefault = tester.getRect(find.byKey(UserBar.cardKey));

      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        // A distinct key rebuilds the tree against the platform in effect.
        await pumpShell(tester, phone, key: const ValueKey('ios'));
        final onIos = tester.getRect(find.byKey(UserBar.cardKey));

        expect(onIos.width, lessThan(byDefault.width));
        expect(onIos.left, UserBar.iosHorizontalMargin);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('the user bar yields the height to the main content', (
      tester,
    ) async {
      await pumpShell(tester, phone);
      expect(find.byType(UserBar), findsOneWidget);

      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();

      expect(find.byType(UserBar), findsNothing);
    });
  });

  group('medium', () {
    testWidgets('shows rail, sidebar and content together', (tester) async {
      await pumpShell(tester, laptop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(RightSidebar), findsNothing);
    });
  });

  group('expanded', () {
    /// A site whose default feed holds one topic, so tests can get from the
    /// list to a topic — the only route the details panel applies to.
    FakeDiscourseApi apiWithTopic() => FakeDiscourseApi(
      feeds: {
        '/latest.json': const [
          Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
        ],
      },
      topics: {
        7: TopicDetail(
          id: 7,
          title: 'A real topic',
          posts: const [
            Post(
              id: 1,
              postNumber: 1,
              username: 'joffreyj',
              name: 'Joffrey',
              cooked: '<p>First post body</p>',
            ),
          ],
          stream: const [1],
        ),
      },
    );

    Future<void> pumpTopic(WidgetTester tester) async {
      await pumpShell(tester, desktop, api: apiWithTopic());
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows rail, sidebar and content, but no details', (
      tester,
    ) async {
      await pumpShell(tester, desktop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
      // The list is not a topic, so it keeps the full width.
      expect(find.byType(RightSidebar), findsNothing);
    });

    testWidgets('adds the right sidebar once a topic is open', (tester) async {
      await pumpTopic(tester);

      expect(find.byType(RightSidebar), findsOneWidget);
    });

    testWidgets('drops the right sidebar again on the way back', (
      tester,
    ) async {
      await pumpTopic(tester);
      expect(find.byType(RightSidebar), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(RightSidebar), findsNothing);
    });

    testWidgets('the user bar spans the rail and the sidebar', (tester) async {
      await pumpShell(tester, desktop);

      final railLeft = tester.getTopLeft(find.byType(InstanceRail)).dx;
      final sidebarRight = tester
          .getBottomRight(find.byType(InstanceSidebar))
          .dx;
      final bar = tester.getRect(find.byType(UserBar));

      expect(bar.left, railLeft);
      expect(bar.right, sidebarRight);
      // ...and stops short of the main content.
      expect(
        bar.right,
        lessThan(tester.getTopLeft(find.byType(MainContent)).dx + 1),
      );
    });

    testWidgets('the user bar floats over the columns', (tester) async {
      await pumpShell(tester, desktop);

      final rail = tester.getRect(find.byType(InstanceRail));
      final sidebar = tester.getRect(find.byType(InstanceSidebar));
      final bar = tester.getRect(find.byType(UserBar));

      // Both columns run to the bottom edge behind the bar rather than being
      // pushed up by it — that is what makes the bar read as floating.
      expect(rail.bottom, bar.bottom);
      expect(sidebar.bottom, bar.bottom);
      expect(sidebar.top, lessThan(bar.top));
    });

    testWidgets('the right sidebar can be collapsed', (tester) async {
      await pumpTopic(tester);

      await tester.tap(find.byIcon(Icons.view_sidebar));
      await tester.pumpAndSettle();

      expect(find.byType(RightSidebar), findsNothing);
      expect(find.byType(MainContent), findsOneWidget);
    });
  });

  testWidgets('switching instance swaps the sidebar contents', (tester) async {
    await pumpShell(tester, desktop);

    expect(find.text('Discourse Meta'), findsOneWidget);

    // Second entry in the rail.
    await tester.tap(find.text('DT'));
    await tester.pumpAndSettle();

    expect(find.text('Discourse Team'), findsOneWidget);
    expect(find.text('Discourse Meta'), findsNothing);
  });

  group('adding a site', () {
    testWidgets('shows the empty state with nothing connected', (tester) async {
      await pumpShell(tester, desktop, instances: const []);

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      // The rail is still there, holding the add button.
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('a looked-up site lands in the rail and is persisted', (
      tester,
    ) async {
      final store = FakeInstanceStore(const []);
      final api = FakeDiscourseApi(
        results: {
          'meta.discourse.org': instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ),
        },
      );

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.text('Add a site'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'meta.discourse.org');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(api.lookups, ['meta.discourse.org']);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.text('Discourse Meta'), findsOneWidget);
      expect(store.saveCount, 1);
    });

    testWidgets('a failed lookup reports why and adds nothing', (tester) async {
      final store = FakeInstanceStore(const []);
      final api = FakeDiscourseApi(failure: SiteLookupFailure.notDiscourse);

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.text('Add a site'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is not a Discourse forum'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(store.saveCount, 0);
    });

    testWidgets('the same site cannot be added twice', (tester) async {
      final existing = instance('meta.discourse.org', title: 'Discourse Meta');
      final store = FakeInstanceStore([existing]);
      final api = FakeDiscourseApi(
        results: {'https://meta.discourse.org/': existing},
      );

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'https://meta.discourse.org/',
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already in your list'), findsOneWidget);
      expect(store.saveCount, 0);
    });
  });

  group('topic lists', () {
    final latest = [
      const Topic(
        id: 1,
        title: 'Welcome to the forum',
        slug: 'welcome',
        categoryId: 5,
      ),
      const Topic(
        id: 2,
        title: 'Something unread',
        slug: 'unread-one',
        unreadPosts: 3,
      ),
    ];

    testWidgets('the default destination loads latest on open', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Welcome to the forum'), findsOneWidget);
      expect(find.text('Something unread'), findsOneWidget);
      // The placeholder is gone.
      expect(find.text('Replace with deeper view'), findsNothing);
    });

    testWidgets('picking a destination fetches its own list', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          '/top.json': [
            const Topic(id: 9, title: 'Top topic', slug: 'top-one'),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('Top'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/top.json'));
      expect(find.text('Top topic'), findsOneWidget);
    });

    testWidgets('a list is not refetched when revisited', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          '/top.json': [
            const Topic(id: 9, title: 'Top topic', slug: 'top-one'),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('Top'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();

      expect(
        api.feedPaths.where((p) => p == '/latest.json').length,
        1,
        reason: 'cached lists should not be refetched',
      );
    });

    testWidgets('unread topics carry a count', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('category badges render once categories arrive', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': latest},
        categoryList: const [
          TopicCategory(id: 5, name: 'Feature', color: '0088CC'),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.text('Feature'), findsOneWidget);
    });

    testWidgets('a failing list reports it instead of crashing', (
      tester,
    ) async {
      // No feeds configured, so the call throws.
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);

      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bookmarks has no list endpoint yet', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();

      // Falls back to the placeholder rather than firing a bad request.
      expect(api.feedPaths, isNot(contains('/bookmarks.json')));
      expect(find.text('Replace with deeper view'), findsOneWidget);
    });
  });

  group('infinite scroll', () {
    // The rail and sidebar scroll too, so target the topic list.
    final topicList = find.descendant(
      of: find.byType(TopicListView),
      matching: find.byType(SuperListView),
    );

    List<Topic> page(int from, int count) => [
      for (var i = from; i < from + count; i++)
        Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
    ];

    testWidgets('reaching the end appends the next page', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
          '/latest.json?page=1': page(31, 30),
        },
        // Discourse reports it without the extension.
        nextPages: {'/latest.json': '/latest?page=1'},
      );

      await pumpShell(tester, desktop, api: api);
      expect(find.text('Topic 1'), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);

      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      // The extension was added before requesting.
      expect(api.feedPaths, contains('/latest.json?page=1'));
      expect(find.text('Topic 31'), findsOneWidget);
    });

    testWidgets('a topic repeated across pages is not duplicated', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
          // Topic 30 got bumped and comes back on page two.
          '/latest.json?page=1': [...page(30, 1), ...page(31, 5)],
        },
        nextPages: {'/latest.json': '/latest?page=1'},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      expect(find.text('Topic 30'), findsOneWidget);
    });

    testWidgets('a last page stops further requests', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': page(1, 30)});

      await pumpShell(tester, desktop, api: api);
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      // No more_topics_url, so nothing beyond the first request.
      expect(api.feedPaths, ['/latest.json']);
    });
  });

  testWidgets('a response landing after the shell is gone is ignored', (
    tester,
  ) async {
    tester.view.physicalSize = desktop;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []}, gate: gate);

    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore(twoSites),
        api: api,
        authenticator: FakeAuthenticator(),
      ),
    );
    // Let load() and the first feed request start, but not finish.
    await tester.pump();

    // The shell goes away while the request is still in flight.
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();

    // Notifying a disposed ChangeNotifier throws; the controller must not.
    expect(tester.takeException(), isNull);
  });

  group('opening a topic', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    Post post(int id, int number, String body) => Post(
      id: id,
      postNumber: number,
      username: 'joffreyj',
      cooked: '<p>$body</p>',
    );

    TopicDetail detail({List<int> stream = const [1]}) => TopicDetail(
      id: 7,
      title: 'A real topic',
      posts: [post(1, 1, 'First post body')],
      stream: stream,
    );

    testWidgets('tapping a row replaces the list with the topic', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(find.byType(TopicView), findsOneWidget);
      expect(find.byType(TopicListView), findsNothing);
      // The cooked HTML is rendered, not shown as markup.
      expect(renderedText('First post body'), findsOneWidget);
      expect(renderedText('<p>'), findsNothing);
    });

    testWidgets('back returns to the list without refetching it', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(TopicListView), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('back lands where the list was left, not at the top', (
      tester,
    ) async {
      final many = [
        for (var i = 1; i <= 60; i++)
          Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': many},
        topics: {for (final topic in many) topic.id: detail()},
      );

      await pumpShell(tester, desktop, api: api);

      final list = find.descendant(
        of: find.byType(TopicListView),
        matching: find.byType(Scrollable),
      );
      // Far enough down that the top of the list is no longer built.
      final row = find.text('Topic 40');
      await tester.scrollUntilVisible(row, 400, scrollable: list);
      await tester.pumpAndSettle();
      expect(find.text('Topic 1'), findsNothing);

      await tester.tap(
        find.ancestor(of: row, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Back on the list, still down among the forties rather than at the top.
      expect(find.text('Topic 40'), findsOneWidget);
      expect(find.text('Topic 1'), findsNothing);
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        greaterThan(0),
      );
    });

    testWidgets('a topic that fails to load says so', (tester) async {
      // No topics configured, so the fetch throws.
      final api = FakeDiscourseApi(feeds: {'/latest.json': listed});

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't load this topic"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remaining posts are fetched by id, not by page', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        // Twenty arrive with the topic; the rest are ids only.
        topics: {
          7: detail(stream: [1, 2, 3]),
        },
        postsById: {
          2: post(2, 2, 'Second post body'),
          3: post(3, 3, 'Third post body'),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [2, 3],
      ]);
      expect(renderedText('Second post body'), findsOneWidget);
    });

    testWidgets('a topic already held is not refetched', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
    });
  });

  group('connecting', () {
    testWidgets('the bar invites you to connect until you do', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Tap to connect'), findsOneWidget);
    });

    testWidgets('connecting records the account against the site', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, store: store, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      // Authorized against the selected site, not some other one.
      expect(auth.connected, ['https://meta.discourse.org']);
      expect(find.text('Joffrey'), findsOneWidget);
      expect(find.text('meta.discourse.org'), findsWidgets);
      expect(store.saveCount, 1);
    });

    testWidgets('backing out of the browser is not an error', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.cancelled);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      expect(find.text('Tap to connect'), findsOneWidget);
      expect(find.textContaining('could not be verified'), findsNothing);
    });

    testWidgets('an unverifiable reply is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.badReply);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be verified'), findsOneWidget);
    });

    testWidgets('counters appear once connected', (tester) async {
      final api = FakeDiscourseApi(
        totals: const NotificationTotals(
          unreadNotifications: 3,
          unreadPersonalMessages: 2,
          topicTrackingUnread: 12,
          topicTrackingNew: 7,
        ),
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      // Sidebar counts, each from the single totals call.
      expect(find.text('12'), findsOneWidget); // Unread
      expect(find.text('7'), findsOneWidget); // New
      expect(find.text('2'), findsOneWidget); // Messages
      // Rail badge is things addressed to you: 3 + 2.
      expect(find.text('5'), findsOneWidget);
      expect(api.totalsCalls, 1);
    });

    testWidgets('a site whose counters fail still renders', (tester) async {
      // totals: null makes the call throw.
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      expect(find.text('Joffrey'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching to a connected site refreshes its counters', (
      tester,
    ) async {
      final connected = [
        instance('meta.discourse.org', title: 'Discourse Meta'),
        instance('team.discourse.org', title: 'Discourse Team'),
      ];
      final api = FakeDiscourseApi(totals: const NotificationTotals());
      final auth = FakeAuthenticator();

      await pumpShell(
        tester,
        desktop,
        instances: connected,
        api: api,
        authenticator: auth,
      );

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();
      final afterConnect = api.totalsCalls;

      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();

      expect(api.totalsCalls, greaterThan(afterConnect));
      expect(auth.connected, [
        'https://meta.discourse.org',
        'https://team.discourse.org',
      ]);
    });

    testWidgets('disconnecting revokes the key with the site', (tester) async {
      final api = FakeDiscourseApi(totals: const NotificationTotals());
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, api: api, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      // Told the site, not just our own keychain.
      expect(api.revoked, ['https://meta.discourse.org']);
      expect(auth.disconnected, ['https://meta.discourse.org']);
    });

    testWidgets('disconnecting forgets the key and the account', (
      tester,
    ) async {
      final auth = FakeAuthenticator();
      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(find.text('Tap to connect'));
      await tester.pumpAndSettle();
      expect(find.text('Joffrey'), findsOneWidget);

      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(auth.disconnected, ['https://meta.discourse.org']);
      expect(find.text('Not signed in'), findsOneWidget);
    });
  });

  group('user cards', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    final detail = TopicDetail(
      id: 7,
      title: 'A real topic',
      posts: const [
        Post(
          id: 1,
          postNumber: 1,
          username: 'joffreyj',
          name: 'Joffrey',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
    );

    final card = UserCard(
      username: 'joffreyj',
      name: 'Joffrey',
      title: 'Team member',
      bioExcerpt: '<p>Builds the thing.</p>',
      createdAt: DateTime.utc(2015, 3, 4),
      badgeCount: 12,
    );

    Future<void> openTopic(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping an avatar opens the card', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': card},
      );

      await openTopic(tester, api);
      await tester.tap(
        find.descendant(
          of: find.byType(TopicView),
          matching: find.byType(AvatarImage),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj']);
      expect(find.text('@joffreyj'), findsOneWidget);
      expect(find.text('Team member'), findsOneWidget);
      expect(renderedText('Builds the thing.'), findsOneWidget);
      expect(find.text('Mar 2015'), findsOneWidget);
    });

    testWidgets('tapping the name opens the same card, already held', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': card},
      );

      await openTopic(tester, api);
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();
      expect(find.text('@joffreyj'), findsOneWidget);

      // Dismiss by tapping the barrier, then open it again.
      await tester.tapAt(const Offset(20, 500));
      await tester.pumpAndSettle();
      expect(find.text('@joffreyj'), findsNothing);

      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.text('@joffreyj'), findsOneWidget);
      expect(api.cardsRequested, ['joffreyj']);
    });

    testWidgets('a card that fails to load offers a retry', (tester) async {
      // No cards configured, so the fetch throws.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
      );

      await openTopic(tester, api);
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj', 'joffreyj']);
      expect(tester.takeException(), isNull);
    });
  });

  group('following links', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    /// A topic whose only post is a single link, so there is something to tap.
    TopicDetail linking(String href, String label) => TopicDetail(
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

    /// The topic behind every link below, titled differently from its slug so
    /// the header can be told apart from the guess made before it arrived.
    final landed = TopicDetail(
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

    /// Catches what would have been handed to the platform browser.
    List<String> watchBrowser(WidgetTester tester) {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      return launched;
    }

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
      // The slug was only a stand-in until the topic named itself.
      expect(find.text('The other one [solved]'), findsOneWidget);
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

      // The site's own list is what the topic sits on top of, so back lands
      // there rather than on the site the link was read from.
      await tester.tap(find.byIcon(Icons.arrow_back));
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
      // Same site, but nothing here can draw it.
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
  });

  group('replying', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    List<DiscourseInstance> connectedSites() => [
      instance('meta.discourse.org', title: 'Discourse Meta').copyWith(user: me),
      instance('team.discourse.org', title: 'Discourse Team').copyWith(user: me),
    ];

    FakeAuthenticator signedIn() => FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'meta-key'
      ..keys['https://team.discourse.org'] = 'team-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicDetail detail({bool canCreatePost = true}) => TopicDetail(
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
      postsCount: 1,
      canCreatePost: canCreatePost,
    );

    /// Opens the topic, which is where every reply starts.
    Future<void> openTopic(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: signedIn(),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
    }

    Finder sendButton() => find.widgetWithText(FilledButton, 'Reply');

    testWidgets('the reply affordances wait for permission to use them', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(canCreatePost: false)},
      );

      await openTopic(tester, api);

      // can_create_post is the whole question — the guardian behind it has
      // already accounted for closed, archived and who may post past them.
      expect(find.byTooltip('Reply to this topic'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Reply'), findsNothing);
    });

    testWidgets('replying to a topic posts what was typed', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      // The topic is still readable underneath, which is the point of docking
      // it rather than opening a sheet.
      expect(renderedText('First post body'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Sounds good to me.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created, hasLength(1));
      expect(api.created.single['raw'], 'Sounds good to me.');
      expect(api.created.single['topicId'], 7);
      expect(api.created.single['siteUrl'], 'https://meta.discourse.org');
      expect(api.created.single['draftKey'], 'topic_7');
      // Replying to the topic addresses no particular post.
      expect(api.created.single['replyToPostNumber'], isNull);

      // Posted, so the composer is done and the reply is in the stream.
      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('Sounds good to me.'), findsOneWidget);
    });

    testWidgets('replying to a post addresses it by post number', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.widgetWithText(TextButton, 'Reply'));
      await tester.pumpAndSettle();

      expect(find.text('Reply to @sam'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Agreed.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['replyToPostNumber'], 1);
    });

    testWidgets('always reports how long the reply took to type', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Quick one.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Absent means zero to Discourse, which silences the account on a first
      // post rather than merely queueing it.
      expect(api.created.single['typingDurationMsecs'], isNotNull);
      expect(api.created.single['composerOpenDurationMsecs'], isNotNull);
    });

    testWidgets('cmd-enter sends without reaching for the button', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Shipped.');
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(api.created.single['raw'], 'Shipped.');
    });

    testWidgets('a refused reply keeps the text and says why', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(
          WriteFailure.validation,
          errors: ['Body is too short (minimum is 20 characters)'],
          statusCode: 422,
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(
        find.text('Body is too short (minimum is 20 characters)'),
        findsOneWidget,
      );
      // Losing what someone wrote because the server said no is the one
      // unforgivable thing a composer can do.
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('no'), findsOneWidget);
    });

    testWidgets('a queued reply is not shown as posted', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        creation: const PostCreation(
          outcome: PostOutcome.enqueued,
          message: 'Your post is in the queue.',
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Held for review.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Success, and nothing to put in the stream: the author would otherwise
      // see a reply nobody else can.
      expect(find.text('Your post is in the queue.'), findsOneWidget);
      expect(renderedText('Held for review.'), findsNothing);

      // It was accepted, so sending again would queue a second copy.
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
    });

    testWidgets('switching sites mid-reply does not post to the new one', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Meant for meta.');
      await tester.pumpAndSettle();

      // Switching sites hides the composer rather than discarding it, and it
      // stays bound to where it was opened. (The rail draws initials.)
      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.text('DM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Meant for meta.'), findsOneWidget);

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['siteUrl'], 'https://meta.discourse.org');
    });

    testWidgets('a rate limit holds sending back until the wait is up', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(
          WriteFailure.rateLimited,
          errors: ['You are posting too quickly.'],
          statusCode: 429,
          retryAfter: Duration(seconds: 2),
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Too eager.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text('You are posting too quickly.'), findsOneWidget);
      // Sending again during the wait only earns another refusal.
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
    });

    testWidgets('an unreachable site is checked rather than retried', (
      tester,
    ) async {
      // The post was created; only the answer was lost. Sending again would
      // publish it twice, since a user API key gets no idempotency.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(),
          // What the check finds when it re-reads the topic.
        },
        postsById: {
          2: const Post(
            id: 2,
            postNumber: 2,
            username: 'joffreyj',
            cooked: '<p>It landed.</p>',
            raw: 'It landed.',
          ),
        },
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'It landed.');
      await tester.pumpAndSettle();

      // The re-read shows the post that was made after all.
      api.topics[7] = TopicDetail(
        id: 7,
        title: 'A real topic',
        posts: [detail().posts.first],
        stream: const [1, 2],
        postsCount: 2,
        canCreatePost: true,
      );

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Only ever one create, whatever happened to its answer.
      expect(api.created, hasLength(1));
      // The tail was read with the markdown, so the match is exact rather
      // than a guess at what the server made of it.
      expect(api.postFetches.last, contains(2));
      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('It landed.'), findsOneWidget);
    });

    testWidgets('a check that finds nothing lets the reply be sent again', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Never arrived.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Nothing in the topic matches it, so it really did not post.
      expect(find.text("Couldn't reach the site."), findsOneWidget);
      expect(find.text('Never arrived.'), findsOneWidget);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
    });

    testWidgets('a check that cannot be made holds sending back', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unknown fate.');
      await tester.pumpAndSettle();

      // The site is unreachable for the check too.
      api.topics.remove(7);

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Whether it posted is unknown, and guessing wrong means posting twice.
      expect(find.textContaining('may have posted'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Check again');
      expect(button, findsOneWidget);
      expect(find.text('Unknown fate.'), findsOneWidget);

      // Checking again is the way out, and it does not send anything.
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(api.created, hasLength(1));
    });

    testWidgets('closing the composer sends nothing', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.created, isEmpty);
    });
  });

  group('drafts', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    List<DiscourseInstance> connectedSites() => [
      instance('meta.discourse.org', title: 'Discourse Meta').copyWith(user: me),
    ];

    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'meta-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicDetail detail({ComposerDraft? draft, int draftSequence = 0}) =>
        TopicDetail(
          id: 7,
          title: 'A real topic',
          posts: const [
            Post(
              id: 1,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>First post body</p>',
            ),
          ],
          stream: const [1],
          postsCount: 1,
          canCreatePost: true,
          draft: draft,
          draftSequence: draftSequence,
        );

    Future<void> openComposer(
      WidgetTester tester,
      FakeDiscourseApi api, {
      FakeDraftStore? drafts,
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: signedIn(),
        drafts: drafts,
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    /// Lets the debounce elapse so the save actually goes out.
    Future<void> settleDraft(WidgetTester tester) async {
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();
    }

    testWidgets('typing is saved to the site after a pause', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Half a thought');
      await tester.pumpAndSettle();

      // Not per keystroke.
      expect(api.draftsSaved, isEmpty);

      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(1));
      expect(api.draftsSaved.single['draftKey'], 'topic_7');
      // Sequenced against what the topic payload came with.
      expect(api.draftsSaved.single['sequence'], 4);
      expect(api.draftsSaved.single['data'], contains('Half a thought'));
    });

    testWidgets('a draft is put back when the composer is reopened', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Come back to this');
      await settleDraft(tester);

      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

      // Closing is how you get the topic back, not how you throw a reply away.
      expect(find.text('Come back to this'), findsOneWidget);
    });

    testWidgets('a draft the site already had is restored on open', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            draft: const ComposerDraft(
              reply: 'Started in a browser',
              replyToPostNumber: 1,
              replyToUsername: 'sam',
            ),
          ),
        },
      );

      await openComposer(tester, api);

      // It arrives with the topic payload, so no request of its own.
      expect(find.text('Started in a browser'), findsOneWidget);
      // And it remembers who it was answering.
      expect(find.text('Reply to @sam'), findsOneWidget);
    });

    testWidgets('a draft the site would not take is kept on the device', (
      tester,
    ) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Written offline');
      await settleDraft(tester);

      // The local copy is written first and only removed once the site has the
      // same text, so a failed sync cannot lose it.
      expect(drafts.saved, hasLength(1));
      expect(drafts.saved.values.single, contains('Written offline'));
      expect(
        find.text('Not saved on the site — kept on this device only.'),
        findsOneWidget,
      );
    });

    testWidgets('the sync stops asking a site that will not answer', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api);

      for (var attempt = 1; attempt <= ComposerController.maxDraftFailures; attempt++) {
        await tester.enterText(find.byType(TextField), 'Attempt $attempt');
        await settleDraft(tester);
      }
      expect(api.draftsSaved, hasLength(ComposerController.maxDraftFailures));

      await tester.enterText(find.byType(TextField), 'And one more');
      await settleDraft(tester);

      // Still exactly as many: it gave up rather than kept hammering.
      expect(api.draftsSaved, hasLength(ComposerController.maxDraftFailures));
    });

    testWidgets('posting clears the draft it was written as', (tester) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Going out now');
      await settleDraft(tester);
      expect(drafts.saved, isNotEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Reply'));
      await tester.pumpAndSettle();

      // Discourse deletes its own copy when it accepts a post; ours has to go
      // too, or reopening the composer offers to write the reply again.
      expect(drafts.saved, isEmpty);
    });
  });
}
