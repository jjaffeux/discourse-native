import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _options = [
  DComboboxOption(value: 'next', label: 'Next.js'),
  DComboboxOption(value: 'svelte', label: 'SvelteKit'),
  DComboboxOption(value: 'nuxt', label: 'Nuxt.js', enabled: false),
  DComboboxOption(value: 'remix', label: 'Remix'),
];

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

DCombobox<String> _single({
  ValueChanged<String?>? changed,
  bool autoHighlight = false,
  bool enabled = true,
}) => DCombobox<String>(
  options: _options,
  autoHighlight: autoHighlight,
  enabled: enabled,
  onChanged: (value, _) => changed?.call(value),
  anchor: const DComboboxInput<String>(
    key: ValueKey('input'),
    placeholder: 'Select a framework',
    showClear: true,
  ),
  content: const DComboboxContent(
    children: [
      DComboboxEmpty<String>(child: Text('No items found.')),
      DComboboxList<String>(),
    ],
  ),
);

void main() {
  testWidgets('pointer highlight switches rows without an overlap frame', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_single()));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Next.js')));
    await tester.pumpAndSettle();
    final hover = DTokens.of(tester.element(find.text('Next.js'))).hover;
    expect(_rowBackground(tester, 'next'), hover);

    await mouse.moveTo(tester.getCenter(find.text('SvelteKit')));
    await tester.pump();
    expect(_rowBackground(tester, 'next').a, 0);
    expect(_rowBackground(tester, 'svelte'), hover);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_rowBackground(tester, 'next').a, 0);
    expect(_rowBackground(tester, 'svelte'), hover);
  });

  testWidgets('keyboard highlight replaces a stationary pointer highlight', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _app(_single(changed: (value) => selected = value)),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Next.js')));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_rowBackground(tester, 'next').a, 0);
    expect(_rowBackground(tester, 'svelte').a, greaterThan(0));
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'svelte');
  });

  for (final scenario in [
    (
      name: 'disabled option',
      hover: true,
      controlled: false,
      value: 'next',
      target: 'nuxt',
    ),
    (
      name: 'disabled pointer highlighting',
      hover: false,
      controlled: false,
      value: 'next',
      target: 'svelte',
    ),
    (
      name: 'controlled highlight',
      hover: true,
      controlled: true,
      value: 'next',
      target: 'svelte',
    ),
    (
      name: 'controlled null highlight',
      hover: true,
      controlled: true,
      value: null,
      target: 'svelte',
    ),
  ]) {
    testWidgets('${scenario.name} does not paint an extra hovered row', (
      tester,
    ) async {
      String? requested;
      await tester.pumpWidget(
        _app(
          DCombobox<String>(
            options: _options,
            highlightItemOnHover: scenario.hover,
            highlightControlled: scenario.controlled,
            highlightedValue: scenario.value,
            onHighlightChanged: (value, _) => requested = value,
            anchor: const DComboboxInput<String>(),
            content: const DComboboxContent(
              children: [DComboboxList<String>()],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(
          find.text(
            _options.firstWhere((o) => o.value == scenario.target).label,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_rowBackground(tester, scenario.target).a, 0);
      expect(
        _rowBackground(tester, 'next').a,
        scenario.value == null ? 0 : greaterThan(0),
      );
      expect(requested, scenario.controlled ? scenario.target : null);
    });
  }

  testWidgets(
    'selecting after input blur closes without refocusing the popup',
    (tester) async {
      final inputFocus = FocusNode();
      final controller = DComboboxController<String>();
      addTearDown(inputFocus.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          DCombobox<String>(
            controller: controller,
            focusNode: inputFocus,
            options: _options,
            anchor: DComboboxTrigger<String>(
              builder: (context, trigger) => DButton(
                label: const Text('Choose framework'),
                onPressed: trigger.toggle,
                focusNode: trigger.focusNode,
              ),
            ),
            content: const DComboboxContent(
              children: [
                DComboboxInput<String>(
                  registerAsAnchor: false,
                  showTrigger: false,
                ),
                DComboboxList<String>(),
              ],
            ),
          ),
          theme: ThemeData(platform: TargetPlatform.macOS),
        ),
      );
      await tester.tap(find.text('Choose framework'));
      await tester.pumpAndSettle();
      inputFocus.unfocus();
      await tester.pump();
      await tester.tap(find.text('SvelteKit'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(controller.value, 'svelte');
      expect(controller.isOpen, isFalse);
      expect(inputFocus.hasFocus, isFalse);
      expect(
        tester.widget<DButton>(find.byType(DButton)).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filters, highlights and selects without leaving the editor', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _app(_single(changed: (value) => selected = value, autoHighlight: true)),
    );

    await tester.tap(find.byKey(const ValueKey('input')));
    await tester.pumpAndSettle();
    expect(find.text('Next.js'), findsOneWidget);
    expect(find.text('SvelteKit'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(find.byType(TextField), 'sve');
    await tester.pumpAndSettle();
    expect(find.text('Next.js'), findsNothing);
    expect(find.text('SvelteKit'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'svelte');
    expect(find.text('SvelteKit'), findsOneWidget);
    expect(find.text('No items found.'), findsNothing);
  });

  testWidgets('arrow navigation skips disabled options and loops', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _app(_single(changed: (value) => selected = value)),
    );
    await tester.tap(find.byKey(const ValueKey('input')));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'remix');
  });

  testWidgets('keyboard Done selects the highlighted result once', (
    tester,
  ) async {
    final selected = <String?>[];
    await tester.pumpWidget(_app(_single(changed: selected.add)));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selected, ['svelte']);
    expect(find.byType(DComboboxContent), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'SvelteKit',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selected, ['svelte']);
  });

  testWidgets(
    'keyboard Done leaves unmatched and disabled results unselected',
    (tester) async {
      final selected = <String?>[];
      await tester.pumpWidget(
        _app(_single(changed: selected.add, autoHighlight: true)),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      for (final query in ['missing', 'nuxt']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(selected, isEmpty);
        expect(find.byType(DComboboxContent), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          isTrue,
        );
      }
    },
  );

  for (final closeOnSelect in [true, false]) {
    testWidgets(
      'keyboard Done respects multiple selection closing policy: $closeOnSelect',
      (tester) async {
        final controller = DComboboxController<String>();
        addTearDown(controller.dispose);
        final selected = <List<String>>[];
        await tester.pumpWidget(
          _app(
            DCombobox<String>.multiple(
              controller: controller,
              options: _options,
              closeOnSelect: closeOnSelect,
              autoHighlight: true,
              onValuesChanged: (values, _) => selected.add(values),
              anchor: const DComboboxChips<String>(
                input: DComboboxChipsInput<String>(),
              ),
              content: const DComboboxContent(
                children: [DComboboxList<String>()],
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'sve');
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(selected, [
          ['svelte'],
        ]);
        expect(controller.isOpen, !closeOnSelect);
        expect(controller.query, isEmpty);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          isTrue,
        );
      },
    );
  }

  testWidgets('hovering a row does not scroll its list or the host page', (
    tester,
  ) async {
    final controller = DComboboxController<String>();
    final pageScroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(pageScroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: pageScroll,
            child: Column(
              children: [
                const SizedBox(height: 150),
                SizedBox(
                  width: 360,
                  height: 360,
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => Center(
                        child: DCombobox<String>(
                          controller: controller,
                          options: [
                            for (var index = 0; index < 20; index++)
                              DComboboxOption(
                                value: 'option-$index',
                                label: 'Option $index',
                              ),
                          ],
                          anchor: const DComboboxInput<String>(),
                          content: const DComboboxContent(
                            maxHeight: 120,
                            children: [DComboboxList<String>()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final row = find.text('Option 1');
    final popupScroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(DComboboxList<String>),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    final initialPopupOffset = popupScroll.pixels;
    expect(pageScroll.offset, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();

    expect(controller.highlightedValue, 'option-1');
    expect(popupScroll.pixels, initialPopupOffset);
    expect(pageScroll.offset, 0);

    await mouse.moveTo(Offset.zero);
    for (var index = 0; index < 15; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();

    expect(controller.highlightedValue, 'option-16');
    expect(popupScroll.maxScrollExtent, greaterThan(0));
    expect(popupScroll.pixels, greaterThan(initialPopupOffset));
    expect(pageScroll.offset, 0);
  });

  testWidgets('loop focus passes through the input between list ends', (
    tester,
  ) async {
    final controller = DComboboxController<String>();
    await tester.pumpWidget(
      _app(
        DCombobox<String>(
          controller: controller,
          options: _options,
          anchor: const DComboboxInput<String>(),
          content: const DComboboxContent(children: [DComboboxList<String>()]),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    controller.highlight('remix');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.highlightedValue, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.highlightedValue, 'next');
    controller.highlight('next');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(controller.highlightedValue, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(controller.highlightedValue, 'remix');
    controller.dispose();
  });

  testWidgets('clear action clears selection and restores input focus', (
    tester,
  ) async {
    String? selected = 'next';
    await tester.pumpWidget(
      _app(
        DCombobox<String>(
          options: _options,
          initialValue: 'next',
          onChanged: (value, _) => selected = value,
          anchor: const DComboboxInput<String>(showClear: true),
          content: const DComboboxContent(children: [DComboboxList<String>()]),
        ),
      ),
    );
    expect(find.text('Next.js'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('multiple chips toggle, remove and backspace', (tester) async {
    List<String> values = [];
    await tester.pumpWidget(
      _app(
        DCombobox<String>.multiple(
          options: _options,
          initialValue: const ['next'],
          onValuesChanged: (next, _) => values = next,
          anchor: const DComboboxChips<String>(
            input: DComboboxChipsInput<String>(placeholder: 'Add framework'),
          ),
          content: const DComboboxContent(children: [DComboboxList<String>()]),
        ),
      ),
    );

    expect(find.text('Next.js'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SvelteKit'));
    await tester.pumpAndSettle();
    expect(values, ['next', 'svelte']);

    await tester.tap(
      find.descendant(
        of: find.byType(DComboboxChip<String>).first,
        matching: find.text('Next.js'),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(values, ['next']);
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(values, isEmpty);

    await tester.enterText(find.byType(TextField), 'sve');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SvelteKit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    expect(values, isEmpty);
  });

  testWidgets('multiple input arrows into chips in reading order', (
    tester,
  ) async {
    for (final textDirection in TextDirection.values) {
      var values = ['next', 'svelte'];
      final changes = <List<String>>[];
      final controller = DComboboxController<String>();
      await tester.pumpWidget(
        _app(
          Directionality(
            textDirection: textDirection,
            child: DCombobox<String>.multiple(
              key: ValueKey(textDirection),
              controller: controller,
              initialValue: values,
              options: _options,
              onValuesChanged: (next, _) {
                values = next;
                changes.add(next);
              },
              anchor: const DComboboxChips<String>(
                input: DComboboxChipsInput<String>(),
              ),
              content: const DComboboxContent(
                children: [DComboboxList<String>()],
              ),
            ),
          ),
        ),
      );

      expect(controller.values, ['next', 'svelte']);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(controller.values, ['next', 'svelte'], reason: '$changes');
      final editor = tester.widget<TextField>(find.byType(TextField));
      expect(editor.focusNode?.hasFocus, isTrue);
      expect(editor.controller?.selection.extentOffset, lessThanOrEqualTo(0));
      final towardChips = textDirection == TextDirection.ltr
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;
      await tester.enterText(find.byType(TextField), 'x');
      await tester.sendKeyEvent(towardChips);
      await tester.pump();
      expect(editor.focusNode?.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), '');
      await tester.sendKeyEvent(towardChips);
      await tester.pump();
      expect(controller.values, ['next', 'svelte']);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'DCombobox chip',
        reason: '$textDirection',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(values, ['next'], reason: '$textDirection $changes');
      controller.dispose();
    }
  });

  testWidgets('multiple selection closes by default and can remain open', (
    tester,
  ) async {
    for (final closeOnSelect in [true, false]) {
      final controller = DComboboxController<String>();
      await tester.pumpWidget(
        _app(
          DCombobox<String>.multiple(
            controller: controller,
            closeOnSelect: closeOnSelect,
            options: _options,
            anchor: const DComboboxChips<String>(
              input: DComboboxChipsInput<String>(),
            ),
            content: const DComboboxContent(
              children: [DComboboxList<String>()],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next.js').last);
      await tester.pumpAndSettle();
      expect(controller.isOpen, !closeOnSelect);
      controller.dispose();
    }
  });

  for (final multiple in [false, true]) {
    for (final closeOnSelect in [true, false]) {
      testWidgets('mouse selection preserves focus and the closing policy '
          '(multiple: $multiple, close: $closeOnSelect)', (tester) async {
        final controller = DComboboxController<String>();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        const content = DComboboxContent(children: [DComboboxList<String>()]);
        await tester.pumpWidget(
          _app(
            multiple
                ? DCombobox<String>.multiple(
                    controller: controller,
                    focusNode: focus,
                    options: _options,
                    closeOnSelect: closeOnSelect,
                    anchor: const DComboboxChips<String>(
                      input: DComboboxChipsInput<String>(),
                    ),
                    content: content,
                  )
                : DCombobox<String>(
                    controller: controller,
                    focusNode: focus,
                    options: _options,
                    closeOnSelect: closeOnSelect,
                    anchor: const DComboboxInput<String>(),
                    content: content,
                  ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        final mouse = await tester.startGesture(
          tester.getCenter(find.text('Next.js').last),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 40));
        expect(focus.hasFocus, isTrue);
        await mouse.up();
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(controller.values, ['next']);
        expect(controller.isOpen, !closeOnSelect);
        expect(focus.hasFocus, isTrue);

        // A click beyond the combobox still dismisses and leaves the editor.
        controller.open();
        await tester.pumpAndSettle();
        final outside = await tester.startGesture(
          const Offset(10, 10),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 40));
        await outside.up();
        await outside.removePointer();
        await tester.pumpAndSettle();
        expect(controller.isOpen, isFalse);
        expect(focus.hasFocus, isFalse);
      });
    }
  }

  testWidgets('controlled selection only displays accepted parent values', (
    tester,
  ) async {
    String? request;
    await tester.pumpWidget(
      _app(
        DCombobox<String>.controlled(
          value: null,
          options: _options,
          onChanged: (value, _) => request = value,
          anchor: const DComboboxInput<String>(),
          content: const DComboboxContent(children: [DComboboxList<String>()]),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next.js'));
    await tester.pumpAndSettle();
    expect(request, 'next');
    expect(find.text('Next.js'), findsNothing);
  });

  testWidgets('accepted controlled selection updates the editor label', (
    tester,
  ) async {
    String? value;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => DCombobox<String>.controlled(
            value: value,
            options: _options,
            onChanged: (next, _) => setState(() => value = next),
            anchor: const DComboboxInput<String>(),
            content: const DComboboxContent(
              children: [DComboboxList<String>()],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ne');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next.js'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Next.js',
    );
  });

  testWidgets('dynamic results discard stale highlight but retain selection', (
    tester,
  ) async {
    final controller = DComboboxController<String>();
    late StateSetter update;
    var options = _options;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return DCombobox<String>(
              controller: controller,
              initialValue: 'next',
              options: options,
              anchor: const DComboboxInput<String>(),
              content: const DComboboxContent(
                children: [DComboboxList<String>()],
              ),
            );
          },
        ),
      ),
    );
    controller.highlight('svelte');
    expect(controller.highlightedValue, 'svelte');
    update(
      () => options = const [DComboboxOption(value: 'remix', label: 'Remix')],
    );
    await tester.pump();
    expect(controller.highlightedValue, isNull);
    expect(controller.value, 'next');
    controller.dispose();
  });

  testWidgets('controlled null highlight reports requests without mutating', (
    tester,
  ) async {
    String? requested;
    final controller = DComboboxController<String>();
    await tester.pumpWidget(
      _app(
        DCombobox<String>(
          controller: controller,
          options: _options,
          highlightControlled: true,
          highlightedValue: null,
          onHighlightChanged: (value, _) => requested = value,
          anchor: const DComboboxInput<String>(),
          content: const DComboboxContent(children: [DComboboxList<String>()]),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(requested, 'next');
    expect(controller.highlightedValue, isNull);
    controller.dispose();
  });

  testWidgets(
    'escape closes, restores selected label and retains editor focus',
    (tester) async {
      final controller = DComboboxController<String>();
      await tester.pumpWidget(
        _app(
          DCombobox<String>(
            controller: controller,
            options: _options,
            initialValue: 'next',
            anchor: const DComboboxInput<String>(),
            content: const DComboboxContent(
              children: [DComboboxList<String>()],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'rem');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(find.widgetWithText(TextField, 'Next.js'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
      controller.dispose();
    },
  );

  testWidgets('outside press dismisses the popup', (tester) async {
    final controller = DComboboxController<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 320,
                child: DCombobox<String>(
                  controller: controller,
                  options: _options,
                  anchor: const DComboboxInput<String>(),
                  content: const DComboboxContent(
                    children: [DComboboxList<String>()],
                  ),
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('Outside')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 700));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
    controller.dispose();
  });

  testWidgets('Form reset restores the initial value', (tester) async {
    final form = GlobalKey<FormState>();
    String? value;
    await tester.pumpWidget(
      _app(
        Form(
          key: form,
          child: DCombobox<String>(
            options: _options,
            initialValue: 'next',
            onChanged: (next, _) => value = next,
            anchor: const DComboboxInput<String>(),
            content: const DComboboxContent(
              children: [DComboboxList<String>()],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SvelteKit'));
    await tester.pumpAndSettle();
    expect(value, 'svelte');
    form.currentState!.reset();
    await tester.pump();
    expect(value, 'next');
    expect(find.widgetWithText(TextField, 'Next.js'), findsOneWidget);
  });

  testWidgets('single Form save is typed as the selected value', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? saved;
    await tester.pumpWidget(
      _app(
        Form(
          key: form,
          child: DCombobox<String>(
            initialValue: 'next',
            options: _options,
            onSaved: (value) => saved = value,
            anchor: const DComboboxInput<String>(),
            content: const DComboboxContent(
              children: [DComboboxList<String>()],
            ),
          ),
        ),
      ),
    );
    form.currentState!.save();
    expect(saved, 'next');
  });

  testWidgets('custom equality retains chip keyboard focus after rebuild', (
    tester,
  ) async {
    var ids = ['a', 'b'];
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DCombobox<_Choice>.multipleControlled(
              value: [for (final id in ids) _Choice(id)],
              options: const [],
              equals: (left, right) => left.id == right.id,
              itemToStringLabel: (choice) => choice.id.toUpperCase(),
              onValuesChanged: (values, _) => setState(
                () => ids = values.map((value) => value.id).toList(),
              ),
              anchor: const DComboboxChips<_Choice>(
                input: DComboboxChipsInput<_Choice>(),
              ),
              content: const DComboboxContent(children: []),
            );
          },
        ),
      ),
    );

    rebuild(() {});
    await tester.pump();
    await tester.tap(find.text('A'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(ids, ['a']);
  });

  testWidgets('disabled input cannot open', (tester) async {
    await tester.pumpWidget(_app(_single(enabled: false)));
    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Next.js'), findsNothing);
  });

  testWidgets('read-only input can open but cannot edit, clear, or select', (
    tester,
  ) async {
    String? changed;
    final controller = DComboboxController<String>();
    await tester.pumpWidget(
      _app(
        DCombobox<String>(
          controller: controller,
          readOnly: true,
          initialValue: 'next',
          options: _options,
          onChanged: (value, _) => changed = value,
          anchor: const DComboboxInput<String>(showClear: true),
          content: const DComboboxContent(children: [DComboboxList<String>()]),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);
    await tester.enterText(find.byType(TextField), 'SvelteKit');
    await tester.pump();
    expect(controller.query, 'Next.js');
    await tester.tap(find.text('Next.js').last);
    await tester.pump();
    expect(changed, isNull);
    expect(controller.value, 'next');
    controller.clear();
    expect(controller.value, 'next');
    controller.dispose();
  });

  testWidgets('touch items and actions retain 48 logical pixel targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        DCombobox<String>(
          options: _options,
          anchor: const DComboboxInput<String>(showClear: true),
          content: const DComboboxContent(children: [DComboboxList<String>()]),
        ),
        theme: ThemeData(platform: TargetPlatform.iOS),
      ),
    );
    expect(tester.getSize(find.byType(DInputGroupButton)).height, 48);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('SvelteKit').last).height,
      lessThanOrEqualTo(48),
    );
    expect(tester.getRect(find.byType(DComboboxItem<String>).first).height, 48);
  });

  testWidgets('touch items grow past their minimum target for scaled text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 160,
                child: DCombobox<String>(
                  options: const [
                    DComboboxOption(
                      value: 'long',
                      label: 'A framework name that wraps onto several lines',
                    ),
                  ],
                  anchor: const DComboboxInput<String>(),
                  content: const DComboboxContent(
                    children: [DComboboxList<String>()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(DComboboxItem<String>)).height,
      greaterThan(DSpacing.touchTarget),
    );
  });

  testWidgets('open popup reads live theme tokens', (tester) async {
    late StateSetter update;
    var dark = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return _app(
            _single(),
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
          );
        },
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Next.js'))).brightness,
      Brightness.light,
    );
    update(() => dark = true);
    await tester.pumpAndSettle();
    expect(find.text('Next.js'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Next.js'))).brightness,
      Brightness.dark,
    );
  });
}

Color _rowBackground(WidgetTester tester, String value) {
  final row = find.byWidgetPredicate(
    (widget) => widget is DComboboxItem<String> && widget.option.value == value,
  );
  final background = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.position == DecorationPosition.background,
          ),
        )
        .first,
  );
  return (background.decoration as BoxDecoration).color!;
}

@immutable
class _Choice {
  const _Choice(this.id);

  final String id;
}
