import 'dart:convert';

import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tab_switch_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });
  {
    desktopTest('rapid tab buttons reuse warmed document pages (flat)', (
      tester,
    ) async {
      final shell = await pumpTabSwitchFixture(tester);
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(),
      );
      await tester.pumpAndSettle();
      for (final id in tabSwitchIds) {
        await tapDocumentTab(tester, id);
        await tester.pumpAndSettle();
      }
      final states = <String, State>{};
      final positions = <String, ScrollPosition>{};
      for (final id in tabSwitchIds) {
        await tapDocumentTab(tester, id);
        await tester.pumpAndSettle();
        states[id] = tester.state(_page(id));
        final scrollable = find
            .descendant(
              of: _page(id),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable && widget.axis == Axis.vertical,
              ),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(1000));
        position.jumpTo(400);
        await tester.pumpAndSettle();
        positions[id] = position;
      }
      var builds = 0;
      var pageBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        builds++;
        if (element.widget is TopicView || element.widget is TopicListView) {
          pageBuilds++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var round = 0; round < 3; round++) {
        for (final id in tabSwitchIds) {
          await tapDocumentTab(tester, id);
          await tester.pump();
          expect(shell.activeTabId, id);
          expect(tester.state(_page(id)), same(states[id]));
          expect(positions[id]!.pixels, closeTo(400, 1));
          if (id.startsWith('reader-')) {
            expect(
              shell.visibleTopicContext?.topicId,
              id == 'reader-a' ? 1 : 2,
            );
          }
        }
      }
      debugOnRebuildDirtyWidget = previous;
      debugPrint(
        'TAB_SWITCH_WORK ${jsonEncode({'builds': builds, 'pageBuilds': pageBuilds})}',
      );
      expect(
        pageBuilds,
        0,
        reason: 'Tab visibility must not rebuild whole pages.',
      );
      expect(tester.takeException(), isNull);
      expect(states.values.every((state) => state.mounted), isTrue);
      expect(find.byType(MainContent), findsNWidgets(2));
      expect(find.byType(MainContent, skipOffstage: false), findsNWidgets(4));
      for (final id in ['list-a', 'reader-a']) {
        final page = states[id]!;
        expect(TickerMode.valuesOf(page.context).enabled, isFalse);
        expect(Focus.of(page.context).descendantsAreFocusable, isFalse);
      }
    });
  }

  desktopTest('retained long readers give mounting turns to the selected tab', (
    tester,
  ) async {
    final shell = await pumpTabSwitchFixture(tester);
    final firstPage = tester.state(_page('reader-a'));
    await tapDocumentTab(tester, 'reader-b');
    await tester.pumpAndSettle();
    final secondPage = tester.state(_page('reader-b'));
    for (final (id, label) in [(1001, 'Reader A'), (2001, 'Reader B')]) {
      shell.store.update<Post>(
        'https://tabs.example',
        id,
        (post) =>
            post.copyWith(cooked: List.filled(450, '<p>$label</p>').join()),
      );
    }
    Finder paragraphs(String label) => find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == label,
      skipOffstage: false,
    );
    int count(String label) => paragraphs(label).evaluate().length;
    await tester.pump();
    final initial = count('Reader A');
    expect(initial, inExclusiveRange(0, 450));
    expect(count('Reader B'), initial);
    final firstParagraph = tester.element(paragraphs('Reader A').first);
    expect(TickerMode.valuesOf(firstParagraph).enabled, isFalse);
    await tester.pump();
    expect(count('Reader A'), initial);
    expect(count('Reader B'), greaterThan(initial));
    await tapDocumentTab(tester, 'reader-a');
    await tester.pump();
    final hiddenCount = count('Reader B');
    await tester.pump();
    expect(count('Reader A'), greaterThan(initial));
    expect(count('Reader B'), hiddenCount);
    expect(tester.state(_page('reader-a')), same(firstPage));
    expect(tester.element(paragraphs('Reader A').first), same(firstParagraph));
    await tester.pumpAndSettle();
    expect(count('Reader A'), 450);
    // A hidden reader's unfinished body resumes only once its tab is shown.
    expect(count('Reader B'), hiddenCount);
    expect(hiddenCount, lessThan(450));
    final secondParagraph = tester.element(paragraphs('Reader B').first);
    await tapDocumentTab(tester, 'reader-b');
    await tester.pumpAndSettle();
    expect(tester.state(_page('reader-b')), same(secondPage));
    expect(count('Reader B'), 450);
    expect(tester.element(paragraphs('Reader B').first), same(secondParagraph));
    expect(tester.takeException(), isNull);
  });

  desktopTest('page retention is bounded and releases closed tabs', (
    tester,
  ) async {
    final shell = await pumpTabSwitchFixture(tester);
    final oldest = tester.state(_page('list-a'));
    await tapDocumentTab(tester, 'list-b');
    await tester.pumpAndSettle();
    final recent = tester.state(_page('list-b'));
    for (var i = 0; i < 2; i++) {
      shell.createTab(panel: ForumPanel.main);
      await tester.pumpAndSettle();
    }
    expect(oldest.mounted, isFalse);
    expect(recent.mounted, isTrue);
    expect(find.byType(MainContent, skipOffstage: false), findsNWidgets(4));
    shell.closeTab('list-b');
    await tester.pumpAndSettle();
    expect(recent.mounted, isFalse);
    expect(tester.takeException(), isNull);
  });

  desktopTest('moving a warmed tab keeps its page in the destination panel', (
    tester,
  ) async {
    final shell = await pumpTabSwitchFixture(tester);
    final page = tester.state(_page('list-a'));
    shell.moveTabToPanel('list-a', ForumPanel.secondary);
    await tester.pumpAndSettle();
    expect(tester.state(_page('list-a')), same(page));
    expect(ForumTabScope.panelOf(page.context), ForumPanel.secondary);
    expect(tester.takeException(), isNull);
  });

  desktopTest('a changed account session releases all retained pages', (
    tester,
  ) async {
    final shell = await pumpTabSwitchFixture(tester);
    final pages = tester.stateList(find.byType(MainContent)).toList();
    shell.lifecycle.invalidate('https://tabs.example');
    shell.selectTab('list-b');
    await tester.pumpAndSettle();
    expect(pages.every((page) => !page.mounted), isTrue);
    expect(tester.takeException(), isNull);
  });
}

Finder _page(String id) => find.byElementPredicate(
  (element) =>
      element.widget is MainContent && ForumTabScope.idOf(element) == id,
);

void desktopTest(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });
