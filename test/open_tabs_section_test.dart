import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/open_tabs_section.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = OpenTabItem(
    id: 'topic-1',
    title: 'A long-running topic',
    icon: DIcons.comment,
  );
  const second = OpenTabItem(
    id: 'chat-2',
    title: 'Team chat',
    icon: DIcons.comments,
  );

  testWidgets('shows an always-expanded OPEN header with an add action', (
    tester,
  ) async {
    var addCount = 0;
    await _pumpSection(
      tester,
      items: const [first, second],
      onAdd: () => addCount += 1,
    );

    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('OPEN 2'), findsNothing);
    expect(find.byTooltip('Open a new tab'), findsOneWidget);
    expect(find.byType(DIcon), findsNWidgets(5));

    await tester.tap(find.byKey(const ValueKey('open-tabs-add')));
    expect(addCount, 1);

    expect(
      tester.getSize(find.byKey(const ValueKey('open-tab-row-topic-1'))).height,
      34,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('open-tab-row-chat-2'))).height,
      34,
    );
  });

  testWidgets('selects by stable ID and applies the sidebar active style', (
    tester,
  ) async {
    String? selected;
    await _pumpSection(
      tester,
      items: const [first, second],
      selectedId: first.id,
      onSelect: (id) => selected = id,
    );

    final selectedRow = find.byKey(const ValueKey('open-tab-row-topic-1'));
    final ordinaryRow = find.byKey(const ValueKey('open-tab-row-chat-2'));
    final theme = Theme.of(tester.element(selectedRow));

    expect(_background(tester, selectedRow), theme.shell.selected);
    expect(_background(tester, ordinaryRow), isNull);

    await tester.tap(find.byKey(const ValueKey('open-tab-chat-2')));
    expect(selected, second.id);
  });

  testWidgets('close is a separate, specifically named accessible action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final selected = <String>[];
    final closed = <String>[];
    await _withPlatform(TargetPlatform.macOS, () async {
      await _pumpSection(
        tester,
        items: const [first, second],
        selectedId: first.id,
        onSelect: selected.add,
        onClose: closed.add,
      );

      final close = find.byKey(const ValueKey('open-tab-close-topic-1'));
      final opacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('open-tab-close-opacity-topic-1')),
      );
      final node = tester.getSemantics(close);

      expect(opacity.opacity, 1);
      expect(find.byTooltip('Close A long-running topic'), findsOneWidget);
      expect(node.label, 'Close A long-running topic');
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);

      await tester.tap(close);
      expect(closed, [first.id]);
      expect(selected, isEmpty);
    });
    semantics.dispose();
  });

  testWidgets('desktop reveals idle close actions on row hover', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _pumpSection(
        tester,
        items: const [first, second],
        selectedId: first.id,
      );

      AnimatedOpacity closeOpacity(String id) => tester.widget<AnimatedOpacity>(
        find.byKey(ValueKey('open-tab-close-opacity-$id')),
      );

      expect(closeOpacity(first.id).opacity, 1);
      expect(closeOpacity(second.id).opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('open-tab-row-chat-2'))),
      );
      await tester.pump(const Duration(milliseconds: 121));

      expect(closeOpacity(second.id).opacity, 1);

      await mouse.moveTo(const Offset(500, 500));
      await tester.pump(const Duration(milliseconds: 121));

      expect(closeOpacity(second.id).opacity, 0);
      await mouse.removePointer();
    });
  });

  testWidgets('desktop reveals an idle close action while its row has focus', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      await _pumpSection(
        tester,
        items: const [first, second],
        selectedId: first.id,
      );

      AnimatedOpacity closeOpacity() => tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('open-tab-close-opacity-chat-2')),
      );

      expect(closeOpacity().opacity, 0);

      // Add, first row, and first close precede the second row in traversal.
      for (var index = 0; index < 4; index += 1) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 121));

      expect(closeOpacity().opacity, 1);

      // The close button is the next, distinct focus target.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 121));
      expect(closeOpacity().opacity, 1);
    });
  });

  testWidgets('renders prefixes, unread badges, and ellipsized titles', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const childColor = Color(0xFF0088CC);
    const parentColor = Color(0xFFFF0000);
    const items = [
      OpenTabItem(
        id: 'category-3',
        title: 'A category title too long to fit in this narrow sidebar',
        icon: DIcons.comment,
        color: childColor,
        parentColor: parentColor,
        badge: SidebarBadge.count(3),
      ),
      OpenTabItem(
        id: 'urgent-4',
        title: 'Urgent chat',
        icon: DIcons.comments,
        iconColor: Color(0xFF00AA00),
        badge: SidebarBadge.dot(urgent: true),
      ),
    ];
    await _pumpSection(tester, items: items, width: 190);

    final swatch = tester.widget<Container>(
      find.byKey(const ValueKey('open-tab-prefix-category-3')),
    );
    final gradient = (swatch.decoration! as BoxDecoration).gradient!;
    final longTitle = tester.widget<Text>(find.text(items.first.title));
    final urgentDot = tester.widget<Container>(
      find.byKey(const ValueKey('open-tab-badge-urgent-4')),
    );
    final theme = Theme.of(
      tester.element(find.byKey(const ValueKey('open-tab-row-urgent-4'))),
    );

    expect((gradient as LinearGradient).colors, [parentColor, childColor]);
    expect(longTitle.maxLines, 1);
    expect(longTitle.overflow, TextOverflow.ellipsis);
    expect(find.text('3'), findsOneWidget);
    expect(
      (urgentDot.decoration! as BoxDecoration).color,
      theme.colorScheme.error,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('open-tab-category-3')))
          .label,
      '${items.first.title}, 3 unread items',
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('open-tab-urgent-4')))
          .label,
      'Urgent chat, urgent unread activity',
    );
    semantics.dispose();
  });
}

Color? _background(WidgetTester tester, Finder row) =>
    (tester.widget<Container>(row).decoration! as BoxDecoration).color;

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<OpenTabItem> items,
  String? selectedId,
  VoidCallback? onAdd,
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onClose,
  double width = 240,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: OpenTabsSection(
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
  await tester.pump();
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
