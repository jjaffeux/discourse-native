import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/keyboard_navigation.dart';
import 'package:discourse_native/src/styleguide/examples/radio_group_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Directionality(textDirection: direction, child: child),
  ),
);
const choices = Column(
  children: [
    DRadioGroupItem(value: 'a', label: Text('Alpha')),
    DRadioGroupItem(value: 'b', label: Text('Beta'), enabled: false),
    DRadioGroupItem(value: 'c', label: Text('Charlie')),
  ],
);
void main() {
  testWidgets('label activation updates and reset restores initial selection', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? saved;
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DRadioGroup<String>(
            initialValue: 'a',
            onSaved: (v) => saved = v,
            child: choices,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    form.currentState!.save();
    expect(saved, 'c');
    form.currentState!.reset();
    await tester.pump();
    form.currentState!.save();
    expect(saved, 'a');
  });
  testWidgets('controlled rejection does not change selection or saved value', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? request;
    String? saved;
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DRadioGroup<String>.controlled(
            groupValue: 'a',
            onChanged: (v) => request = v,
            onSaved: (v) => saved = v,
            child: choices,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    form.currentState!.save();
    expect(request, 'c');
    expect(saved, 'a');
  });
  testWidgets(
    'controlled reset preserves accepted value until parent accepts',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? accepted = 'c';
      String? requested;
      String? saved;
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Form(
                key: form,
                child: DRadioGroup<String>.controlled(
                  groupValue: accepted,
                  initialValue: 'a',
                  onChanged: (value) => requested = value,
                  onSaved: (value) => saved = value,
                  validator: (value) => value == accepted ? null : 'Mismatch',
                  child: choices,
                ),
              );
            },
          ),
        ),
      );
      form.currentState!.reset();
      await tester.pump();
      expect(requested, 'a');
      form.currentState!.save();
      expect(saved, 'c');
      expect(form.currentState!.validate(), true);
      update(() => accepted = requested);
      await tester.pump();
      form.currentState!.save();
      expect(saved, 'a');
      expect(form.currentState!.validate(), true);
    },
  );
  for (final direction in TextDirection.values) {
    testWidgets('arrows wrap and skip disabled options in $direction', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        host(
          DRadioGroup<String>(
            initialValue: 'a',
            onChanged: (v) => selected = v,
            child: choices,
          ),
          direction: direction,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, 'c');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(selected, 'a');
      await tester.sendKeyEvent(
        direction == TextDirection.rtl
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight,
      );
      await tester.pump();
      expect(selected, 'c');
    });
  }
  testWidgets(
    'validation error clears after selection and reset notifies owner',
    (tester) async {
      final form = GlobalKey<FormState>();
      String? value;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => Form(
              key: form,
              child: DRadioGroup<String>.controlled(
                groupValue: value,
                onChanged: (v) => setState(() => value = v),
                validator: (v) => v == null ? 'Choose one' : null,
                child: choices,
              ),
            ),
          ),
        ),
      );
      expect(form.currentState!.validate(), false);
      await tester.pump();
      expect(find.text('Choose one'), findsOneWidget);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      expect(form.currentState!.validate(), true);
      await tester.pump();
      expect(find.text('Choose one'), findsNothing);
      form.currentState!.reset();
      await tester.pump();
      expect(value, isNull);
    },
  );
  testWidgets(
    'disabled group and item reject taps and expose radio semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      String? value;
      await tester.pumpWidget(
        host(
          DRadioGroup<String>(
            enabled: false,
            initialValue: 'a',
            onChanged: (v) => value = v,
            child: choices,
          ),
        ),
      );
      await tester.tap(find.text('Charlie'));
      await tester.pump();
      expect(value, isNull);
      expect(
        tester.getSemantics(find.byType(RawRadio<String>).first),
        matchesSemantics(
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: false,
          isInMutuallyExclusiveGroup: true,
          label: 'Alpha',
          textDirection: TextDirection.ltr,
        ),
      );
      semantics.dispose();
    },
  );
  testWidgets('live palette keeps selection and exact radio geometry', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    String? saved;
    var theme = ThemeData(
      platform: TargetPlatform.macOS,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
    );
    Widget build() => host(
      Form(
        key: form,
        child: DRadioGroup<String>(
          initialValue: 'a',
          onSaved: (value) => saved = value,
          child: choices,
        ),
      ),
      theme: theme,
    );
    await tester.pumpWidget(build());
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    theme = ThemeData(
      platform: TargetPlatform.macOS,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.purple,
        brightness: Brightness.dark,
      ),
    );
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    form.currentState!.save();
    expect(saved, 'c');
    final circles = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    expect(circles, findsNWidgets(4));
    expect(
      circles
          .evaluate()
          .map((element) => tester.getSize(find.byWidget(element.widget)))
          .where((size) => size == const Size(16, 16))
          .length,
      3,
    );
    final selected = tester
        .widgetList<Container>(circles)
        .where(
          (widget) =>
              (widget.decoration! as BoxDecoration).color ==
              theme.colorScheme.primary,
        );
    expect(selected.length, 1);
    final dot = circles.evaluate().where(
      (element) =>
          tester.getSize(find.byWidget(element.widget)) == const Size(8, 8),
    );
    expect(dot.length, 1);
  });
  testWidgets(
    'radio focus blocks application reading shortcuts and Tab leaves group',
    (tester) async {
      final node = FocusNode();
      final after = FocusNode();
      addTearDown(node.dispose);
      addTearDown(after.dispose);
      late BuildContext reading;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              reading = context;
              return Column(
                children: [
                  DRadioGroup<String>(
                    child: Column(
                      children: [
                        DRadioGroupItem(
                          value: 'a',
                          label: const Text('Alpha'),
                          focusNode: node,
                        ),
                        const DRadioGroupItem(value: 'b', label: Text('Beta')),
                      ],
                    ),
                  ),
                  TextButton(
                    focusNode: after,
                    onPressed: () {},
                    child: const Text('After'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(navigationShortcutsAllowed(reading), false);
      expect(navigationShortcutsAllowed(reading, activation: true), false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(after.hasFocus, true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('borrowed focus survives replacement and disposal', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget build(FocusNode node) => host(
      DRadioGroup<String>(
        child: DRadioGroupItem(
          value: 'a',
          label: const Text('Alpha'),
          focusNode: node,
        ),
      ),
    );
    await tester.pumpWidget(build(first));
    await tester.pumpWidget(build(second));
    second.requestFocus();
    await tester.pump();
    expect(second.hasFocus, true);
    await tester.pumpWidget(const SizedBox());
    first.addListener(() {});
    second.addListener(() {});
  });
  testWidgets('all real examples fit narrow large-text RTL and touch bounds', (
    tester,
  ) async {
    for (final example in radioGroupExamples.examples) {
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: SizedBox(
                width: 260,
                child: Builder(builder: example.builder),
              ),
            ),
          ),
          direction: TextDirection.rtl,
          theme: ThemeData(platform: TargetPlatform.iOS),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
      for (final element in find.byType(RawRadio<String>).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}
