import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets(
    'long variable-height combobox reveals and selects the last option',
    (tester) async {
      int? selected;
      var builds = 0;
      await tester.pumpWidget(
        _app(
          DCombobox<int>(
            options: _options(),
            onChanged: (value, _) => selected = value,
            anchor: const DComboboxInput<int>(),
            content: DComboboxContent(
              children: [
                DComboboxList<int>(
                  itemBuilder: (context, option) {
                    builds++;
                    return SizedBox(
                      height: 40.0 + option.value % 3 * 40,
                      child: Text(option.label),
                    );
                  },
                ),
              ],
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      _expectComboboxVisible(tester, 199);
      expect(builds, lessThan(100));
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 199);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long combobox reveals the accepted controlled highlight', (
    tester,
  ) async {
    late StateSetter update;
    int? highlighted;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return DCombobox<int>(
              options: _options(),
              highlightControlled: true,
              highlightedValue: highlighted,
              anchor: const DComboboxInput<int>(),
              content: const DComboboxContent(children: [DComboboxList<int>()]),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('option-199')), findsNothing);
    update(() => highlighted = 190);
    await tester.pumpAndSettle();
    _expectComboboxVisible(tester, 190);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long inline grouped combobox reveals custom-equal initial selection',
    (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            height: 400,
            child: DCombobox<_Person>.controlled(
              value: const _Person(190),
              onChanged: (_, _) {},
              options: const [],
              equals: (left, right) => left.id == right.id,
              groups: [
                DComboboxOptionGroup(
                  label: 'People',
                  options: [
                    for (var index = 0; index < 200; index++)
                      DComboboxOption(
                        value: _Person(index),
                        label: 'Person $index',
                        itemKey: ValueKey('person-$index'),
                      ),
                  ],
                ),
              ],
              anchor: const DComboboxInput<_Person>(),
              content: const DComboboxContent.inline(
                children: [DComboboxList<_Person>()],
              ),
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('person-190'));
      expect(row, findsOneWidget);
      final scrollable = find
          .ancestor(of: row, matching: find.byType(Scrollable))
          .first;
      expect(tester.getRect(scrollable).overlaps(tester.getRect(row)), isTrue);
      expect(
        find
            .byType(DComboboxItem<_Person>, skipOffstage: false)
            .evaluate()
            .length,
        lessThan(40),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filtering cancels a pending long combobox reveal', (
    tester,
  ) async {
    final controller = DComboboxController<int>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        DCombobox<int>(
          controller: controller,
          options: _options(),
          anchor: const DComboboxInput<int>(),
          content: const DComboboxContent(children: [DComboboxList<int>()]),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    controller.highlight(199);
    await tester.enterText(find.byType(TextField), 'Option 0');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('option-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('option-199')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('many combobox groups stay lazy and reveal a far group', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final controller = DComboboxController<int>();
      final options = _options();
      await tester.pumpWidget(
        _app(
          DCombobox<int>(
            controller: controller,
            options: const [],
            groups: [
              for (var index = 0; index < 200; index++)
                DComboboxOptionGroup(
                  label: 'Group $index',
                  options: [options[index]],
                ),
            ],
            anchor: const DComboboxInput<int>(),
            content: const DComboboxContent(children: [DComboboxList<int>()]),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(
        find.byType(DComboboxItem<int>, skipOffstage: false).evaluate().length,
        lessThan(40),
      );
      final group = tester.getSemantics(find.byType(SliverSemantics).first);
      expect(group.label, 'Group 0');
      expect(_semanticsContains(group, 'Option 0\nOption 0'), isTrue);
      controller.highlight(199);
      await tester.pumpAndSettle();
      _expectComboboxVisible(tester, 199);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    } finally {
      semantics.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long combobox reveals fresh custom-equal options after reorder',
    (tester) async {
      late StateSetter update;
      var reversed = false;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DCombobox<_Person>(
                equals: (left, right) => left.id == right.id,
                highlightControlled: true,
                highlightedValue: const _Person(190),
                options: [
                  for (var index = 0; index < 200; index++)
                    DComboboxOption(
                      value: _Person(reversed ? 199 - index : index),
                      label: 'Person ${reversed ? 199 - index : index}',
                      itemKey: ValueKey(
                        'person-${reversed ? 199 - index : index}',
                      ),
                    ),
                ],
                anchor: const DComboboxInput<_Person>(),
                content: const DComboboxContent(
                  children: [DComboboxList<_Person>()],
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('person-190')), findsOneWidget);
      update(() => reversed = true);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('person-190'));
      expect(row, findsOneWidget);
      expect(
        tester
            .getRect(find.byType(DPopoverContent))
            .overlaps(tester.getRect(row)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pointer highlight in a long inline combobox leaves scroll positions unchanged',
    (tester) async {
      final page = ScrollController(initialScrollOffset: 200);
      addTearDown(page.dispose);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            controller: page,
            child: Column(
              children: [
                const SizedBox(height: 300),
                SizedBox(
                  height: 300,
                  child: DCombobox<int>(
                    options: _options(),
                    anchor: const DComboboxInput<int>(),
                    content: const DComboboxContent.inline(
                      children: [DComboboxList<int>()],
                    ),
                  ),
                ),
                const SizedBox(height: 700),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('option-0'));
      final list = tester
          .state<ScrollableState>(
            find.ancestor(of: row, matching: find.byType(Scrollable)).first,
          )
          .position;
      final pageOffset = page.offset;
      final listOffset = list.pixels;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(row));
      await tester.pumpAndSettle();
      expect(page.offset, pageOffset);
      expect(list.pixels, listOffset);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long multiple select preserves custom equality and borrowed scrolling',
    (tester) async {
      var values = [const _Person(190)];
      final scroll = ScrollController();
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => DMultiSelect<_Person>.controlled(
              value: values,
              onChanged: (next) => setState(() => values = next),
              isItemEqualToValue: (left, right) => left?.id == right?.id,
              scrollController: scroll,
              entries: [
                const DSelectSeparator<_Person>(),
                DSelectGroup<_Person>(
                  label: const Text('People'),
                  children: [
                    for (var index = 0; index < 200; index++)
                      DSelectItem<_Person>(
                        value: _Person(index),
                        textValue: 'Person $index',
                        description: 'Details',
                        child: Text('Person $index', key: ValueKey<int>(index)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.byKey(const Key('d-select-trigger-visual')));
      await tester.pumpAndSettle();
      _expectSelectFocused(tester, 190);
      expect(scroll.hasClients, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(values.map((person) => person.id), [190, 199]);
      _expectSelectFocused(tester, 199);
      await tester.pumpWidget(const SizedBox());
      expect(() => scroll.dispose(), returnsNormally);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long select keeps selected-trigger alignment with desktop arrows',
    (tester) async {
      await tester.pumpWidget(
        _app(_select(initialValue: 100), platform: TargetPlatform.macOS),
      );
      final trigger = tester.getRect(
        find.byKey(const Key('d-select-trigger-visual')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      _expectSelectFocused(tester, 100);
      expect(
        (tester.getCenter(find.byKey(const ValueKey<int>(100))).dy -
                trigger.center.dy)
            .abs(),
        lessThanOrEqualTo(4),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filtered custom-equal groups retain their membership and lazy rendering',
    (tester) async {
      await tester.pumpWidget(
        _app(
          DCombobox<_Person>(
            options: const [],
            query: 'Person 0',
            equals: (left, right) => left.id == right.id,
            groups: [
              for (var index = 0; index < 200; index++)
                DComboboxOptionGroup(
                  label: 'Group $index',
                  options: [
                    DComboboxOption(
                      value: const _Person(0),
                      label: 'Person $index',
                      itemKey: ValueKey('filtered-$index'),
                    ),
                  ],
                ),
            ],
            anchor: const DComboboxInput<_Person>(),
            content: const DComboboxContent(
              children: [DComboboxList<_Person>()],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final mounted = find
          .byType(DComboboxItem<_Person>, skipOffstage: false)
          .evaluate()
          .length;
      expect(mounted, greaterThan(1));
      expect(mounted, lessThan(40));
      expect(tester.takeException(), isNull);
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
    testWidgets('long combobox builds bounded options at ${scale}x', (
      tester,
    ) async {
      var builds = 0;
      await tester.pumpWidget(
        _app(
          _combobox(
            itemBuilder: (context, option) {
              builds++;
              return Text(option.label);
            },
          ),
          scale: scale,
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final mounted = find
          .byType(DComboboxItem<int>, skipOffstage: false)
          .evaluate()
          .length;
      debugPrint(
        jsonEncode({
          'component': 'combobox',
          'scale': scale,
          'mounted': mounted,
          'builds': builds,
        }),
      );
      expect(mounted, lessThan(40));
      expect(builds, lessThan(100));
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app(
  Widget child, {
  double scale = 1,
  TargetPlatform platform = TargetPlatform.iOS,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
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

DCombobox<int> _combobox({DComboboxItemBuilder<int>? itemBuilder}) =>
    DCombobox<int>(
      options: [
        for (var index = 0; index < 200; index++)
          DComboboxOption(value: index, label: 'Option $index'),
      ],
      anchor: const DComboboxInput<int>(),
      content: DComboboxContent(
        children: [DComboboxList<int>(itemBuilder: itemBuilder)],
      ),
    );

List<DComboboxOption<int>> _options() => [
  for (var index = 0; index < 200; index++)
    DComboboxOption(
      value: index,
      label: 'Option $index',
      itemKey: ValueKey('option-$index'),
    ),
];

void _expectComboboxVisible(WidgetTester tester, int value) {
  final row = find.byKey(ValueKey('option-$value'));
  expect(row, findsOneWidget);
  expect(
    tester.getRect(find.byType(DPopoverContent)).overlaps(tester.getRect(row)),
    isTrue,
  );
}

class _Person {
  const _Person(this.id);
  final int id;
}
