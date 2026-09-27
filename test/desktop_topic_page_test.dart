import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/topic_presentation_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_presentation.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_settings_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/platform.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_presentation.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/topic_scroll_capture.dart';

final _reader = find.byType(TopicView);
final _allLists = find.byType(TopicListView, skipOffstage: false);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'panel tabs and layout actions sit above a continuous page header',
    (tester) async {
      final h = await _setup(tester, size: const Size(1800, 1000));
      final tabs = find.byKey(const ValueKey('forum-tabs-bar'));
      final options = find.byKey(const ValueKey('minimize-panel-main'));
      final title = find.byKey(const ValueKey('topic-list-title'));
      final filters = find.byKey(const ValueKey('topic-list-feed-row'));
      final separator = find.byKey(
        const ValueKey('topic-list-heading-separator'),
      );
      final filterAction = find.byKey(const ValueKey('topic-list-filter'));
      expect(find.byKey(const ValueKey('topic-list-display')), findsNothing);
      expect(tester.widget<Text>(title).data, 'Latest topics');
      expect(
        find.descendant(of: tabs, matching: find.byType(DSeparator)),
        findsNothing,
      );
      expect(tester.getCenter(tabs).dy, tester.getCenter(options).dy);
      expect(
        tester.getRect(title).top,
        greaterThan(tester.getRect(tabs).bottom),
      );
      expect(
        tester.getRect(filters).top,
        greaterThan(tester.getRect(title).bottom),
      );
      expect(separator, findsOneWidget);
      expect(
        tester.getRect(separator).top,
        greaterThan(tester.getRect(filters).bottom),
      );
      expect(tester.getRect(separator).left, tester.getRect(filters).left);
      expect(tester.getRect(separator).right, tester.getRect(filters).right);
      expect(tester.getCenter(filterAction).dy, tester.getCenter(title).dy);
      expect(
        tester.widget<DButton>(filterAction).variant,
        DButtonVariant.transparentBackground,
      );

      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      final listTabs = find.descendant(
        of: find.byKey(const ValueKey('desktop-panel-main')),
        matching: tabs,
      );
      final minimize = find.byKey(const ValueKey('minimize-panel-main'));
      expect(tester.getCenter(listTabs).dy, tester.getCenter(options).dy);
      expect(tester.getCenter(listTabs).dy, tester.getCenter(minimize).dy);
      expect(tester.getRect(minimize).left, tester.getRect(options).left);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('all desktop pages keep panel tabs and position controls', (
    tester,
  ) async {
    final h = await _setup(tester);
    for (final id in [
      'users',
      'drafts',
      'upcoming-events',
      'groups',
      'latest',
    ]) {
      h.shell.selectDestination(
        SidebarDestination(id: id, label: id, icon: DIcons.folder),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('forum-tabs-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-view-options')), findsNothing);
      for (final panel in ForumPanel.values) {
        expect(
          find.byKey(ValueKey('minimize-panel-${panel.name}')),
          findsOneWidget,
        );
      }
    }
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('forum-tabs-bar')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('narrow topic header separates controls from the list', (
    tester,
  ) async {
    await _setup(tester, size: const Size(390, 844));
    final title = tester.getRect(
      find.byKey(const ValueKey('topic-list-title')),
    );
    final controls = tester.getRect(
      find.byKey(const ValueKey('topic-list-feed-row')),
    );
    final separator = tester.getRect(
      find.byKey(const ValueKey('topic-list-heading-separator')),
    );
    expect(controls.left, title.left);
    expect(controls.top, greaterThan(title.bottom));
    final heading = tester.getRect(
      find.byKey(const ValueKey('topic-list-primary-row')),
    );
    final spaceAboveTitle = title.top - heading.top;
    final spaceBelowTitle = controls.top - title.bottom;
    expect(spaceAboveTitle, greaterThanOrEqualTo(16));
    expect(spaceAboveTitle, greaterThan(spaceBelowTitle));
    expect(separator.top, greaterThan(controls.bottom));
    expect(separator.left, controls.left);
    expect(separator.right, controls.right);
    expect(
      find.byKey(const ValueKey('topic-list-tracking-button')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('root topic list has no back button in a compact layout', (
    tester,
  ) async {
    await _setup(tester, size: const Size(390, 844));
    final heading = find.byKey(const ValueKey('topic-list-heading'));
    expect(heading, findsOneWidget);
    expect(
      find.descendant(of: heading, matching: find.byTooltip('Back')),
      findsNothing,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('topic-list-title'))).left,
      tester.getRect(find.byKey(const ValueKey('topic-list-feed-row'))).left,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Latest topics has no tracking menu', (tester) async {
    final h = await _setup(tester, size: const Size(1800, 1000));
    expect(
      find.byKey(const ValueKey('topic-list-tracking-button')),
      findsNothing,
    );
    expect(find.byType(DNotificationLevelMenu<int>), findsNothing);
    expect(h.api.userPreferenceUpdates, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'beside-list cards preserve the saved mode across presentation changes',
    (tester) async {
      final h = await _setup(tester, size: const Size(1800, 1000));
      await h.shell.appSettings.setTopicListMode(TopicListDisplayMode.compact);
      await tester.pumpAndSettle();
      final listState = tester.state(_allLists);
      expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
      final previous = find.byKey(const ValueKey('inbox-previous-topic'));
      final next = find.byKey(const ValueKey('inbox-next-topic'));
      expect(previous, findsNothing);
      expect(next, findsNothing);

      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      expect(previous, findsOneWidget);
      expect(next, findsOneWidget);
      expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
      expect(find.byType(DCardFooter), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('compact-topic-list-header')),
        findsNothing,
      );
      expect(h.shell.appSettings.topicListMode, TopicListDisplayMode.compact);
      expect(tester.state(_allLists), same(listState));

      await tester.tap(find.byKey(const ValueKey('minimize-panel-main')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-card-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-card-1'), skipOffstage: false),
        findsOneWidget,
      );
      expect(h.shell.appSettings.topicListMode, TopicListDisplayMode.compact);
      expect(tester.state(_allLists), same(listState));

      await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
      h.shell.selectTab(h.shell.selectedTabIn(ForumPanel.secondary)!.id);
      h.shell.closeTopic();
      await tester.pumpAndSettle();
      expect(previous, findsNothing);
      expect(next, findsNothing);
      expect(find.byKey(const ValueKey('topic-card-1')), findsOneWidget);
      expect(h.shell.appSettings.topicListMode, TopicListDisplayMode.compact);
      expect(tester.state(_allLists), same(listState));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'merged reader and editor retain accessible workspace navigation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await const TopicPresentationStore().write(TopicPresentation.merged);
        final h = await _setup(tester, size: const Size(1280, 860));
        expect(find.bySemanticsLabel('Forum navigation'), findsOneWidget);
        _openTopicTab(h.shell, h.topics.first);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Forum navigation'), findsOneWidget);
        h.shell.openReply();
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Forum navigation'), findsOneWidget);
        expect(h.shell.visibleComposer!.focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('a merged reader never mounts a sheet', (tester) async {
    await const TopicPresentationStore().write(TopicPresentation.merged);
    final h = await _setup(tester);
    await h.shell.loadTopic(h.topics.first.id, h.topics.first.slug);
    _openTopicTab(h.shell, h.topics.first);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final reader
          in find.byType(TopicView, skipOffstage: false).evaluate()) {
        var inSheet = false;
        reader.visitAncestorElements((element) {
          if (element.widget is DSheetContent) inSheet = true;
          return true;
        });
        expect(
          inSheet,
          isFalse,
          reason: 'Reader built inside sheet on frame $frame',
        );
      }
    }
    expect(_reader, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final mode in TopicPresentation.values) {
    testWidgets('opening composer preserves cooked trees in ${mode.name}', (
      tester,
    ) async {
      await const TopicPresentationStore().write(mode);
      final h = await _setup(tester);
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      final cooked = find.byType(CookedHtml).evaluate().toSet();
      expect(cooked, isNotEmpty);
      final rebuilt = <Element>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (cooked.contains(element)) rebuilt.add(element);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      h.shell.openReply();
      await tester.pumpAndSettle();
      expect(rebuilt, isEmpty);
      expect(find.byType(CookedHtml).evaluate().toSet(), containsAll(cooked));
      expect(h.shell.visibleComposer!.focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets(
    'a hidden source list retains its state when composer space changes',
    (tester) async {
      await const TopicPresentationStore().write(TopicPresentation.merged);
      final h = await _setup(tester, size: const Size(1280, 860));
      final listState = tester.state(_allLists);
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      final rows = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'topic-card-',
                ),
            skipOffstage: false,
          )
          .evaluate()
          .toSet();
      expect(rows, isNotEmpty);
      h.shell.openReply();
      await tester.pumpAndSettle();
      expect(tester.state(_allLists), same(listState));
      h.shell.closeComposer();
      h.shell.closeTopic();
      await tester.pumpAndSettle();
      expect(tester.state(_allLists), same(listState));
      expect(find.byType(TopicListView).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final mode in TopicPresentation.values) {
    testWidgets('visible replies precede scroll cache in ${mode.name}', (
      tester,
    ) async {
      await const TopicPresentationStore().write(mode);
      final h = await _setup(tester);
      await h.shell.loadTopic(h.topics.first.id, h.topics.first.slug);
      _openTopicTab(h.shell, h.topics.first);
      final scroll = find.descendant(
        of: _reader,
        matching: find.byType(CustomScrollView),
      );
      for (var frame = 0; frame < 8 && scroll.evaluate().isEmpty; frame++) {
        await tester.pump();
      }
      expect(scroll, findsOneWidget);
      expect(
        tester.widget<CustomScrollView>(scroll).scrollCacheExtent,
        const ScrollCacheExtent.pixels(0),
      );
      final position = _readerScroll(tester).pixels;
      await tester.pump();
      expect(tester.widget<CustomScrollView>(scroll).scrollCacheExtent, isNull);
      expect(_readerScroll(tester).pixels, position);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('minimizing the list panel retains the reader and editor', (
    tester,
  ) async {
    final h = await _setup(
      tester,
      size: const Size(2400, 1000),
      theme: AppTheme.dark,
    );
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    final readerState = tester.state(_reader);
    final listState = tester.state(_allLists);
    await tester.drag(_reader, const Offset(0, -400));
    await tester.pumpAndSettle();
    h.shell.openReply();
    await tester.pumpAndSettle();
    final composer = h.shell.visibleComposer!;
    composer.text.text = 'A retained reply';
    composer.text.selection = const TextSelection(
      baseOffset: 2,
      extentOffset: 8,
    );
    await tester.pump(const Duration(seconds: 2));
    final editorState = tester.state(find.byType(ComposerEditor));
    final readingPost = h.shell.topicScrollPostNumber(h.topics.first.id);
    for (final action in [
      'minimize-panel-main',
      'panel-rail-restore',
      'minimize-panel-main',
      'panel-rail-restore',
    ]) {
      await tester.tap(find.byKey(ValueKey(action)));
      await tester.pumpAndSettle();
      expect(tester.state(_reader), same(readerState));
      expect(tester.state(_allLists), same(listState));
      expect(tester.state(find.byType(ComposerEditor)), same(editorState));
      expect(composer.raw, 'A retained reply');
      expect(
        composer.text.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );
      expect(h.shell.topicScrollPostNumber(h.topics.first.id), readingPost);
      expect(find.byType(DSheetContent), findsNothing);
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('an unknown route shows Not found without demo actions', (
    tester,
  ) async {
    final h = await _setup(tester);
    h.shell.selectDestination(
      const SidebarDestination(
        id: 'missing-page',
        label: 'Missing page',
        icon: DIcons.folder,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not found'), findsOneWidget);
    expect(find.text('Replace with deeper view'), findsNothing);
    expect(find.text('Show sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('category navigation reuses the reader tab', (tester) async {
    final h = await _setup(tester, size: const Size(2200, 1000));
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    final readerId = h.shell.activeTabId;
    h.api.feedPaths.clear();
    h.api.feeds['/c/general/5.json'] = [
      const Topic(
        id: 101,
        title: 'A general category topic',
        slug: 'general-topic',
      ),
    ];

    h.shell.browseTopicCategory(
      const TopicCategory(
        id: 5,
        name: 'general',
        slug: 'general',
        color: '0088CC',
      ),
      keepTopicOpen: true,
    );
    await tester.pumpAndSettle();

    expect(h.shell.activeTabId, readerId);
    expect(h.shell.activeTab?.panel, ForumPanel.secondary);
    expect(h.shell.tabsForCurrentForum, hasLength(2));
    expect(h.shell.currentContent?.topicId, isNull);
    expect(h.shell.topicListContent?.categoryId, 5);
    expect(h.api.feedPaths, contains(h.shell.topicListContent!.feedPath));
    expect(h.shell.currentFeed?.topicIds, [101]);
    expect(find.text('A general category topic'), findsOneWidget);
    expect(find.byType(TopicListView).hitTestable(), findsNWidgets(2));
    expect(find.text('Not found'), findsNothing);
    expect(find.text('Replace with deeper view'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('panels scope tabs and minimize without replacing the reader', (
    tester,
  ) async {
    final h = await _setup(tester, size: const Size(2200, 1000));
    final listId = h.shell.activeTabId!;
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    final firstId = h.shell.activeTabId!;
    _openTopicTab(h.shell, h.topics[1]);
    await tester.pumpAndSettle();
    final secondId = h.shell.activeTabId!;
    final listPanel = find.byKey(const ValueKey('desktop-panel-main'));
    final readerPanel = find.byKey(const ValueKey('desktop-panel-secondary'));
    expect(
      find.descendant(
        of: listPanel,
        matching: find.byKey(ValueKey('forum-tab-item-$listId')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: readerPanel,
        matching: find.byKey(ValueKey('forum-tab-item-$firstId')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: listPanel,
        matching: find.byKey(ValueKey('forum-tab-item-$firstId')),
      ),
      findsNothing,
    );
    final readerState = tester.state(_reader);
    expect(
      tester.getRect(listPanel).left,
      lessThan(tester.getRect(readerPanel).left),
    );
    final split = tester.getRect(readerPanel);
    await tester.tap(find.byKey(const ValueKey('minimize-panel-main')));
    await tester.pumpAndSettle();
    final rail = tester.getRect(find.byKey(const ValueKey('panel-rail-main')));
    expect(rail.right, lessThan(tester.getRect(readerPanel).left));
    expect(tester.getRect(readerPanel).right, split.right);
    expect(tester.getRect(readerPanel).width, greaterThan(split.width));
    expect(tester.state(_reader), same(readerState));
    await tester.tap(find.byKey(const ValueKey('panel-rail-restore')));
    await tester.pumpAndSettle();
    expect(tester.getRect(readerPanel), split);
    expect(tester.state(_reader), same(readerState));
    h.shell.createTab(panel: ForumPanel.main);
    await tester.pumpAndSettle();
    final otherList = h.shell.listPanelTab!.id;
    expect(otherList, isNot(listId));
    expect(
      h.shell.selectedTabIn(ForumPanel.secondary)?.currentContent.topicId,
      2,
    );
    h.shell.selectTab(listId);
    await tester.pumpAndSettle();
    expect(h.shell.listPanelTab!.id, listId);
    expect(
      h.shell.selectedTabIn(ForumPanel.secondary)?.currentContent.topicId,
      2,
    );
    h.shell.closeOtherTabs(secondId, panel: ForumPanel.secondary);
    await tester.pumpAndSettle();
    expect(
      h.shell.tabsForCurrentForum.map((tab) => tab.id),
      containsAll([listId, otherList, secondId]),
    );
    expect(
      h.shell.tabsForCurrentForum.map((tab) => tab.id),
      isNot(contains(firstId)),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('moving topics between panels preserves tabs', (tester) async {
    final h = await _setup(tester);
    final listId = h.shell.activeTabId!;
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    final topicId = h.shell.activeTabId!;
    h.shell.moveTabToPanel(topicId, ForumPanel.main);
    await tester.pumpAndSettle();
    expect(h.shell.tabsForCurrentForum, hasLength(3));
    expect(
      h.shell.selectedTabIn(ForumPanel.secondary)?.currentContent.isNewTab,
      isTrue,
    );
    expect(find.byType(TopicListView).hitTestable(), findsNothing);
    h.shell.selectTab(listId);
    await tester.pumpAndSettle();
    expect(find.byType(TopicListView).hitTestable(), findsOneWidget);
    h.shell.moveTabToPanel(topicId, ForumPanel.secondary);
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.topicId, 1);
    expect(h.shell.selectedTabIn(ForumPanel.main)?.id, listId);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a reader panel retries its own failed topic', (tester) async {
    final h = await _setup(tester);
    final listId = h.shell.activeTabId!;
    final topic = h.topics[1];
    final payload = h.api.topics.remove(topic.id)!;
    h.shell.openLinkInNewTab(
      '/t/${topic.slug}/${topic.id}/3',
      title: topic.title,
      panel: ForumPanel.secondary,
    );
    h.shell.selectTab(h.shell.tabsForCurrentForum.last.id);
    await tester.pumpAndSettle();
    expect(h.api.topicPostNumbersOpened.last, 3);
    final reader = find.byKey(const ValueKey('desktop-panel-secondary'));
    final retry = find.descendant(
      of: reader,
      matching: find.byKey(const ValueKey('topic-load-retry')),
    );
    expect(retry, findsOneWidget);

    h.shell.selectTab(listId);
    await tester.pumpAndSettle();
    h.api.topics[topic.id] = payload;
    // A screen reader activates the button without the pointer or focus that
    // would first hand its panel the active tab.
    tester.widget<DButton>(retry).onPressed!();
    await tester.pumpAndSettle();

    // The post the link named lives on the reader's tab, not the active one.
    expect(h.api.topicPostNumbersOpened.last, 3);
    expect(h.shell.activeTabId, listId);
    expect(retry, findsNothing);
    expect(
      find.descendant(of: reader, matching: find.byType(CookedHtml)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'list visibility reserves 320 pixels for the topic after composer sizing',
    (tester) async {
      final h = await _setup(tester, size: const Size(1800, 900));
      final chrome =
          1800 -
          tester
              .getSize(find.byKey(const ValueKey('desktop-panel-main')))
              .width -
          tester
              .getSize(find.byKey(const ValueKey('desktop-panel-secondary')))
              .width;
      final listState = tester.state(_allLists);
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      final readerState = tester.state(_reader);
      await tester.drag(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        const Offset(120, 0),
      );
      await tester.pumpAndSettle();
      final preferredWidth = tester.getSize(find.byType(TopicListView)).width;
      tester.view.physicalSize = Size(chrome + 304 + 320 + 12, 900);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView), findsOneWidget);
      expect(tester.getSize(_reader).width, greaterThanOrEqualTo(320));
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView).hitTestable(), findsNothing);
      expect(tester.state(_allLists), same(listState));
      expect(tester.state(_reader), same(readerState));

      tester.view.physicalSize = const Size(1800, 900);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(TopicListView)).width, preferredWidth);
      h.shell.openReply();
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView).hitTestable(), findsOneWidget);
      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView).hitTestable(), findsNothing);
      tester.view.physicalSize = const Size(2400, 900);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView), findsOneWidget);
      expect(tester.getSize(_reader).width, greaterThanOrEqualTo(320));
      expect(tester.state(_reader), same(readerState));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final direction in TextDirection.values) {
    testWidgets('panels retain list width beside the reader ($direction)', (
      tester,
    ) async {
      final h = await _setup(
        tester,
        direction: direction,
        size: const Size(1800, 900),
      );
      final listElement = tester.element(_allLists);
      final listRect = tester.getRect(find.byType(TopicListView));
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      expect(_reader, findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(tester.element(_allLists), same(listElement));
      final reader = tester.getRect(_reader);
      final reducedList = tester.getRect(find.byType(TopicListView));
      expect(reducedList.width, listRect.width);
      expect(reducedList.width, inInclusiveRange(304, 480));
      if (direction == TextDirection.ltr) {
        expect(reader.left, greaterThanOrEqualTo(reducedList.right));
      } else {
        expect(reader.right, lessThanOrEqualTo(reducedList.left));
      }
      expect(reader.width, greaterThanOrEqualTo(320));
      await tester.drag(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        Offset(direction == TextDirection.ltr ? 60 : -60, 0),
      );
      await tester.pumpAndSettle();
      final resizedWidth = tester.getSize(find.byType(TopicListView)).width;
      expect(resizedWidth, greaterThan(reducedList.width));
      final topicState = tester.state(_reader);
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView).hitTestable(), findsNothing);
      expect(tester.element(_allLists), same(listElement));
      expect(tester.state(_reader), same(topicState));
      tester.view.physicalSize = const Size(1800, 900);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(TopicListView)).width, resizedWidth);
      expect(tester.state(_reader), same(topicState));
      expect(find.byType(InstanceRail).hitTestable(), findsOneWidget);
      expect(find.byType(InstanceSidebar).hitTestable(), findsOneWidget);
      expect(Navigator.of(tester.element(_reader)).canPop(), isFalse);
      final previous = find.byKey(const ValueKey('inbox-previous-topic'));
      final next = find.byKey(const ValueKey('inbox-next-topic'));
      expect(tester.getCenter(previous).dy, tester.getCenter(next).dy);
      expect(tester.widget<DButton>(previous).onPressed, isNull);
      for (final tab in h.shell.currentWorkspace!.tabsIn(
        ForumPanel.secondary,
      )) {
        h.shell.closeTab(tab.id);
      }
      h.shell.selectTab(h.shell.listPanelTab!.id);
      await tester.pumpAndSettle();
      expect(_reader, findsNothing);
      expect(find.byType(TopicListView), findsOneWidget);
      expect(tester.element(_allLists), same(listElement));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets(
    'narrow page restores exact list scroll and topic reading position',
    (tester) async {
      final h = await _setup(tester, size: const Size(600, 900));
      await tester.drag(find.byType(TopicListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      final listPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: _allLists,
              matching: find.byType(Scrollable, skipOffstage: false),
              skipOffstage: false,
            ),
          )
          .position;
      final listOffset = listPosition.pixels;
      expect(listOffset, greaterThan(0));
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      await tester.drag(_reader, const Offset(0, -380));
      await tester.pumpAndSettle();
      final readingOffset = _readerScroll(tester).pixels;
      final readerId = h.shell.activeTabId!;
      expect(readingOffset, greaterThan(0));
      h.shell.selectTab(h.shell.listPanelTab!.id);
      await tester.pumpAndSettle();
      expect(listPosition.pixels, closeTo(listOffset, 1));
      h.shell.selectTab(readerId);
      await tester.pumpAndSettle();
      expect(_readerScroll(tester).pixels, closeTo(readingOffset, 1));
      _openTopicTab(h.shell, h.topics[1]);
      await tester.pumpAndSettle();
      h.shell.selectTab(h.shell.listPanelTab!.id);
      await tester.pumpAndSettle();
      expect(listPosition.pixels, closeTo(listOffset, 1));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('changing topics keeps the draft destination', (tester) async {
    final h = await _setup(tester);
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    h.shell.openReply();
    await tester.pumpAndSettle();
    final composer = h.shell.visibleComposer!;
    composer.text.text = 'My reply to the first topic';
    await tester.pump(const Duration(seconds: 2));
    final editorState = tester.state(find.byType(ComposerEditor));
    h.shell.openTopicFromList(h.topics[11]);
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.topicId, 12);
    expect(h.shell.visibleComposer, same(composer));
    expect(composer.target.topicId, 1);
    expect(composer.raw, 'My reply to the first topic');
    expect(tester.state(find.byType(ComposerEditor)), same(editorState));
    await tester.tap(find.byKey(const ValueKey('composer-return-to-topic')));
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.topicId, 1);
    expect(composer.raw, 'My reply to the first topic');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the earlier header has no switcher and U returns to the list', (
    tester,
  ) async {
    final h = await _setup(tester);
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-page-navigation')), findsNothing);
    expect(find.byKey(const ValueKey('topic-switcher-trigger')), findsNothing);
    await tester.tap(_reader, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.isTopicList, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'responsive docking retains editor and reader while rail stays visible',
    (tester) async {
      final h = await _setup(tester);
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      final topicState = tester.state(_reader);
      h.shell.openReply();
      await tester.pumpAndSettle();
      final composer = h.shell.visibleComposer!;
      composer.text.text = 'A draft that survives resizing';
      await tester.pump(const Duration(seconds: 2));
      composer.text.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      final editor = find.byType(ComposerEditor);
      final editorState = tester.state(editor);
      for (final width in [1440.0, 960.0, 720.0, 390.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        expect(tester.state(_reader), same(topicState));
        expect(tester.state(editor), same(editorState));
        expect(
          composer.text.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
        expect(find.byType(InstanceRail).hitTestable(), findsOneWidget);
        final reader = tester.getRect(_reader);
        final panel = tester.getRect(find.byType(ComposerPanel));
        if (width >= 720) {
          expect(panel.left, greaterThanOrEqualTo(reader.right));
          expect(reader.width, greaterThanOrEqualTo(320));
        } else {
          expect(panel.top, greaterThanOrEqualTo(reader.bottom));
        }
        expect(
          find.byKey(const ValueKey('desktop-navigation-trigger')),
          width < 1100 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      expect(composer.raw, 'A draft that survives resizing');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'narrow navigation opens and dismisses without losing topic or draft',
    (tester) async {
      final h = await _setup(tester, size: const Size(960, 900));
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      h.shell.openReply();
      await tester.pumpAndSettle();
      final composer = h.shell.visibleComposer!;
      composer.text.text = 'Still here';
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(
        find.byKey(const ValueKey('desktop-navigation-trigger')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InstanceSidebar).hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byType(InstanceSidebar).hitTestable()).left,
        greaterThanOrEqualTo(tester.getRect(find.byType(InstanceRail)).right),
      );
      expect(find.byKey(const ValueKey('topic-sheet')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.currentContent?.topicId, 1);
      expect(composer.raw, 'Still here');
      expect(find.byType(InstanceSidebar).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final dock in ['left', 'bottom', 'right']) {
    testWidgets('$dock dock leaves rail, sidebar and titlebar in place', (
      tester,
    ) async {
      final h = await _setup(tester);
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      final rail = tester.getRect(find.byType(InstanceRail));
      final sidebar = tester.getRect(find.byType(InstanceSidebar));
      final titlebar = tester.getRect(find.byType(ShellTitleBar));
      h.shell.openReply();
      await tester.pumpAndSettle();
      if (dock == 'right') {
        await tester.tap(find.byTooltip('Dock side'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Dock bottom'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Dock side'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dock $dock'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(InstanceRail)), rail);
      expect(tester.getRect(find.byType(InstanceSidebar)), sidebar);
      expect(tester.getRect(find.byType(ShellTitleBar)), titlebar);
      expect(h.shell.visibleComposer!.focus.hasFocus, isTrue);
      expect(find.byType(TopicListView).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets(
    'full-screen composer fills the desktop workspace and restores docking',
    (tester) async {
      final h = await _setup(tester);
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      final workspace = tester.getRect(find.byType(TopicWorkspace));
      h.shell.openReply();
      await tester.pumpAndSettle();
      final editor = tester.state(find.byType(ComposerEditor));
      final composer = h.shell.visibleComposer!;
      composer.text.text = 'A full-screen draft';
      await composer.flushDraft();
      await tester.tap(find.byTooltip('Full screen'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ComposerPanel)), workspace);
      expect(find.byTooltip('Dock side').hitTestable(), findsOneWidget);
      expect(composer.raw, 'A full-screen draft');
      expect(tester.state(find.byType(ComposerEditor)), same(editor));
      await tester.tap(find.byTooltip('Dock side'));
      await tester.pumpAndSettle();
      final restored = tester.getRect(find.byType(ComposerPanel));
      expect(restored.right, workspace.right);
      expect(restored.width, lessThan(workspace.width));
      expect(tester.state(find.byType(ComposerEditor)), same(editor));
      await tester.tap(find.byTooltip('Dock side'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dock bottom'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(ComposerPanel)).bottom,
        workspace.bottom,
      );
      expect(
        tester.getSize(find.byType(ComposerPanel)).height,
        lessThan(workspace.height),
      );
      expect(tester.state(find.byType(ComposerEditor)), same(editor));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final dock in ['left', 'bottom', 'right']) {
    testWidgets(
      'Escape restores the $dock composer from full screen without closing it',
      (tester) async {
        final h = await _setup(tester);
        _openTopicTab(h.shell, h.topics.first);
        await tester.pumpAndSettle();
        h.shell.openReply();
        await tester.pumpAndSettle();
        if (dock == 'right') {
          await tester.tap(find.byTooltip('Dock side'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Dock bottom'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Dock side'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Dock $dock'));
        await tester.pumpAndSettle();
        final docked = tester.getRect(find.byType(ComposerPanel));
        final editor = tester.state(find.byType(ComposerEditor));
        final composer = h.shell.visibleComposer!;
        composer.text.text = 'Keep this draft';
        await composer.flushDraft();
        await tester.tap(find.byTooltip('Full screen'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(h.shell.visibleComposer, same(composer));
        expect(composer.raw, 'Keep this draft');
        expect(tester.getRect(find.byType(ComposerPanel)), docked);
        expect(tester.state(find.byType(ComposerEditor)), same(editor));
        expect(composer.focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('tabs preserve each topic position and the active draft', (
    tester,
  ) async {
    final h = await _setup(tester, size: const Size(2200, 900));
    _openTopicTab(h.shell, h.topics.first);
    final firstTab = h.shell.activeTabId!;
    await tester.pumpAndSettle();
    await tester.drag(_reader, const Offset(0, -350));
    await tester.pumpAndSettle();
    final offset = _readerScroll(tester).pixels;
    h.shell.openReply();
    await tester.pumpAndSettle();
    final composer = h.shell.visibleComposer!;
    composer.text.text = 'Draft in the first topic';
    await tester.pump(const Duration(seconds: 2));
    h.shell.createTab();
    await tester.pumpAndSettle();
    _openTopicTab(h.shell, h.topics[1]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('forum-tab-item-$firstTab')));
    await tester.pumpAndSettle();
    expect(h.shell.currentContent?.topicId, 1);
    expect(_readerScroll(tester).pixels, closeTo(offset, 1));
    expect(h.shell.visibleComposer, same(composer));
    expect(composer.raw, 'Draft in the first topic');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final reply in [true, false]) {
    testWidgets('compose shortcut works from the topic scope ($reply)', (
      tester,
    ) async {
      final h = await _setup(tester);
      _openTopicTab(h.shell, h.topics.first);
      await tester.pumpAndSettle();
      FocusScope.of(tester.element(_reader)).unfocus();
      await tester.pump();
      await _composeShortcut(tester, reply: reply);
      await tester.pumpAndSettle();
      expect(h.shell.visibleComposer, isNotNull);
      expect(h.shell.visibleComposer!.target.createsTopic, !reply);
      expect(h.shell.visibleComposer!.focus.hasFocus, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('dialogs block compose shortcuts until dismissed', (
    tester,
  ) async {
    final h = await _setup(tester);
    _openTopicTab(h.shell, h.topics.first);
    await tester.pumpAndSettle();
    final dialog = showDDialog<void>(
      context: tester.element(_reader),
      builder: (context, controller) => const DDialogContent(
        children: [DDialogTitle(child: Text('Topic details'))],
      ),
    );
    await tester.pumpAndSettle();
    await _composeShortcut(tester, reply: true);
    await tester.pumpAndSettle();
    expect(h.shell.visibleComposer, isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await dialog;
    await _composeShortcut(tester, reply: true);
    await tester.pumpAndSettle();
    expect(h.shell.visibleComposer, isNotNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('mobile uses the shared reader without desktop navigation', (
    tester,
  ) async {
    final h = await _setup(tester, size: const Size(390, 844));
    h.shell.openTopicFromList(h.topics.first);
    await tester.pumpAndSettle();
    expect(_reader, findsOneWidget);
    expect(find.byKey(const ValueKey('topic-page-navigation')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

ScrollPosition _readerScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(TopicView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    )
    .position;

Future<void> _composeShortcut(
  WidgetTester tester, {
  required bool reply,
}) async {
  if (reply) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(
    reply ? LogicalKeyboardKey.keyR : LogicalKeyboardKey.keyC,
  );
  if (reply) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

Future<({ShellController shell, List<Topic> topics, FakeDiscourseApi api})>
_setup(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  TextDirection direction = TextDirection.ltr,
  AppSettingsController? settings,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 1, username: 'reader', canCreateTopic: true);
  final topics = [
    for (var id = 1; id <= 40; id++)
      Topic(id: id, title: 'Conversation $id', slug: 'conversation-$id'),
  ];
  final api = FakeDiscourseApi(
    user: user,
    feeds: {'/latest.json': topics},
    creatableFeedPaths: const {'/latest.json'},
    topics: {
      for (final topic in topics)
        topic.id: (
          detail: TopicDetail(
            id: topic.id,
            title: topic.title,
            stream: [topic.id * 10],
            postsCount: 1,
            canCreatePost: true,
          ),
          posts: [
            Post(
              id: topic.id * 10,
              postNumber: 1,
              username: 'sam',
              cooked:
                  '<p>${List.filled(100, 'A conversation with enough text to scroll.').join(' ')}</p>',
            ),
          ],
        ),
    },
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('sheet.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys['https://sheet.example'] = 'key',
    mobileNavigationEnabled: usesMobileNavigation(defaultTargetPlatform),
    forumTabsEnabled: !usesMobileNavigation(defaultTargetPlatform),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  final diagnostics = (await tester.runAsync(
    () => DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: topicScrollCaptureWithoutVm(),
    ),
  ))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    shell.dispose();
    await tester.runAsync(diagnostics.close);
  });
  await shell.load();
  await shell.loadFeed('latest');
  await tester.pumpWidget(
    DiagnosticsScope(
      controller: diagnostics,
      child: ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          builder: (context, child) => DFocusHighlight(child: child!),
          home: DDirection(
            textDirection: direction,
            child: settings == null
                ? const AdaptiveShell()
                : ContentSettingsScope(
                    controller: settings,
                    child: const AdaptiveShell(),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (shell: shell, topics: topics, api: api);
}

void _openTopicTab(ShellController shell, Topic topic) {
  shell.openLinkInNewTab(
    '/t/${topic.slug}/${topic.id}',
    title: topic.title,
    panel: ForumPanel.secondary,
  );
  shell.selectTab(shell.tabsForCurrentForum.last.id);
}
