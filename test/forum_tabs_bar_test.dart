import 'dart:ui'
    show PointerDeviceKind, SemanticsAction, SemanticsRole, Tristate;

import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = ForumTabItem(
    id: 'topic-1',
    title: 'A long-running topic',
    icon: DIcons.comment,
  );
  const second = ForumTabItem(
    id: 'chat-2',
    title: 'Team chat',
    icon: DIcons.comments,
  );

  testWidgets('matches shell geometry and places add after the final tab', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      items: const [first, second],
      selectedId: first.id,
      width: 500,
    );

    const barKey = ValueKey('forum-tabs-bar');
    const addKey = ValueKey('forum-tabs-add');
    final bar = find.byKey(barKey);
    final add = find.byKey(addKey);
    final selected = find.byKey(const ValueKey('forum-tab-item-topic-1'));
    final ordinary = find.byKey(const ValueKey('forum-tab-item-chat-2'));
    final indicator = find.byKey(const ValueKey('forum-tab-indicator-topic-1'));
    final theme = Theme.of(tester.element(bar));

    expect(ForumTabsBar.height, shellHeaderHeight);
    expect(tester.getSize(bar).height, shellHeaderHeight);
    expect(tester.getSize(bar).width, 500);
    expect(
      tester.getSize(add),
      const Size.square(ForumTabsBar.minimumActionTarget),
    );
    expect(tester.getSize(selected).width, 205);
    expect(tester.getSize(ordinary).width, 205);

    final barDecoration = _decoration(tester, bar);
    expect(barDecoration.color, theme.shell.sidebar);
    final bottomDivider = (barDecoration.border! as Border).bottom;
    expect(bottomDivider.color, theme.shell.divider);
    expect(bottomDivider.width, 1);

    final barRect = tester.getRect(bar);
    final selectedRect = tester.getRect(selected);
    final ordinaryRect = tester.getRect(ordinary);
    expect(selectedRect.left, barRect.left);
    expect(selectedRect.top, barRect.top + 4);
    expect(selectedRect.bottom, barRect.bottom - bottomDivider.width);
    expect(ordinaryRect.top, selectedRect.top);
    expect(ordinaryRect.bottom, selectedRect.bottom);

    expect(_decoration(tester, selected).color, theme.shell.content);
    expect(_decoration(tester, ordinary).color, Colors.transparent);
    expect(tester.getSize(indicator).height, 2);
    expect(_decoration(tester, indicator).color, theme.colorScheme.primary);
    expect(
      tester.getRect(indicator),
      Rect.fromLTRB(
        tester.getRect(selected).left + 9,
        tester.getRect(selected).bottom - 2,
        tester.getRect(selected).right - 9,
        tester.getRect(selected).bottom,
      ),
    );

    final addRect = tester.getRect(add);
    expect(addRect.left, ordinaryRect.right + 4);
    expect(
      addRect.center.dy,
      barRect.top + 4 + (shellHeaderHeight - 4 - bottomDivider.width) / 2,
    );

    final close = find.byKey(const ValueKey('forum-tab-close-topic-1'));
    expect(
      tester.getSize(close).width,
      greaterThanOrEqualTo(ForumTabsBar.minimumActionTarget),
    );
    expect(
      tester.getSize(close).height,
      greaterThanOrEqualTo(ForumTabsBar.minimumActionTarget),
    );
  });

  testWidgets('delegates add, selection, and separate close actions by ID', (
    tester,
  ) async {
    var addCount = 0;
    final selected = <String>[];
    final closed = <String>[];
    await _pumpBar(
      tester,
      items: const [first, second],
      selectedId: first.id,
      onAdd: () => addCount += 1,
      onSelect: selected.add,
      onClose: closed.add,
    );

    final secondTabRect = tester.getRect(
      find.byKey(const ValueKey('forum-tab-chat-2')),
    );
    final selectionGesture = await tester.startGesture(
      Offset(secondTabRect.left + 20, secondTabRect.top + 1),
    );
    // Native desktop tabs activate on pointer-down rather than waiting for the
    // complete click gesture, and the full tab height is selectable.
    expect(selected, [second.id]);
    expect(closed, isEmpty);
    await selectionGesture.up();
    expect(selected, [second.id]);

    await tester.tap(find.byKey(const ValueKey('forum-tab-close-topic-1')));
    expect(closed, [first.id]);
    expect(selected, [second.id]);

    await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
    expect(addCount, 1);
    expect(find.byTooltip('Open a new tab'), findsOneWidget);
    expect(find.byTooltip('Close A long-running topic'), findsOneWidget);
  });

  testWidgets('delegates horizontal drag and drop reordering by ID', (
    tester,
  ) async {
    final reordered = <({String id, int newIndex})>[];
    await _pumpBar(
      tester,
      items: const [first, second],
      selectedId: first.id,
      onReorder: (id, newIndex) => reordered.add((id: id, newIndex: newIndex)),
    );

    final firstTab = find.byKey(const ValueKey('forum-tab-item-topic-1'));
    final secondTab = find.byKey(const ValueKey('forum-tab-item-chat-2'));
    final drag = await tester.startGesture(tester.getCenter(firstTab));
    await drag.moveTo(tester.getCenter(secondTab));
    await tester.pump();

    final targetDecoration = _decoration(tester, secondTab);
    expect(targetDecoration.border, isNotNull);

    await drag.up();
    await tester.pumpAndSettle();

    expect(reordered, [(id: first.id, newIndex: 1)]);
  });

  testWidgets('shows the click cursor across each tab', (tester) async {
    await _pumpBar(tester, items: const [first, second], selectedId: first.id);

    for (final item in const [first, second]) {
      final hoverRegion = find.byKey(ValueKey('forum-tab-pointer-${item.id}'));

      expect(hoverRegion, findsOneWidget);
      expect(
        tester.widget<MouseRegion>(hoverRegion).cursor,
        SystemMouseCursors.click,
      );
    }
  });

  testWidgets('keeps the close hover surface compact inside its hit target', (
    tester,
  ) async {
    await _pumpBar(tester, items: const [first], selectedId: first.id);

    const closeKey = ValueKey('forum-tab-close-topic-1');
    const surfaceKey = ValueKey('forum-tab-close-surface-topic-1');
    final close = find.byKey(closeKey);
    final surface = find.byKey(surfaceKey);
    final theme = Theme.of(tester.element(close));

    expect(tester.getSize(close).width, ForumTabsBar.minimumActionTarget);
    expect(
      tester.getSize(close).height,
      greaterThanOrEqualTo(ForumTabsBar.minimumActionTarget),
    );
    expect(tester.getSize(surface), const Size.square(26));
    expect(_decoration(tester, surface).color, Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer();
    await pointer.moveTo(tester.getCenter(close));
    await tester.pumpAndSettle();

    expect(_decoration(tester, surface).color, theme.shell.selected);
    expect(tester.getSize(surface), const Size.square(26));
  });

  testWidgets('keeps the add hover surface compact and clear of the last tab', (
    tester,
  ) async {
    await _pumpBar(tester, items: const [first], selectedId: first.id);

    const addKey = ValueKey('forum-tabs-add');
    const surfaceKey = ValueKey('forum-tabs-add-surface');
    final tab = find.byKey(const ValueKey('forum-tab-item-topic-1'));
    final add = find.byKey(addKey);
    final surface = find.byKey(surfaceKey);
    final theme = Theme.of(tester.element(add));

    expect(
      tester.getSize(add),
      const Size.square(ForumTabsBar.minimumActionTarget),
    );
    expect(tester.getSize(surface), const Size.square(32));
    expect(tester.getRect(add).left, tester.getRect(tab).right + 4);
    expect(tester.getRect(surface).left, tester.getRect(tab).right + 10);
    expect(_decoration(tester, surface).color, Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer();
    await pointer.moveTo(tester.getCenter(add));
    await tester.pumpAndSettle();

    expect(_decoration(tester, surface).color, theme.shell.hover);
    expect(tester.getSize(surface), const Size.square(32));
  });

  testWidgets('renders prefixes, unread badges, and ellipsized labels', (
    tester,
  ) async {
    const childColor = Color(0xFF0088CC);
    const parentColor = Color(0xFFFF0000);
    const iconColor = Color(0xFF00AA00);
    const items = [
      ForumTabItem(
        id: 'category-3',
        title: 'A category title too long to fit in this narrow tab',
        icon: DIcons.comment,
        color: childColor,
        parentColor: parentColor,
        badge: SidebarBadge.count(3),
      ),
      ForumTabItem(
        id: 'urgent-4',
        title: 'Urgent chat',
        icon: DIcons.comments,
        iconColor: iconColor,
        badge: SidebarBadge.dot(urgent: true),
      ),
    ];
    await _pumpBar(
      tester,
      items: items,
      selectedId: items.first.id,
      width: 280,
    );

    final swatch = tester.widget<Container>(
      find.byKey(const ValueKey('forum-tab-prefix-category-3')),
    );
    final gradient = (swatch.decoration! as BoxDecoration).gradient!;
    final longTitle = tester.widget<Text>(find.text(items.first.title));
    final countBadge = find.byKey(const ValueKey('forum-tab-badge-category-3'));
    final urgentDot = find.byKey(const ValueKey('forum-tab-badge-urgent-4'));
    final theme = Theme.of(tester.element(urgentDot));

    expect((gradient as LinearGradient).colors, [parentColor, childColor]);
    expect(longTitle.maxLines, 1);
    expect(longTitle.overflow, TextOverflow.ellipsis);
    expect(find.text('3'), findsOneWidget);
    expect(tester.getSize(countBadge).height, 18);
    expect(tester.getSize(urgentDot), const Size(8, 8));
    expect(_decoration(tester, urgentDot).color, theme.discourse.success);

    final urgentIcon = tester.widget<DIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('forum-tab-item-urgent-4')),
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.comments,
        ),
      ),
    );
    expect(urgentIcon.color, iconColor);
    expect(urgentIcon.size, 15);
  });

  testWidgets('does not render an OPEN label or opened-tab totals', (
    tester,
  ) async {
    final items = [
      for (var index = 0; index < 5; index++)
        ForumTabItem(
          id: 'tab-$index',
          title: 'Tab $index',
          icon: DIcons.comment,
        ),
    ];
    await _pumpBar(tester, items: items, selectedId: items.first.id);

    expect(find.text('OPEN'), findsNothing);
    expect(find.text('5 open'), findsNothing);
    expect(find.text('5'), findsNothing);
    expect(find.text('+5'), findsNothing);
    expect(find.text('+2'), findsNothing);
    expect(find.byKey(const ValueKey('forum-tabs-add')), findsOneWidget);
  });

  testWidgets('scrolls overflowing tabs with add after the final tab', (
    tester,
  ) async {
    final items = [
      for (var index = 0; index < 8; index++)
        ForumTabItem(
          id: 'tab-$index',
          title: 'Forum tab $index',
          icon: DIcons.comment,
          badge: index == 3 ? const SidebarBadge.count(999) : SidebarBadge.none,
        ),
    ];
    await _pumpBar(
      tester,
      items: items,
      selectedId: items.first.id,
      width: 320,
    );

    final scrollable = _scrollable(tester);
    final add = find.byKey(const ValueKey('forum-tabs-add'));
    final initialAddRect = tester.getRect(add);
    final initialLastTabRect = tester.getRect(
      find.byKey(ValueKey('forum-tab-item-${items.last.id}')),
    );
    final initialViewportRect = tester.getRect(
      find.byKey(const ValueKey('forum-tabs-scroll')),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(scrollable.position.pixels, 0);
    expect(initialAddRect.left, initialLastTabRect.right + 4);
    expect(initialAddRect.left, greaterThan(initialViewportRect.right));
    expect(find.byKey(const ValueKey('forum-tab-badge-tab-3')), findsNothing);
    for (final item in items) {
      expect(find.byKey(ValueKey('forum-tab-${item.id}')), findsOneWidget);
    }

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('forum-tabs-scroll')),
        ),
        scrollDelta: const Offset(180, 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getRect(add).left, lessThan(initialAddRect.left));
    expect(
      tester.getRect(add).left,
      tester
              .getRect(find.byKey(ValueKey('forum-tab-item-${items.last.id}')))
              .right +
          4,
    );

    await _pumpBar(tester, items: items, selectedId: items.last.id, width: 320);
    await tester.pumpAndSettle();

    expect(_scrollable(tester).position.pixels, greaterThan(0));
    final lastTabRect = tester.getRect(
      find.byKey(ValueKey('forum-tab-item-${items.last.id}')),
    );
    final viewportRect = tester.getRect(
      find.byKey(const ValueKey('forum-tabs-scroll')),
    );
    expect(lastTabRect.left, greaterThanOrEqualTo(viewportRect.left));
    expect(lastTabRect.right, lessThanOrEqualTo(viewportRect.right));
    expect(tester.getRect(add).left, lastTabRect.right + 4);
    expect(tester.getRect(add).right, lessThanOrEqualTo(viewportRect.right));
  });

  testWidgets('exposes a named tab bar, selected tabs, and close actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const items = [
      ForumTabItem(
        id: 'topic-1',
        title: 'A long-running topic',
        icon: DIcons.comment,
        badge: SidebarBadge.count(3),
      ),
      ForumTabItem(
        id: 'chat-2',
        title: 'Team chat',
        icon: DIcons.comments,
        badge: SidebarBadge.dot(urgent: true),
      ),
    ];
    await _pumpBar(tester, items: items, selectedId: items.first.id);

    final tabBar = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.role == SemanticsRole.tabBar,
    );
    final selectedNode = tester.getSemantics(
      find.byKey(const ValueKey('forum-tab-topic-1')),
    );
    final ordinaryNode = tester.getSemantics(
      find.byKey(const ValueKey('forum-tab-chat-2')),
    );
    final closeNode = tester.getSemantics(
      find.byKey(const ValueKey('forum-tab-close-topic-1')),
    );

    expect(tabBar, findsOneWidget);
    expect(tester.getSemantics(tabBar).label, 'Open tabs in Discourse Meta');
    expect(selectedNode.getSemanticsData().role, SemanticsRole.tab);
    expect(selectedNode.label, 'A long-running topic, 3 unread items');
    expect(
      selectedNode.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(ordinaryNode.getSemanticsData().role, SemanticsRole.tab);
    expect(ordinaryNode.label, 'Team chat, urgent unread activity');
    expect(
      ordinaryNode.getSemanticsData().flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(closeNode.label, 'Close A long-running topic');
    expect(closeNode.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('forum-tabs-add'))).label,
      'Open a new tab',
    );

    semantics.dispose();
  });

  testWidgets('announces and disables add at tab capacity', (tester) async {
    final semantics = tester.ensureSemantics();

    await _pumpBar(
      tester,
      items: const [
        ForumTabItem(id: 'one', title: 'One', icon: DIcons.comments),
      ],
      selectedId: 'one',
      addEnabled: false,
    );

    final target = find.byKey(const ValueKey('forum-tabs-add'));
    final data = tester.getSemantics(target).getSemanticsData();
    expect(data.label, 'Close a tab before opening another');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });
}

