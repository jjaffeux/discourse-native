import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _entries = <DNativeSelectEntry<String>>[
  DNativeSelectOption(value: 'apple', label: 'Apple'),
  DNativeSelectOption(value: 'banana', label: 'Banana'),
  DNativeSelectOption(value: 'grape', label: 'Grape', enabled: false),
  DNativeSelectOptGroup(
    label: 'Vegetables',
    enabled: false,
    options: [DNativeSelectOption(value: 'carrot', label: 'Carrot')],
  ),
];

Widget _app(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  ThemeData? theme,
  bool reduced = false,
  double width = 240,
}) => MaterialApp(
  theme: theme ?? ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduced,
      ),
      child: Directionality(
        textDirection: direction,
        child: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

FormFieldState<String> _state(WidgetTester tester) =>
    tester.state<FormFieldState<String>>(
      find.byWidgetPredicate((w) => w is FormField<String>),
    );
Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.byType(MenuAnchor));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'content width stays stable across selections and expanded fills its parent',
    (tester) async {
      await tester.pumpWidget(
        _app(
          DNativeSelect<String>(
            placeholder: 'Pick',
            entries: _entries,
            onChanged: (_) {},
          ),
        ),
      );
      final width = tester.getSize(find.byType(MenuAnchor)).width;
      expect(width, lessThan(240));
      await _pick(tester, 'Apple');
      expect(tester.getSize(find.byType(MenuAnchor)).width, width);
      await tester.pumpWidget(
        _app(
          DNativeSelect<String>(
            isExpanded: true,
            entries: _entries,
            onChanged: (_) {},
          ),
        ),
      );
      expect(tester.getSize(find.byType(MenuAnchor)).width, 240);
    },
  );

  testWidgets(
    'type-ahead cycles repeated letters skips disabled groups and commits a prefix from the menu',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      const entries = <DNativeSelectEntry<String>>[
        DNativeSelectOption(value: 'apple', label: 'Apple'),
        DNativeSelectOption(value: 'banana', label: 'Banana'),
        DNativeSelectOption(
          value: 'blackberry',
          label: 'Blackberry',
          enabled: false,
        ),
        DNativeSelectOption(value: 'blueberry', label: 'Blueberry'),
        DNativeSelectOptGroup(
          label: 'B vegetables',
          options: [DNativeSelectOption(value: 'broccoli', label: 'Broccoli')],
        ),
        DNativeSelectOptGroup(
          label: 'B unavailable',
          enabled: false,
          options: [DNativeSelectOption(value: 'beet', label: 'Beet')],
        ),
      ];
      await tester.pumpWidget(
        _app(
          DNativeSelect<String>(
            focusNode: focus,
            initialValue: 'apple',
            entries: entries,
            onChanged: (_) {},
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      for (final expected in ['banana', 'blueberry', 'broccoli', 'banana']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
        await tester.pump();
        expect(_state(tester).value, expected);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL, character: 'l');
      await tester.pumpAndSettle();
      expect(_state(tester).value, 'banana');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_state(tester).value, 'blueberry');
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(() => focus.requestFocus(), returnsNormally);
    },
  );

  testWidgets(
    'uncontrolled select validates saves and resets the mount-time default',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? saved;
      String? initial = 'apple';
      late StateSetter rebuild;
      final changes = <String?>[];
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Form(
                key: form,
                child: DNativeSelect<String>(
                  initialValue: initial,
                  entries: _entries,
                  onChanged: changes.add,
                  validator: (v) => v == null ? 'Required' : null,
                  onSaved: (v) => saved = v,
                ),
              );
            },
          ),
        ),
      );
      await _pick(tester, 'Banana');
      expect(_state(tester).value, 'banana');
      form.currentState!.save();
      expect(saved, 'banana');
      rebuild(() => initial = 'banana');
      await tester.pump();
      form.currentState!.reset();
      expect(_state(tester).value, 'apple');
      expect(changes, ['banana', 'apple']);
      await tester.pump();
      await _pick(tester, 'Select an option');
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      form.currentState!.reset();
      await tester.pump();
      expect(find.text('Required'), findsNothing);
    },
  );

  testWidgets(
    'controlled decline and reset keep accepted values synchronously in Form callbacks',
    (tester) async {
      final form = GlobalKey<FormState>();
      final observed = <String?>[];
      final proposed = <String?>[];
      final validated = <String?>[];
      String? saved;
      String? accepted = 'banana';
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Form(
                key: form,
                onChanged: () => observed.add(_state(tester).value),
                child: DNativeSelect<String>.controlled(
                  value: accepted,
                  initialValue: 'apple',
                  entries: _entries,
                  validator: (v) {
                    validated.add(v);
                    return null;
                  },
                  onSaved: (v) => saved = v,
                  onChanged: (v) {
                    proposed.add(v);
                    observed.add(_state(tester).value);
                    form.currentState!.save();
                    form.currentState!.validate();
                  },
                ),
              );
            },
          ),
        ),
      );
      await _pick(tester, 'Apple');
      expect(proposed, ['apple']);
      expect(observed, everyElement('banana'));
      expect(validated, everyElement('banana'));
      expect(saved, 'banana');
      form.currentState!.reset();
      expect(_state(tester).value, 'banana');
      expect(saved, 'banana');
      expect(observed, everyElement('banana'));
      expect(validated, everyElement('banana'));
      rebuild(() => accepted = 'apple');
      await tester.pump();
      form.currentState!.save();
      expect(saved, 'apple');
      expect(_state(tester).value, 'apple');
    },
  );

  testWidgets('disabled option and group cannot change the selection', (
    tester,
  ) async {
    final changes = <String?>[];
    await tester.pumpWidget(
      _app(
        DNativeSelect<String>(
          entries: _entries,
          initialValue: 'apple',
          onChanged: changes.add,
        ),
      ),
    );
    await _pick(tester, 'Carrot');
    expect(changes, isEmpty);
    expect(_state(tester).value, 'apple');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _pick(tester, 'Grape');
    expect(changes, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(const DNativeSelect<String>(entries: _entries, onChanged: null)),
    );
    await tester.tap(find.byType(DNativeSelect<String>));
    await tester.pumpAndSettle();
    expect(find.text('Vegetables').hitTestable(), findsNothing);
  });

  testWidgets('keyboard opens selects dismisses and restores borrowed focus', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        DNativeSelect<String>(
          focusNode: focus,
          entries: _entries,
          initialValue: 'apple',
          onChanged: (_) {},
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_state(tester).value, 'banana');
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(() => focus.requestFocus(), returnsNormally);
  });

  testWidgets(
    'standard small and large text retain reference geometry and RTL layout',
    (tester) async {
      for (final size in DNativeSelectSize.values) {
        await tester.pumpWidget(
          _app(
            DNativeSelect<String>(
              size: size,
              entries: _entries,
              onChanged: (_) {},
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(DNativeSelect<String>)).height,
          size == DNativeSelectSize.small ? 28 : 32,
        );
      }
      await tester.pumpWidget(
        _app(
          DNativeSelect<String>(entries: _entries, onChanged: (_) {}),
          direction: TextDirection.rtl,
          scale: 2.5,
          reduced: true,
          width: 150,
        ),
      );
      expect(tester.getSize(find.byType(DNativeSelect<String>)).height, 60);
      expect(tester.takeException(), isNull);
      await _pick(tester, 'Banana');
      expect(_state(tester).value, 'banana');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the invisible iOS touch padding opens the popup and label names the control',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _app(
          DNativeSelect<String>(
            label: 'Fruit',
            isRequired: true,
            entries: _entries,
            onChanged: (_) {},
          ),
          theme: ThemeData(platform: TargetPlatform.iOS),
        ),
      );
      final field = find.byType(DNativeSelect<String>);
      final rect = tester.getRect(field);
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
      await tester.pumpAndSettle();
      expect(find.text('Vegetables').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Fruit')), findsWidgets);
      semantics.dispose();
    },
  );

  testWidgets(
    'palette direction and text scale updates keep the open popup usable',
    (tester) async {
      final light = ThemeData(platform: TargetPlatform.macOS);
      final dark = ThemeData.dark().copyWith(platform: TargetPlatform.macOS);
      Widget build(ThemeData theme) => _app(
        DNativeSelect<String>(entries: _entries, onChanged: (_) {}),
        theme: theme,
        direction: theme.brightness == Brightness.dark
            ? TextDirection.rtl
            : TextDirection.ltr,
        scale: theme.brightness == Brightness.dark ? 1.5 : 1,
      );
      await tester.pumpWidget(build(light));
      await tester.tap(find.byType(DNativeSelect<String>));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(dark));
      await tester.pumpAndSettle();
      expect(find.text('Vegetables').hitTestable(), findsOneWidget);
      final menu = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
      expect(
        menu.style!.backgroundColor!.resolve({}),
        dark.colorScheme.surface,
      );
      final optionContext = tester.element(find.text('Vegetables').last);
      expect(Directionality.of(optionContext), TextDirection.rtl);
      expect(MediaQuery.textScalerOf(optionContext).scale(14), 21);
      expect(
        tester
            .widgetList<Material>(
              find.ancestor(
                of: find.text('Vegetables'),
                matching: find.byType(Material),
              ),
            )
            .map((material) => material.color),
        contains(dark.colorScheme.surface),
      );
      await tester.ensureVisible(find.text('Banana').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banana').last);
      await tester.pumpAndSettle();
      expect(_state(tester).value, 'banana');
    },
  );
}
