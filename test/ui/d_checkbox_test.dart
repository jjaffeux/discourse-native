import 'dart:ui'
    show
        CheckedState,
        SemanticsAction,
        SemanticsActionEvent,
        SemanticsValidationResult;
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  TargetPlatform platform = TargetPlatform.macOS,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: SizedBox(width: 360, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('controlled form does not retain a value the caller declined', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    bool? proposed;
    bool? saved;
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DCheckboxFormField.controlled(
            value: false,
            onChanged: (v) => proposed = v,
            title: const Text('Declined'),
            onSaved: (v) => saved = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Declined'));
    await tester.pump();
    expect(proposed, true);
    expect(tester.widget<DCheckbox>(find.byType(DCheckbox)).value, false);
    form.currentState!.save();
    expect(saved, false);
  });

  testWidgets(
    'readOnly retains focus without pointer, Space or semantic mutation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final focus = FocusNode();
        var changes = 0;
        await tester.pumpWidget(
          host(
            DCheckbox(
              value: true,
              readOnly: true,
              focusNode: focus,
              title: const Text('Read only'),
              onChanged: (_) => changes++,
            ),
          ),
        );
        await tester.tap(find.text('Read only'));
        await tester.pump();
        expect(focus.hasFocus, true);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(changes, 0);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Read only'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          false,
        );
        await tester.pumpWidget(const SizedBox());
        focus.dispose();
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'pointer transfers focus before Space; mixed activates to checked',
    (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      bool? secondValue;
      var firstChanges = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => Column(
              children: [
                DCheckbox(
                  value: false,
                  focusNode: first,
                  title: const Text('First'),
                  onChanged: (_) => firstChanges++,
                ),
                DCheckbox(
                  value: secondValue,
                  tristate: true,
                  focusNode: second,
                  title: const Text('Second'),
                  onChanged: (v) => update(() => secondValue = v),
                ),
              ],
            ),
          ),
        ),
      );
      first.requestFocus();
      await tester.pump();
      await tester.tap(find.text('Second'));
      await tester.pump();
      expect(second.hasFocus, true);
      expect(secondValue, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(secondValue, false);
      expect(firstChanges, 0);
      await tester.pumpWidget(const SizedBox());
      first.dispose();
      second.dispose();
    },
  );

  testWidgets('controlled form follows external updates and reset callback', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    final value = ValueNotifier<bool?>(false);
    bool? saved;
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<bool?>(
          valueListenable: value,
          builder: (_, current, _) => Form(
            key: form,
            child: DCheckboxFormField.controlled(
              value: current,
              onChanged: (next) => value.value = next,
              title: const Text('Controlled'),
              onSaved: (next) => saved = next,
            ),
          ),
        ),
      ),
    );
    value.value = true;
    await tester.pump();
    form.currentState!.save();
    expect(saved, true);
    form.currentState!.reset();
    await tester.pump();
    expect(value.value, false);
    await tester.pumpWidget(const SizedBox());
    value.dispose();
  });

  testWidgets(
    'controlled label, Space and semantic action share one value owner',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final focus = FocusNode();
      addTearDown(focus.dispose);
      bool? value = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => DCheckbox(
              value: value,
              focusNode: focus,
              title: const Text('Accept terms'),
              onChanged: (next) => update(() => value = next),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Accept terms'));
      await tester.pump();
      expect(value, true);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(value, false);
      final node = tester.getSemantics(find.bySemanticsLabel('Accept terms'));
      expect(
        node.getSemanticsData().flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pump();
      expect(value, true);
      await tester.pumpWidget(const SizedBox());
      focus.addListener(() {}); // Borrowed node remains usable.
      semantics.dispose();
    },
  );

  testWidgets(
    'default state toggles without cycling to mixed; disabled mixed preserves state',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          const DCheckbox.defaultValue(tristate: true, title: Text('Choice')),
        ),
      );
      for (final expected in [
        CheckedState.isTrue,
        CheckedState.isFalse,
        CheckedState.isTrue,
      ]) {
        await tester.tap(find.text('Choice'));
        await tester.pump();
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Choice'))
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          expected,
        );
      }
      await tester.pumpWidget(
        host(
          const DCheckbox(
            value: null,
            tristate: true,
            onChanged: null,
            title: Text('Disabled'),
          ),
        ),
      );
      await tester.tap(find.text('Disabled'));
      await tester.pump();
      final data = tester
          .getSemantics(find.bySemanticsLabel('Disabled'))
          .getSemanticsData();
      expect(data.flagsCollection.isChecked, CheckedState.mixed);
      expect(data.hasAction(SemanticsAction.tap), false);
      semantics.dispose();
    },
  );

  testWidgets('form validates, recovers, saves and resets its initial value', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    bool? saved;
    bool? changed;
    await tester.pumpWidget(
      host(
        Form(
          key: form,
          child: DCheckboxFormField(
            title: const Text('Consent'),
            validator: (v) => v == true ? null : 'Consent required',
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onSaved: (v) => saved = v,
            onChanged: (v) => changed = v,
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), false);
    await tester.pump();
    expect(find.text('Consent required'), findsOneWidget);
    await tester.tap(find.text('Consent'));
    await tester.pump();
    expect(find.text('Consent required'), findsNothing);
    expect(changed, true);
    form.currentState!.save();
    expect(saved, true);
    form.currentState!.reset();
    await tester.pump();
    expect(changed, false);
    expect(tester.widget<DCheckbox>(find.byType(DCheckbox)).value, false);
  });

  testWidgets(
    'compact artwork with touch bounds, long RTL labels and live invalid semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          Center(
            child: DCheckbox(
              value: false,
              onChanged: (_) {},
              semanticLabel: 'Standalone',
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(GestureDetector)), const Size(40, 32));
      await tester.pumpWidget(
        host(
          Center(
            child: DCheckbox(
              value: false,
              onChanged: (_) {},
              semanticLabel: 'Standalone',
            ),
          ),
          platform: TargetPlatform.iOS,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GestureDetector)), const Size(48, 48));
      await tester.pumpWidget(
        host(
          DCheckbox(
            value: true,
            onChanged: (_) {},
            invalid: true,
            title: const Text(
              'قبول الشروط والأحكام الطويلة حتى نتمكن من متابعة جميع الأخبار والتحديثات',
            ),
            subtitle: const Text(
              'A long description that wraps without clipping at large text sizes.',
            ),
          ),
          direction: TextDirection.rtl,
          scale: 2,
        ),
      );
      expect(tester.takeException(), null);
      final data = tester
          .getSemantics(find.bySemanticsLabel(RegExp("قبول")))
          .getSemanticsData();
      expect(data.validationResult, SemanticsValidationResult.invalid);
      semantics.dispose();
    },
  );
}
