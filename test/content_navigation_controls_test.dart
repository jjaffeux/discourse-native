import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/content_navigation_controls.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    final macOS = platform == TargetPlatform.macOS;
    final modifier = macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.altLeft;
    final back = macOS
        ? LogicalKeyboardKey.bracketLeft
        : LogicalKeyboardKey.arrowLeft;
    final forward = macOS
        ? LogicalKeyboardKey.bracketRight
        : LogicalKeyboardKey.arrowRight;
    final refresh = macOS ? LogicalKeyboardKey.keyR : LogicalKeyboardKey.f5;

    _testOnPlatform(
      platform,
      '${platform.name} buttons share mouse and keyboard history',
      (tester) async {
        await pumpShell(tester, desktop);
        final shell = _shell(tester);
        final tabId = shell.activeTabId;

        expect(find.byType(DButtonGroup), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(DButtonGroup)),
          matchesSemantics(label: 'Content navigation', hasEnabledState: false),
        );

        expect(
          _button(tester, ContentNavigationControls.backKey).onPressed,
          isNull,
        );
        expect(
          _button(tester, ContentNavigationControls.forwardKey).onPressed,
          isNull,
        );
        _expectShortcut(
          tester,
          ContentNavigationControls.backKey,
          back,
          meta: macOS,
          alt: !macOS,
        );
        _expectShortcut(
          tester,
          ContentNavigationControls.forwardKey,
          forward,
          meta: macOS,
          alt: !macOS,
        );
        _expectShortcut(
          tester,
          ContentNavigationControls.refreshKey,
          refresh,
          meta: macOS,
        );
        expect(
          _button(tester, ContentNavigationControls.backKey).tooltip,
          contains('mouse back button'),
        );
        final field = tester.getRect(find.byKey(ForumSearch.inputKey));
        var previousRight = 0.0;
        for (final key in [
          ContentNavigationControls.backKey,
          ContentNavigationControls.forwardKey,
          ContentNavigationControls.refreshKey,
        ]) {
          final rect = tester.getRect(find.byKey(key));
          expect(rect.left, greaterThanOrEqualTo(previousRight));
          expect(rect.right, lessThan(field.left));
          previousRight = rect.right;
        }

        shell.pushContent(
          const ContentRoute(
            id: 'navigation-test',
            title: 'Navigation test',
            icon: DIcons.comments,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ContentNavigationControls.backKey));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'latest');
        expect(
          _button(tester, ContentNavigationControls.backKey).onPressed,
          isNull,
        );
        await tester.tap(find.byKey(ContentNavigationControls.forwardKey));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'navigation-test');

        await _press(tester, back, modifier: modifier);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'latest');
        await _press(tester, forward, modifier: modifier);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'navigation-test');
        await tester.tapAt(
          tester.getBottomRight(find.byType(MainContent)) -
              const Offset(20, 20),
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ContentNavigationControls.forwardKey));
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'navigation-test');
        expect(shell.activeTabId, tabId);

        shell.createTab();
        await tester.pumpAndSettle();
        expect(
          _button(tester, ContentNavigationControls.backKey).onPressed,
          isNull,
        );
        expect(
          _button(tester, ContentNavigationControls.forwardKey).onPressed,
          isNull,
        );
        shell.selectTab(tabId!);
        await tester.pumpAndSettle();
        expect(
          _button(tester, ContentNavigationControls.backKey).onPressed,
          isNotNull,
        );
      },
    );

    _testOnPlatform(
      platform,
      '${platform.name} refresh reloads the active feed and ignores modals',
      (tester) async {
        final gates = <String, Completer<void>>{};
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': []},
          feedGates: gates,
        );
        await pumpShell(tester, desktop, api: api);
        final shell = _shell(tester);
        api.feedPaths.clear();
        api.feeds['/latest.json'] = const [
          Topic(id: 99, title: 'Updated feed', slug: 'updated-feed'),
        ];
        await tester.tap(find.byKey(ContentNavigationControls.refreshKey));
        await tester.pumpAndSettle();
        expect(api.feedPaths, ['/latest.json']);
        expect(find.text('Updated feed'), findsOneWidget);

        final gate = Completer<void>();
        gates['/latest.json'] = gate;
        await tester.tap(find.byKey(ForumSearch.inputKey));
        await tester.pumpAndSettle();
        await _press(tester, refresh, modifier: macOS ? modifier : null);
        await tester.pump();
        expect(shell.refreshingCurrentTab, isTrue);
        expect(
          _button(tester, ContentNavigationControls.refreshKey).loading,
          isTrue,
        );
        await _press(tester, refresh, modifier: macOS ? modifier : null);
        await tester.pump();
        expect(api.feedPaths, ['/latest.json', '/latest.json']);
        gate.complete();
        await tester.pumpAndSettle();
        expect(shell.refreshingCurrentTab, isFalse);

        shell.search.closePanel();
        unawaited(
          showDialog<void>(
            context: tester.element(find.byType(MainContent)),
            builder: (_) => const AlertDialog(title: Text('Navigation dialog')),
          ),
        );
        await tester.pumpAndSettle();
        await _press(tester, refresh, modifier: macOS ? modifier : null);
        await _press(tester, back, modifier: modifier);
        await tester.pumpAndSettle();
        expect(find.text('Navigation dialog'), findsOneWidget);
        expect(api.feedPaths, ['/latest.json', '/latest.json']);
      },
    );

    _testOnPlatform(
      platform,
      '${platform.name} desktop controls fit a narrow window',
      (tester) async {
        await pumpShell(tester, const Size(500, 800));
        expect(
          find.byKey(ContentNavigationControls.refreshKey),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  _testOnPlatform(
    TargetPlatform.macOS,
    'refresh keeps topic history, reading position, drafts, and other tabs',
    (tester) async {
      const user = DiscourseUser(id: 7, username: 'sam');
      const topic = Topic(
        id: 42,
        title: 'Current topic',
        slug: 'current-topic',
      );
      const other = Topic(
        id: 43,
        title: 'Background topic',
        slug: 'background',
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: const {
          '/latest.json': [topic, other],
        },
        topics: {
          for (final row in [topic, other])
            row.id: topicPayload(
              id: row.id,
              title: row.title,
              canCreatePost: true,
              posts: [
                Post(
                  id: row.id * 100,
                  postNumber: 1,
                  username: 'sam',
                  cooked: '<p>Post body</p>',
                ),
              ],
            ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [instance('meta.example').copyWith(user: user)],
      );
      final shell = _shell(tester);
      final originalTab = shell.activeTabId!;
      shell.openTopic(other);
      await tester.pumpAndSettle();
      shell.createTab();
      await tester.pumpAndSettle();
      shell.openTopic(topic);
      await tester.pumpAndSettle();
      shell.openReply();
      await tester.pumpAndSettle();
      final composer = shell.visibleComposer!;
      composer.text.text = 'A draft that must survive refreshing this tab.';
      await tester.pumpAndSettle();
      final tab = shell.activeTab!;
      final position = shell.topicScrollPostNumber(topic.id);
      api.topicsOpened.clear();
      api.feedPaths.clear();

      await _press(
        tester,
        LogicalKeyboardKey.keyR,
        modifier: LogicalKeyboardKey.metaLeft,
      );
      await tester.pumpAndSettle();
      expect(api.topicsOpened, [topic.id]);
      expect(api.feedPaths, ['/latest.json']);
      expect(shell.activeTabId, tab.id);
      expect(shell.contentStack, tab.contentStack);
      expect(shell.activeTab!.forwardStack, tab.forwardStack);
      expect(shell.topicScrollPostNumber(topic.id), position);
      expect(shell.visibleComposer, same(composer));
      expect(composer.raw, 'A draft that must survive refreshing this tab.');
      expect(
        shell.tabsForCurrentForum
            .firstWhere((tab) => tab.id == originalTab)
            .currentContent
            .topicId,
        other.id,
      );
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    _testOnPlatform(
      platform,
      '${platform.name} retains the mobile search layout',
      (tester) async {
        await pumpShell(tester, phone);
        expect(find.byType(ForumSearch), findsOneWidget);
        expect(find.byType(ContentNavigationControls), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _testOnPlatform(
  TargetPlatform platform,
  String description,
  Future<void> Function(WidgetTester) test,
) {
  testWidgets(description, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = platform;
    try {
      await test(tester);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

ShellController _shell(WidgetTester tester) =>
    ShellScope.read(tester.element(find.byType(MainContent)));

DButton _button(WidgetTester tester, Key key) =>
    tester.widget<DButton>(find.byKey(key));

void _expectShortcut(
  WidgetTester tester,
  Key key,
  LogicalKeyboardKey trigger, {
  bool meta = false,
  bool alt = false,
}) {
  final tooltip = tester.widget<DTooltip>(
    find.descendant(of: find.byKey(key), matching: find.byType(DTooltip)),
  );
  expect(tooltip.shortcut![0].trigger, trigger);
  expect(tooltip.shortcut![0].meta, meta);
  expect(tooltip.shortcut![0].alt, alt);
  expect(tooltip.shortcut![0].control, isFalse);
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? modifier,
}) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
}
