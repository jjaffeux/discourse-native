import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

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
      // Never the real one: it opens a long poll, and its backoff timer
      // outlives the tree the binding then complains about.
      trackers: FakeSiteTracker.reset(),
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

/// The surface the first post paints for itself, which is what hovering it
/// changes. The innermost [ColoredBox] above the body is the post's own.
Color postBackground(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .ancestor(
            of: renderedText('First post body'),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

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

/// The account avatar in the top right, wherever the layout has put it.
final Finder userMenu = find.byKey(UserMenuButton.avatarKey);

/// A sidebar entry by its label. Scoped to the sidebar because the user menu
/// names some of the same things — "Messages" is both a destination and a tab.
Finder sidebarDestination(String label) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.text(label),
);

/// Opens the account menu and walks to the section holding the real actions.
/// On touch that is a row leading to a nested sheet; with a pointer it is an
/// icon in the tab rail, named only by its tooltip.
Future<void> openProfileSection(WidgetTester tester) async {
  await tester.tap(userMenu);
  await tester.pumpAndSettle();

  final tab = find.byTooltip('Profile');
  await tester.tap(tab.evaluate().isEmpty ? find.text('Profile') : tab);
  await tester.pumpAndSettle();
}

/// Moves a mouse over the first post, which is what reveals its actions.
Future<TestGesture> hoverPost(
  WidgetTester tester, {
  String body = 'First post body',
}) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(renderedText(body)));
  await tester.pumpAndSettle();
  return gesture;
}

