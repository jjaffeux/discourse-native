import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/field_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  double width = 500,
  double scale = 1,
  bool rtl = false,
}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final example in fieldExamples.examples) {
    testWidgets('${example.title} wraps at 280px with 200% RTL text', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Builder(builder: example.builder),
          width: 280,
          scale: 2,
          rtl: true,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(example.code, contains('void main()'));
    });
  }
  testWidgets(
    'merged Input label focuses and retains the editable name and help',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(host(const FieldEditorsExample()));
        await tester.tap(find.text('Username'));
        await tester.enterText(find.byType(TextField).first, 'reader');
        await tester.pump();
        final control = find.byWidgetPredicate(
          (widget) => widget is DFieldControl && widget.label == 'Username',
        );
        final node = tester.getSemantics(control);
        expect(node.label, 'Username');
        final editor = node.getSemanticsData();
        expect(editor.value, 'reader');
        expect(node.hint, 'Choose a unique username for your account.');
        expect(editor.hasAction(SemanticsAction.setText), isTrue);
        expect(
          tester.widget<DInput>(find.byType(DInput).first).focusNode!.hasFocus,
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('merged Checkbox row toggles once by label and Space', (
    tester,
  ) async {
    await tester.pumpWidget(host(const FieldCheckboxExample()));
    await tester.tap(find.text('Hard disks'));
    await tester.pump();
    expect(
      tester.widget<DCheckbox>(find.byType(DCheckbox).first).value,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(
      tester.widget<DCheckbox>(find.byType(DCheckbox).first).value,
      isFalse,
    );
  });

  testWidgets('merged Switch tile keeps one compact row activation owner', (
    tester,
  ) async {
    await tester.pumpWidget(host(const FieldNotificationsExample()));
    final control = find.byType(DSwitch);
    expect(control, findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(tester.widget<DSwitch>(control).value, isFalse);

    await tester.tap(find.text('Multi-factor authentication'));
    await tester.pump();

    expect(tester.widget<DSwitch>(control).value, isTrue);
  });

  testWidgets('merged Slider keeps each range thumb as its own owner', (
    tester,
  ) async {
    await tester.pumpWidget(host(const FieldSliderExample()));
    final slider = tester.widget<DMultiSlider>(find.byType(DMultiSlider));
    expect(slider.values, const [200, 800]);
    expect(slider.semanticLabels, const ['Minimum price', 'Maximum price']);
    expect(find.byType(RangeSlider), findsNothing);
  });

  testWidgets(
    'merged Radio choice label focuses its item and arrows preserve group ownership',
    (tester) async {
      await tester.pumpWidget(host(const FieldChoiceExample()));
      await tester.ensureVisible(find.text('Virtual Machine'));
      await tester.tap(find.text('Virtual Machine'));
      await tester.pump();
      final item = tester.widget<DRadioGroupItem<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DRadioGroupItem<String> &&
              widget.value == 'Virtual Machine',
        ),
      );
      expect(item.focusNode!.hasFocus, isTrue);
      expect(
        tester
            .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>).last)
            .groupValue,
        'Virtual Machine',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        tester
            .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>).last)
            .groupValue,
        'Kubernetes',
      );
      await tester.tap(
        find.text('Unavailable environment'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(
        tester
            .widget<DRadioGroup<String>>(find.byType(DRadioGroup<String>).last)
            .groupValue,
        'Kubernetes',
      );
    },
  );

  testWidgets(
    'responsive example validates saves and resets its sole field owner',
    (tester) async {
      await tester.pumpWidget(host(const FieldResponsiveExample()));
      await tester.tap(find.text('Submit profile'));
      await tester.pump();
      expect(find.text('Provide your full name.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Evil Rabbit');
      await tester.tap(find.text('Submit profile'));
      await tester.pump();
      expect(find.text('Saved locally: Evil Rabbit'), findsOneWidget);
      await tester.pumpWidget(
        host(const FieldResponsiveExample(), width: 280, scale: 2),
      );
      expect(find.text('Evil Rabbit'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Reset profile'));
      await tester.tap(find.text('Reset profile'));
      await tester.pump();
      expect(find.text('Saved locally: Evil Rabbit'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.text('Provide your full name.'), findsNothing);
    },
  );
}
