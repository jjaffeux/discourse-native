import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/app_shortcuts.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/platform.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _compact = Size(390, 844);
const _medium = Size(1000, 800);
const _expanded = Size(1440, 900);

void main() {
  final binding = _ExitRecordingBinding();
  setUp(binding.exitRequests.clear);

  testWidgets(
    'topic and sidebar clicks reuse the active tab',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      final originalId = controller.activeTabId;
      controller.openTopicUrl('/t/current-topic/42');
      await tester.pumpAndSettle();
      expect(controller.activeTabId, originalId);
      expect(controller.activeTab?.panel, ForumPanel.main);
      expect(
        controller.selectedTabIn(ForumPanel.secondary)?.currentContent.isNewTab,
        isTrue,
      );
      expect(controller.currentContent?.topicId, 42);

      await tester.tap(_sidebarText('Topics'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(controller.activeTabId, originalId);
      expect(controller.tabsForCurrentForum, hasLength(2));
      expect(controller.currentContent?.id, 'latest');
      expect(controller.handleBack(canReturnToSidebar: false), isTrue);
      expect(controller.currentContent?.topicId, 42);
    }),
  );

  testWidgets(
    'middle-click opens a sidebar destination in a new main tab',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      final original = controller.activeTab!;

      await tester.tap(
        find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.text('Topics'),
        ),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();

      expect(controller.currentWorkspace?.tabById(original.id), original);
      expect(controller.activeTabId, original.id);
      expect(controller.tabsForCurrentForum, hasLength(3));
      final opened = controller.tabsForCurrentForum.last;
      expect(opened.panel, ForumPanel.main);
      expect(opened.currentContent.id, 'latest');
      expect(opened.contentStack, hasLength(1));
    }),
  );

  testWidgets(
    'middle-click opens topic rows and tags in new main tabs',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      const topic = Topic(
        id: 42,
        title: 'A topic to read',
        slug: 'a-topic-to-read',
        tags: [TopicTag(name: 'flutter', id: 12, slug: 'flutter')],
      );
      await _pumpShell(
        tester,
        api: FakeDiscourseApi(
          feeds: const {
            '/latest.json': [topic],
          },
        ),
      );
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      final original = controller.activeTab!;

      await tester.tap(
        find.text(topic.title).first,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();

      expect(controller.currentWorkspace?.tabById(original.id), original);
      expect(controller.activeTab?.panel, ForumPanel.main);
      expect(controller.tabsForCurrentForum, hasLength(3));
      final opened = controller.tabsForCurrentForum.last;
      expect(opened.currentContent.topicId, topic.id);
      expect(opened.currentContent.title, topic.title);

      controller.selectTab(original.id);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('flutter'),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pumpAndSettle();
      expect(controller.currentWorkspace?.tabById(original.id), original);
      expect(controller.activeTab?.panel, ForumPanel.main);
      expect(controller.tabsForCurrentForum, hasLength(4));
      expect(
        controller.tabsForCurrentForum.last.currentContent.feedPath,
        '/tag/flutter/12.json',
      );
      expect(
        controller.tabsForCurrentForum.last.currentContent.topicId,
        isNull,
      );

      controller.selectTab(opened.id);
      await tester.pumpAndSettle();
      expect(controller.currentContent?.topicId, topic.id);
    }),
  );

  testWidgets(
    'number shortcuts map the first nine ordered forums',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      final forums = [
        for (var index = 1; index <= 9; index++)
          instance('forum-$index.example', title: 'Forum $index'),
      ];
      await _pumpShell(tester, instances: forums);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );

      for (var index = 0; index < forums.length; index++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(
          await tester.sendKeyEvent(forumSwitchShortcutKeys[index]),
          isTrue,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(controller.rootMode, ShellRootMode.forum);
        expect(controller.instanceIndex, index);
        expect(controller.currentInstance?.url, forums[index].url);
      }
    }),
  );

  testWidgets(
    'rail tooltips show the shortcuts for each forum',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(
        tester,
        instances: [
          instance('one.example', title: 'Discourse Team'),
          instance('two.example', title: 'Discourse Meta'),
        ],
      );

      final forum = find.byKey(const ValueKey('https://two.example'));
      final rawTooltip = tester.widget<DTooltip>(
        find.descendant(of: forum, matching: find.byType(DTooltip)),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final (key, message) in [
        ('add-instance-rail-button', 'Add a Discourse site'),
        ('styleguide-rail-button', 'Open component styleguide'),
        ('settings-rail-button', 'Settings'),
      ]) {
        final button = find.byKey(ValueKey(key));
        await mouse.moveTo(tester.getCenter(button));
        await tester.pump(DTooltip.defaultHoverDelay);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text(message).last).left,
          greaterThan(tester.getRect(button).right),
          reason: '$message should appear to the right of the rail control',
        );
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
      }
      await mouse.moveTo(tester.getCenter(forum));
      await tester.pump(rawTooltip.hoverDelay);
      await tester.pumpAndSettle();

      final callout = find.byKey(
        const ValueKey('instance-rail-callout-https://two.example'),
      );
      final keycaps = find.descendant(
        of: find
            .ancestor(of: callout, matching: find.byType(SingleChildScrollView))
            .first,
        matching: find.byType(DShortcutKeycaps),
      );
      final shortcut = tester.widget<DShortcutKeycaps>(keycaps).shortcut[0];
      expect(shortcut.trigger, LogicalKeyboardKey.digit2);
      expect(shortcut.meta, isTrue);
      expect(shortcut.control, isFalse);
      expect(tester.getSize(keycaps).height, 20);
      expect(tester.getSize(callout).height, lessThanOrEqualTo(64));
    }),
  );

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} switches forums only with its primary shortcut',
      (tester) => _withPlatform(platform, () async {
        await _pumpShell(tester, twoForums: true);
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        controller.createTab();
        controller.createTab();
        await tester.pump();

        final activeTabId = controller.activeTabId;
        expect(controller.instanceIndex, 0);

        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit2), isFalse);
        expect(controller.instanceIndex, 0);

        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit2), isTrue);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();

        expect(controller.instanceIndex, 1);
        expect(_bar(tester).forumName, 'Two');

        await tester.sendKeyDownEvent(modifier);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit3), isFalse);
        await tester.sendKeyUpEvent(modifier);
        expect(controller.instanceIndex, 1);

        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit1), isFalse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(modifier);
        expect(controller.instanceIndex, 1);

        await tester.sendKeyDownEvent(modifier);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit1), isTrue);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();

        expect(controller.instanceIndex, 0);
        expect(controller.activeTabId, activeTabId);
      }),
    );
  }

  testWidgets('tab shortcuts stay idle under a dialog', (tester) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      final originalTabId = controller.activeTabId!;
      expect(controller.tabsForCurrentForum, hasLength(2));

      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(MainContent).first),
          builder: (_) => const AlertDialog(title: Text('Remove this forum?')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove this forum?'), findsOneWidget);

      expect(
        await _pressShortcut(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyW,
        ),
        isFalse,
      );
      expect(
        await _pressShortcut(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyT,
        ),
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(controller.tabsForCurrentForum, hasLength(2));
      expect(find.text('Remove this forum?'), findsOneWidget);
      expect(binding.exitRequests, isEmpty);

      Navigator.of(tester.element(find.text('Remove this forum?'))).pop();
      await tester.pumpAndSettle();

      expect(
        await _pressShortcut(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyW,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(controller.currentWorkspace!.tabById(originalTabId), isNull);
      expect(controller.currentContent!.isNewTab, isTrue);
      expect(binding.exitRequests, isEmpty);
    });
  });

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} opens, closes, and reopens tabs with primary shortcuts',
      (tester) => _withPlatform(platform, () async {
        await _pumpShell(tester);
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        final originalTabId = controller.activeTabId!;
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;

        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyT), isFalse);
        expect(controller.tabsForCurrentForum, hasLength(2));
        expect(
          await _pressShortcut(
            tester,
            modifier,
            LogicalKeyboardKey.keyT,
            shift: true,
          ),
          isFalse,
        );

        expect(
          await _pressShortcut(tester, modifier, LogicalKeyboardKey.keyT),
          isTrue,
        );
        await tester.pumpAndSettle();

        final openedTabId = controller.activeTabId!;
        expect(openedTabId, isNot(originalTabId));
        expect(controller.tabsForCurrentForum, hasLength(3));
        expect(_bar(tester).selectedId, openedTabId);

        expect(
          await _pressShortcut(tester, modifier, LogicalKeyboardKey.keyW),
          isTrue,
        );
        await tester.pumpAndSettle();

        expect(
          controller.currentWorkspace!
              .tabsIn(ForumPanel.main)
              .map((tab) => tab.id),
          [originalTabId],
        );
        expect(controller.activeTabId, originalTabId);
        expect(_bar(tester).selectedId, originalTabId);
        expect(binding.exitRequests, isEmpty);

        expect(
          await _pressShortcut(
            tester,
            modifier,
            LogicalKeyboardKey.keyT,
            shift: true,
          ),
          isTrue,
        );
        await tester.pumpAndSettle();

        expect(
          controller.currentWorkspace!
              .tabsIn(ForumPanel.main)
              .map((tab) => tab.id),
          [originalTabId, openedTabId],
        );
        expect(controller.activeTabId, openedTabId);
        expect(_bar(tester).selectedId, openedTabId);
      }),
    );

    for (final rootMode in [ShellRootMode.forum]) {
      testWidgets(
        '${platform.name} closing the last ${rootMode.name} tab keeps a usable workspace',
        (tester) => _withPlatform(platform, () async {
          await _pumpShell(tester);
          final controller = ShellScope.read(
            tester.element(find.byType(MainContent).first),
          );

          final originalTabId = _bar(tester).selectedId;
          final modifier = platform == TargetPlatform.macOS
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft;

          expect(
            await _pressShortcut(tester, modifier, LogicalKeyboardKey.keyW),
            isTrue,
          );
          await tester.pumpAndSettle();

          expect(binding.exitRequests, isEmpty);
          expect(controller.currentWorkspace!.tabById(originalTabId), isNull);
          expect(controller.currentContent!.isNewTab, isTrue);
          expect(
            controller
                .selectedTabIn(ForumPanel.secondary)!
                .currentContent
                .isNewTab,
            isTrue,
          );
        }),
      );
    }
  }

  for (final platform in const [TargetPlatform.macOS, TargetPlatform.linux]) {
    for (final tabCount in const [1, 2]) {
      testWidgets(
        '${platform.name} primary W in a focused composer closes only the '
        'composer with $tabCount open tab(s)',
        (tester) => _withPlatform(platform, () async {
          const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');
          const topic = Topic(
            id: 7,
            title: 'A real topic',
            slug: 'a-real-topic',
          );
          await _pumpShell(
            tester,
            instances: [
              instance('one.example', title: 'One').copyWith(user: me),
            ],
            authenticator: FakeAuthenticator()
              ..keys['https://one.example'] = 'one-key',
            api: FakeDiscourseApi(
              feeds: const {
                '/latest.json': [topic],
              },
              topics: {
                topic.id: topicPayload(
                  id: topic.id,
                  title: topic.title,
                  canCreatePost: true,
                  posts: const [
                    Post(
                      id: 1,
                      postNumber: 1,
                      username: 'sam',
                      cooked: '<p>First post body</p>',
                    ),
                  ],
                ),
              },
            ),
          );
          final controller = ShellScope.read(
            tester.element(find.byType(MainContent).first),
          );
          if (tabCount == 2) {
            controller.createTab();
            await tester.pumpAndSettle();
          }
          controller.openTopic(topic);
          await tester.pumpAndSettle();
          final tabIds = [
            for (final tab in controller.tabsForCurrentForum) tab.id,
          ];
          final activeTabId = controller.activeTabId!;
          expect(tabIds, hasLength(tabCount + 1));

          controller.openReply();
          await tester.pumpAndSettle();
          final body = find
              .descendant(
                of: find.byType(ComposerPanel),
                matching: find.byType(EditableText),
              )
              .first;
          await tester.tap(body);
          await tester.enterText(body, 'A reply in progress');
          await tester.pumpAndSettle();
          final modifier = platform == TargetPlatform.macOS
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft;

          expect(
            await _pressShortcut(tester, modifier, LogicalKeyboardKey.keyW),
            isTrue,
          );
          await tester.pumpAndSettle();

          expect(find.byType(ComposerPanel), findsNothing);
          expect(controller.visibleComposer, isNull);
          expect(controller.tabsForCurrentForum.map((tab) => tab.id), tabIds);
          expect(controller.activeTabId, activeTabId);
          expect(controller.currentContent?.topicId, topic.id);
          expect(binding.exitRequests, isEmpty);

          // Outside the composer the chord closes the tab as before.
          expect(
            await _pressShortcut(tester, modifier, LogicalKeyboardKey.keyW),
            isTrue,
          );
          await tester.pumpAndSettle();

          if (tabCount == 1) {
            expect(binding.exitRequests, isEmpty);
            expect(controller.currentWorkspace!.tabById(activeTabId), isNull);
            expect(controller.currentContent!.isNewTab, isTrue);
            expect(controller.tabsForCurrentForum, hasLength(2));
          } else {
            expect(binding.exitRequests, isEmpty);
            expect(controller.tabsForCurrentForum.map((tab) => tab.id), [
              for (final id in tabIds)
                if (id != activeTabId) id,
            ]);
          }
        }),
      );
    }
  }

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} cycles forum tabs with arrow shortcuts',
      (tester) => _withPlatform(platform, () async {
        await _pumpShell(tester);
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;

        final firstForumTabId = controller.activeTabId!;
        controller.createTab();
        controller.createTab();
        await tester.pumpAndSettle();
        final lastForumTabId = controller.activeTabId!;
        final sidebarWidth = tester.getSize(find.byType(InstanceSidebar)).width;
        final resizeFocus = tester
            .widget<Focus>(find.byKey(const ValueKey('sidebar-resize-focus')))
            .focusNode!;
        resizeFocus.requestFocus();
        await tester.pump();
        expect(resizeFocus.hasFocus, isTrue);

        expect(
          await _pressShortcut(tester, modifier, LogicalKeyboardKey.arrowRight),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(controller.activeTabId, firstForumTabId);
        expect(_bar(tester).selectedId, firstForumTabId);
        expect(
          tester.getSize(find.byType(InstanceSidebar)).width,
          sidebarWidth,
        );
        expect(resizeFocus.hasFocus, isFalse);

        expect(
          await _pressShortcut(tester, modifier, LogicalKeyboardKey.arrowLeft),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(controller.activeTabId, lastForumTabId);
        expect(_bar(tester).selectedId, lastForumTabId);
        expect(
          tester.getSize(find.byType(InstanceSidebar)).width,
          sidebarWidth,
        );

        controller.selectInstance(0);
        controller.selectTab(firstForumTabId);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ForumSearch.inputKey));
        await tester.pump();

        await _pressShortcut(tester, modifier, LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(
          controller.activeTabId,
          firstForumTabId,
          reason: 'Focused form controls retain native arrow navigation.',
        );
      }),
    );
  }

  testWidgets(
    'maps current routes and delegates tab lifecycle actions',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      final originalId = controller.activeTabId!;

      expect(find.byType(ForumTabsBar), findsNWidgets(2));
      expect(_bar(tester).forumName, 'One');
      expect(_bar(tester).items.single.title, 'Latest');
      expect(_bar(tester).selectedId, originalId);

      controller.openContentInNewTab(
        ContentRoute.topicList(TopicListMode.topYearly),
      );
      await tester.pumpAndSettle();
      expect(_bar(tester).items.last.title, 'Top - year');
      expect(_bar(tester).items, hasLength(2));

      controller.openContentInNewTab(
        ContentRoute.filteredTopicList(
          TopicListMode.topMonthly,
          tags: const ['design'],
        ),
      );
      await tester.pumpAndSettle();
      expect(_bar(tester).items.last.title, 'Top - month');
      expect(_bar(tester).items, hasLength(3));

      await tester.tap(find.byKey(const ValueKey('forum-tabs-add')).first);
      await tester.pumpAndSettle();

      final newId = controller.activeTabId!;
      expect(newId, isNot(originalId));
      expect(_bar(tester).items, hasLength(4));
      expect(_bar(tester).selectedId, newId);
      expect(controller.currentContent?.isNewTab, isTrue);

      const color = Color(0xFF0088CC);
      controller.pushContent(
        ContentRoute.topic(
          topicId: 42,
          slug: 'native-tabs',
          title: 'Native tabs',
          color: color,
        ),
      );
      await tester.pumpAndSettle();

      final topicId = controller.activeTabId!;
      expect(controller.activeTabId, newId);
      expect(controller.activeTab?.panel, ForumPanel.main);
      final ForumTabItem routedItem = tester
          .widgetList<ForumTabsBar>(find.byType(ForumTabsBar))
          .expand((bar) => bar.items)
          .singleWhere((item) => item.id == topicId);
      expect(routedItem.title, 'Native tabs');
      expect(routedItem.icon, DNativeIcons.topic);
      expect(routedItem.color, color);

      await tester.ensureVisible(find.byKey(ValueKey('forum-tab-$originalId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('forum-tab-$originalId')));
      await tester.pumpAndSettle();
      expect(controller.activeTabId, originalId);
      expect(_bar(tester).selectedId, originalId);

      await tester.tap(find.byKey(const ValueKey('forum-tabs-switcher')).first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('forum-tabs-switcher-open-$originalId')),
          matching: find.byType(DButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.tabsForCurrentForum, hasLength(4));
      expect(
        controller.tabsForCurrentForum.where(
          (tab) => !tab.currentContent.isTopic,
        ),
        hasLength(3),
      );
      expect(_bar(tester).items.map((item) => item.id), contains(newId));
      expect(_bar(tester).selectedId, isNot(originalId));
      expect(_bar(tester).recentlyClosedItems.single.id, originalId);
      await tester.tap(
        find.byKey(ValueKey('forum-tabs-switcher-recent-$originalId')),
      );
      await tester.pumpAndSettle();

      expect(controller.activeTabId, originalId);
      expect(_bar(tester).selectedId, originalId);
      expect(_bar(tester).items, hasLength(4));
      expect(_bar(tester).recentlyClosedItems, isEmpty);
    }),
  );

  testWidgets(
    'shows only the selected forum workspace and restores each one',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, twoForums: true);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );

      controller.createTab();
      await tester.pumpAndSettle();
      final firstForumIds = [for (final item in _bar(tester).items) item.id];
      final firstForumActive = _bar(tester).selectedId;
      expect(_bar(tester).forumName, 'One');
      expect(firstForumIds, hasLength(2));

      controller.selectInstance(1);
      await tester.pumpAndSettle();

      expect(_bar(tester).forumName, 'Two');
      expect(_bar(tester).items, hasLength(1));
      expect(firstForumIds, isNot(contains(_bar(tester).items.single.id)));

      controller.createTab();
      await tester.pumpAndSettle();
      final secondForumIds = [for (final item in _bar(tester).items) item.id];
      final secondForumActive = _bar(tester).selectedId;
      expect(secondForumIds, hasLength(2));
      expect(secondForumIds, everyElement(isNot(isIn(firstForumIds))));

      controller.selectInstance(0);
      await tester.pumpAndSettle();

      expect(_bar(tester).forumName, 'One');
      expect([for (final item in _bar(tester).items) item.id], firstForumIds);
      expect(_bar(tester).selectedId, firstForumActive);

      controller.selectInstance(1);
      await tester.pumpAndSettle();

      expect(_bar(tester).forumName, 'Two');
      expect([for (final item in _bar(tester).items) item.id], secondForumIds);
      expect(_bar(tester).selectedId, secondForumActive);
    }),
  );

  testWidgets(
    'activates and renders an existing tab before its feed finishes',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      const siteUrl = 'https://one.example';
      const firstTabId = 'tab-latest';
      const slowTabId = 'tab-slow';
      const latestRoute = ContentRoute(
        id: 'latest',
        title: 'Topics',
        icon: DIcons.layerGroup,
      );
      const slowRoute = ContentRoute(
        id: 'slow-list',
        title: 'Slow destination',
        icon: DIcons.folder,
        feedPath: '/slow.json',
      );
      final workspace = ForumWorkspace(
        siteUrl: siteUrl,
        accountIdentity: 'anonymous',
        tabs: [
          ForumTab(
            id: firstTabId,
            rootDestinationId: latestRoute.id,
            contentStack: const [latestRoute],
          ),
          ForumTab(
            id: slowTabId,
            rootDestinationId: slowRoute.id,
            contentStack: const [slowRoute],
          ),
        ],
        activeTabId: firstTabId,
      );
      final releaseSlowFeed = Completer<void>();
      final slowFeedStarted = Completer<void>();
      addTearDown(() {
        if (!releaseSlowFeed.isCompleted) releaseSlowFeed.complete();
      });
      final api = _PathGatedApi(
        heldPath: slowRoute.feedPath!,
        release: releaseSlowFeed,
        started: slowFeedStarted,
        feeds: const {'/latest.json': [], '/slow.json': []},
      );
      final tabStore = FakeForumTabStore([workspace]);

      await _pumpShell(tester, api: api, forumTabs: tabStore);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      const originalViewportKey = ValueKey('inbox-topic-list-pane');
      final slowViewportKey = ValueKey<(String?, String?, String, int?)>((
        siteUrl,
        slowTabId,
        slowRoute.id,
        null,
      ));

      expect(controller.activeTabId, firstTabId);
      expect(find.byKey(originalViewportKey), findsOneWidget);
      expect(slowFeedStarted.isCompleted, isFalse);

      final savesBeforeRapidSwitch = tabStore.saveCount;
      controller.selectTab(slowTabId);
      controller.selectTab(firstTabId);
      expect(controller.activeTabId, firstTabId);
      await tester.pump();
      expect(tabStore.saveCount, savesBeforeRapidSwitch + 1);
      expect(slowFeedStarted.isCompleted, isFalse);

      final savesBeforeTap = tabStore.saveCount;
      var paintedBeforeBackgroundWork = false;
      tester.binding.addPostFrameCallback((_) {
        paintedBeforeBackgroundWork = true;
        expect(_bar(tester).selectedId, slowTabId);
        expect(
          find.byKey(const ValueKey('forum-tab-item-tab-slow')),
          findsOneWidget,
        );
        expect(find.byKey(originalViewportKey), findsNothing);
        expect(find.byKey(slowViewportKey), findsOneWidget);
        expect(slowFeedStarted.isCompleted, isFalse);
        expect(tabStore.saveCount, savesBeforeTap);
      });

      await tester.tap(find.byKey(const ValueKey('forum-tab-tab-slow')));

      // Gesture activation mutates navigation state synchronously. Neither a
      // frame nor the destination's response is required for this state move.
      expect(controller.activeTabId, slowTabId);
      expect(releaseSlowFeed.isCompleted, isFalse);
      expect(tabStore.saveCount, savesBeforeTap);

      // Paint the optimistic switch once. `pumpAndSettle` here would wait
      // through tab reveal and hide a regression tied to async hydration.
      await tester.pump();

      expect(paintedBeforeBackgroundWork, isTrue);
      expect(slowFeedStarted.isCompleted, isTrue);
      expect(releaseSlowFeed.isCompleted, isFalse);
      expect(tabStore.saveCount, savesBeforeTap + 1);
      expect(_bar(tester).selectedId, slowTabId);
      expect(
        find.byKey(const ValueKey('forum-tab-item-tab-slow')),
        findsOneWidget,
      );
      expect(find.byKey(originalViewportKey), findsNothing);
      expect(find.byKey(slowViewportKey), findsOneWidget);
      final slowContentText = _contentTextOutsideTabs('Slow destination');
      expect(
        slowContentText,
        findsOneWidget,
        reason: 'the route title appears in the content header',
      );
      expect(
        tester.getCenter(slowContentText.first).dy,
        lessThan(tester.getTopLeft(find.byKey(slowViewportKey)).dy),
      );

      releaseSlowFeed.complete();
      await tester.pumpAndSettle();
    }),
  );

  testWidgets(
    'keeps tab presentation out of InstanceSidebar',
    (tester) => _withPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester);

      expect(_inSidebar(find.byType(ForumTabsBar)), findsNothing);
      expect(_inSidebar(find.text('OPEN')), findsNothing);
      expect(_inWorkspace(find.byType(ForumTabsBar)), findsNWidgets(2));
      expect(find.byType(ForumTabsBar), findsNWidgets(2));
    }),
  );

  for (final platform in const [
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      '${platform.name} keeps forum tabs in the content panel at every width',
      (tester) => _withPlatform(platform, () async {
        for (final size in const [_compact, _medium, _expanded]) {
          await _pumpShell(
            tester,
            size: size,
            key: ValueKey('${platform.name}-${size.width}'),
          );

          expect(_inSidebar(find.byType(ForumTabsBar)), findsNothing);
          expect(_inSidebar(find.text('OPEN')), findsNothing);

          final panelCount = size == _compact ? 1 : 2;
          expect(find.byType(MainContent), findsNWidgets(panelCount));
          expect(find.byType(ForumTabsBar), findsNWidgets(panelCount));
          expect(
            tester.getRect(find.byType(ForumTabsBar).first).top,
            lessThanOrEqualTo(
              tester.getRect(find.byType(MainContent).first).top,
            ),
          );
          expect(find.byType(CurrentForumTabsBar), findsWidgets);
          expect(
            find.byKey(const ValueKey('forum-tabs-add')),
            findsNWidgets(panelCount),
          );
          expect(_bar(tester).items.single.title, 'Latest');
        }
      }),
    );
  }

  for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} omits the forum-tab subtree at every width',
      (tester) => _withPlatform(platform, () async {
        for (final size in const [_compact, _medium, _expanded]) {
          await _pumpShell(
            tester,
            size: size,
            key: ValueKey('${platform.name}-${size.width}'),
          );

          expect(_inSidebar(find.text('OPEN')), findsNothing);

          if (size == _compact && find.byType(MainContent).evaluate().isEmpty) {
            await tester.tap(_sidebarText('Topics'));
            await tester.pumpAndSettle();
          }
          expect(find.byType(MainContent), findsOneWidget);

          expect(
            find.byType(CurrentForumTabsBar, skipOffstage: false),
            findsNothing,
          );
          expect(find.byType(ForumTabsBar, skipOffstage: false), findsNothing);
          expect(
            find.byKey(const ValueKey('forum-tabs-add'), skipOffstage: false),
            findsNothing,
          );
        }
      }),
    );
  }
}

