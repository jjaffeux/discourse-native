import 'package:discourse_native/discourse_ui.dart';
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
    await tester.tap(find.byIcon(Icons.close));
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
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(values, isEmpty);
  });

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
  });

  testWidgets('disabled input cannot open', (tester) async {
    await tester.pumpWidget(_app(_single(enabled: false)));
    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Next.js'), findsNothing);
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
