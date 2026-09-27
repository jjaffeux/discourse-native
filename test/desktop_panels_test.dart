import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/panel_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  for (final panel in ForumPanel.values) {
    test('list and sidebar navigation reuse the active $panel tab', () {
      shell.moveTabToPanel(shell.activeTabId!, panel);
      final original = shell.activeTabId;
      shell.pushContent(
        const ContentRoute(id: 'users', title: 'Users', icon: DIcons.user),
      );
      expect(shell.activeTabId, original);
      expect(shell.activeTab?.panel, panel);
      expect(shell.currentContent?.id, 'users');

      shell.pushContent(
        const ContentRoute(id: 'all-tags', title: 'Tags', icon: DIcons.tag),
      );
      expect(shell.activeTabId, original);
      expect(shell.currentContent?.id, 'all-tags');
      expect(shell.handleBack(canReturnToSidebar: false), isTrue);
      expect(shell.currentContent?.id, 'users');
      expect(shell.handleForward(), isTrue);
      expect(shell.currentContent?.id, 'all-tags');

      shell.selectDestination(
        const SidebarDestination(
          id: 'all-categories',
          label: 'Categories',
          icon: DIcons.folder,
        ),
      );
      expect(shell.activeTabId, original);
      expect(shell.activeTab?.panel, panel);
      expect(shell.currentContent?.id, 'all-categories');
      expect(
        shell.tabsForCurrentForum,
        hasLength(panel == ForumPanel.main ? 1 : 2),
      );
    });
  }

  test('topic clicks reuse the active tab and retain history', () {
    final main = shell.activeTab!;
    expect(shell.openTopicFromList(_topic), TabOpenResult.opened);
    expect(shell.activeTabId, main.id);
    expect(shell.activeTab?.panel, ForumPanel.main);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.tabsForCurrentForum, hasLength(1));

    expect(shell.openTopicFromList(_otherTopic), TabOpenResult.opened);
    expect(shell.activeTabId, main.id);
    expect(shell.currentContent?.topicId, 43);
    expect(shell.contentStack, hasLength(2));
    expect(shell.tabsForCurrentForum, hasLength(1));
    expect(shell.handleBack(canReturnToSidebar: false), isTrue);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.handleForward(), isTrue);
    expect(shell.currentContent?.topicId, 43);
  });

  test('topic links use the active panel and reset explicit posts', () {
    final main = shell.activeTab!;
    shell.createTab(panel: ForumPanel.secondary);
    final selectedId = shell.activeTabId!;
    shell.createTab(panel: ForumPanel.secondary);
    final other = shell.activeTab!;
    shell.selectTab(selectedId);
    shell.openTopic(_topic);
    shell.saveTopicScrollPost(42, 9);
    shell.openTopic(_otherTopic);
    shell.selectTab(main.id);

    expect(shell.openTopicUrl('/t/panel-topic/42/3'), isTrue);
    expect(shell.activeTabId, main.id);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.currentContent?.postNumber, 3);
    expect(shell.topicScrollPostNumber(42), 3);
    expect(shell.activeTab?.anchors['topic-42'], isNull);
    expect(shell.currentWorkspace?.tabById(other.id), other);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, selectedId);
    expect(shell.tabsForCurrentForum, hasLength(3));
  });

  test('topic clicks retain the current list as their source', () {
    final mainId = shell.activeTabId!;
    shell.openTopicFromList(_topic);
    expect(shell.activeTabId, mainId);
    shell.openListUrl('/tag/flutter');
    final list = shell.currentContent;

    shell.openTopicFromList(_otherTopic);

    expect(shell.activeTabId, mainId);
    expect(shell.topicListContent, list);
    expect(shell.currentContent?.topicId, 43);
    expect(shell.tabsForCurrentForum, hasLength(1));
    expect(shell.handleBack(canReturnToSidebar: false), isTrue);
    expect(shell.currentContent, list);
  });

  test(
    'move, persist, close and reopen retain tab state and panel selections',
    () {
      _openTopicTab(shell, _topic);
      final topic = shell.activeTab!;
      shell.saveTopicScrollPost(42, 7, viewportOffset: 21);
      final beforeMove = shell.activeTab!;
      shell.moveTabToPanel(topic.id, ForumPanel.main, index: 0);
      expect(shell.activeTab, beforeMove.copyWith(panel: ForumPanel.main));
      expect(
        shell.selectedTabIn(ForumPanel.secondary)?.currentContent.isNewTab,
        isTrue,
      );

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
    _openTopicTab(shell, _topic);
    final first = shell.activeTabId!;
    _openTopicTab(shell, _otherTopic);
    shell.closeOtherTabs(first, panel: ForumPanel.secondary);
    expect(shell.tabsForCurrentForum.map((tab) => tab.id), [mainId, first]);
  });

  test(
    'opening the first secondary tab at the limit leaves main unchanged',
    () {
      while (shell.canCreateTab) {
        shell.createTab(panel: ForumPanel.main);
      }
      final before = shell.currentWorkspace;

      expect(
        shell.openContentInPanel(
          ContentRoute.topic(
            topicId: _topic.id,
            slug: _topic.slug,
            title: _topic.title,
          ),
          panel: ForumPanel.secondary,
        ),
        TabOpenResult.limitReached,
      );

      expect(shell.currentWorkspace, before);
      expect(shell.selectedTabIn(ForumPanel.secondary), isNull);
    },
  );

  test('explicit new tabs at the limit preserve every existing document', () {
    while (shell.canCreateTab) {
      shell.createTab();
    }
    final workspace = shell.currentWorkspace;
    _openTopicTab(shell, _topic);
    expect(shell.currentWorkspace, workspace);
  });

  testWidgets(
    'middle-click explains the tab limit and opens after closing a tab',
    (tester) async {
      final main = shell.activeTabId!;
      while (shell.canCreateTab) {
        shell.createTab(panel: ForumPanel.secondary);
      }
      final extraTab = shell.activeTabId!;
      shell.selectTab(main);
      await _pump(tester, shell);
      final workspace = shell.currentWorkspace;
      final row = find.byKey(const ValueKey('topic-card-42')).first;

      await tester.tap(
        row,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();

      expect(shell.currentWorkspace, workspace);
      expect(find.text('Close a tab before opening another.'), findsOneWidget);

      shell.closeTab(extraTab);
      await tester.pumpAndSettle();
      await tester.tap(
        row,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(shell.activeTab?.panel, ForumPanel.main);
      expect(shell.activeTabId, main);
      expect(shell.tabsForCurrentForum.last.currentContent.topicId, 42);
      shell.selectTab(shell.tabsForCurrentForum.last.id);
      await tester.pumpAndSettle();
      expect(find.text('Content for 42', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('both visible topics stay subscribed when either panel is focused', () {
    _openTopicTab(shell, _topic);
    final first = shell.activeTabId!;
    shell.moveTabToPanel(first, ForumPanel.main);
    _openTopicTab(shell, _otherTopic);
    final tracker = FakeSiteTracker.built.last;
    expect(tracker.watchedChannels, containsAll(['/topic/42', '/topic/43']));
    shell.selectTab(first);
    expect(tracker.watchedChannels, containsAll(['/topic/42', '/topic/43']));
    shell.closeTab(first);
    expect(tracker.watchedChannels, ['/topic/43']);
  });

  test('reading an inactive panel never changes input focus', () {
    final mainId = shell.activeTabId!;
    _openTopicTab(shell, _topic);
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
      _openTopicTab(shell, _topic);
      _openTopicTab(shell, _otherTopic);
      final closing = shell.activeTabId!;
      _openTopicTab(shell, _topic);
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
    'both panels keep their content when focus moves and a panel minimizes',
    (tester) async {
      _openTopicTab(shell, _topic);
      final readerTab = shell.activeTabId!;
      await _pump(tester, shell);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-view-options')), findsNothing);
      expect(find.byTooltip('Minimize panel'), findsNWidgets(2));
      expect(find.byTooltip('Switch panel positions'), findsNothing);
      final reader = tester.state(find.byType(TopicView));
      final main = shell.selectedTabIn(ForumPanel.main)!.id;
      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(find.text('Content for 42', findRichText: true), findsOneWidget);
      expect(tester.state(find.byType(TopicView)), same(reader));
      final list = tester.getRect(_mainPanel);

      await tester.tap(find.byKey(const ValueKey('minimize-panel-secondary')));
      await tester.pumpAndSettle();
      expect(find.byType(TopicView), findsNothing);
      expect(
        tester.state(find.byType(TopicView, skipOffstage: false)),
        same(reader),
      );
      final rail = tester.getRect(_rail(ForumPanel.secondary));
      expect(rail.width, PanelRail.width);
      expect(rail.right, 1200);
      expect(tester.getRect(_mainPanel).left, list.left);
      expect(
        tester.getRect(_mainPanel).right,
        1200 - PanelRail.width - workspacePanelGap,
      );
      expect(shell.activeTabId, main);

      await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
      await tester.pumpAndSettle();
      expect(_rail(ForumPanel.secondary), findsNothing);
      expect(tester.state(find.byType(TopicView)), same(reader));
      expect(tester.getRect(_mainPanel), list);
      expect(shell.activeTabId, main);
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, readerTab);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a panel cannot stand down while the other one is empty', (
    tester,
  ) async {
    final main = shell.activeTabId!;
    await _pump(tester, shell);
    final minimizeMain = tester.widget<DButton>(
      find.byKey(const ValueKey('minimize-panel-main')),
    );
    expect(minimizeMain.onPressed, isNull);
    expect(minimizeMain.tooltip, 'Open a tab in the other panel first');

    await tester.tap(find.byKey(const ValueKey('minimize-panel-secondary')));
    await tester.pumpAndSettle();
    expect(find.text('Secondary panel'), findsNothing);
    expect(
      find.descendant(
        of: _rail(ForumPanel.secondary),
        matching: find.byType(DButton),
      ),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('minimize-panel-main')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('panel-rail-new-tab')));
    await tester.pumpAndSettle();
    expect(_rail(ForumPanel.secondary), findsNothing);
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.activeTabId, isNot(main));
    expect(shell.tabsForCurrentForum, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a topic from the list keeps the other panel minimized', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    final readerTab = shell.activeTabId!;
    shell.selectTab(shell.selectedTabIn(ForumPanel.main)!.id);
    await _pump(tester, shell);
    await tester.tap(find.byKey(const ValueKey('minimize-panel-secondary')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('topic-card-43')).first);
    await tester.pumpAndSettle();

    expect(_rail(ForumPanel.secondary), findsOneWidget);
    expect(shell.activeTabId, shell.selectedTabIn(ForumPanel.main)?.id);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, readerTab);
    expect(find.text('Content for 43', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tab picked from the rail restores its panel on that tab', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    final first = shell.activeTabId!;
    _openTopicTab(shell, _otherTopic);
    final second = shell.activeTabId!;
    final main = shell.selectedTabIn(ForumPanel.main)!.id;
    await _pump(tester, shell);
    await tester.tap(find.byKey(const ValueKey('minimize-panel-secondary')));
    await tester.pumpAndSettle();
    expect(shell.activeTabId, main);
    expect(
      tester
          .widgetList<DButton>(
            find.descendant(
              of: _rail(ForumPanel.secondary),
              matching: find.byType(DButton),
            ),
          )
          .map((button) => button.tooltip),
      ['Restore panel', 'Panel topic', 'Another topic', 'New tab'],
    );

    await tester.tap(find.byKey(ValueKey('panel-rail-tab-$first')));
    await tester.pumpAndSettle();

    expect(_rail(ForumPanel.secondary), findsNothing);
    expect(shell.activeTabId, first);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, first);
    expect(shell.currentWorkspace?.tabById(second), isNotNull);
    expect(find.text('Content for 42', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('a minimized main panel docks at its start and reads out '
        'over the reader in $direction', (tester) async {
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, direction: direction);
      final list = tester.state(find.byType(TopicListView));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 500));
      addTearDown(mouse.removePointer);

      await tester.tap(find.byKey(const ValueKey('minimize-panel-main')));
      await tester.pumpAndSettle();
      final rail = tester.getRect(_rail(ForumPanel.main));
      final reader = tester.getRect(_secondaryPanel);
      if (direction == TextDirection.ltr) {
        expect(rail.left, 0);
        expect(reader.left, PanelRail.width + workspacePanelGap);
      } else {
        expect(rail.right, 1200);
        expect(reader.right, 1200 - PanelRail.width - workspacePanelGap);
      }
      expect(find.byType(TopicListView), findsNothing);

      await mouse.moveTo(rail.center);
      await tester.pumpAndSettle();
      final readOut = find.byKey(const ValueKey('panel-rail-read-out'));
      expect(
        find.descendant(of: readOut, matching: find.text('Restore panel')),
        findsOneWidget,
      );
      expect(
        tester.getRect(readOut).overlaps(reader),
        isTrue,
        reason: 'the read-out opens over the panel beside the rail',
      );
      await mouse.moveTo(reader.center);
      await tester.pumpAndSettle();
      expect(readOut, findsNothing);

      await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TopicListView)), same(list));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a rail that appears under the pointer does not read itself '
      'out until it has been left', (tester) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final button = tester.getCenter(
      find.byKey(const ValueKey('minimize-panel-secondary')),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: button);
    addTearDown(mouse.removePointer);
    await mouse.down(button);
    await mouse.up();
    await tester.pumpAndSettle();

    final rail = tester.getRect(_rail(ForumPanel.secondary));
    expect(rail.contains(button), isTrue);
    final readOut = find.byKey(const ValueKey('panel-rail-read-out'));
    expect(readOut, findsNothing);

    await mouse.moveTo(rail.center);
    await tester.pumpAndSettle();
    expect(readOut, findsNothing);
    await mouse.moveTo(const Offset(600, 500));
    await tester.pump();
    await mouse.moveTo(rail.center);
    await tester.pumpAndSettle();
    expect(readOut, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimizing and restoring move no document to another parent', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    // Reparenting a document would rebuild every widget in it that reads an
    // inherited value, so each panel must keep its chain of ancestors.
    List<Element> ancestry(ForumPanel panel) {
      final chain = <Element>[];
      tester
          .element(
            find.byKey(
              ValueKey('desktop-panel-${panel.name}'),
              skipOffstage: false,
            ),
          )
          .visitAncestorElements((ancestor) {
            if (ancestor.widget is DesktopPanels) return false;
            chain.add(ancestor);
            return true;
          });
      return chain;
    }

    final before = {
      for (final panel in ForumPanel.values) panel: ancestry(panel),
    };
    for (final action in [
      'minimize-panel-secondary',
      'panel-rail-restore',
      'minimize-panel-main',
      'panel-rail-restore',
    ]) {
      await tester.tap(find.byKey(ValueKey(action)));
      await tester.pumpAndSettle();
      for (final panel in ForumPanel.values) {
        final after = ancestry(panel);
        expect(after, hasLength(before[panel]!.length), reason: action);
        for (var index = 0; index < after.length; index++) {
          expect(
            after[index],
            same(before[panel]![index]),
            reason: '$action: ${after[index].widget.runtimeType} of $panel',
          );
        }
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a minimized panel folds toward its rail as the other opens up', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final reader = tester.getRect(_secondaryPanel);
    await tester.tap(find.byKey(const ValueKey('minimize-panel-secondary')));
    // The frame that lays the panels out anew, then the motion's first tick:
    // nothing has moved yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(_secondaryPanel), reader);

    await tester.pump(const Duration(milliseconds: 100));
    final folding = tester.getRect(_secondaryPanel);
    expect(find.byType(TopicView), findsOneWidget);
    expect(folding.left, greaterThan(reader.left));
    expect(folding.left, lessThan(1200 - PanelRail.width));
    final list = tester.renderObject<RenderClipRRect>(
      find.ancestor(of: _mainPanel, matching: find.byType(ClipRRect)).first,
    );
    // The list's revealed edge keeps one gap from the folding reader's edge.
    expect(
      list.clipper!.getClip(list.size).right,
      closeTo(folding.left - workspacePanelGap, 0.01),
    );

    await tester.pumpAndSettle();
    expect(find.byType(TopicView), findsNothing);
    expect(
      tester.getRect(_mainPanel).right,
      1200 - PanelRail.width - workspacePanelGap,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restored panel slides back in before the seam returns', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final reader = tester.getRect(_secondaryPanel);
    final seam = find.byKey(const ValueKey('main-panel-resize-handle'));
    expect(seam, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('minimize-panel-secondary')));
    await tester.pumpAndSettle();
    expect(seam, findsNothing);

    await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final folded = tester.getRect(_secondaryPanel);
    expect(folded.left, 1200 - PanelRail.width);
    await tester.pump(const Duration(milliseconds: 100));
    final opening = tester.getRect(_secondaryPanel);
    expect(opening.left, inExclusiveRange(reader.left, folded.left));
    expect(seam, findsNothing);
    // The list keeps its wide layout until the motion settles, cut at one
    // gap from the returning reader, so no hole opens between them.
    expect(
      tester.getRect(_mainPanel).right,
      1200 - PanelRail.width - workspacePanelGap,
    );
    final list = tester.renderObject<RenderClipRRect>(
      find.ancestor(of: _mainPanel, matching: find.byType(ClipRRect)).first,
    );
    expect(
      list.clipper!.getClip(list.size).right,
      closeTo(opening.left - workspacePanelGap, 0.01),
    );

    await tester.pumpAndSettle();
    expect(tester.getRect(_secondaryPanel), reader);
    expect(tester.getRect(_mainPanel).right, reader.left - workspacePanelGap);
    expect(seam, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with reduced motion a panel minimizes and restores at once', (
    tester,
  ) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell, reduceMotion: true);
    final reader = tester.getRect(_secondaryPanel);
    await tester.tap(find.byKey(const ValueKey('minimize-panel-secondary')));
    await tester.pump();
    expect(find.byType(TopicView), findsNothing);
    expect(
      tester.getRect(_mainPanel).right,
      1200 - PanelRail.width - workspacePanelGap,
    );

    await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
    await tester.pump();
    expect(find.byType(TopicView), findsOneWidget);
    expect(tester.getRect(_secondaryPanel), reader);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoration hydrates both selected tabs while main has focus', (
    tester,
  ) async {
    final main = shell.activeTabId!;
    _openTopicTab(shell, _topic);
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

  testWidgets('primary click reuses the current tab even at the limit', (
    tester,
  ) async {
    final main = shell.activeTabId;
    while (shell.canCreateTab) {
      shell.createTab(panel: ForumPanel.secondary);
    }
    final secondary = shell.activeTab;
    shell.selectTab(main!);
    await _pump(tester, shell);

    await tester.tap(
      find.byKey(const ValueKey('topic-card-42')).first,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(shell.activeTabId, main);
    expect(shell.currentContent?.topicId, 42);
    expect(shell.tabsForCurrentForum, hasLength(ForumWorkspace.maximumTabs));
    expect(shell.selectedTabIn(ForumPanel.main)?.id, main);
    expect(shell.selectedTabIn(ForumPanel.secondary)?.id, secondary!.id);
    expect(find.text('Close a tab before opening another.'), findsNothing);
    expect(find.text('Content for 42', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('middle click opens a new tab in the current panel', (
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
    expect(shell.activeTabId, main);
    expect(shell.tabsForCurrentForum.last.panel, ForumPanel.main);
    expect(shell.tabsForCurrentForum.last.currentContent.topicId, 42);
    expect(shell.currentWorkspace?.tabById(main!)?.currentContent.id, 'latest');
    expect(tester.takeException(), isNull);
  });

  for (final pressDuration in [1, 50, 250]) {
    testWidgets(
      'topic click survives panel activation after $pressDuration ms',
      (tester) async {
        _openTopicTab(shell, _topic);
        final reader = shell.activeTab;
        final main = shell.selectedTabIn(ForumPanel.main)!.id;
        await _pump(tester, shell);
        final row = find.byKey(const ValueKey('topic-card-43'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1190, 840));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(row));
        await tester.pump(const Duration(milliseconds: 40));
        await mouse.down(tester.getCenter(row));
        await tester.pump(Duration(milliseconds: pressDuration));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(shell.activeTabId, main);
        expect(shell.currentContent?.topicId, 43);
        expect(shell.selectedTabIn(ForumPanel.secondary)?.id, reader!.id);
        expect(
          shell.selectedTabIn(ForumPanel.secondary)?.currentContent.topicId,
          42,
        );
        expect(shell.selectedTabIn(ForumPanel.main)?.id, main);
        expect(shell.tabsForCurrentForum, hasLength(2));
        expect(find.text('Content for 43', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dragging the last tab leaves a Start page in each panel', (
    tester,
  ) async {
    await _pump(tester, shell);
    final id = shell.activeTabId!;
    Future<void> moveToPanel(Finder target) async {
      final tab = find.byKey(ValueKey('forum-tab-$id'));
      final gesture = await tester.startGesture(
        tester.getCenter(tab),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(target));
      await tester.pumpAndSettle();
      final indicator = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(indicator, findsOneWidget);
      expect(tester.getRect(indicator).width, 3);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(indicator, findsNothing);
    }

    await moveToPanel(find.text('Secondary panel'));
    await tester.pumpAndSettle();
    expect(shell.activeTab?.panel, ForumPanel.secondary);
    expect(shell.activeTabId, id);
    final main = shell.selectedTabIn(ForumPanel.main)!;
    expect(main.currentContent.title, 'Start page');
    expect(main.currentContent.icon, DIcons.house);
    final startTab = find.byKey(ValueKey('forum-tab-${main.id}'));
    expect(
      find.descendant(of: startTab, matching: find.text('Start page')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: startTab,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.house,
        ),
      ),
      findsOneWidget,
    );

    await moveToPanel(startTab);
    await tester.pumpAndSettle();
    expect(shell.activeTab?.panel, ForumPanel.main);
    expect(shell.activeTabId, id);
    expect(
      shell.selectedTabIn(ForumPanel.secondary)?.currentContent.isNewTab,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty panel previews its first tab and clears on drag exit', (
    tester,
  ) async {
    await _pump(tester, shell);
    final original = shell.currentWorkspace!;
    final source = find.byKey(ValueKey('forum-tab-${shell.activeTabId}'));
    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Secondary panel')));
    await tester.pumpAndSettle();
    final placeholder = find.byKey(
      const ValueKey('forum-tab-drop-placeholder'),
    );
    expect(placeholder, findsOneWidget);
    expect(tester.getRect(placeholder).bottom, lessThan(100));
    expect(shell.currentWorkspace, original);

    await gesture.moveTo(const Offset(-20, -20));
    await tester.pumpAndSettle();
    expect(placeholder, findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(shell.currentWorkspace, original);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('the placeholder matches the insertion position in $direction', (
      tester,
    ) async {
      final initial = shell.activeTabId!;
      shell.openContentInNewTab(
        const ContentRoute(id: 'panel-a', title: 'A', icon: DIcons.tag),
      );
      final first = shell.activeTabId!;
      shell.closeTab(initial);
      shell.openContentInNewTab(
        const ContentRoute(id: 'panel-b', title: 'B', icon: DIcons.tag),
      );
      final second = shell.activeTabId!;
      _openTopicTab(shell, _topic);
      final incoming = shell.activeTabId!;
      await _pump(tester, shell, direction: direction);
      final source = find.byKey(ValueKey('forum-tab-$incoming'));
      final target = find.byKey(ValueKey('forum-tab-$second'));
      final barRect = tester.getRect(
        find.ancestor(of: target, matching: find.byType(ForumTabsBar)),
      );
      final targetRect = tester.getRect(target);
      final destination = Offset(
        direction == TextDirection.ltr
            ? targetRect.left + 2
            : targetRect.right - 2,
        targetRect.center.dy,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(destination);
      await tester.pumpAndSettle();
      final placeholder = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(placeholder, findsOneWidget);
      final previewRect = tester.getRect(placeholder);
      expect(previewRect.width, 3);
      expect(previewRect.height, 28);
      expect(
        tester
            .widget<Container>(
              find.descendant(
                of: placeholder,
                matching: find.byType(Container),
              ),
            )
            .decoration,
        isA<BoxDecoration>().having(
          (decoration) => decoration.color,
          'color',
          Theme.of(tester.element(placeholder)).colorScheme.primary,
        ),
      );
      final firstRect = tester.getRect(
        find.byKey(ValueKey('forum-tab-$first')),
      );
      final secondRect = tester.getRect(target);
      if (direction == TextDirection.ltr) {
        expect(previewRect.left, greaterThan(firstRect.right));
        expect(previewRect.right, lessThan(secondRect.left));
      } else {
        expect(previewRect.right, lessThan(firstRect.left));
        expect(previewRect.left, greaterThan(secondRect.right));
      }
      // Moving within the same insertion region must not chase the shifted tabs.
      await gesture.moveTo(destination + const Offset(1, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(placeholder), previewRect);

      // Cross several child hit targets, then return to the original slot.
      await gesture.moveTo(
        Offset(
          direction == TextDirection.ltr ? barRect.right - 2 : barRect.left + 2,
          destination.dy,
        ),
      );
      await tester.pumpAndSettle();
      final appended = tester.getRect(placeholder);
      final last = tester.getRect(target);
      expect(
        direction == TextDirection.ltr
            ? appended.left > last.right
            : appended.right < last.left,
        isTrue,
      );
      await gesture.moveTo(
        Offset(
          direction == TextDirection.ltr ? barRect.left + 2 : barRect.right - 2,
          destination.dy,
        ),
      );
      await tester.pumpAndSettle();
      final prepended = tester.getRect(placeholder);
      final leading = tester.getRect(find.byKey(ValueKey('forum-tab-$first')));
      expect(
        direction == TextDirection.ltr
            ? prepended.right < leading.left
            : prepended.left > leading.right,
        isTrue,
      );
      await gesture.moveTo(destination);
      await tester.pumpAndSettle();
      expect(tester.getRect(placeholder), previewRect);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(placeholder, findsNothing);
      expect(
        shell.currentWorkspace!.tabsIn(ForumPanel.main).map((tab) => tab.id),
        [first, incoming, second],
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dropping over panel content previews an appended tab', (
    tester,
  ) async {
    final original = shell.activeTabId!;
    _openTopicTab(shell, _topic);
    final incoming = shell.activeTabId!;
    await _pump(tester, shell);
    final source = find.byKey(ValueKey('forum-tab-$incoming'));
    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(TopicListView)));
    await tester.pumpAndSettle();
    final placeholder = find.byKey(
      const ValueKey('forum-tab-drop-placeholder'),
    );
    expect(placeholder, findsOneWidget);
    expect(
      tester.getRect(placeholder).left,
      greaterThan(
        tester.getRect(find.byKey(ValueKey('forum-tab-$original'))).right,
      ),
    );
    final tabRect = tester.getRect(find.byKey(ValueKey('forum-tab-$original')));
    await gesture.moveTo(Offset(tabRect.left + 2, tabRect.center.dy));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(placeholder).right,
      lessThan(
        tester.getRect(find.byKey(ValueKey('forum-tab-$original'))).left,
      ),
    );
    await gesture.moveTo(tester.getCenter(find.byType(TopicListView)));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(placeholder, findsNothing);
    expect(
      shell.currentWorkspace!.tabsIn(ForumPanel.main).map((tab) => tab.id),
      [original, incoming],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs select independently and move into an occupied strip', (
    tester,
  ) async {
    final original = shell.activeTabId!;
    shell.createTab();
    final second = shell.activeTabId!;
    _openTopicTab(shell, _topic);
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

  testWidgets('dragging the divider changes both panel widths', (tester) async {
    _openTopicTab(shell, _topic);
    await _pump(tester, shell);
    final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
    expect(tester.getRect(_mainPanel).width, 400);

    await tester.drag(handle, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(tester.getRect(_mainPanel).width, 480);
    expect(tester.getRect(_secondaryPanel).width, 708);
    expect(tester.takeException(), isNull);
  });

  for (final panel in ForumPanel.values) {
    testWidgets('reordering within ${panel.name} shows an insertion bar', (
      tester,
    ) async {
      if (panel == ForumPanel.secondary) {
        _openTopicTab(shell, _topic);
      }
      final first = shell.selectedTabIn(panel)!.id;
      shell.createTab(panel: panel);
      final second = shell.selectedTabIn(panel)!.id;
      await _pump(tester, shell);

      final source = find.byKey(ValueKey('forum-tab-$first'));
      final target = find.byKey(ValueKey('forum-tab-$second'));
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      final targetRect = tester.getRect(target);
      final sourceRect = tester.getRect(source);
      await gesture.moveTo(Offset(targetRect.right - 2, targetRect.center.dy));
      await tester.pumpAndSettle();
      final indicator = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      expect(indicator, findsOneWidget);
      expect(tester.getRect(indicator).left, greaterThan(targetRect.right));
      expect(tester.getRect(target), targetRect);
      expect(tester.getRect(source), sourceRect);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(indicator, findsNothing);
      expect(shell.currentWorkspace!.tabsIn(panel).map((tab) => tab.id), [
        second,
        first,
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reordering within ${panel.name} keeps the dragged tab in '
        'place and drops past a whole neighbour', (tester) async {
      if (panel == ForumPanel.secondary) {
        _openTopicTab(shell, _topic);
      }
      final first = shell.selectedTabIn(panel)!.id;
      shell.createTab(panel: panel);
      final second = shell.selectedTabIn(panel)!.id;
      shell.createTab(panel: panel);
      final third = shell.selectedTabIn(panel)!.id;
      await _pump(tester, shell);

      Rect rectOf(String id) =>
          tester.getRect(find.byKey(ValueKey('forum-tab-$id')));
      final indicator = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );
      final gesture = await tester.startGesture(
        rectOf(second).center,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      // Pressing selects the tab, which widens it for its close action.
      final firstRect = rectOf(first);
      final secondRect = rectOf(second);
      final thirdRect = rectOf(third);

      Future<void> hover(double dx) async {
        await gesture.moveTo(Offset(dx, secondRect.center.dy));
        await tester.pumpAndSettle();
      }

      expect(
        find.ancestor(
          of: find.byKey(ValueKey('forum-tab-$second')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity == 0,
          ),
        ),
        findsNothing,
      );

      // Its own slot would not move it.
      await hover(secondRect.left + 2);
      expect(indicator, findsNothing);
      await hover(secondRect.right - 2);
      expect(indicator, findsNothing);

      // Either half of a neighbour answers that neighbour's far side.
      for (final dx in [firstRect.right - 2, firstRect.left + 2]) {
        await hover(dx);
        expect(indicator, findsOneWidget);
        expect(tester.getRect(indicator).right, lessThan(firstRect.left));
      }
      for (final dx in [thirdRect.left + 2, thirdRect.right - 2]) {
        await hover(dx);
        expect(indicator, findsOneWidget);
        expect(tester.getRect(indicator).left, greaterThan(thirdRect.right));
      }

      await hover(thirdRect.left + 2);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shell.currentWorkspace!.tabsIn(panel).map((tab) => tab.id), [
        first,
        third,
        second,
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dragging the divider after an edge resize resets the preferred split',
    (tester) async {
      final frame = ValueNotifier<Rect?>(
        const Rect.fromLTWH(100, 0, 1200, 850),
      );
      addTearDown(frame.dispose);
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, windowFrame: frame);
      frame.value = const Rect.fromLTWH(100, 0, 1160, 850);
      tester.view.physicalSize = const Size(1160, 850);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 360);

      final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
      await tester.drag(handle, const Offset(50, 0));
      await tester.pumpAndSettle();

      expect(tester.getRect(_mainPanel).width, 410);
      expect(tester.getRect(_secondaryPanel).width, 738);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'divider can return exactly to its preferred width after edge resize',
    (tester) async {
      final frame = ValueNotifier<Rect?>(
        const Rect.fromLTWH(100, 0, 1200, 850),
      );
      addTearDown(frame.dispose);
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, windowFrame: frame);
      frame.value = const Rect.fromLTWH(100, 0, 1160, 850);
      tester.view.physicalSize = const Size(1160, 850);
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 360);

      final handle = find.byKey(const ValueKey('main-panel-resize-handle'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.getRect(_mainPanel).width, 400);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('right-edge resize shrinks main to 320 then docks its rail', (
    tester,
  ) async {
    final frame = ValueNotifier<Rect?>(const Rect.fromLTWH(100, 0, 1200, 850));
    addTearDown(frame.dispose);
    _openTopicTab(shell, _topic);
    shell.selectTab(shell.selectedTabIn(ForumPanel.main)!.id);
    await _pump(tester, shell, windowFrame: frame);

    frame.value = const Rect.fromLTWH(100, 0, 1160, 850);
    tester.view.physicalSize = const Size(1160, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 360);
    expect(tester.getRect(_secondaryPanel).width, 788);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('main-panel-resize-handle')))
          .center
          .dx,
      366,
    );

    frame.value = const Rect.fromLTWH(100, 0, 1120, 850);
    tester.view.physicalSize = const Size(1120, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 320);
    expect(tester.getRect(_secondaryPanel).width, 788);

    frame.value = const Rect.fromLTWH(100, 0, 1119, 850);
    tester.view.physicalSize = const Size(1119, 850);
    await tester.pumpAndSettle();
    expect(_mainPanel, findsNothing);
    final mainRail = tester.getRect(_rail(ForumPanel.main));
    expect(mainRail.left, 0);
    expect(mainRail.width, PanelRail.width);
    expect(
      tester.getRect(_secondaryPanel),
      const Rect.fromLTWH(
        PanelRail.width + workspacePanelGap,
        0,
        1119 - PanelRail.width - workspacePanelGap,
        850,
      ),
    );
    expect(find.byKey(const ValueKey('panel-rail-restore')), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-rail-new-tab')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main-panel-resize-handle')),
      findsNothing,
    );
    expect(shell.activeTab?.panel, ForumPanel.secondary);

    // A collapsing navigation sidebar can widen the document workspace
    // even as the outer window keeps getting narrower.
    frame.value = const Rect.fromLTWH(100, 0, 1099, 850);
    tester.view.physicalSize = const Size(1051, 850);
    await tester.pumpAndSettle();
    expect(_mainPanel, findsNothing);
    expect(_rail(ForumPanel.main), findsOneWidget);

    frame.value = const Rect.fromLTWH(100, 0, 1200, 850);
    tester.view.physicalSize = const Size(1200, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 400);
    expect(tester.getRect(_secondaryPanel).width, 788);
    expect(_rail(ForumPanel.main), findsNothing);
    expect(
      find.byKey(const ValueKey('main-panel-resize-handle')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('left-edge resize shrinks secondary to 320 then docks its rail', (
    tester,
  ) async {
    final frame = ValueNotifier<Rect?>(const Rect.fromLTWH(100, 0, 1200, 850));
    addTearDown(frame.dispose);
    _openTopicTab(shell, _topic);
    await _pump(tester, shell, windowFrame: frame);

    frame.value = const Rect.fromLTWH(140, 0, 1160, 850);
    tester.view.physicalSize = const Size(1160, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 400);
    expect(tester.getRect(_secondaryPanel).width, 748);

    frame.value = const Rect.fromLTWH(568, 0, 732, 850);
    tester.view.physicalSize = const Size(732, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 400);
    expect(tester.getRect(_secondaryPanel).width, 320);

    frame.value = const Rect.fromLTWH(569, 0, 731, 850);
    tester.view.physicalSize = const Size(731, 850);
    await tester.pumpAndSettle();
    expect(_secondaryPanel, findsNothing);
    final secondaryRail = tester.getRect(_rail(ForumPanel.secondary));
    expect(secondaryRail.right, 731);
    expect(secondaryRail.width, PanelRail.width);
    expect(
      tester.getRect(_mainPanel).width,
      731 - PanelRail.width - workspacePanelGap,
    );
    expect(find.byKey(const ValueKey('panel-rail-restore')), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-rail-new-tab')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main-panel-resize-handle')),
      findsNothing,
    );
    expect(shell.activeTab?.panel, ForumPanel.main);

    frame.value = const Rect.fromLTWH(700, 0, 600, 850);
    tester.view.physicalSize = const Size(600, 850);
    await tester.pumpAndSettle();
    expect(_rail(ForumPanel.secondary), findsOneWidget);
    expect(tester.getRect(_mainPanel).width, 550);
    expect(_secondaryPanel, findsNothing);

    await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
    await tester.pumpAndSettle();
    expect(_rail(ForumPanel.secondary), findsNothing);
    expect(_mainPanel, findsNothing);
    expect(_secondaryPanel, findsOneWidget);
    expect(shell.activeTab?.panel, ForumPanel.secondary);

    frame.value = const Rect.fromLTWH(100, 0, 1200, 850);
    tester.view.physicalSize = const Size(1200, 850);
    await tester.pumpAndSettle();
    expect(tester.getRect(_mainPanel).width, 400);
    expect(tester.getRect(_secondaryPanel).width, 788);
    expect(_rail(ForumPanel.secondary), findsNothing);
    expect(
      find.byKey(const ValueKey('main-panel-resize-handle')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restoring a window-collapsed main panel brings back the draggable seam',
    (tester) async {
      final frame = ValueNotifier<Rect?>(
        const Rect.fromLTWH(100, 0, 1200, 850),
      );
      addTearDown(frame.dispose);
      _openTopicTab(shell, _topic);
      await _pump(tester, shell, windowFrame: frame);

      frame.value = const Rect.fromLTWH(100, 0, 1119, 850);
      tester.view.physicalSize = const Size(1119, 850);
      await tester.pumpAndSettle();
      expect(_rail(ForumPanel.main), findsOneWidget);
      expect(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
      await tester.pumpAndSettle();
      expect(_rail(ForumPanel.main), findsNothing);
      expect(tester.getRect(_mainPanel).width, 400);
      expect(tester.getRect(_secondaryPanel).width, 707);

      await tester.drag(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        const Offset(30, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(_mainPanel).width, 430);
      expect(tester.getRect(_secondaryPanel).width, 677);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow windows show only the visible panel tabs and restore both on resize',
    (tester) async {
      final main = shell.activeTabId!;
      _openTopicTab(shell, _topic);
      final reader = shell.activeTabId!;
      await _pump(tester, shell);
      expect(find.byType(ForumTabsBar), findsNWidgets(2));

      tester.view.physicalSize = const Size(580, 850);
      await tester.pumpAndSettle();
      expect(find.byType(ForumTabsBar), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$main')), findsNothing);
      expect(find.byKey(ValueKey('forum-tab-$reader')), findsOneWidget);
      expect(find.byType(TopicView), findsOneWidget);

      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(find.byType(ForumTabsBar), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$main')), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$reader')), findsNothing);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsNothing);

      // One panel is all a narrow window shows, so neither stands down.
      expect(find.byTooltip('Minimize panel'), findsNothing);

      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpAndSettle();
      expect(find.byType(ForumTabsBar), findsNWidgets(2));
      expect(find.byKey(ValueKey('forum-tab-$main')), findsOneWidget);
      expect(find.byKey(ValueKey('forum-tab-$reader')), findsOneWidget);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.byType(TopicView), findsOneWidget);
      expect(shell.selectedTabIn(ForumPanel.main)?.id, main);
      expect(shell.selectedTabIn(ForumPanel.secondary)?.id, reader);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two topic readers show their own posts and save separate anchors',
    (tester) async {
      _openTopicTab(shell, _topic);
      final first = shell.activeTabId!;
      shell.moveTabToPanel(first, ForumPanel.main);
      _openTopicTab(shell, _otherTopic);
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

final _mainPanel = find.byKey(const ValueKey('desktop-panel-main'));
final _secondaryPanel = find.byKey(const ValueKey('desktop-panel-secondary'));

Finder _rail(ForumPanel panel) =>
    find.byKey(ValueKey('panel-rail-${panel.name}'));

Future<void> _pump(
  WidgetTester tester,
  ShellController shell, {
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
  ValueListenable<Rect?>? windowFrame,
}) async {
  tester.view.physicalSize = const Size(1200, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: Directionality(
              textDirection: direction,
              child: TopicPresentationPreferences(
                child: DToaster(
                  child: Scaffold(
                    body: DesktopPanels(windowFrame: windowFrame),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _openTopicTab(ShellController shell, Topic topic) {
  final result = shell.openLinkInNewTab(
    '/t/${topic.slug}/${topic.id}',
    title: topic.title,
    panel: ForumPanel.secondary,
  );
  if (result == TabOpenResult.opened) {
    shell.selectTab(shell.tabsForCurrentForum.last.id);
  }
}
