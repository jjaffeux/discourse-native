import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

/// The phone bar's panel of places inside the shell: what it must leave
/// alone while it moves, and what the shell leaves to it.
void main() {
  final panel = find.byKey(DMobileDock.panelKey);

  testWidgets('a drag on the bar rebuilds neither the shell nor the page', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    final root = tester.element(find.byType(MobileForumRoot));
    final chrome = tester.element(
      find
          .descendant(
            of: find.byType(MobileForumRoot),
            matching: find.byType(ListenableBuilder),
          )
          .first,
    );
    final page = tester.element(find.byType(TopicListView));
    final header = tester.element(find.byKey(const ValueKey('mobile-header')));
    var notifications = 0;
    void count() => notifications++;
    shell.addListener(count);
    addTearDown(() => shell.removeListener(count));
    final rebuilt = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    final topics = tester.getCenter(
      find.byKey(const ValueKey('mobile-mode-topics')),
    );
    final gesture = await tester.createGesture();
    await gesture.down(topics, timeStamp: Duration.zero);
    for (var step = 1; step <= 6; step++) {
      await gesture.moveBy(
        const Offset(0, -12),
        timeStamp: Duration(milliseconds: 16 * step),
      );
      await tester.pump();
    }
    expect(panel, findsOneWidget);
    expect(rebuilt, isNotEmpty);
    expect(rebuilt, isNot(contains(root)));
    expect(rebuilt, isNot(contains(chrome)));
    expect(rebuilt, isNot(contains(page)));
    expect(rebuilt, isNot(contains(header)));
    expect(notifications, 0);
    await gesture.up(timeStamp: const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(rebuilt, isNot(contains(root)));
    expect(rebuilt, isNot(contains(chrome)));
    expect(rebuilt, isNot(contains(page)));
    expect(notifications, 0);
    // The drag pressed nothing: Topics was under the finger and is still
    // the place, not a place gone to.
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the system back closes the panel and goes nowhere else', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.isTopic, isTrue);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(shell.currentContent?.isTopic, isTrue);
    // Closed, the back is the shell's again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.isTopic, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('while the panel is out nothing under it scrolls, and the bar '
      'does not fold', (tester) async {
    await fixture.pumpMobileShellFixture(
      tester,
      topics: [
        for (var id = 7; id < 40; id++)
          Topic(id: id, title: 'Discussion $id', slug: 'discussion-$id'),
      ],
    );
    final surface = find.byKey(const ValueKey('mobile-dock-surface'));
    final rest = tester.getRect(surface);
    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(TopicListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final offset = list.position.pixels;
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    // A scroll over the page meets the dim: the press closes the panel and
    // the page never moves.
    await tester.drag(
      find.byKey(const ValueKey('mobile-header')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(list.position.pixels, offset);
    expect(tester.getRect(surface), rest);
    // Closed, the same scroll moves the page and folds the bar.
    await tester.drag(find.byType(TopicListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(list.position.pixels, greaterThan(offset));
    expect(tester.getSize(surface).width, lessThan(rest.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel is put away with the bar, by the sidebar or a '
      'composer', (tester) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    shell.toggleMobileSidebar();
    await tester.pump();
    expect(panel, findsNothing);
    shell.closeMobileSidebar();
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(
      tester.widget<DMobileDockItem>(find.byKey(DMobileDock.moreKey)).expanded,
      isFalse,
    );
    // The action in the panel's head does what it does, and the composer it
    // opens puts the bar, and the panel with it, away the frame it arrives.
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-new-topic')));
    final composer = find.byKey(const ValueKey('composer-topic-title'));
    for (var frame = 0; composer.evaluate().isEmpty && frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(composer, findsOneWidget);
    expect(panel, findsNothing);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place in the panel\'s head closes it and goes there', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(shell.mobileNavigation.tab, const MobileTab.panel('chat'));
    expect(tester.takeException(), isNull);
  });
}