ForumTabsBar _bar(WidgetTester tester) =>
    tester.widget<ForumTabsBar>(find.byType(ForumTabsBar).first);

Finder _inSidebar(Finder matching) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: matching,
  skipOffstage: false,
);

Finder _inWorkspace(Finder matching) => find.descendant(
  of: find.byType(DesktopPanels),
  matching: matching,
  skipOffstage: false,
);

Finder _sidebarText(String text) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.text(text),
);

Finder _contentTextOutsideTabs(String label) =>
    find.byElementPredicate((element) {
      final widget = element.widget;
      if (widget is! Text || widget.data != label) return false;

      var inMainContent = false;
      var inTabBar = false;
      element.visitAncestorElements((ancestor) {
        inMainContent |= ancestor.widget is MainContent;
        inTabBar |= ancestor.widget is ForumTabsBar;
        return true;
      });
      return inMainContent && !inTabBar;
    }, description: 'main content text outside forum tabs labelled "$label"');

Future<void> _pumpShell(
  WidgetTester tester, {
  bool twoForums = false,
  List<DiscourseInstance>? instances,
  Size size = _medium,
  Key? key,
  FakeDiscourseApi? api,
  FakeAuthenticator? authenticator,
  FakeForumTabStore? forumTabs,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final configuredInstances =
      instances ??
      [
        instance('one.example', title: 'One'),
        if (twoForums) instance('two.example', title: 'Two'),
      ];
  await tester.pumpWidget(
    DiscourseApp(
      key: key,
      store: FakeInstanceStore(configuredInstances),
      api: api ?? FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: authenticator ?? FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: forumTabs ?? FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await tester.pumpAndSettle();

  // iOS and Android keep the mobile shell at tablet widths, where the sidebar
  // lives behind the hamburger rather than beside the content.
  if (size.width < 768 || usesMobileNavigation(defaultTargetPlatform)) return;
  if (find.byTooltip('Expand sidebar').evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('Expand sidebar'));
    await tester.pumpAndSettle();
  }
  expect(find.byType(InstanceSidebar), findsOneWidget);
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

class _ExitRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  final exitRequests = <({AppExitType type, int exitCode})>[];

  @override
  Future<AppExitResponse> exitApplication(
    AppExitType exitType, [
    int exitCode = 0,
  ]) {
    exitRequests.add((type: exitType, exitCode: exitCode));
    return super.exitApplication(exitType, exitCode);
  }
}

Future<bool> _pressShortcut(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final handled = await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  return handled;
}

final class _PathGatedApi extends FakeDiscourseApi {
  _PathGatedApi({
    required this.heldPath,
    required this.release,
    required this.started,
    required super.feeds,
  });

  final String heldPath;
  final Completer<void> release;
  final Completer<void> started;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (path == heldPath) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    return super.topicList(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
