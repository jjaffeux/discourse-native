import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;

/// The phone bar's panel of places inside the shell: what it must leave
/// alone while it moves, and what the shell leaves to it.
void main() {
  final panel = find.byKey(DMobileDock.panelKey);

  testWidgets('the profile tile opens the profile menu and the bell opens '
      'notifications', (tester) async {
    await fixture.pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(DMobileDock.tileKey(const ValueKey('mobile-mode-profile'))),
    );
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(find.byType(UserMenuPanel), findsNothing);
    expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(UserMenuButton.bellKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<UserMenuPanel>(find.byType(UserMenuPanel)).view,
      UserMenuView.notifications,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the profile tile can move into the bar and keeps its position '
    'after remounting',
    (tester) async {
      final shell = await fixture.pumpMobileShellFixture(tester);
      const profileKey = ValueKey('mobile-mode-profile');
      final profile = find.byKey(DMobileDock.tileKey(profileKey));
      final surface = find.byKey(const ValueKey('mobile-dock-surface'));
      List<String> barLabels() => [
        for (final item in tester.widgetList<DMobileDockItem>(
          find.descendant(of: surface, matching: find.byType(DMobileDockItem)),
        ))
          if (item.key != DMobileDock.moreKey) item.label,
      ];
      await tester.tap(find.byKey(DMobileDock.moreKey));
      await tester.pumpAndSettle();
      final destination = tester.getCenter(
        find.byKey(const ValueKey('mobile-mode-topics')),
      );
      final gesture = await tester.startGesture(tester.getCenter(profile));
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byKey(DMobileDock.movingKey(profileKey)), findsOneWidget);
      await gesture.moveTo(destination);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(barLabels(), ['reader', 'Topics', 'Chat']);
      expect(panel, findsOneWidget);
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(shell.mobileNavigation.tab, MobileTab.topics);

      await fixture.pumpMobileShellFixture(tester);
      expect(barLabels(), ['reader', 'Topics', 'Chat']);
      await tester.tap(find.byKey(profileKey));
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byKey(const ValueKey('user-menu-own-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

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

  testWidgets('notifications paused recolours the you tile\'s ring without '
      'rebuilding the shell\'s chrome', (tester) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    final you = find.byKey(
      DMobileDock.tileKey(const ValueKey('mobile-mode-profile')),
    );
    final ringBox = find.descendant(
      of: you,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    Color? ring() =>
        (tester.widget<DecoratedBox>(ringBox).decoration as BoxDecoration)
            .border
            ?.top
            .color;
    final tokens = DTokens.of(tester.element(you));
    expect(ring(), tokens.success);
    // The chrome's builder ran if and only if the frame it builds is a new
    // widget; the dirty set says what was told to rebuild.
    final frame = find.byKey(const ValueKey('mobile-root'));
    final header = find.byKey(const ValueKey('mobile-header'));
    final frameBefore = tester.widget(frame);
    final headerBefore = tester.widget(header);
    final root = tester.element(find.byType(MobileForumRoot));
    final chrome = tester.element(
      find.ancestor(of: frame, matching: find.byType(ListenableBuilder)).first,
    );
    final page = tester.element(find.byType(TopicListView));
    final rebuilt = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    shell.doNotDisturb.acceptSnapshot(
      shell.currentInstance!.url,
      DateTime.now().add(const Duration(hours: 1)),
      isCurrent: true,
    );
    await tester.pump();
    expect(ring(), tokens.subtleMark);
    expect(rebuilt, isNotEmpty);
    expect(rebuilt, isNot(contains(root)));
    expect(rebuilt, isNot(contains(chrome)));
    expect(rebuilt, isNot(contains(page)));
    expect(tester.widget(frame), same(frameBefore));
    expect(tester.widget(header), same(headerBefore));
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

  testWidgets('the back is the shell\'s again once the sidebar has taken the '
      'bar away with the panel out', (tester) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    shell.toggleMobileSidebar();
    await tester.pump();
    expect(panel, findsNothing);
    shell.closeMobileSidebar();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-card-7')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.isTopic, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(shell.currentContent?.isTopic, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings held and dropped on Bookmarks\' slot is the bar\'s '
      'third, the shell left alone, and a remount keeps the order', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(tester);
    final surface = find.byKey(const ValueKey('mobile-dock-surface'));
    List<String> barLabels() => [
      for (final item in tester.widgetList<DMobileDockItem>(
        find.descendant(of: surface, matching: find.byType(DMobileDockItem)),
      ))
        if (item.key != DMobileDock.moreKey) item.label,
    ];
    List<String> panelLabels() => [
      for (final item in tester.widgetList<DMobileDockItem>(
        find.descendant(of: panel, matching: find.byType(DMobileDockItem)),
      ))
        if (item.key !=
            DMobileDock.tileKey(const ValueKey('mobile-mode-profile')))
          item.label,
    ];
    expect(barLabels(), ['Topics', 'Chat', 'Bookmarks']);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
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

    final settings = tester.getCenter(
      find.descendant(
        of: panel,
        matching: find.widgetWithText(DMobileDockItem, 'Interface'),
      ),
    );
    final bookmarks = tester.getCenter(
      find.byKey(const ValueKey('mobile-mode-destination/user-bookmarks')),
    );
    final gesture = await tester.createGesture();
    await gesture.down(settings, timeStamp: Duration.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    final moving = find.byKey(
      DMobileDock.movingKey(
        const ValueKey('mobile-mode-destination/appearance'),
      ),
    );
    expect(moving, findsOneWidget);
    await gesture.moveTo(
      bookmarks,
      timeStamp: const Duration(milliseconds: 340),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    // The lift, the follow and the slot it was brought to left the shell,
    // its chrome and the page alone.
    expect(rebuilt, isNotEmpty);
    expect(rebuilt, isNot(contains(root)));
    expect(rebuilt, isNot(contains(chrome)));
    expect(rebuilt, isNot(contains(page)));
    expect(rebuilt, isNot(contains(header)));
    expect(notifications, 0);
    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    // Let go, the new order shows through the place list alone: the chrome
    // rebuilt with it, the page and the shell did not.
    expect(moving, findsNothing);
    expect(rebuilt, isNot(contains(root)));
    expect(rebuilt, isNot(contains(page)));
    expect(notifications, 0);
    expect(barLabels(), ['Topics', 'Chat', 'Interface']);
    expect(panelLabels().take(3), ['Bookmarks', 'Inbox', 'Users']);
    // The release pressed nothing.
    expect(shell.mobileNavigation.tab, MobileTab.topics);
    expect(panel, findsOneWidget);

    await fixture.pumpMobileShellFixture(tester);
    expect(barLabels(), ['Topics', 'Chat', 'Interface']);
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    expect(panelLabels().take(3), ['Bookmarks', 'Inbox', 'Users']);
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
