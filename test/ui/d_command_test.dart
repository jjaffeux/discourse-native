import 'dart:ui' show CheckedState, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(child: SizedBox(width: 384, child: child)),
        ),
      ),
    );

class _MutableCommandValue {
  _MutableCommandValue(this.label);

  String label;

  @override
  String toString() => label;
}

Widget _command({
  DCommandController<String>? controller,
  String? query,
  String? value,
  ValueChanged<String>? onQueryChanged,
  ValueChanged<String?>? onValueChanged,
  ValueChanged<String>? onSelected,
  bool shouldFilter = true,
  bool loop = false,
  bool loading = false,
  TextEditingController? editingController,
  FocusNode? inputFocus,
  VoidCallback? onEmptyBackspace,
}) => DCommand<String>(
  controller: controller,
  query: query,
  value: value,
  onQueryChanged: onQueryChanged,
  onValueChanged: onValueChanged,
  onSelected: onSelected,

  shouldFilter: shouldFilter,
  loop: loop,
  loading: loading,

  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DCommandInput<String>(
        controller: editingController,
        focusNode: inputFocus,
        onEmptyBackspace: onEmptyBackspace,
      ),
      const DCommandList<String>(
        children: [
          DCommandLoading(child: Text('Loading results…')),
          DCommandEmpty(child: Text('No results found.')),
          DCommandGroup<String>(
            heading: Text('Suggestions'),
            items: [
              DCommandItem(
                value: 'Calendar',
                keywords: ['date', 'schedule'],
                child: Text('Calendar'),
              ),
              DCommandItem(
                value: 'Search Emoji',
                keywords: ['smile'],
                child: Text('Search Emoji'),
              ),
              DCommandItem(
                value: 'Calculator',
                enabled: false,
                child: Text('Calculator'),
              ),
            ],
          ),
          DCommandSeparator<String>(),
          DCommandGroup<String>(
            heading: Text('Settings'),
            items: [
              DCommandItem(value: 'Profile', child: Text('Profile')),
              DCommandItem(value: 'Billing', child: Text('Billing')),
              DCommandItem(value: 'Settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
    ],
  ),
);

void main() {
  for (final count in [3, 80]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'guided command choices retain activation and directional inset ($count, $direction)',
        (tester) async {
          final selections = <String>[];
          final controller = DCommandController<String>();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            _host(
              DCommand<String>(
                controller: controller,
                onSelected: selections.add,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DCommandInput<String>(),
                    DCommandList<String>(
                      maxHeight: 300,
                      children: [
                        const DCommandItem<String>(
                          value: 'flat',
                          child: Text('Flat'),
                        ),
                        DCommandGroup<String>(
                          heading: const Text('Kinds'),
                          showGuide: true,
                          items: [
                            for (var i = 0; i < count; i++)
                              DCommandItem<String>(
                                value: 'guide-$i',
                                child: Text('Guided $i'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              direction: direction,
            ),
          );
          await tester.pumpAndSettle();
          final flat = tester.getRect(find.text('Flat'));
          final guided = tester.getRect(find.text('Guided 0'));
          expect(
            direction == TextDirection.ltr
                ? guided.left - flat.left
                : flat.right - guided.right,
            10,
          );
          await tester.tap(find.text('Guided 0'));
          expect(selections, ['guide-0']);
          await tester.tap(find.byType(DCommandInput<String>));
          controller.highlight('guide-1');
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(selections, ['guide-0', 'guide-1']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('compact query fills remaining space and wraps at 90px', (
    tester,
  ) async {
    for (final width in [250.0, 190.0]) {
      await tester.pumpWidget(
        _host(
          Align(
            child: SizedBox(
              width: width,
              child: const DCommand<String>(
                child: DCommandInput<String>(
                  autofocus: false,
                  density: DCommandInputDensity.menuFilter,
                  tokens: [
                    SizedBox(key: ValueKey('token'), width: 100, height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final token = tester.getRect(find.byKey(const ValueKey('token')));
      final field = tester.getRect(find.byType(DInput));
      if (width == 250) {
        expect(field.left, token.right + 5 + 4);
        expect(field.center.dy, closeTo(token.center.dy, .01));
      } else {
        expect(field.left, token.left + 4);
        expect(field.top, token.bottom + 5 + 3);
      }
      expect(tester.widget<DInput>(find.byType(DInput)).style!.fontSize, 13);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('filter token keyboard focus does not move command selection', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialValue: 'first');
    addTearDown(controller.dispose);
    var edits = 0;
    var selected = 0;
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          onSelected: (_) => selected++,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DCommandInput<String>(
                autofocus: false,
                density: DCommandInputDensity.menuFilter,
                tokens: [
                  DFilterToken(
                    label: 'Category',
                    value: 'baking',
                    editLabel: 'Edit category',
                    removeLabel: 'Remove category',
                    onEdited: () => edits++,
                    onRemoved: () {},
                  ),
                ],
              ),
              const DCommandList<String>(
                children: [
                  DCommandItem(value: 'first', child: Text('First')),
                  DCommandItem(value: 'second', child: Text('Second')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Category: baking'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.value, 'first');
    // Native directional traversal may move focus to a result. Return to the
    // token before checking its independent activation shortcut.
    await tester.pump();
    Focus.of(tester.element(find.text('Category: baking'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(edits, 1);
    expect(selected, 0);
  });

  testWidgets('long command results mount a bounded number of rows', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          child: DCommandList<String>(
            children: [
              DCommandGroup<String>(
                heading: const Text('Tags'),
                items: [
                  for (var i = 0; i < 1000; i++)
                    DCommandItem<String>(
                      value: 'tag-$i',
                      child: Text('tag-$i'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    int mountedRows() => find
        .byWidgetPredicate(
          (widget) =>
              widget is Text && (widget.data?.startsWith('tag-') ?? false),
        )
        .evaluate()
        .length;
    expect(mountedRows(), lessThan(60));
    expect(mountedRows(), greaterThan(0));
    expect(find.text('tag-0').hitTestable(), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byType(DCommandList<String>),
      matching: find.byType(Scrollable),
    );
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(400),
    );
    expect(mountedRows(), lessThan(60));
    expect(mountedRows(), greaterThan(0));
    expect(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                RegExp(r'^tag-(?:[1-9]\d*)$').hasMatch(widget.data!),
          )
          .hitTestable(),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard reveals unmounted variable-height command results', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DCommandInput<String>(),
              DCommandList<String>(
                children: [
                  DCommandGroup<String>(
                    heading: const Text('Results'),
                    items: [
                      for (var i = 0; i < 500; i++)
                        DCommandItem<String>(
                          value: 'Row $i',
                          child: Text(
                            i.isEven
                                ? 'Row $i'
                                : 'Row $i\nSecond line\nThird line',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final results = find.descendant(
      of: find.byType(DCommandList<String>),
      matching: find.byType(Scrollable),
    );
    expect(find.text('Row 499\nSecond line\nThird line'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(controller.value, 'Row 499');
    expect(
      tester
          .getRect(results)
          .contains(
            tester.getCenter(find.text('Row 499\nSecond line\nThird line')),
          ),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(controller.value, 'Row 0');
    expect(
      tester.getRect(results).contains(tester.getCenter(find.text('Row 0'))),
      isTrue,
    );
    controller.highlight('Row 250');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.value, 'Row 251');
    expect(
      tester
          .getRect(results)
          .contains(
            tester.getCenter(find.text('Row 251\nSecond line\nThird line')),
          ),
      isTrue,
    );
    controller.updateQuery('Row 499');
    await tester.pumpAndSettle();
    expect(find.text('Row 499\nSecond line\nThird line'), findsOneWidget);
    controller.updateQuery('');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(controller.value, 'Row 0');
    expect(
      tester.getRect(results).contains(tester.getCenter(find.text('Row 0'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('highlight work stays bounded in long command lists', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _host(
          DCommand<String>(
            controller: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DCommandInput<String>(),
                DCommandList<String>(
                  children: [
                    for (var i = 0; i < 500; i++)
                      DCommandItem<String>(
                        value: 'Row $i',
                        child: Text('Row $i'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Tristate selected(String value) => tester
          .getSemantics(
            find
                .ancestor(
                  of: find.text(value),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        widget.properties.selected != null,
                  ),
                )
                .first,
          )
          .flagsCollection
          .isSelected;
      controller.highlight('Row 0');
      await tester.pump();
      expect(selected('Row 0'), Tristate.isTrue);
      var builds = 0;
      var listBuilds = 0;
      var inputBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        builds++;
        if (element.widget is DCommandList<String>) listBuilds++;
        if (element.widget is DCommandInput<String>) inputBuilds++;
      };
      try {
        var previousValue = 'Row 0';
        for (final value in ['Row 1', 'Row 2', 'Row 3']) {
          builds = 0;
          controller.highlight(value);
          await tester.pump();
          expect(controller.value, value);
          expect(selected(previousValue), Tristate.isFalse);
          expect(selected(value), Tristate.isTrue);
          previousValue = value;
          expect(
            builds,
            lessThan(200),
            reason: 'Only the old and new highlight should rebuild.',
          );
        }
        expect(listBuilds, 0);
        expect(inputBuilds, 0);
        expect(tester.takeException(), isNull);
      } finally {
        debugOnRebuildDirtyWidget = previous;
      }
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'inline command input leaves focus idle and retains IME and selection',
    (tester) async {
      final focus = FocusNode();
      final editing = TextEditingController();
      final command = DCommandController<String>();
      addTearDown(focus.dispose);
      addTearDown(editing.dispose);
      addTearDown(command.dispose);
      String? selected;
      await tester.pumpWidget(
        _host(
          DCommand<String>(
            controller: command,
            onSelected: (value) => selected = value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DCommandInput<String>(
                  borderless: true,
                  autofocus: false,
                  focusNode: focus,
                  controller: editing,
                ),
                const DCommandList<String>(
                  children: [
                    DCommandItem(value: 'Calendar', child: Text('Calendar')),
                    DCommandItem(value: 'Profile', child: Text('Profile')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      final input = tester.widget<DInput>(find.byType(DInput));
      expect(input.borderless, isTrue);
      expect(input.suffix, isNull);
      await tester.enterText(find.byType(EditableText), 'Cal');
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Cal',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, isNull);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Cal',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selected, 'Calendar');
    },
  );
  testWidgets(
    'empty Backspace leaves query state and focus with the caller',
    (tester) async {
      final editing = TextEditingController();
      final focus = FocusNode();
      final queries = <String>[];
      var deletes = 0;
      addTearDown(editing.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _host(
          _command(
            editingController: editing,
            inputFocus: focus,
            onQueryChanged: queries.add,
            onEmptyBackspace: () => deletes++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(editing.text, isEmpty);
      expect(queries, isEmpty);
      expect(focus.hasFocus, isTrue);

      final mobile =
          Theme.of(tester.element(find.byType(DInput))).platform !=
          TargetPlatform.macOS;
      // A soft keyboard deletes DInput's empty boundary through text input.
      if (mobile) {
        tester.testTextInput.updateEditingValue(TextEditingValue.empty);
        await tester.pumpAndSettle();
        expect(deletes, 2);
        expect(editing.text, isEmpty);
        expect(queries, isEmpty);
        expect(focus.hasFocus, isTrue);
      }

      final emptyDeletes = deletes;
      await tester.enterText(find.byType(EditableText), 'x');
      await tester.pumpAndSettle();
      if (mobile) {
        tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      }
      await tester.pumpAndSettle();
      expect(editing.text, isEmpty);
      expect(queries, ['x', '']);
      expect(deletes, emptyDeletes);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'external editor key routing retains focus and respects IME and detach',
    (tester) async {
      final controller = DCommandController<String>();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      String? selected;
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              TextField(focusNode: focus),
              _command(
                controller: controller,
                onSelected: (value) => selected = value,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      const down = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      );
      final initial = controller.value;
      expect(
        controller.handleKeyEvent(down, isComposing: true),
        KeyEventResult.ignored,
      );
      expect(controller.value, initial);
      expect(controller.handleKeyEvent(down), KeyEventResult.handled);
      expect(controller.value, isNot(initial));
      expect(focus.hasFocus, isTrue);
      controller.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );
      expect(selected, controller.value);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.handleKeyEvent(down), KeyEventResult.ignored);
    },
  );

  test(
    'detached controller retains imperative query and highlight updates',
    () {
      final controller = DCommandController<String>();
      addTearDown(controller.dispose);

      controller.updateQuery('profile');
      controller.highlight('Profile');

      expect(controller.query, 'profile');
      expect(controller.value, 'Profile');
    },
  );

  testWidgets('filters by values and keyword aliases and exposes empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_command()));
    await tester.pump();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('No results found.'), findsNothing);

    await tester.enterText(find.byType(TextField), 'schedule');
    await tester.pump();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Search Emoji'), findsNothing);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('Calendar'), findsNothing);
    expect(find.text('No results found.'), findsOneWidget);
    expect(find.text('Suggestions'), findsNothing);
  });

  testWidgets('search preserves score tiers, stable groups and whitespace', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialQuery: '  CAL  ');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          child: const DCommandList<String>(
            children: [
              DCommandGroup<String>(
                heading: Text('First group'),
                items: [
                  DCommandItem(
                    value: 'contains',
                    searchValue: 'My calendar',
                    child: Text('Contains'),
                  ),
                  DCommandItem(
                    value: 'prefix-first',
                    searchValue: '  Calendar  ',
                    child: Text('First prefix'),
                  ),
                  DCommandItem(
                    value: 'exact',
                    searchValue: ' CAL ',
                    keywords: ['  extra alias  ', '  '],
                    child: Text('Exact with aliases'),
                  ),
                  DCommandItem(
                    value: 'prefix-second',
                    searchValue: 'Call',
                    child: Text('Second prefix'),
                  ),
                  DCommandItem(
                    value: 'forced',
                    forceMount: true,
                    child: Text('Forced'),
                  ),
                  DCommandItem(
                    value: 'tokens',
                    searchValue: '  red green  ',
                    keywords: ['  Blue  ', '  '],
                    child: Text('Separate tokens'),
                  ),
                  DCommandItem(
                    value: 'token-exact',
                    searchValue: 'BLUE   red',
                    child: Text('Exact tokens'),
                  ),
                  DCommandItem(
                    value: 'token-prefix',
                    searchValue: 'blue   red extra',
                    child: Text('Prefix tokens'),
                  ),
                  DCommandItem(
                    value: 'token-contains',
                    searchValue: 'extra blue   red extra',
                    child: Text('Contained tokens'),
                  ),
                  DCommandItem(value: 'missing', child: Text('Missing')),
                ],
              ),
              DCommandSeparator<String>(),
              DCommandGroup<String>(
                heading: Text('Second group'),
                items: [
                  DCommandItem(
                    value: 'second-group',
                    searchValue: 'cal',
                    child: Text('Second group exact'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    List<String?> labels() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(DCommandList<String>),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .toList();
    expect(labels(), [
      'First group',
      'Exact with aliases',
      'Forced',
      'First prefix',
      'Second prefix',
      'Contains',
      'Second group',
      'Second group exact',
    ]);
    expect(controller.value, 'exact');

    controller.updateQuery(' blue   RED ');
    await tester.pump();
    expect(labels(), [
      'First group',
      'Forced',
      'Exact tokens',
      'Prefix tokens',
      'Contained tokens',
      'Separate tokens',
    ]);

    controller.updateQuery('');
    await tester.pump();
    final unfiltered = labels();
    final separators = find.descendant(
      of: find.byType(DCommandList<String>),
      matching: find.byType(Divider),
    );
    expect(separators, findsOneWidget);
    controller.updateQuery('   ');
    await tester.pump();
    expect(labels(), unfiltered);
    expect(separators, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('query changes observe keyword mutations on the same item', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialQuery: 'old alias');
    final keywords = ['old alias'];
    final item = DCommandItem<String>(
      value: 'action',
      keywords: keywords,
      child: const Text('Action'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          child: DCommandList<String>(
            children: [
              const DCommandEmpty(child: Text('Empty')),
              item,
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Action'), findsOneWidget);

    keywords[0] = 'new alias';
    controller.updateQuery('new alias');
    await tester.pump();
    expect(find.text('Action'), findsOneWidget);
    controller.updateQuery('old alias');
    await tester.pump();
    expect(find.text('Empty'), findsOneWidget);

    keywords.add('added alias');
    controller.updateQuery('added alias');
    await tester.pump();
    expect(find.text('Action'), findsOneWidget);
    keywords.clear();
    controller.updateQuery('added');
    await tester.pump();
    expect(find.text('Empty'), findsOneWidget);
  });

  testWidgets('query changes observe mutable generic search values', (
    tester,
  ) async {
    final controller = DCommandController<_MutableCommandValue>(
      initialQuery: 'before',
    );
    final value = _MutableCommandValue('before');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<_MutableCommandValue>(
          controller: controller,
          child: DCommandList<_MutableCommandValue>(
            children: [
              const DCommandEmpty(child: Text('Empty')),
              DCommandItem<_MutableCommandValue>(
                value: value,
                child: const Text('Mutable action'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Mutable action'), findsOneWidget);
    value.label = 'after';
    controller.updateQuery('after');
    await tester.pump();
    expect(find.text('Mutable action'), findsOneWidget);
    controller.updateQuery('before');
    await tester.pump();
    expect(find.text('Empty'), findsOneWidget);
    expect(controller.value, isNull);
  });

  testWidgets(
    'replacing a keyed result updates search, content and selection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = DCommandController<String>(initialQuery: 'before');
      final selected = <String>[];
      var replacement = false;
      late StateSetter rebuild;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              final isReplacement = replacement;
              return DCommand<String>(
                controller: controller,
                child: DCommandList<String>(
                  children: [
                    const DCommandEmpty(child: Text('Empty')),
                    DCommandItem<String>(
                      key: const ValueKey('same-result'),
                      value: 'action',
                      searchValue: isReplacement ? 'after' : 'before',
                      semanticLabel: isReplacement
                          ? 'New action'
                          : 'Old action',
                      onSelected: (_) =>
                          selected.add(isReplacement ? 'new' : 'old'),
                      child: Text(isReplacement ? 'After' : 'Before'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      controller.activate();
      expect(selected, ['old']);

      rebuild(() => replacement = true);
      await tester.pump();
      expect(find.text('Empty'), findsOneWidget);
      controller.updateQuery('after');
      await tester.pump();
      expect(find.text('Before'), findsNothing);
      expect(find.text('After'), findsOneWidget);
      expect(find.bySemanticsLabel('New action'), findsOneWidget);
      await tester.tap(find.text('After'));
      expect(selected, ['old', 'new']);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('disabled-only results retain lazy rows and loading states', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialQuery: 'disabled');
    var loading = false;
    late StateSetter rebuild;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DCommand<String>(
              controller: controller,
              loading: loading,
              child: DCommandList<String>(
                children: [
                  const DCommandLoading(child: Text('Loading')),
                  const DCommandEmpty(child: Text('Empty')),
                  DCommandGroup<String>(
                    items: [
                      for (var i = 0; i < 65; i++)
                        DCommandItem<String>(
                          value: 'Disabled $i',
                          enabled: false,
                          child: Text('Disabled $i'),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final list = find.byType(DCommandList<String>);
    expect(
      find.descendant(of: list, matching: find.byType(ListView)),
      findsOneWidget,
    );
    expect(find.text('Disabled 0'), findsOneWidget);
    expect(find.text('Empty'), findsNothing);
    expect(controller.value, isNull);
    controller.activate('Disabled 0');
    expect(controller.value, isNull);

    rebuild(() => loading = true);
    await tester.pump();
    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Disabled 0'), findsOneWidget);
    expect(find.text('Empty'), findsNothing);
    controller.updateQuery('missing');
    await tester.pump();
    expect(find.text('Loading'), findsOneWidget);
    expect(find.text('Disabled 0'), findsNothing);
    rebuild(() => loading = false);
    await tester.pump();
    expect(find.text('Empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'IME composition suppresses command keys until native editing commits',
    (tester) async {
      final controller = DCommandController<String>();
      final focus = FocusNode();
      final editing = TextEditingController();
      final selected = <String>[];
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        _host(
          _command(
            controller: controller,
            loop: true,
            inputFocus: focus,
            editingController: editing,
            onSelected: selected.add,
          ),
        ),
      );
      await tester.pump();
      focus.requestFocus();
      editing.value = const TextEditingValue(
        text: 'e',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      final initialHighlight = controller.value;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(editing.value.composing, const TextRange(start: 0, end: 1));
      expect(controller.value, initialHighlight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, isEmpty);

      editing.value = editing.value.copyWith(composing: TextRange.empty);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.value, isNot(initialHighlight));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected, hasLength(1));
      expect(find.text(selected.single), findsOneWidget);
    },
  );

  testWidgets(
    'selection and composing-only edits do not report query changes',
    (tester) async {
      final editing = TextEditingController();
      final queries = <String>[];
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        _host(
          _command(editingController: editing, onQueryChanged: queries.add),
        ),
      );
      await tester.pump();
      editing.text = 'calendar';
      await tester.pump();
      queries.clear();

      editing.selection = const TextSelection.collapsed(offset: 2);
      editing.value = editing.value.copyWith(
        composing: const TextRange(start: 0, end: 2),
      );
      await tester.pump();

      expect(queries, isEmpty);
    },
  );

  testWidgets('Ctrl bindings skip disabled rows without moving editor focus', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(_command(controller: controller, inputFocus: focus, loop: true)),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(controller.value, 'Search Emoji');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(controller.value, 'Profile');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(controller.value, 'Search Emoji');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.value, 'Calendar');
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('Home, End, Meta-arrow, and Alt-arrow navigate like cmdk', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(_command(controller: controller, inputFocus: focus)),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(controller.value, 'Settings');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(controller.value, 'Calendar');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(controller.value, 'Settings');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(controller.value, 'Calendar');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(controller.value, 'Profile');
  });

  testWidgets('a fixed height holds while results change and centres states', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    final editing = TextEditingController();
    var loading = false;
    late StateSetter setLoading;
    addTearDown(controller.dispose);
    addTearDown(editing.dispose);
    final list = find.byKey(const ValueKey('fixed-list'));
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            setLoading = setState;
            return DCommand<String>(
              controller: controller,
              loading: loading,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DCommandInput<String>(controller: editing),
                  DCommandList<String>(
                    key: const ValueKey('fixed-list'),
                    height: 200,
                    children: [
                      const DCommandLoading(child: Text('Loading results…')),
                      const DCommandEmpty(child: Text('No results found.')),
                      DCommandGroup<String>(
                        items: [
                          for (final value in ['Calendar', 'Calculator'])
                            DCommandItem(value: value, child: Text(value)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final bounds = tester.getRect(list);
    expect(bounds.height, 200);
    expect(
      tester.getTopLeft(find.text('Calendar')).dy - bounds.top,
      lessThan(bounds.height / 4),
    );

    for (final query in ['Calen', 'zzz']) {
      await tester.enterText(find.byType(EditableText), query);
      await tester.pump();
      expect(tester.getRect(list), bounds, reason: query);
    }
    expect(
      tester.getCenter(find.text('No results found.')).dy,
      moreOrLessEquals(bounds.center.dy, epsilon: 1),
    );

    setLoading(() => loading = true);
    await tester.pump();
    expect(tester.getRect(list), bounds);
    expect(
      tester.getCenter(find.text('Loading results…')).dy,
      moreOrLessEquals(bounds.center.dy, epsilon: 1),
    );
  });

  testWidgets('disabled rows are skipped by keyboard and cannot be tapped', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialValue: 'Search Emoji');
    final selected = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(_command(controller: controller, onSelected: selected.add)),
    );
    await tester.pump();
    controller.activate('Calculator');
    expect(selected, isEmpty);
    await tester.tap(find.text('Calculator'));
    await tester.pump();
    expect(selected, isEmpty);
  });

  testWidgets('dynamic results retire disabled and removed highlights', (
    tester,
  ) async {
    final controller = DCommandController<String>(initialValue: 'Calendar');
    var calendarEnabled = true;
    var showProfile = true;
    late StateSetter rebuild;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DCommand<String>(
              controller: controller,
              child: DCommandList<String>(
                children: [
                  DCommandItem(
                    value: 'Calendar',
                    enabled: calendarEnabled,
                    child: const Text('Calendar'),
                  ),
                  if (showProfile)
                    const DCommandItem(
                      value: 'Profile',
                      child: Text('Profile'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(controller.value, 'Calendar');

    rebuild(() => calendarEnabled = false);
    await tester.pump();
    await tester.pump();
    expect(controller.value, 'Profile');

    rebuild(() => showProfile = false);
    await tester.pump();
    await tester.pump();
    expect(controller.value, isNull);
  });

  testWidgets('input and custom item labels reach semantics', (tester) async {
    await tester.pumpWidget(
      _host(
        const DCommand<String>(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DCommandInput<String>(semanticLabel: 'Find an action'),
              DCommandList<String>(
                children: [
                  DCommandItem(
                    value: 'Profile',
                    semanticLabel: 'Open your profile',
                    child: Text('Profile'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final inputSemantics = find.ancestor(
      of: find.byType(TextField),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Find an action',
      ),
    );
    expect(inputSemantics, findsOneWidget);
    final inputData = tester.getSemantics(inputSemantics).getSemanticsData();
    expect(inputData.flagsCollection.isTextField, isTrue);
    expect(find.bySemanticsLabel('Open your profile'), findsOneWidget);
  });

  testWidgets('disabled rows use one half-opacity treatment', (tester) async {
    await tester.pumpWidget(_host(_command()));
    await tester.pump();

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Calculator'),
    );
    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text('Calculator'),
            matching: find.byType(Opacity),
          ),
        )
        .map((widget) => widget.opacity);
    expect(paragraph.text.style?.color?.a, 1);
    expect(opacities, contains(.5));
  });

  testWidgets('selected shortcuts use foreground color', (tester) async {
    final controller = DCommandController<String>(initialValue: 'Profile');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          child: const DCommandList<String>(
            children: [
              DCommandItem(
                value: 'Profile',
                trailing: DCommandShortcut(Text('⌘P')),
                child: Text('Profile'),
              ),
              DCommandItem(
                value: 'Billing',
                trailing: DCommandShortcut(Text('⌘B')),
                child: Text('Billing'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final tokens = DTokens.of(tester.element(find.byType(DCommand<String>)));

    expect(
      DefaultTextStyle.of(tester.element(find.text('⌘P'))).style.color,
      tokens.foreground,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('⌘B'))).style.color,
      tokens.mutedForeground,
    );
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('keyboard selection holds until the pointer moves again', (
    tester,
  ) async {
    final controller = DCommandController<String>();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(_command(controller: controller)));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Profile')));
    await tester.pumpAndSettle();
    expect(controller.value, 'Profile');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.value, 'Billing');
    await mouse.moveTo(
      tester.getCenter(find.text('Profile')) + const Offset(1, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.value, 'Profile');
    await mouse.removePointer();
  });

  testWidgets('checked state is semantic and touch rows match visible bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Theme(
          data: ThemeData(platform: TargetPlatform.iOS),
          child: const DCommand<String>(
            child: DCommandList<String>(
              children: [
                DCommandItem(
                  value: 'Settings',
                  checked: true,
                  child: Text('Settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final checkedSemantics = find.ancestor(
      of: find.text('Settings'),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.checked == true,
      ),
    );
    expect(checkedSemantics, findsOneWidget);
    final data = tester.getSemantics(checkedSemantics).getSemanticsData();
    expect(data.flagsCollection.isChecked, CheckedState.isTrue);
    expect(tester.getSize(checkedSemantics).height, 32);
  });

  testWidgets('Return activates an individually focused row', (tester) async {
    final controller = DCommandController<String>(initialValue: 'Calendar');
    final selected = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        DCommand<String>(
          controller: controller,
          onSelected: selected.add,
          child: const DCommandList<String>(
            children: [
              DCommandItem(value: 'Calendar', child: Text('Calendar')),
              DCommandItem(value: 'Profile', child: Text('Profile')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    Focus.of(tester.element(find.text('Profile'))).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected, ['Profile']);
  });

  testWidgets(
    'controlled query and value report changes without losing state',
    (tester) async {
      final queries = <String>[];
      final values = <String?>[];
      await tester.pumpWidget(
        _host(
          _command(
            query: '',
            value: 'Calendar',
            onQueryChanged: queries.add,
            onValueChanged: values.add,
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'profile');
      await tester.pump();
      expect(queries.last, 'profile');
      expect(find.text('Profile'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(values, isNotEmpty);
    },
  );

  testWidgets('loading, borrowed resources and RTL remain live', (
    tester,
  ) async {
    final command = DCommandController<String>();
    final editing = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(
      _host(
        _command(
          controller: command,
          editingController: editing,
          inputFocus: focus,
          loading: true,
        ),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pump();
    expect(find.text('Loading results…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(() => command.updateQuery('safe'), returnsNormally);
    expect(() => editing.text = 'safe', returnsNormally);
    expect(() => focus.requestFocus(), returnsNormally);
    command.dispose();
    editing.dispose();
    focus.dispose();
  });

  testWidgets(
    'dialog selection returns result and Escape restores trigger focus',
    (tester) async {
      final trigger = FocusNode();
      final dialog = DDialogController<String>();
      String? result;
      addTearDown(trigger.dispose);
      addTearDown(dialog.dispose);
      await tester.pumpWidget(
        _host(
          DCommandDialog<String>(
            controller: dialog,
            finalFocusNode: trigger,
            onOpenChanged: (details) {
              if (!details.open) result = details.result;
            },
            trigger: DDialogTrigger(
              builder: (context, open) => DButton(
                focusNode: trigger,
                onPressed: open,
                label: const Text('Open Menu'),
              ),
            ),
            command: DCommand<String>(
              onSelected: dialog.close,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DCommandInput<String>(),
                  DCommandList<String>(
                    children: [
                      DCommandGroup<String>(
                        items: [
                          DCommandItem(
                            value: 'Profile',
                            child: Text('Profile'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(trigger));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsNothing);
      expect(trigger.hasFocus, isTrue);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(result, 'Profile');
      expect(find.text('Profile'), findsNothing);
      expect(trigger.hasFocus, isTrue);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'initially open command palette can close and reopen',
    (tester) async {
      await tester.pumpWidget(
        _host(
          DCommandDialog<String>(
            initiallyOpen: true,
            trigger: DDialogTrigger(
              builder: (context, open) =>
                  DButton(label: const Text('Open Menu'), onPressed: open),
            ),
            command: _command(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DCommandInput<String>), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(DCommandInput<String>), findsNothing);
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();
      expect(find.byType(DCommandInput<String>), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );
}
