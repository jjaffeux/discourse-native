import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue nativeValue(WidgetTester tester) =>
    TextEditingValue.fromJSON(tester.testTextInput.editingState!);

void backspace(WidgetTester tester) {
  final value = nativeValue(tester);
  final selection = value.selection;
  final start = selection.isCollapsed
      ? (selection.start - 1).clamp(0, value.text.length)
      : selection.start;
  if (start == selection.end) return;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(start, selection.end, ''),
      selection: TextSelection.collapsed(offset: start),
    ),
  );
}

Future<void> pumpInput(WidgetTester tester, DInput input) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, child: input)),
    ),
  ),
);

void main() {
  const mobile = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  testWidgets('empty backspace preserves hint, semantics and form value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    var deletes = 0;
    String? submitted;
    await pumpInput(
      tester,
      DInput(
        controller: controller,
        hintText: 'To-do',
        borderless: true,
        onChanged: changes.add,
        onSubmitted: (value) => submitted = value,
        onEmptyBackspace: () => deletes++,
      ),
    );
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(DInput));
    expect(find.text('To-do'), findsOneWidget);
    expect(tester.getSemantics(find.byType(EditableText)).value, isEmpty);
    expect(controller.text, isEmpty);

    // A tap at the left edge cannot move before the deletion boundary.
    await tester.tapAt(tester.getTopLeft(find.byType(EditableText)));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      backspace(tester);
      await tester.pumpAndSettle();
      expect(deletes, i + 1);
      expect(controller.text, isEmpty);
      expect(
        tester.state<FormFieldState<String>>(find.byType(DInput)).value,
        '',
      );
      expect(tester.getSize(find.byType(DInput)), size);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, '');
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  }, variant: mobile);

  testWidgets('typing and IME receive ordinary text and composing offsets', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var deletes = 0;
    final edits = <(TextEditingValue, TextEditingValue)>[];
    final changes = <String>[];
    await pumpInput(
      tester,
      DInput(
        controller: controller,
        onEmptyBackspace: () => deletes++,
        onChanged: changes.add,
        inputFormatters: [
          TextInputFormatter.withFunction((before, after) {
            edits.add((before, after));
            return after;
          }),
        ],
      ),
    );
    await tester.showKeyboard(find.byType(EditableText));
    final native = nativeValue(tester);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${native.text}文',
        selection: TextSelection.collapsed(offset: native.text.length + 1),
        composing: TextRange(
          start: native.text.length,
          end: native.text.length + 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.text, '文');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
    expect(controller.value.composing, const TextRange(start: 0, end: 1));
    expect(edits.single.$1.text, '');
    expect(edits.single.$2, controller.value);
    expect(nativeValue(tester), controller.value);
    expect(changes, ['文']);

    tester.testTextInput.updateEditingValue(
      controller.value.copyWith(composing: TextRange.empty),
    );
    await tester.pumpAndSettle();
    backspace(tester);
    await tester.pumpAndSettle();
    expect(controller.text, '');
    expect(deletes, 0);
    expect(changes, ['文', '']);
    backspace(tester);
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(tester.takeException(), isNull);
  }, variant: mobile);

  testWidgets('formatters can reject input without deleting the empty field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var deletes = 0;
    await pumpInput(
      tester,
      DInput(
        controller: controller,
        onEmptyBackspace: () => deletes++,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 2,
      ),
    );
    await tester.showKeyboard(find.byType(EditableText));
    var value = nativeValue(tester);
    tester.testTextInput.enterText('${value.text}abc');
    await tester.pumpAndSettle();
    expect(controller.text, '');
    expect(deletes, 0);
    value = nativeValue(tester);
    tester.testTextInput.enterText('${value.text}123');
    await tester.pumpAndSettle();
    expect(controller.text, '12');
    expect(deletes, 0);
    expect(tester.takeException(), isNull);
  }, variant: mobile);

  testWidgets('read-only and disabled fields have no deletion boundary', (
    tester,
  ) async {
    for (final readOnly in [false, true]) {
      await pumpInput(
        tester,
        DInput(
          enabled: readOnly,
          readOnly: readOnly,
          onEmptyBackspace: () => fail('Read-only field was deleted'),
        ),
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '',
      );
    }
  }, variant: mobile);

  testWidgets('programmatic changes and form reset rearm empty backspace', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var deletes = 0;
    await pumpInput(
      tester,
      DInput(controller: controller, onEmptyBackspace: () => deletes++),
    );
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.enterText('${nativeValue(tester).text}First');
    await tester.pumpAndSettle();
    expect(controller.text, 'First');
    controller.text = '';
    await tester.pumpAndSettle();
    backspace(tester);
    await tester.pumpAndSettle();
    expect(deletes, 1);
    controller.text = 'Replacement';
    await tester.pumpAndSettle();
    tester.state<FormFieldState<String>>(find.byType(DInput)).reset();
    await tester.pumpAndSettle();
    backspace(tester);
    await tester.pumpAndSettle();
    expect(deletes, 2);
    expect(controller.text, '');
    expect(tester.takeException(), isNull);
  }, variant: mobile);
}