/// The painted decoration, whichever box is carrying it.
///
/// A box that only decorates is a `DecoratedBox`; one that also pads or sizes
/// is a `Container`. Which of the two a given piece of chrome needs is a
/// layout decision, not something a test about colour should have to track.
BoxDecoration _decoration(WidgetTester tester, Finder finder) => switch (tester
    .widget(finder)) {
  final Container box => box.decoration! as BoxDecoration,
  final AnimatedContainer box => box.decoration! as BoxDecoration,
  final DecoratedBox box => box.decoration as BoxDecoration,
  final widget => throw StateError('${widget.runtimeType} decorates nothing'),
};

ScrollableState _scrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('forum-tabs-scroll')),
        matching: find.byType(Scrollable),
      ),
    );

Future<void> _pumpBar(
  WidgetTester tester, {
  required List<ForumTabItem> items,
  required String selectedId,
  VoidCallback? onAdd,
  bool addEnabled = true,
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onClose,
  void Function(String id, int newIndex)? onReorder,
  double width = 500,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                ForumTabsBar(
                  forumName: 'Discourse Meta',
                  items: items,
                  selectedId: selectedId,
                  onAdd: addEnabled ? (onAdd ?? () {}) : null,
                  onSelect: onSelect ?? (_) {},
                  onClose: onClose ?? (_) {},
                  onReorder: onReorder ?? (_, _) {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
