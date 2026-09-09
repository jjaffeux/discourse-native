import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/select_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
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
      'Button Group handoff',
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
      expect(value, 'blueberry');
      expect(find.text('Blueberry'), findsOneWidget);
    },
  );

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

  testWidgets('button-group handoff keeps adjacent actions independent', (
    tester,
  ) async {
    final example = selectExamples.examples.firstWhere(
      (example) => example.title == 'Button Group handoff',
    );
    await _mount(tester, Builder(builder: example.builder));
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

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
