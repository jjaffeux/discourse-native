import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() => optionListVirtualizationTests();

void optionListVirtualizationTests() {
  testWidgets('long select reveals and selects a far keyboard target', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      _app(_select(onChanged: (value) => selected = value), scale: 2),
    );
    await tester.tap(find.byKey(const Key('d-select-trigger-visual')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    _expectSelectFocused(tester, 199);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    _expectSelectFocused(tester, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 199);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long select initially reveals the selected far item', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_select(initialValue: 190), scale: 2));
    await tester.tap(find.byKey(const Key('d-select-trigger-visual')));
    await tester.pumpAndSettle();
    _expectSelectFocused(tester, 190);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    _expectSelectFocused(tester, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'O');
    await tester.pumpAndSettle();
    _expectSelectFocused(tester, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long select keeps logical focus when same-count options reorder',
    (tester) async {
      late StateSetter update;
      var reversed = false;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DSelect<int>(
                entries: [
                  for (final value
                      in reversed
                          ? List.generate(200, (index) => 199 - index)
                          : List.generate(200, (index) => index))
                    DSelectItem(
                      value: value,
                      textValue: 'Option $value',
                      child: Text('Option $value', key: ValueKey<int>(value)),
                    ),
                ],
                onChanged: (_) {},
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('d-select-trigger-visual')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      _expectSelectFocused(tester, 199);
      update(() => reversed = true);
      await tester.pumpAndSettle();
      _expectSelectFocused(tester, 199);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      _expectSelectFocused(tester, 198);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long select preserves group semantics and skips distant groups',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _app(
            DSelect<int>(
              entries: [
                for (var index = 0; index < 200; index++)
                  DSelectGroup(
                    label: Text('Group $index'),
                    children: [
                      DSelectItem(
                        value: index,
                        textValue: 'Option $index',
                        description: 'Description',
                        child: Text('Option $index', key: ValueKey<int>(index)),
                      ),
                    ],
                  ),
              ],
              onChanged: (_) {},
            ),
            scale: 2,
          ),
        );
        await tester.tap(find.byKey(const Key('d-select-trigger-visual')));
        await tester.pumpAndSettle();
        expect(
          find
              .byWidgetPredicate(
                (widget) => widget.key is ValueKey<int>,
                skipOffstage: false,
              )
              .evaluate()
              .length,
          lessThan(20),
        );
        final group = tester.getSemantics(find.byType(SliverSemantics).first);
        expect(
          group
              .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
              .any((node) => node.label == 'Group 0'),
          isTrue,
        );
        expect(_semanticsContains(group, 'Option 0, Description'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        _expectSelectFocused(tester, 199);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('long grouped select mounts bounded options at ${scale}x', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_select(), scale: scale));
      await tester.tap(find.byKey(const Key('d-select-trigger-visual')));
      await tester.pumpAndSettle();
      final mounted = find
          .byWidgetPredicate(
            (widget) => widget.key is ValueKey<int>,
            skipOffstage: false,
          )
          .evaluate()
          .length;
      debugPrint(
        jsonEncode({'component': 'select', 'scale': scale, 'mounted': mounted}),
      );
      expect(mounted, lessThan(40));
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.iOS),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: Center(child: SizedBox(width: 320, child: child)),
    ),
  ),
);

DSelect<int> _select({int? initialValue, ValueChanged<int?>? onChanged}) =>
    DSelect<int>(
      initialValue: initialValue,
      onChanged: onChanged,
      entries: [
        DSelectGroup(
          label: const Text('A large group'),
          children: [
            for (var index = 0; index < 200; index++)
              DSelectItem(
                value: index,
                textValue: 'Option $index',
                child: Text('Option $index', key: ValueKey<int>(index)),
              ),
          ],
        ),
      ],
    );

void _expectSelectFocused(WidgetTester tester, int value) {
  final row = find.byKey(ValueKey<int>(value));
  expect(row, findsOneWidget);
  expect(Focus.of(tester.element(row)).hasPrimaryFocus, isTrue);
  expect(
    tester.getRect(find.byType(DPopoverContent)).overlaps(tester.getRect(row)),
    isTrue,
  );
}

bool _semanticsContains(SemanticsNode node, String label) =>
    node.label == label ||
    node
        .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
        .any((child) => _semanticsContains(child, label));