void main() {
  group('compact', () {
    testWidgets('shows the rail and the sidebar, but no main content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
    });

    testWidgets('selecting a destination replaces the sidebar with content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      // The rail never goes away.
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('back returns from content to the sidebar', (tester) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
    });

    testWidgets('back unwinds the content stack before the sidebar', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace with deeper view'));
      await tester.pumpAndSettle();

      expect(find.text('Topic 1'), findsWidgets);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      // First back pops the stack; the sidebar is still not showing.
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
    });

    testWidgets('the avatar follows whichever pane is showing', (tester) async {
      await pumpShell(tester, phone);

      // Only one pane is on screen at a time, so there is only ever one.
      expect(userMenu, findsOneWidget);
      final onSidebar = tester.getRect(userMenu);

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      expect(userMenu, findsOneWidget);
      // Same corner, now belonging to the content header.
      expect(tester.getRect(userMenu), onSidebar);
    });
  });

  group('medium', () {
    testWidgets('shows rail, sidebar and content together', (tester) async {
      await pumpShell(tester, laptop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
    });
  });

  group('expanded', () {
    testWidgets('shows rail, sidebar and content', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
    });

    testWidgets('the avatar sits in the top right corner', (tester) async {
      await pumpShell(tester, desktop);

      // Only in the column reaching furthest right: the sidebar's own header
      // stays free of it while the main content is on screen.
      expect(userMenu, findsOneWidget);

      final content = tester.getRect(find.byType(MainContent));
      final avatar = tester.getRect(userMenu);

      expect(content.right - avatar.right, lessThan(16));
      expect(avatar.top - content.top, lessThan(shellHeaderHeight));
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

      await tester.tap(find.dIcon(DIcons.plus));
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

  group('removing a site', () {
    /// The rail draws no text of its own, so a site is identified by the
    /// tooltip naming it.
    Finder railItem(String title, String host) =>
        find.byTooltip('$title\n$host');

    final meta = railItem('Discourse Meta', 'meta.discourse.org');

    testWidgets('a long press leads to the removal through a sheet', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      await tester.longPress(meta);
      await tester.pumpAndSettle();

      // A thumb ends up inside the menu it just opened, so the destructive
      // action is not in it — only the way to it.
      expect(find.text('More Options'), findsOneWidget);
      expect(find.text('Remove forum'), findsNothing);

      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();

      expect(find.text('Remove forum'), findsOneWidget);
    });

    testWidgets('a right click offers the removal directly', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // A distinct key rebuilds the tree against the platform in effect.
        await pumpShell(tester, desktop, key: const ValueKey('macos'));

        await tester.tap(meta, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        expect(find.text('Remove forum'), findsOneWidget);
        expect(find.text('More Options'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('holding a site does not pop its tooltip as well', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.longPress(meta);
      await tester.pumpAndSettle();

      // The tooltip's own long-press trigger would otherwise fire under the
      // menu, naming the site twice.
      expect(find.text('Discourse Meta\nmeta.discourse.org'), findsNothing);
    });

    testWidgets('removing asks first, and answering no keeps the site', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Discourse Meta?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(meta, findsOneWidget);
      expect(store.saveCount, 0);
    });

    testWidgets('confirming takes the site out of the rail and stores it', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final api = FakeDiscourseApi();
      final auth = FakeAuthenticator();

      await pumpShell(
        tester,
        phone,
        store: store,
        api: api,
        authenticator: auth,
      );

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(meta, findsNothing);
      expect(railItem('Discourse Team', 'team.discourse.org'), findsOneWidget);
      // The site that was being read went away, so the one left takes over.
      expect(find.text('Discourse Team'), findsOneWidget);
      expect(auth.disconnected, ['https://meta.discourse.org']);
      expect(store.saveCount, 1);
    });

    testWidgets('a keychain that refuses cannot hold the site in the rail', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator(
        disconnectFailure: PlatformException(
          code: '-34018',
          message: "A required entitlement isn't present.",
        ),
      );

      await pumpShell(tester, phone, store: store, authenticator: auth);

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Abandoning the removal half done is the worse answer: the key is gone
      // from the site either way, and the user is left unable to remove it.
      expect(meta, findsNothing);
      expect(store.saveCount, 1);
    });

    testWidgets('removing the last site leaves the empty state', (
      tester,
    ) async {
      final store = FakeInstanceStore([
        instance('meta.discourse.org', title: 'Discourse Meta'),
      ]);

      await pumpShell(tester, desktop, store: store);

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('removing one site does not disturb the one being read', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
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
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: [1],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await tester.longPress(railItem('Discourse Team', 'team.discourse.org'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // The reader was on the other site; taking this one away is not a reason
      // to throw away where they were.
      expect(renderedText('First post body'), findsOneWidget);
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

    /// Messages is the only destination the sidebar offers besides Topics, and
    /// the inbox is named after the signed-in user, so reaching it means
    /// connecting first.
    const inbox = '/topics/private-messages/joffreyj.json';

    testWidgets('picking a destination fetches its own list', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains(inbox));
      expect(find.text('A private message'), findsOneWidget);
    });

    testWidgets('a list is not refetched when revisited', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Topics'));
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

    testWidgets('messages has no list endpoint without a username', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      // The inbox path is named after the account, so with no signed-in user
      // it falls back to the placeholder rather than firing a bad request.
      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Replace with deeper view'), findsOneWidget);
    });
  });

  group('incoming topics', () {
    final onList = [
      const Topic(id: 1, title: 'Welcome to the forum', slug: 'welcome'),
      const Topic(id: 2, title: 'Something else', slug: 'something-else'),
    ];

    /// `/new`, shaped as `TopicTrackingState.publish_new` sends it.
    Map<String, Object?> created(int topicId) => {
      'topic_id': topicId,
      'message_type': 'new_topic',
      'payload': {'highest_post_number': 1, 'created_in_new_period': true},
    };

    /// `/latest`, published when a post bumps a topic that already exists.
    Map<String, Object?> bumped(int topicId) => {
      'topic_id': topicId,
      'message_type': 'latest',
      'payload': {'bumped_at': '2026-08-06T09:00:00.000Z'},
    };

    /// The tracker for the site the shell opened on.
    FakeSiteTracker tracker() => FakeSiteTracker.built.first;

    Future<void> pumpWithFeeds(
      WidgetTester tester,
      FakeDiscourseApi api,
    ) async {
      await pumpShell(tester, desktop, api: api);
      // The tracker is opened once the keychain has answered.
      await tester.pumpAndSettle();
    }

    testWidgets('a topic created on the site announces itself', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      expect(find.textContaining('See '), findsNothing);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();

      expect(find.text('See 1 new or updated topic'), findsOneWidget);
    });

    testWidgets('the count is of topics, not of messages', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      tracker()
        ..deliver(created(99))
        ..deliver(created(100))
        // A reply to one of them is the same row, not another one.
        ..deliver(bumped(99));
      await tester.pumpAndSettle();

      expect(find.text('See 2 new or updated topics'), findsOneWidget);
    });

    testWidgets('tapping it fetches those topics and puts them on top', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': onList,
          '/latest.json?topic_ids=99': [
            const Topic(id: 99, title: 'Just posted', slug: 'just-posted'),
          ],
        },
      );
      await pumpWithFeeds(tester, api);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      // Asked of the list route itself, so the row arrives with everything
      // that list draws rather than as a bare topic.
      expect(api.feedPaths, contains('/latest.json?topic_ids=99'));
      expect(find.text('Just posted'), findsOneWidget);
      expect(find.text('Welcome to the forum'), findsOneWidget);
      // Nothing left to announce.
      expect(find.textContaining('See '), findsNothing);
    });

    testWidgets('a topic that was only bumped is moved, not duplicated', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': onList,
          '/latest.json?topic_ids=2': [onList[1]],
        },
      );
      await pumpWithFeeds(tester, api);

      tracker().deliver(bumped(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      expect(find.text('Something else'), findsOneWidget);
    });

    testWidgets('a fetch that fails leaves the banner to be tried again', (
      tester,
    ) async {
      // No `topic_ids` feed configured, so the call throws.
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      expect(find.text('See 1 new or updated topic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refetching the list clears what it is about to contain', (
      tester,
    ) async {
      // Pull-to-refresh replaces the list wholesale, so what the banner was
      // offering to fetch arrives in the response instead.
      final controller = ShellController(
        instanceStore: FakeInstanceStore(twoSites),
        api: FakeDiscourseApi(feeds: {'/latest.json': onList}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      // The tracker is opened once the keychain has answered.
      await tester.pump();

      FakeSiteTracker.built.first.deliver(created(99));
      expect(controller.incomingCount('latest'), 1);

      await controller.loadFeed('latest', force: true);

      expect(controller.incomingCount('latest'), 0);
    });

    testWidgets('only the site being read holds a connection open', (
      tester,
    ) async {
      await pumpWithFeeds(tester, FakeDiscourseApi());

      expect(FakeSiteTracker.built, hasLength(1));

      // Second entry in the rail.
      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built, hasLength(2));
      expect(FakeSiteTracker.built.first.polling, isFalse);
      expect(FakeSiteTracker.built.last.polling, isTrue);
    });

    testWidgets('an app coming back to the front reconnects at once', (
      tester,
    ) async {
      await pumpWithFeeds(tester, FakeDiscourseApi());

      // Backgrounded, the connection is left to the client's own pacing.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tracker().pollNowCalls, 0);

      // Back in front, it is asked immediately rather than waiting out a
      // backoff that started while the connection was dead.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tracker().pollNowCalls, 1);
    });
  });

  group('live counters', () {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');

    final dot = find.byKey(UserMenuButton.unreadDotKey);

    /// A site that is already signed in, so the counter channels have an
    /// account to be named after.
    Future<FakeSiteTracker> pumpConnected(
      WidgetTester tester, {
      NotificationTotals totals = const NotificationTotals(),
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: FakeDiscourseApi(totals: totals),
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.pumpAndSettle();
      return FakeSiteTracker.built.first;
    }

    testWidgets('the account id is what names the counter channels', (
      tester,
    ) async {
      final tracker = await pumpConnected(tester);

      expect(tracker.userId, 7);
    });

    testWidgets('a notification arriving marks the avatar', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(dot, findsNothing);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 1,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(dot, findsOneWidget);
    });

    testWidgets('reading them somewhere else takes the mark away', (
      tester,
    ) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      expect(dot, findsOneWidget);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 0,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(dot, findsNothing);
    });

    testWidgets('the counts move with it, not just the mark', (tester) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      // The rail badge, which is everything addressed to this account.
      expect(find.text('3'), findsOneWidget);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 5,
        'new_personal_messages_notifications_count': 2,
      });
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
      // And the private messages counted once, under their own name.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a filling review queue marks it too', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(dot, findsNothing);

      // Published on a channel of its own, and only to staff.
      tracker.deliverReviewableCounts(const {
        'reviewable_count': 4,
        'unseen_reviewable_count': 2,
      });
      await tester.pumpAndSettle();

      expect(dot, findsOneWidget);
    });

    testWidgets('a site with nobody signed in has no counters to track', (
      tester,
    ) async {
      await pumpShell(tester, desktop);
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built.first.userId, isNull);
      expect(dot, findsNothing);
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

    testWidgets('the next page can be asked for from inside a layout', (
      tester,
    ) async {
      // The caller this stands in for is the load-more handler. A viewport
      // that has to correct its scroll position starts a scroll from inside
      // its own layout, and the notification that comes out of it reaches the
      // handler there — so the controller is asked for a page mid-frame, where
      // marking the tree dirty is an error rather than a rebuild.
      //
      // Re-creating that correction takes a precise pile of geometry;
      // LayoutBuilder puts the call in the same phase directly, which is the
      // part that has to hold.
      final controller = ShellController(
        instanceStore: FakeInstanceStore(twoSites),
        api: FakeDiscourseApi(
          feeds: {
            '/latest.json': page(1, 3),
            '/latest.json?page=1': page(4, 3),
          },
          nextPages: {'/latest.json': '/latest?page=1'},
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            home: LayoutBuilder(
              builder: (context, _) {
                ShellScope.of(context).loadMoreFeed('latest');
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // And the page was actually fetched, rather than the ask being dropped.
      expect(controller.currentFeed?.topicIds, hasLength(6));
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

    TopicPayload detail({List<int> stream = const [1]}) => topicPayload(
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
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(TopicListView), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('reading a topic clears its unread count on every list it is '
        'in', (tester) async {
      // A list holds ids, and there is one topic behind an id — so reading it
      // is one write, and no list has to be told anything.
      final unread = [
        const Topic(
          id: 7,
          title: 'A real topic',
          slug: 'a-real-topic',
          unreadPosts: 3,
        ),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': unread},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      // The row it was opened from.
      expect(find.text('3'), findsNothing);

      // There is nothing left holding a count: the topic itself now reads as
      // read, so any other list holding its id draws the corrected row without
      // a fetch and without being told.
      final controller = ShellScope.of(
        tester.element(find.byType(InstanceRail)),
      );
      expect(
        controller.store
            .read<Topic>(controller.currentInstance!.url, 7)!
            .hasUnread,
        isFalse,
      );
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
      await tester.tap(find.dIcon(DIcons.arrowLeft));
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
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
    });

    testWidgets('the post under the pointer is picked out', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final hover = Theme.of(
        tester.element(find.byType(TopicView)),
      ).shell.hover;

      // Idle posts take the column's own surface rather than painting one.
      expect(postBackground(tester), Colors.transparent);

      final gesture = await hoverPost(tester);
      expect(postBackground(tester), hover);

      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(postBackground(tester), Colors.transparent);
    });
  });

  group('connecting', () {
    testWidgets('the avatar says so until you connect', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byTooltip('Not signed in'), findsOneWidget);
    });

    testWidgets('connecting records the account against the site', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, store: store, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      // Authorized against the selected site, not some other one.
      expect(auth.connected, ['https://meta.discourse.org']);
      expect(find.byTooltip('Joffrey'), findsOneWidget);
      expect(find.text('meta.discourse.org'), findsWidgets);
      expect(store.saveCount, 1);
    });

    testWidgets('backing out of the browser is not an error', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.cancelled);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Not signed in'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an unverifiable reply is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.badReply);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      // Nothing is left on screen to hold the failure, so it is announced.
      expect(find.byType(SnackBar), findsOneWidget);
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
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      // Messages is the one sidebar entry with a count of its own.
      expect(find.text('2'), findsOneWidget);
      // Topic tracking has no entry to sit on: the sidebar collapses Latest,
      // New and Unread into a single Topics destination.
      expect(find.text('12'), findsNothing);
      expect(find.text('7'), findsNothing);
      // Rail badge is things addressed to you: 3 + 2.
      expect(find.text('5'), findsOneWidget);
      // All of it from the one totals call.
      expect(api.totalsCalls, 1);
    });

    testWidgets('a site whose counters fail still renders', (tester) async {
      // totals: null makes the call throw.
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Joffrey'), findsOneWidget);
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

      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      final afterConnect = api.totalsCalls;

      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      await tester.tap(userMenu);
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

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      await openProfileSection(tester);
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

      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Joffrey'), findsOneWidget);

      await openProfileSection(tester);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(auth.disconnected, ['https://meta.discourse.org']);
      // Both sheets are gone with it, and the avatar is back to signed out.
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byTooltip('Not signed in'), findsOneWidget);
    });
  });

  group('the user menu', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');
    final connected = [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
    ];

    /// These instances carry an account without having been through the
    /// connect flow, which is what would otherwise have left a key behind.
    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'api-key';

    const notifications = [
      DiscourseNotification(
        id: 1,
        kind: NotificationKind.replied,
        actor: 'sam',
        title: 'Better image handling',
        topicId: 7,
        slug: 'better-image-handling',
        path: '/t/better-image-handling/7',
      ),
      DiscourseNotification(
        id: 2,
        kind: NotificationKind.liked,
        read: true,
        actor: 'david',
        title: 'Merge CVSS',
        topicId: 8,
        path: '/t/merge-cvss/8',
      ),
      // This app has no badge page, so this one leads out to the browser.
      DiscourseNotification(
        id: 3,
        kind: NotificationKind.grantedBadge,
        badgeName: 'Nice Reply',
        path: '/badges/24/nice-reply',
      ),
      // And this one points at nothing at all.
      DiscourseNotification(
        id: 4,
        kind: NotificationKind.unknown,
        title: 'Something from a plugin',
      ),
    ];

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
    }

    /// Opens the notifications tab on a touch layout, which is a sheet of its
    /// own on top of the menu.
    Future<void> openNotifications(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
    }

    testWidgets('a thumb gets a sheet, and one sheet per section inside it', (
      tester,
    ) async {
      await pumpShell(tester, phone, instances: connected);
      await openMenu(tester);

      // Listed rather than tabbed, and no popover in sight.
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.text('Joffrey'), findsOneWidget);
      expect(find.text('@joffreyj · meta.discourse.org'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();

      expect(find.textContaining('joshua.m replied to'), findsOneWidget);
      // The sheet it came from is still under this one — nested, not swapped —
      // so the way out of this one is back to it.
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.dIcon(DIcons.arrowLeft), findsOneWidget);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.textContaining('joshua.m replied to'), findsNothing);
    });

    testWidgets('a title bar takes the avatar off the columns', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // A distinct key rebuilds the tree against the platform in effect.
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          key: const ValueKey('macos'),
        );

        expect(userMenu, findsOneWidget);
        final avatar = tester.getRect(userMenu);

        // In the strip spanning the window, above every column rather than
        // inside one of them.
        expect(
          tester.getRect(find.byType(ShellTitleBar)).contains(avatar.center),
          isTrue,
        );
        expect(
          avatar.bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(MainContent)).top),
        );
        expect(desktop.width - avatar.right, lessThan(16));
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('a pointer gets a popover with a tab per section', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // A distinct key rebuilds the tree against the platform in effect.
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          api: FakeDiscourseApi(notificationList: notifications),
          authenticator: signedIn(),
          key: const ValueKey('macos'),
        );
        await openMenu(tester);

        expect(find.byType(UserMenuPanel), findsOneWidget);
        // Opens on the notifications tab, the way Discourse does.
        expect(
          find.textContaining('sam replied to Better image handling'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Likes'));
        await tester.pumpAndSettle();

        expect(find.text('Likes'), findsOneWidget);
        expect(find.textContaining('sam replied to'), findsNothing);
        expect(find.textContaining('liked your post'), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('the account section is last and holds the disconnect', (
      tester,
    ) async {
      await pumpShell(tester, phone, instances: connected);
      await openMenu(tester);

      // Nothing else in the menu can act on the account.
      expect(find.text('Disconnect'), findsNothing);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('everything not built yet is orange', (tester) async {
      await pumpShell(tester, phone, instances: connected);
      await openMenu(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final placeholder = Theme.of(
        tester.element(find.text('Preferences')),
      ).shell.placeholder;

      expect(
        tester.widget<Text>(find.text('Preferences')).style?.color,
        placeholder,
      );
      // ...and the one thing that works is not.
      expect(
        tester.widget<Text>(find.text('Disconnect')).style?.color,
        isNot(placeholder),
      );
    });

    testWidgets('the notifications tab reads what the site sent', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(api.notificationCalls, 1);
      // A sentence per kind, phrased from the payload rather than listed as
      // whatever the site called it.
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
      expect(
        find.textContaining('david liked your post in Merge CVSS'),
        findsOneWidget,
      );
      expect(
        find.textContaining('You earned the Nice Reply badge'),
        findsOneWidget,
      );
      // Nothing in here is a stand-in any more.
      final tab = tester.widget<Text>(find.text('Notifications').first);
      expect(
        tab.style?.color,
        isNot(Theme.of(tester.element(find.text('Profile'))).shell.placeholder),
      );
    });

    testWidgets('tapping one opens its topic and marks it read', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        notificationList: notifications,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Better image handling',
            posts: [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: [1],
          ),
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(
        find.textContaining('sam replied to Better image handling'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(api.markedRead, [1]);
      // Both sheets are out of the way of the topic they led to.
      expect(find.byType(NotificationRow), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('one the app has no page for opens the browser', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.textContaining('You earned the Nice Reply badge'));
      await tester.pumpAndSettle();

      // Resolved against the site it came from, since Discourse writes its own
      // links site-relative.
      expect(launched, ['https://meta.discourse.org/badges/24/nice-reply']);
      expect(api.markedRead, [3]);
      expect(find.byType(NotificationRow), findsNothing);
    });

    testWidgets('one with nowhere to go is read where it stands', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.textContaining('Something from a plugin'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [4]);
      expect(launched, isEmpty);
      // Closing the menu would only have revealed the screen it was already
      // over, so it stays.
      expect(find.byType(NotificationRow), findsWidgets);
    });

    testWidgets('notifications that will not load can be asked for again', (
      tester,
    ) async {
      // No list configured, so the fetch throws.
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.notificationCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty inbox says so rather than spinning', (tester) async {
      final api = FakeDiscourseApi(notificationList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(find.text('Nothing new.'), findsOneWidget);
    });

    testWidgets('reopening the tab asks the site again', (tester) async {
      final api = FakeDiscourseApi(notificationList: notifications);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      // A list of what other people just did is stale within minutes.
      expect(api.notificationCalls, 2);
      // ...and the rows already in hand stay put while it is refetched.
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
    });

    const bookmarks = [
      // Site-relative, which is what the parse leaves a topic link as — see
      // `Bookmark._path`.
      Bookmark(
        id: 8,
        title: 'Thinking about the next project',
        name: 'read this properly',
        author: 'sam',
        path: '/t/next-project/7/3',
      ),
      // Bookmarked on something this app has no view for, so it leads out to
      // the browser, and keeps the absolute URL the site sent.
      Bookmark(
        id: 9,
        title: 'A message in #dev',
        author: 'david',
        path: 'https://meta.discourse.org/chat/c/-/9/44',
      ),
    ];

    /// A reminder that has come due, which the tab lists above the bookmarks.
    const reminder = DiscourseNotification(
      id: 41,
      kind: NotificationKind.bookmarkReminder,
      title: 'Better image handling',
      topicId: 7,
      slug: 'better-image-handling',
      path: '/t/better-image-handling/7',
    );

    Future<void> openBookmarks(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
    }

    testWidgets('the bookmarks tab reads what the site sent', (tester) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        reminderList: const [reminder],
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      // The account's own bookmarks; Discourse refuses anybody else's.
      expect(api.bookmarksRequested, ['joffreyj']);
      // The reminder first, then what is kept.
      expect(
        find.textContaining('Reminder: Better image handling'),
        findsOneWidget,
      );
      expect(
        find.textContaining('sam Thinking about the next project'),
        findsOneWidget,
      );
      // Nothing in here is a stand-in any more.
      final tab = tester.widget<Text>(find.text('Bookmarks').first);
      expect(
        tab.style?.color,
        isNot(Theme.of(tester.element(find.text('Profile'))).shell.placeholder),
      );
    });

    testWidgets('tapping one opens the topic it was kept from', (tester) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Thinking about the next project',
            posts: [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: [1],
          ),
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(
        find.textContaining('sam Thinking about the next project'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      // Both sheets are out of the way of the topic they led to.
      expect(find.byType(BookmarkRow), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('a topic opens here even when the site named another host', (
      tester,
    ) async {
      // Straight off the wire, because it is the parse that has to take the
      // host off: `Discourse.base_url` is the site's own idea of where it
      // lives, and a development site's is not the origin the app connected
      // through. Left alone, its own topics look like somebody else's and go
      // to the browser.
      final api = FakeDiscourseApi(
        bookmarkList: [
          Bookmark.fromJson(const {
            'id': 8,
            'title': 'Thinking about the next project',
            'bookmarkable_url': 'http://localhost:4200/t/next-project/7/3',
            'user': {'username': 'sam'},
          }),
        ],
        topics: {
          7: topicPayload(id: 7, title: 'Thinking about the next project'),
        },
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: [instance('localhost:3000').copyWith(user: me)],
        api: api,
        authenticator: FakeAuthenticator()
          ..keys['https://localhost:3000'] = 'api-key',
      );
      await openBookmarks(tester);
      await tester.tap(
        find.textContaining('sam Thinking about the next project'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(launched, isEmpty);
    });

    testWidgets('one on something the app has no page for opens the browser', (
      tester,
    ) async {
      final api = FakeDiscourseApi(bookmarkList: bookmarks);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(find.textContaining('david A message in #dev'));
      await tester.pumpAndSettle();

      expect(launched, ['https://meta.discourse.org/chat/c/-/9/44']);
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('a reminder in here is read like any other notification', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        reminderList: const [reminder],
        topics: {7: topicPayload(id: 7, title: 'Better image handling')},
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(find.textContaining('Reminder: Better image handling'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [41]);
      expect(api.topicsOpened, [7]);
    });

    testWidgets('nothing kept says so rather than spinning', (tester) async {
      final api = FakeDiscourseApi(bookmarkList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      expect(find.text('Nothing bookmarked yet.'), findsOneWidget);
    });

    testWidgets('bookmarks that will not load can be asked for again', (
      tester,
    ) async {
      // No list configured, so the fetch throws.
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.bookmarksRequested.length, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('user cards', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    final detail = topicPayload(
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

    /// The topic behind every link below, titled differently from its slug so
    /// the header can be told apart from the guess made before it arrived.
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
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
      instance(
        'team.discourse.org',
        title: 'Discourse Team',
      ).copyWith(user: me),
    ];

    FakeAuthenticator signedIn() => FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'meta-key'
      ..keys['https://team.discourse.org'] = 'team-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail({bool canCreatePost = true}) => topicPayload(
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
      await hoverPost(tester);
      expect(find.byTooltip('Reply to this post'), findsNothing);
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
      await hoverPost(tester);
      await tester.tap(find.byTooltip('Reply to this post'));
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
      api.topics[7] = topicPayload(
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

    testWidgets('a post keeps its actions out of the way until hovered', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      // A long topic should not read as a column of buttons.
      expect(find.byTooltip('Reply to this post'), findsNothing);

      final gesture = await hoverPost(tester);
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // Leaving takes them away on the very next frame — no grace period to
      // wait out, which reads as lag.
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('the menu follows its post, and stays in the viewport', (
      tester,
    ) async {
      // One post far taller than the window, which is the case that put the
      // menu above the fold when it was pinned to the post's top edge.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>Top of the long post</p>${'<p>filler</p>' * 120}',
              ),
            ],
            stream: const [1],
            postsCount: 1,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      await hoverPost(tester, body: 'Top of the long post');
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      final before = tester.getTopLeft(find.byTooltip('Reply to this post'));
      final viewport = tester.getRect(find.byType(TopicView));
      expect(before.dy, greaterThanOrEqualTo(viewport.top));

      await tester.drag(find.byType(TopicView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Still there, and still inside the topic rather than over the header.
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
      final after = tester.getTopLeft(find.byTooltip('Reply to this post'));
      expect(after.dy, greaterThanOrEqualTo(viewport.top));
      expect(after.dy, lessThan(viewport.bottom));
    });

    testWidgets('the menu goes when its post scrolls out of sight', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              for (var i = 1; i <= 20; i++)
                Post(
                  id: i,
                  postNumber: i,
                  username: 'sam',
                  cooked: '<p>Post body $i</p>',
                ),
            ],
            stream: [for (var i = 1; i <= 20; i++) i],
            postsCount: 20,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      final gesture = await hoverPost(tester, body: 'Post body 5');
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // Park the pointer outside the list so no other post picks the menu up,
      // then scroll post 5 away.
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await tester.drag(find.byType(TopicView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('on a touch screen the actions arrive as a sheet', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.longPress(renderedText('First post body'));
      await tester.pumpAndSettle();

      // There is no pointer to hover with, so the same action is reached by
      // holding the post.
      expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Reply'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Reply to @sam'), findsOneWidget);
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

  group('editing and deleting', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    Post mine({
      bool canEdit = true,
      bool canDelete = true,
      bool canRecover = false,
      DateTime? deletedAt,
    }) => Post(
      id: 1,
      postNumber: 1,
      username: 'joffreyj',
      cooked: '<p>First post body</p>',
      canEdit: canEdit,
      canDelete: canDelete,
      canRecover: canRecover,
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
      await tester.tap(find.byTooltip('Edit this post'));
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
      // Sent, so the composer goes and the rewritten post is what is drawn.
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
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      // Not a rule of ours — the site refuses an unchanged edit — but there is
      // no reason to spend a request finding that out.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('an edit never saves over a post it could not read', (
      tester,
    ) async {
      // No raw to be had: the fetch answers with nothing for this id.
      await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      // The field is empty, and saving that would blank the post rather than
      // leave it alone — so there is nothing to press.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('deleting re-reads what it did, and offers the undo', (
      tester,
    ) async {
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
      await tester.tap(find.byTooltip('Delete this post'));
      await tester.pumpAndSettle();

      // Nothing to confirm: the undo is the next thing in the same menu.
      expect(api.deleted, [1]);
      // Shown as deleted rather than taken away, because the person who can
      // undo it is the person looking at it.
      expect(find.text('deleted'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Put this post back'), findsOneWidget);
      expect(find.byTooltip('Delete this post'), findsNothing);
    });

    testWidgets('a post that is really gone stops being drawn', (tester) async {
      // Nothing comes back for the id, which is the site saying it is no
      // longer there — or no longer ours to see.
      final api = await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Delete this post'));
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
      await tester.tap(find.byTooltip('Put this post back'));
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
      await tester.tap(find.byTooltip('Delete this post'));
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(find.textContaining("You can't post that here"), findsOneWidget);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('on a touch screen the same actions arrive as a sheet', (
      tester,
    ) async {
      await openTopic(tester, post: mine());

      await tester.longPress(renderedText('First post body'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Delete'), findsOneWidget);
    });
  });

  group('likes', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    /// A post in whichever of the four states a like can leave it in.
    Post post({
      int likeCount = 0,
      bool liked = false,
      bool canLike = true,
      bool canUnlike = false,
    }) => Post(
      id: 1,
      postNumber: 1,
      username: 'sam',
      cooked: '<p>First post body</p>',
      likeCount: likeCount,
      liked: liked,
      canLike: canLike,
      canUnlike: canUnlike,
    );

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required Post first,
      Map<int, List<PostLiker>> likersById = const {},
      Map<int, Post> likeResponses = const {},
      Map<int, Post> postsById = const {},
      WriteException? likeFailure,
      Completer<void>? likerGate,
      Completer<void>? likeGate,
    }) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [first],
            stream: const [1],
            postsCount: 1,
          ),
        },
        postsById: postsById,
        likersById: likersById,
        likeResponses: likeResponses,
        likeFailure: likeFailure,
        likerGate: likerGate,
        likeGate: likeGate,
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

    /// The count under the post, which is also what opens the list of names.
    Finder count(String value) =>
        find.descendant(of: find.byType(PostLikes), matching: find.text(value));

    testWidgets('a post nobody has liked says so by saying nothing', (
      tester,
    ) async {
      await openTopic(tester, first: post());

      // No count: an empty one would be a row of zeroes down a topic nobody
      // has got round to reading yet.
      expect(find.byType(PostLikes), findsOneWidget);
      expect(count('0'), findsNothing);

      // The heart is in the menu instead, which is out of the way until the
      // post is pointed at.
      await hoverPost(tester);
      expect(find.byTooltip('Like this post'), findsOneWidget);
    });

    testWidgets(
      'liking from the menu draws the count before the site answers',
      (tester) async {
        final api = await openTopic(tester, first: post());

        await hoverPost(tester);
        await tester.tap(find.byTooltip('Like this post'));
        await tester.pumpAndSettle();

        expect(api.liked, [1]);
        expect(count('1'), findsOneWidget);
      },
    );

    testWidgets('a like of your own is the heart that takes it back', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false, canUnlike: true),
      );

      await hoverPost(tester);

      expect(find.byTooltip('Remove your like'), findsOneWidget);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('a like past the undo window leaves nothing to press', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false),
      );

      await hoverPost(tester);

      // The count still says it was liked, and by whom — the button would
      // only be one that refuses.
      expect(count('1'), findsOneWidget);
      expect(find.byTooltip('Remove your like'), findsNothing);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('the site has the last word on the count', (tester) async {
      // Two other people liked it while this reader was reading, which is
      // what the post the route answers with is for.
      await openTopic(
        tester,
        first: post(),
        likeResponses: {
          1: post(likeCount: 3, liked: true, canLike: false, canUnlike: true),
        },
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(count('3'), findsOneWidget);
    });

    testWidgets('tapping a like of your own takes it back', (tester) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false, canUnlike: true),
      );

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.unliked, [1]);
      expect(api.liked, isEmpty);
      expect(find.byType(PostLikes), findsOneWidget);
      expect(count('1'), findsNothing);
    });

    testWidgets('tapping somebody else\'s adds yours to it', (tester) async {
      final api = await openTopic(tester, first: post(likeCount: 1));

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(count('2'), findsOneWidget);
    });

    testWidgets('a refused like says why and puts the count back', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 1),
        likeFailure: const WriteException(WriteFailure.rateLimited),
      );

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(find.textContaining('Too fast'), findsOneWidget);
      expect(count('1'), findsOneWidget);
      expect(count('2'), findsNothing);
    });

    testWidgets('a post you may not like still shows what others thought', (
      tester,
    ) async {
      // Your own post: the site reports the count and no way to act on it.
      final api = await openTopic(
        tester,
        first: post(likeCount: 2, canLike: false),
      );

      expect(count('2'), findsOneWidget);

      await hoverPost(tester);
      expect(find.byTooltip('Like this post'), findsNothing);

      await tester.tap(count('2'));
      await tester.pumpAndSettle();
      expect(api.liked, isEmpty);
    });

    testWidgets('resting on the count says who liked it', (tester) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 2),
        likersById: {
          1: const [
            PostLiker(id: 3, username: 'sam', name: 'Sam Saffron'),
            PostLiker(id: 4, username: 'codinghorror'),
          ],
        },
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(count('2')));
      // Crossing the count on the way somewhere else must not open it, or
      // spend a request finding out who liked a post nobody asked about.
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.likersRequested, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(api.likersRequested, [1]);
      expect(find.text('Sam Saffron'), findsOneWidget);
      // No name on the account, so the username is the name.
      expect(find.text('codinghorror'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsNothing);
    });

    testWidgets('and says so when it cannot find out', (tester) async {
      await openTopic(tester, first: post(likeCount: 2));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(count('2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't reach"), findsOneWidget);
    });

    testWidgets('on a touch screen the names arrive as a sheet', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1),
        likersById: {
          1: const [PostLiker(id: 3, username: 'sam', name: 'Sam Saffron')],
        },
      );

      // The post underneath opens its own sheet on a long press; the count is
      // the nearer of the two and wins.
      await tester.longPress(count('1'));
      await tester.pumpAndSettle();

      expect(find.text('1 like'), findsOneWidget);
      expect(find.text('Sam Saffron'), findsOneWidget);
    });

    testWidgets('liking with the panel open leaves it saying something true', (
      tester,
    ) async {
      // Refused, which is the case that used to strand the panel: the names
      // were thrown away when the like was made and nothing put them back.
      final api = await openTopic(
        tester,
        first: post(likeCount: 2),
        likersById: {
          1: const [
            PostLiker(id: 3, username: 'sam', name: 'Sam Saffron'),
            PostLiker(id: 4, username: 'codinghorror'),
          ],
        },
        likeFailure: const WriteException(WriteFailure.rateLimited),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final pill = tester.getCenter(count('2'));
      await gesture.moveTo(pill);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsOneWidget);

      // Pressed without the pointer ever leaving the pill, so the panel is
      // still open when the refusal comes back.
      await gesture.down(pill);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('Too fast'), findsOneWidget);
      expect(count('2'), findsOneWidget);
      // Names, not a spinner, and asked for again rather than assumed.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(api.likersRequested, [1, 1]);
    });

    testWidgets('a double tap does not send two contradicting writes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        first: post(likeCount: 1),
        likeGate: gate,
      );

      // Twice, before the first has come back. The second reads the guess the
      // first wrote, so unguarded it would send an undo of a like the site has
      // not recorded yet — and whichever answer landed last would win.
      await tester.tap(count('1'));
      await tester.pump();
      await tester.tap(count('2'));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(api.unliked, isEmpty);
      expect(count('2'), findsOneWidget);
    });

    testWidgets('editing a post you liked leaves the like alone', (
      tester,
    ) async {
      // `PostsController#update` serializes without the reader's own post
      // actions, so the edit comes back claiming the post is unliked and
      // likeable — on a post they have in fact already liked.
      final api = await openTopic(
        tester,
        first: Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
          canEdit: true,
          likeCount: 3,
          liked: true,
          canUnlike: true,
        ),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'sam',
            cooked: '<p>First post body</p>',
            canEdit: true,
            raw: 'First post body',
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'First post body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(renderedText('First post body!'), findsOneWidget);
      // The heart survived the typo fix.
      expect(count('3'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(renderedText('First post body!')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove your like'), findsOneWidget);
    });
  });

  group('rich mode', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail() => topicPayload(
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
    );

    Future<void> openComposer(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    testWidgets('posts exactly the markdown that was written', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(
        find.byType(TextField),
        'press <kbd>Esc</kbd> to close',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit richly'));
      await tester.pumpAndSettle();
      expect(find.byType(SuperEditor), findsOneWidget);
      // The tags are gone from the surface — they are attributions now.
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Reply'));
      await tester.pumpAndSettle();

      // And the payload is byte-for-byte what was typed. The document model
      // is a view; the markdown is the thing.
      expect(api.created.single['raw'], 'press <kbd>Esc</kbd> to close');
    });

    testWidgets('goes back to the markdown unchanged', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'hey @sam **look**');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit richly'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit the markdown'));
      await tester.pumpAndSettle();

      expect(find.byType(SuperEditor), findsNothing);
      expect(find.text('hey @sam **look**'), findsOneWidget);
    });

    testWidgets('the toolbar marks up the markdown in plain mode', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'say hello');
      await tester.pumpAndSettle();

      // Select "hello".
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.bold));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'say **hello**');

      // The selection stayed on the word, so italic composes onto it.
      await tester.tap(find.dIcon(DIcons.italic));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'say ***hello***');
    });

    testWidgets('is refused for a post it would rewrite', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      // A table has no representation yet, so the offer is withdrawn rather
      // than silently reformatting someone's post.
      await tester.enterText(
        find.byType(TextField),
        '| a | b |\n| - | - |\n| 1 | 2 |',
      );
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Rich editing is not available for this post'),
        findsOneWidget,
      );
      expect(find.byTooltip('Edit richly'), findsNothing);
    });
  });

  group('drafts', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    List<DiscourseInstance> connectedSites() => [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
    ];

    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'meta-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail({ComposerDraft? draft, int draftSequence = 0}) =>
        topicPayload(
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

      for (
        var attempt = 1;
        attempt <= ComposerController.maxDraftFailures;
        attempt++
      ) {
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
