import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _topic = Topic(id: 42, title: 'Panel topic', slug: 'panel-topic');
const _otherTopic = Topic(
  id: 43,
  title: 'Another topic',
  slug: 'another-topic',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ShellController shell;
  late FakeDiscourseApi api;

  setUp(() async {
    shell = ShellController(
      instanceStore: FakeInstanceStore([instance('panels.example')]),
      api: api = FakeDiscourseApi(
        creatableFeedPaths: const {'/latest.json'},
        feeds: const {
          '/latest.json': [_topic, _otherTopic],
        },
        topics: {
          for (final topic in [_topic, _otherTopic])
            topic.id: (
              detail: TopicDetail(
                id: topic.id,
                title: topic.title,
                stream: [topic.id],
                postsCount: 1,
              ),
              posts: [
                Post(
                  id: topic.id,
                  postNumber: 1,
                  username: 'reader',
                  cooked: '<p>Content for ${topic.id}</p>',
                ),
              ],
            ),
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await shell.load();
    await shell.loadFeed('latest');
    shell.desktopTopicTabs = true;
  });
  tearDown(() => shell.dispose());

  test('navigation opens tabs in their panel and topics in secondary', () {
    final main = shell.activeTabId;
    shell.openTopic(_topic);
    final topic = shell.activeTab!;
    expect(topic.panel, ForumPanel.secondary);
    expect(shell.selectedTabIn(ForumPanel.main)?.id, main);

    shell.pushContent(
      const ContentRoute(id: 'all-tags', title: 'Tags', icon: DIcons.tag),
    );
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.currentWorkspace?.tabById(topic.id), topic);

    shell.selectTab(main!);
    shell.selectDestination(
      const SidebarDestination(
        id: 'all-categories',
        label: 'Categories',
        icon: DIcons.folder,
      ),
    );
    expect(shell.activeTab?.panel, ForumPanel.main);
    expect(shell.activeTabId, isNot(main));
    expect(shell.tabsForCurrentForum, hasLength(4));
  });

  test(
    'move, persist, close and reopen retain tab state and panel selections',
    () {
      shell.openTopic(_topic);
      final topic = shell.activeTab!;
      shell.saveTopicScrollPost(42, 7, viewportOffset: 21);
      final beforeMove = shell.activeTab!;
      shell.moveTabToPanel(topic.id, ForumPanel.main, index: 0);
      expect(shell.activeTab, beforeMove.copyWith(panel: ForumPanel.main));
      expect(shell.selectedTabIn(ForumPanel.secondary), isNull);

      shell.createTab(panel: ForumPanel.secondary);
      final secondaryId = shell.activeTabId;
      final workspace = shell.currentWorkspace!;
      final restored = ForumWorkspace.tryFromJson(
        jsonDecode(jsonEncode(workspace.toJson())),
      )!;
      expect(restored, workspace);
      expect(restored.selectedTabIn(ForumPanel.main)?.id, topic.id);
      expect(restored.selectedTabIn(ForumPanel.secondary)?.id, secondaryId);

      shell.closeTab(topic.id);
      expect(shell.activeTabId, secondaryId);
      expect(shell.reopenClosedTab(topic.id), isTrue);
      expect(shell.activeTab, beforeMove.copyWith(panel: ForumPanel.main));
      expect(shell.topicScrollPostNumber(42), 7);
    },
  );

  test('closing other tabs is confined to the requested panel', () {
    final mainId = shell.activeTabId!;
    shell.openTopic(_topic);
    final first = shell.activeTabId!;
    shell.openTopic(_otherTopic);
    shell.closeOtherTabs(first, panel: ForumPanel.secondary);
    expect(shell.tabsForCurrentForum.map((tab) => tab.id), [mainId, first]);
  });

  test('opening at the tab limit preserves every existing document', () {
    while (shell.canCreateTab) {
      shell.createTab();
    }
    final workspace = shell.currentWorkspace;
    shell.openTopic(_topic);
    expect(shell.currentWorkspace, workspace);
  });

  test('both visible topics stay subscribed when either panel is focused', () {
    shell.openTopic(_topic);
    final first = shell.activeTabId!;
    shell.moveTabToPanel(first, ForumPanel.main);
    shell.openTopic(_otherTopic);
    final tracker = FakeSiteTracker.built.last;
    expect(tracker.watchedChannels, containsAll(['/topic/42', '/topic/43']));
    shell.selectTab(first);
    expect(tracker.watchedChannels, containsAll(['/topic/42', '/topic/43']));
    shell.closeTab(first);
    expect(tracker.watchedChannels, ['/topic/43']);
  });

  test('reading an inactive panel never changes input focus', () {
    final mainId = shell.activeTabId!;
    shell.openTopic(_topic);
    final readerId = shell.activeTabId!;
    expect(shell.readTab(mainId, () => shell.currentContent?.id), 'latest');
    expect(shell.activeTabId, readerId);
    expect(
      () => shell.readTab(mainId, () => throw StateError('read')),
      throwsStateError,
    );
    expect(shell.activeTabId, readerId);
  });

  test(
    'closing the unfocused selected tab activates its neighbour in place',
    () {
      final main = shell.activeTabId!;
      shell.openTopic(_topic);
      shell.openTopic(_otherTopic);
      final closing = shell.activeTabId!;
      shell.openTopic(_topic);
      final neighbour = shell.activeTabId!;
      shell.selectTab(closing);
      shell.selectTab(main);
      expect(FakeSiteTracker.built.last.watchedChannels, ['/topic/43']);

      shell.closeTab(closing);

      expect(shell.activeTabId, main);
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, neighbour);
      expect(FakeSiteTracker.built.last.watchedChannels, ['/topic/42']);
    },
  );

  testWidgets(
    'both panels keep their content when focus and positions change',
    (tester) async {
      shell.openTopic(_topic);
      await _pump(tester, shell);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-view-options')), findsNothing);
      expect(find.byTooltip('Switch panel positions'), findsNWidgets(2));
      final reader = tester.state(find.byType(TopicView));
      final main = shell.selectedTabIn(ForumPanel.main)!.id;
      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(find.text('Content for 42', findRichText: true), findsOneWidget);
      expect(tester.state(find.byType(TopicView)), same(reader));
      final before = tester.getCenter(find.byType(TopicView)).dx;
      await tester.tap(find.byKey(const ValueKey('swap-panels-main')));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byType(TopicView)).dx, lessThan(before));
      expect(tester.state(find.byType(TopicView)), same(reader));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restoration hydrates both selected tabs while main has focus', (
    tester,
  ) async {
    final main = shell.activeTabId!;
    shell.openTopic(_topic);
    final topic = shell.activeTabId!;
    shell.selectTab(main);
    final restored = ShellController(
      instanceStore: FakeInstanceStore([instance('panels.example')]),
      api: api,
      ownsApi: false,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore([shell.currentWorkspace!]),
      trackers: FakeSiteTracker.factory,
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(restored.dispose);
    await restored.load();
    await _pump(tester, restored);
    expect(restored.activeTabId, main);
    expect(restored.selectedTabIn(ForumPanel.secondary)?.id, topic);
    expect(find.byType(TopicListView), findsOneWidget);
    expect(find.text('Content for 42', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a list keeps its heading, creation action and filter ownership',
    (tester) async {
      await _pump(tester, shell);
      final main = shell.activeTabId!;
      shell.openContentInNewTab(
        const ContentRoute(
          id: 'all-categories',
          title: 'All categories',
          icon: DIcons.folder,
        ),
        panel: ForumPanel.secondary,
        rootDestinationId: 'all-categories',
      );
      final secondary = shell.activeTabId!;
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('topic-list-title')))
            .data,
        'Latest topics',
      );
      expect(find.byKey(const ValueKey('new-topic-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-list-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open topics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filter'));
      await tester.pumpAndSettle();

      expect(shell.activeTabId, main);
      expect(shell.currentContent?.topicFilterQuery, 'status:open');
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, secondary);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('middle click opens in secondary without replacing the list', (
    tester,
  ) async {
    await _pump(tester, shell);
    final main = shell.activeTabId;
    await tester.tap(
      find.text(_topic.title),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.selectedTabIn(ForumPanel.main)?.id, main);
    expect(find.byType(TopicListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lone tab can be dragged to an empty panel and back', (
    tester,
  ) async {
    await _pump(tester, shell);
    final id = shell.activeTabId!;
    final tab = find
        .descendant(
          of: find.byType(ForumTabsBar),
          matching: find.byType(DDocumentTab),
        )
        .first;
    final target = find.text('Secondary panel');
    await tester.dragFrom(
      tester.getCenter(tab),
      tester.getCenter(target) - tester.getCenter(tab),
    );
    await tester.pumpAndSettle();
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.activeTabId, id);
    expect(find.text('Main panel'), findsOneWidget);

    final moved = find
        .descendant(
          of: find.byType(ForumTabsBar),
          matching: find.byType(DDocumentTab),
        )
        .first;
    await tester.dragFrom(
      tester.getCenter(moved),
      tester.getCenter(find.text('Main panel')) - tester.getCenter(moved),
    );
    await tester.pumpAndSettle();
    expect(shell.activeTab?.panel, ForumPanel.main);
    expect(shell.activeTabId, id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs select independently and move into an occupied strip', (
    tester,
  ) async {
    final original = shell.activeTabId!;
    shell.createTab();
    final second = shell.activeTabId!;
    shell.openTopic(_topic);
    final reader = shell.activeTabId!;
    await _pump(tester, shell);
    await tester.tap(find.byKey(ValueKey('forum-tab-$original')));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, original);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, reader);
    await tester.tap(find.byKey(ValueKey('forum-tab-$second')));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, second);
    final source = find.byKey(ValueKey('forum-tab-$second'));
    final target = find.byKey(ValueKey('forum-tab-$reader'));
    await tester.dragFrom(
      tester.getCenter(source),
      tester.getCenter(target) - tester.getCenter(source),
    );
    await tester.pumpAndSettle();
    expect(shell.activeTabId, second);
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.selectedTabIn(ForumPanel.main)?.id, original);
    expect(shell.currentWorkspace!.tabsIn(ForumPanel.secondary), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow windows keep both strips usable for selection and drops',
    (tester) async {
      final main = shell.activeTabId!;
      shell.openTopic(_topic);
      final reader = shell.activeTabId!;
      await _pump(tester, shell);
      tester.view.physicalSize = const Size(580, 850);
      await tester.pumpAndSettle();
      expect(find.byType(ForumTabsBar), findsNWidgets(2));
      expect(find.byType(TopicView), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('forum-tab-$main')));
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsNothing);
      final source = find.byKey(ValueKey('forum-tab-$reader'));
      final target = find.byKey(ValueKey('forum-tab-$main'));
      await tester.dragFrom(
        tester.getCenter(source),
        tester.getCenter(target) - tester.getCenter(source),
      );
      await tester.pumpAndSettle();
      expect(shell.activeTab?.panel, ForumPanel.main);
      expect(shell.activeTabId, reader);
      expect(find.byType(TopicView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two topic readers show their own posts and save separate anchors',
    (tester) async {
      shell.openTopic(_topic);
      final first = shell.activeTabId!;
      shell.moveTabToPanel(first, ForumPanel.main);
      shell.openTopic(_otherTopic);
      final second = shell.activeTabId!;
      await _pump(tester, shell);
      expect(find.byType(TopicView), findsNWidgets(2));
      expect(find.text('Content for 42', findRichText: true), findsOneWidget);
      expect(find.text('Content for 43', findRichText: true), findsOneWidget);
      shell.saveTopicScrollPost(42, 8, tabId: first);
      shell.saveTopicScrollPost(43, 5, tabId: second);
      expect(shell.topicScrollPostNumber(42, tabId: first), 8);
      expect(shell.topicScrollPostNumber(43, tabId: second), 5);
      expect(shell.activeTabId, second);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(WidgetTester tester, ShellController shell) async {
  tester.view.physicalSize = const Size(1200, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: const TopicPresentationPreferences(
          child: Scaffold(body: DesktopPanels()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
