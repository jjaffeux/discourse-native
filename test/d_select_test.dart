import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/select_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Select registers implemented styleguide examples', () {
    expect(componentExamples['select'], same(selectExamples));
    expect(selectExamples.status, ComponentStatus.implemented);
    expect(selectExamples.examples.map((example) => example.title), [
      'Default',
      'Align Item With Trigger',
      'Groups',
      'Scrollable',
      'Disabled',
      'Invalid and Form',
      'RTL',
      'Multiple and custom value',
      'Button Group composition',
    ]);
  });

  testWidgets('examples mount at narrow 200 percent RTL in live palettes', (
    tester,
  ) async {
    for (final example in selectExamples.examples) {
      for (final theme in [
        AppTheme.light,
        AppTheme.dark,
        StyleguideTheme.forest.resolve(AppTheme.light),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: 216,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('open options inherit live theme changes', (tester) async {
    final dark = ValueNotifier(false);
    final optionKey = GlobalKey();
    addTearDown(dark.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: dark,
        builder: (context, value, child) => MaterialApp(
          theme: value ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: Center(
              child: DSelect<String>(
                initialValue: 'apple',
                semanticLabel: 'Fruit',
                entries: [
                  DSelectOption(
                    value: 'apple',
                    label: 'Apple',
                    child: SizedBox(key: optionKey, child: const Text('Apple')),
                  ),
                ],
                onChanged: _noopString,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    final lightBackground = DTokens.of(optionKey.currentContext!).background;

    dark.value = true;
    await tester.pumpAndSettle();

    expect(find.byType(DPopoverContent), findsOneWidget);
    expect(
      DTokens.of(optionKey.currentContext!).background,
      isNot(lightBackground),
    );
  });

  testWidgets(
    'keyboard opens, highlights with typeahead, selects and restores focus',
    (tester) async {
      String? value = 'apple';
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DSelect<String>(
            value: value,
            semanticLabel: 'Fruit',
            entries: const [
              DSelectOption(
                value: 'apple',
                label: 'Apple',
                child: Text('Apple'),
              ),
              DSelectOption(
                value: 'banana',
                label: 'Banana',
                child: Text('Banana'),
              ),
              DSelectOption(
                value: 'blueberry',
                label: 'Blueberry',
                child: Text('Blueberry'),
              ),
            ],
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Banana'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(value, 'banana');
      expect(find.text('Banana'), findsOneWidget);
    },
  );

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'pointer highlight is visible without overlap in ${theme.brightness}',
      (tester) async {
        await _mount(
          tester,
          DSelect<String>.controlled(
            value: 'apple',
            semanticLabel: 'Fruit',
            entries: const [
              DSelectOption(
                value: 'apple',
                label: 'Apple',
                child: Text('Apple'),
              ),
              DSelectOption(
                value: 'banana',
                label: 'Banana',
                child: Text('Banana'),
              ),
            ],
            onChanged: _noopString,
          ),
          theme: theme,
        );

        await tester.tap(find.text('Apple'));
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(find.text('Banana')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          tester.widget(
            find.byKey(
              const ValueKey<(String, String?)>(('d-select-item', 'banana')),
            ),
          ),
          isA<Container>(),
        );
        expect(_rowBackground(tester, 'apple').a, 0);
        expect(_rowBackground(tester, 'banana'), theme.hoverColor);
        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pumpAndSettle();
        expect(_rowBackground(tester, 'banana'), theme.hoverColor);
        await mouse.moveTo(const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(_rowBackground(tester, 'banana'), Colors.transparent);
        await mouse.moveTo(tester.getCenter(find.text('Banana')));
        await tester.pumpAndSettle();

        expect(
          _rowBackground(tester, 'banana'),
          isNot(theme.extension<DTokens>()!.surface),
        );
      },
    );
  }

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'Select rows match Dropdown Menu styling in ${theme.brightness}',
      (tester) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await _mount(
          tester,
          DDropdownMenu(
            defaultOpen: true,
            content: DDropdownMenuContent(
              width: 180,
              children: [
                DDropdownMenuCheckboxItem(
                  checked: true,
                  onChanged: (_) {},
                  child: const Text('Reference'),
                ),
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (_, state) =>
                  DButton(label: const Text('Open'), onPressed: state.toggle),
            ),
          ),
          theme: theme,
        );
        await tester.pumpAndSettle();
        final referenceText = find.text('Reference');
        final referenceRow = find
            .ancestor(
              of: referenceText,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container && widget.decoration is BoxDecoration,
              ),
            )
            .first;
        await mouse.moveTo(tester.getCenter(referenceText));
        await tester.pumpAndSettle();
        final decoration = tester.widget<Container>(referenceRow).decoration;
        final padding = tester.widget<Container>(referenceRow).padding;
        final textStyle = DefaultTextStyle.of(
          tester.element(referenceText),
        ).style;
        final referenceBounds = tester.getRect(referenceRow);
        final referencePopup = tester.getRect(find.byType(DPopoverContent));
        final inset = referenceBounds.left - referencePopup.left;
        await tester.pumpWidget(const SizedBox());
        await _mount(
          tester,
          DSelect<String>(
            initialValue: 'reference',
            width: 180,
            entries: const [
              DSelectOption(
                value: 'reference',
                label: 'Reference',
                child: Text('Reference'),
              ),
            ],
            onChanged: _noopString,
          ),
          theme: theme,
        );
        await tester.tap(find.text('Reference'));
        await tester.pumpAndSettle();
        final row = find.byKey(
          const ValueKey<(String, String?)>(('d-select-item', 'reference')),
        );
        await mouse.moveTo(tester.getCenter(row));
        await tester.pumpAndSettle();
        final selectContainer = tester.widget<Container>(row);
        expect(selectContainer.decoration, decoration);
        expect(selectContainer.padding, padding);
        final actualText = find.descendant(
          of: row,
          matching: find.text('Reference'),
        );
        final actualStyle = DefaultTextStyle.of(
          tester.element(actualText),
        ).style;
        expect(actualStyle.color, textStyle.color);
        expect(actualStyle.fontSize, textStyle.fontSize);
        expect(actualStyle.height, textStyle.height);
        final popup = tester.getRect(find.byType(DPopoverContent));
        expect(tester.getRect(row).left - popup.left, inset);
        expect(popup.right - tester.getRect(row).right, inset);
      },
    );
  }

  testWidgets('disabled pointer highlighting preserves one keyboard row', (
    tester,
  ) async {
    await _mount(
      tester,
      DSelect<String>.controlled(
        value: 'apple',
        semanticLabel: 'Fruit',
        highlightItemOnHover: false,
        entries: const [
          DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
          DSelectOption(
            value: 'banana',
            label: 'Banana',
            child: Text('Banana'),
          ),
        ],
        onChanged: _noopString,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Banana')));
    await tester.pumpAndSettle();

    expect(_rowBackground(tester, 'apple').a, greaterThan(0));
    expect(_rowBackground(tester, 'banana').a, 0);
  });

  testWidgets(
    'closed trigger typeahead commits enabled matches without opening',
    (tester) async {
      String? value;
      DSelectChangeReason? reason;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DSelect<String>.controlled(
            value: value,
            semanticLabel: 'Fruit',
            entries: const [
              DSelectOption(
                value: 'apricot',
                label: 'Apricot',
                enabled: false,
                child: Text('Apricot'),
              ),
              DSelectOption(
                value: 'apple',
                label: 'Apple',
                child: Text('Apple'),
              ),
              DSelectOption(
                value: 'avocado',
                label: 'Avocado',
                child: Text('Avocado'),
              ),
            ],
            onChanged: (next) => setState(() => value = next),
            onChangedWithReason: (next, nextReason) => reason = nextReason,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(value, 'apple');
      expect(find.byType(DPopoverContent), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(value, 'avocado');
      expect(reason, DSelectChangeReason.keyboard);
      expect(find.byType(DPopoverContent), findsNothing);
    },
  );

  testWidgets('trigger arrow keys open at the first and last enabled item', (
    tester,
  ) async {
    String? value;
    late StateSetter update;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return DSelect<String>.controlled(
            value: value,
            semanticLabel: 'Fruit',
            entries: const [
              DSelectOption(
                value: 'apple',
                label: 'Apple',
                child: Text('Apple'),
              ),
              DSelectOption(
                value: 'banana',
                label: 'Banana',
                enabled: false,
                child: Text('Banana'),
              ),
              DSelectOption(
                value: 'grapes',
                label: 'Grapes',
                child: Text('Grapes'),
              ),
            ],
            onChanged: (next) => setState(() => value = next),
          );
        },
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'DSelect option 0');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, 'apple');

    update(() => value = null);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, 'grapes');
  });

  testWidgets('space remains part of an active popup typeahead query', (
    tester,
  ) async {
    String? value = 'paris';
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DSelect<String>.controlled(
          value: value,
          semanticLabel: 'City',
          entries: const [
            DSelectOption(value: 'paris', label: 'Paris', child: Text('Paris')),
            DSelectOption(
              value: 'new-delhi',
              label: 'New Delhi',
              child: Text('New Delhi'),
            ),
            DSelectOption(
              value: 'new-york',
              label: 'New York',
              child: Text('New York'),
            ),
          ],
          onChanged: (next) => setState(() => value = next),
        ),
      ),
    );

    await tester.tap(find.text('Paris'));
    await tester.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyY,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();

    expect(value, 'paris');
    expect(find.byType(DPopoverContent), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, 'new-york');
  });

  testWidgets('read-only closed trigger ignores typeahead commits', (
    tester,
  ) async {
    var value = 'apple';
    await _mount(
      tester,
      DSelect<String>.controlled(
        value: value,
        readOnly: true,
        semanticLabel: 'Fruit',
        entries: const [
          DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
          DSelectOption(
            value: 'banana',
            label: 'Banana',
            child: Text('Banana'),
          ),
        ],
        onChanged: (next) => value = next ?? value,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(value, 'apple');
    expect(find.byType(DPopoverContent), findsNothing);
  });

  testWidgets('disabled item and disabled trigger ignore activation', (
    tester,
  ) async {
    String? value = 'apple';
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            DSelect<String>(
              value: 'locked',
              enabled: false,
              semanticLabel: 'Locked',
              entries: const [
                DSelectOption(
                  value: 'locked',
                  label: 'Locked',
                  child: Text('Locked'),
                ),
              ],
              onChanged: (next) => setState(() => value = next),
            ),
            DSelect<String>(
              value: value,
              semanticLabel: 'Fruit',
              entries: const [
                DSelectOption(
                  value: 'apple',
                  label: 'Apple',
                  child: Text('Apple'),
                ),
                DSelectOption(
                  value: 'banana',
                  label: 'Banana unavailable',
                  enabled: false,
                  child: Text('Banana unavailable'),
                ),
              ],
              onChanged: (next) => setState(() => value = next),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Locked'));
    await tester.pumpAndSettle();
    expect(find.text('Banana unavailable'), findsNothing);

    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banana unavailable').last);
    await tester.pumpAndSettle();
    expect(value, 'apple');
  });

  testWidgets('form field validates, saves, and resets through Flutter Form', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String saved = 'Not saved';
    await _mount(
      tester,
      Form(
        key: form,
        child: Column(
          children: [
            DSelectField<String>(
              initialValue: null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Fruit',
                hintText: 'Select a fruit',
              ),
              items: const [
                DropdownMenuItem(value: 'apple', child: Text('Apple')),
                DropdownMenuItem(value: 'banana', child: Text('Banana')),
              ],
              validator: (value) =>
                  value == null ? 'Please select a fruit.' : null,
              onSaved: (value) => saved = value ?? 'none',
              onChanged: (_) {},
            ),
            DButton(
              label: const Text('Save'),
              onPressed: form.currentState?.save,
            ),
          ],
        ),
      ),
    );

    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Please select a fruit.'), findsOneWidget);

    await tester.tap(find.text('Select a fruit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banana').last);
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.save();
    expect(saved, 'banana');
    form.currentState!.reset();
    await tester.pump();
    expect(find.text('Select a fruit'), findsOneWidget);
  });

  testWidgets('selected item aligns with trigger until alignment is disabled', (
    tester,
  ) async {
    await _mount(
      tester,
      Center(
        child: DSelect<String>(
          value: 'banana',
          semanticLabel: 'Fruit',
          entries: const [
            DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
            DSelectOption(
              value: 'banana',
              label: 'Banana',
              child: Text('Banana'),
            ),
            DSelectOption(
              value: 'grapes',
              label: 'Grapes',
              child: Text('Grapes'),
            ),
          ],
          onChanged: _noopString,
        ),
      ),
    );
    final triggerCenter = tester.getCenter(find.text('Banana').first);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final selectedCenter = tester.getCenter(find.text('Banana').last);
    expect((selectedCenter.dy - triggerCenter.dy).abs(), lessThanOrEqualTo(4));
  });

  testWidgets('selected last item aligns with the trigger when space permits', (
    tester,
  ) async {
    await _mount(
      tester,
      DSelect<String>.controlled(
        value: 'grapes',
        semanticLabel: 'Fruit',
        entries: const [
          DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
          DSelectOption(
            value: 'banana',
            label: 'Banana',
            child: Text('Banana'),
          ),
          DSelectOption(
            value: 'blueberry',
            label: 'Blueberry',
            child: Text('Blueberry'),
          ),
          DSelectOption(
            value: 'grapes',
            label: 'Grapes',
            child: Text('Grapes'),
          ),
        ],
        onChanged: _noopString,
      ),
    );

    final triggerCenter = tester.getCenter(find.text('Grapes'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final selectedCenter = tester.getCenter(find.text('Grapes').last);
    expect((selectedCenter.dy - triggerCenter.dy).abs(), lessThanOrEqualTo(4));
  });

  testWidgets('caller-owned popup scrolling stays bounded', (tester) async {
    await _mount(
      tester,
      DSelect<int>(
        initialValue: 0,
        semanticLabel: 'Number',
        maxPopupHeight: 120,
        entries: [
          for (var value = 0; value < 30; value++)
            DSelectOption(
              value: value,
              label: 'Number $value',
              child: Text('Number $value'),
            ),
        ],
        onChanged: (_) {},
      ),
    );

    await tester.tap(find.text('Number 0'));
    await tester.pumpAndSettle();

    final content = find.byType(DPopoverContent);
    expect(tester.getSize(content).height, lessThanOrEqualTo(120));
    expect(tester.widget<DPopoverContent>(content).scrollable, isFalse);
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('button-group composition keeps adjacent actions independent', (
    tester,
  ) async {
    final example = selectExamples.examples.firstWhere(
      (example) => example.title == 'Button Group composition',
    );
    await _mount(tester, Builder(builder: example.builder));
    expect(find.byType(DButtonGroup), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Actions: 1, mode: week'), findsOneWidget);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();
    expect(find.text('Actions: 1, mode: month'), findsOneWidget);
  });

  testWidgets('controlled null value selects without changing ownership mode', (
    tester,
  ) async {
    String? value;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DSelect<String>.controlled(
          value: value,
          semanticLabel: 'Fruit',
          entries: const [
            DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
          ],
          onChanged: (next) => setState(() => value = next),
        ),
      ),
    );

    expect(find.text('Select an option'), findsOneWidget);
    await tester.tap(find.text('Select an option'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apple').last);
    await tester.pumpAndSettle();
    expect(value, 'apple');
    expect(find.text('Apple'), findsOneWidget);
  });

  testWidgets('multiple selection toggles items and keeps popup open', (
    tester,
  ) async {
    var values = <String>[];
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DMultiSelect<String>.controlled(
          value: values,
          semanticLabel: 'Languages',
          entries: const [
            DSelectOption(value: 'dart', label: 'Dart', child: Text('Dart')),
            DSelectOption(value: 'ruby', label: 'Ruby', child: Text('Ruby')),
          ],
          onChanged: (next) => setState(() => values = next),
        ),
      ),
    );

    await tester.tap(find.text('Select options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dart').last);
    await tester.pumpAndSettle();
    expect(values, ['dart']);
    expect(find.text('Ruby'), findsOneWidget);
    await tester.tap(find.text('Ruby'));
    await tester.pumpAndSettle();
    expect(values, ['dart', 'ruby']);
    expect(find.text('Dart (+1 more)'), findsOneWidget);
  });

  testWidgets('external controlled opening enables and focuses popup options', (
    tester,
  ) async {
    var open = false;
    String? value = 'apple';
    late StateSetter update;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return DSelect<String>.controlled(
            open: open,
            value: value,
            semanticLabel: 'Fruit',
            entries: const [
              DSelectOption(
                value: 'apple',
                label: 'Apple',
                child: Text('Apple'),
              ),
              DSelectOption(
                value: 'banana',
                label: 'Banana',
                child: Text('Banana'),
              ),
            ],
            onChanged: (next) => setState(() => value = next),
          );
        },
      ),
    );

    update(() => open = true);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('DSelect option '),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(value, 'banana');
  });

  testWidgets(
    'disabled selected option falls back to an enabled focus target',
    (tester) async {
      String? value = 'grapes';
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => DSelect<String>.controlled(
            value: value,
            semanticLabel: 'Fruit',
            entries: const [
              DSelectOption(
                value: 'apple',
                label: 'Apple',
                child: Text('Apple'),
              ),
              DSelectOption(
                value: 'grapes',
                label: 'Grapes',
                enabled: false,
                child: Text('Grapes'),
              ),
            ],
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      );

      await tester.tap(find.text('Grapes'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(value, 'apple');
    },
  );

  testWidgets('repeated-letter typeahead cycles enabled matching options', (
    tester,
  ) async {
    String? value = 'apple';
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DSelect<String>.controlled(
          value: value,
          semanticLabel: 'Fruit',
          entries: const [
            DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
            DSelectOption(
              value: 'apricot',
              label: 'Apricot',
              child: Text('Apricot'),
            ),
            DSelectOption(
              value: 'avocado',
              label: 'Avocado',
              child: Text('Avocado'),
            ),
          ],
          onChanged: (next) => setState(() => value = next),
        ),
      ),
    );

    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(value, 'avocado');
  });

  testWidgets('large text expands trigger and rows without clipping', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: DSelect<String>(
                initialValue: 'apple',
                semanticLabel: 'Fruit',
                entries: const [
                  DSelectOption(
                    value: 'apple',
                    label: 'Apple',
                    child: Text('Apple'),
                  ),
                  DSelectOption(
                    value: 'banana',
                    label: 'Banana',
                    child: Text('Banana'),
                  ),
                ],
                onChanged: _noopString,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('d-select-trigger-visual'))).height,
      greaterThanOrEqualTo(50),
    );
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    final row = find.byKey(
      const ValueKey<(String, String?)>(('d-select-item', 'apple')),
    );
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'initial scroll-down arrow is actionable for an overflowing list',
    (tester) async {
      await _mount(
        tester,
        Theme(
          data: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          child: DSelect<int>(
            initialValue: 0,
            semanticLabel: 'Number',
            maxPopupHeight: 120,
            entries: [
              for (var value = 0; value < 30; value++)
                DSelectOption(
                  value: value,
                  label: 'Number $value',
                  child: Text('Number $value'),
                ),
            ],
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Number 0'));
      await tester.pumpAndSettle();
      final arrow = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Scroll options down',
      );
      expect(arrow, findsOneWidget);
      final before = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      await tester.tap(arrow);
      await tester.pumpAndSettle();
      final after = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      expect(after, greaterThan(before));
    },
  );

  testWidgets('read-only select opens and navigates but cannot mutate', (
    tester,
  ) async {
    var value = 'apple';
    await _mount(
      tester,
      DSelect<String>.controlled(
        value: value,
        readOnly: true,
        semanticLabel: 'Fruit',
        entries: const [
          DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
          DSelectOption(
            value: 'banana',
            label: 'Banana',
            child: Text('Banana'),
          ),
        ],
        onChanged: (next) => value = next ?? value,
      ),
    );

    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banana').last);
    await tester.pumpAndSettle();
    expect(value, 'apple');
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets('dynamic items reconcile while the popup is open', (
    tester,
  ) async {
    late StateSetter update;
    var includeBanana = false;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return DSelect<String>(
            semanticLabel: 'Fruit',
            entries: [
              const DSelectOption(
                value: 'apple',
                label: 'Apple',
                child: Text('Apple'),
              ),
              if (includeBanana)
                const DSelectOption(
                  value: 'banana',
                  label: 'Banana',
                  child: Text('Banana'),
                ),
            ],
            onChanged: (_) {},
          );
        },
      ),
    );

    await tester.tap(find.text('Select an option'));
    await tester.pumpAndSettle();
    update(() => includeBanana = true);
    await tester.pump();
    expect(find.text('Banana'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets(
    'borrowed focus, popover and scroll resources remain caller owned',
    (tester) async {
      final focus = FocusNode();
      final popover = DPopoverController();
      final scroll = ScrollController();
      await _mount(
        tester,
        DSelect<String>(
          focusNode: focus,
          popoverController: popover,
          scrollController: scroll,
          entries: const [
            DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
          ],
          onChanged: (_) {},
        ),
      );
      await tester.pumpWidget(const SizedBox());

      expect(() => focus.requestFocus(), returnsNormally);
      expect(() => popover.open(), returnsNormally);
      expect(() => scroll.dispose(), returnsNormally);
      expect(() => focus.dispose(), returnsNormally);
      expect(() => popover.dispose(), returnsNormally);
    },
  );

  testWidgets('selected overlap falls back near the viewport edge', (
    tester,
  ) async {
    await _mount(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: DSelect<String>.controlled(
          value: 'banana',
          semanticLabel: 'Fruit',
          entries: const [
            DSelectOption(value: 'apple', label: 'Apple', child: Text('Apple')),
            DSelectOption(
              value: 'banana',
              label: 'Banana',
              child: Text('Banana'),
            ),
          ],
          onChanged: _noopString,
        ),
      ),
    );
    final trigger = tester.getRect(find.text('Banana'));
    await tester.tap(find.text('Banana'));
    await tester.pumpAndSettle();
    final popupItem = tester.getRect(find.text('Banana').last);
    expect(popupItem.top, greaterThanOrEqualTo(trigger.bottom));
  });
}

void _noopString(String? _) {}

Color _rowBackground(WidgetTester tester, String value) {
  final row = tester.widget(
    find.byKey(ValueKey<(String, String?)>(('d-select-item', value))),
  );
  final decoration = switch (row) {
    Container(:final decoration) => decoration,
    AnimatedContainer(:final decoration) => decoration,
    _ => throw StateError('Unexpected select row ${row.runtimeType}'),
  };
  return (decoration as BoxDecoration).color!;
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: (theme ?? AppTheme.light).copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
