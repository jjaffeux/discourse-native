import 'dart:ui' show SemanticsRole, Tristate;

import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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

  testWidgets('matches the shared shell header geometry and keeps add fixed', (
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
    expect(tester.getSize(add), const Size(34, 30));
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
    expect(addRect.right, 495);
    expect(
      addRect.center.dy,
      barRect.top + 4 + (shellHeaderHeight - 4 - bottomDivider.width) / 2,
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

    final selectionGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('forum-tab-chat-2'))),
    );
    // Native desktop tabs activate on pointer-down rather than waiting for the
    // complete click gesture.
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
      width: 220,
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
    expect(_decoration(tester, urgentDot).color, theme.colorScheme.error);

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

  testWidgets('scrolls overflowing tabs while add stays fixed', (tester) async {
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
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(scrollable.position.pixels, 0);
    expect(find.byKey(const ValueKey('forum-tab-badge-tab-3')), findsNothing);
    for (final item in items) {
      expect(find.byKey(ValueKey('forum-tab-${item.id}')), findsOneWidget);
    }

    await tester.drag(
      find.byKey(const ValueKey('forum-tabs-scroll')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getRect(add), initialAddRect);

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
    expect(tester.getRect(add), initialAddRect);
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
}

BoxDecoration _decoration(WidgetTester tester, Finder finder) =>
    tester.widget<Container>(finder).decoration! as BoxDecoration;

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
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onClose,
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
            child: ForumTabsBar(
              forumName: 'Discourse Meta',
              items: items,
              selectedId: selectedId,
              onAdd: onAdd ?? () {},
              onSelect: onSelect ?? (_) {},
              onClose: onClose ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
