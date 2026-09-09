import 'dart:ui' show SemanticsValidationResult, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Directionality(
      textDirection: direction,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  testWidgets('uses one native editor for all projected slots', (tester) async {
    await tester.pumpWidget(
      host(
        DInputOTP(
          maxLength: 6,
          initialValue: '123',
          semanticLabel: 'Verification code',
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.byType(DInputOTPSlot), findsNWidgets(6));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).autofillHints,
      contains(AutofillHints.oneTimeCode),
    );

    expect(find.bySemanticsLabel('Verification code'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byType(EditableText))
          .getSemanticsData()
          .flagsCollection
          .isTextField,
      isTrue,
    );
  });

  testWidgets('filters and transforms a pasted value then completes once', (
    tester,
  ) async {
    final changes = <String>[];
    final completions = <String>[];
    await tester.pumpWidget(
      host(
        DInputOTP(
          maxLength: 6,
          pattern: dInputOTPAlphanumeric,
          inputTransformer: (value) => value.toUpperCase(),
          onChanged: changes.add,
          onCompleted: completions.add,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'ab-12 cd-more');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'AB12CD',
    );
    expect(changes, ['AB12CD']);
    expect(completions, ['AB12CD']);

    await tester.enterText(find.byType(TextField), 'AB12CD');
    await tester.pump();
    expect(completions, ['AB12CD']);
  });

  testWidgets('platform selection and deletion update the shared value', (
    tester,
  ) async {
    final controller = TextEditingController(text: '123456');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(DInputOTP(maxLength: 6, controller: controller)),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 4);
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '1256',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(controller.text, '1256');
    expect(find.text('5'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('digits pattern rejects non-digit typing', (tester) async {
    await tester.pumpWidget(
      host(DInputOTP(maxLength: 4, pattern: dInputOTPDigits)),
    );
    await tester.enterText(find.byType(TextField), '1a2b3c4d5');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1234',
    );
  });

  testWidgets(
    'controlled value changes synchronize without replacing equal selection',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var value = '123';
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DInputOTP(
                maxLength: 6,
                value: value,
                onChanged: (next) => update(() => value = next),
              );
            },
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 1);
      update(() {});
      await tester.pump();
      expect(field.controller!.selection.baseOffset, 1);

      update(() => value = '654321');
      await tester.pump();
      expect(field.controller!.text, '654321');
      expect(field.controller!.selection.baseOffset, 6);
    },
  );

  testWidgets('borrowed controller and focus survive widget disposal', (
    tester,
  ) async {
    final controller = TextEditingController(text: '12');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(DInputOTP(maxLength: 6, controller: controller, focusNode: focus)),
    );
    await tester.pumpWidget(host(const SizedBox()));
    controller.text = '34';
    expect(controller.text, '34');
    void listener() {}
    expect(() {
      focus.addListener(listener);
      focus.removeListener(listener);
    }, returnsNormally);
  });

  testWidgets('Form validates saves and resets the mount value', (
    tester,
  ) async {
    final key = GlobalKey<FormState>();
    String? saved;
    final changes = <String>[];
    var resets = 0;
    await tester.pumpWidget(
      host(
        Form(
          key: key,
          child: DInputOTP(
            maxLength: 4,
            initialValue: '1',
            pattern: dInputOTPDigits,
            validator: (value) => value?.length == 4 ? null : 'Four required',
            onSaved: (value) => saved = value,
            onReset: () => resets++,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byType(DInputOTP))
          .getSemanticsData()
          .validationResult,
      SemanticsValidationResult.invalid,
    );

    await tester.enterText(find.byType(TextField), '1234');
    key.currentState!.save();
    expect(saved, '1234');
    key.currentState!.reset();
    await tester.pump();
    expect(resets, 1);
    expect(changes.last, '1');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
    );
  });

  testWidgets('disabled editor cannot focus or mutate and exposes state', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        DInputOTP(
          maxLength: 6,
          value: '123456',
          enabled: false,
          focusNode: focus,
          semanticLabel: 'Disabled code',
        ),
      ),
    );
    await tester.tap(find.byType(DInputOTP));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Disabled code'))
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
  });

  testWidgets('pointer position selects a slot in LTR and RTL', (tester) async {
    final controller = TextEditingController(text: '123456');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(DInputOTP(maxLength: 6, controller: controller)),
    );
    final rect = tester.getRect(find.byType(DInputOTP));
    await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
    await tester.pump();
    expect(controller.selection.extentOffset, 0);

    await tester.pumpWidget(
      host(
        DInputOTP(maxLength: 6, controller: controller),
        direction: TextDirection.rtl,
      ),
    );
    final rtlRect = tester.getRect(find.byType(DInputOTP));
    await tester.tapAt(Offset(rtlRect.left + 2, rtlRect.center.dy));
    await tester.pump();
    expect(controller.selection.extentOffset, 5);
  });

  testWidgets(
    'slot geometry grows for 200 percent text and follows RTL corners',
    (tester) async {
      await tester.pumpWidget(
        host(
          DInputOTP(maxLength: 4, initialValue: '1234'),
          direction: TextDirection.rtl,
          textScale: 2,
        ),
      );
      for (final slot in find.byType(DInputOTPSlot).evaluate()) {
        expect(
          tester.getSize(find.byWidget(slot.widget)).height,
          greaterThan(32),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom composition keeps one editor and separator semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        DInputOTP(
          maxLength: 4,
          children: const [
            DInputOTPGroup(
              children: [DInputOTPSlot(index: 0), DInputOTPSlot(index: 1)],
            ),
            DInputOTPSeparator(),
            DInputOTPGroup(
              children: [DInputOTPSlot(index: 2), DInputOTPSlot(index: 3)],
            ),
          ],
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(DInputOTPSeparator), findsOneWidget);
    expect(find.byType(DInputOTPGroup), findsNWidgets(2));
  });
}
