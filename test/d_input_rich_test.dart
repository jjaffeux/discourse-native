import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('borderless input grows while preserving its editing session', (
    tester,
  ) async {
    final text = TextEditingController(text: 'First');
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: DInput(
                controller: text,
                focusNode: focus,
                borderless: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'First\nSecond\n文',
        selection: TextSelection.collapsed(offset: 14),
        composing: TextRange(start: 13, end: 14),
      ),
    );
    await tester.pump();
    final after = tester.getSize(find.byType(EditableText));
    expect(after.height, greaterThan(before.height * 2));
    expect(after.width, before.width);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(text.value.composing, const TextRange(start: 13, end: 14));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'borderless expanding input fills a bounded viewport and scrolls',
    (tester) async {
      final text = TextEditingController(
        text: List.generate(30, (i) => 'Line $i').join('\n'),
      );
      final scroll = ScrollController();
      addTearDown(text.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 220,
                height: 120,
                child: DInput(
                  controller: text,
                  borderless: true,
                  maxLines: null,
                  expands: true,
                  scrollController: scroll,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(EditableText)), const Size(220, 120));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(scroll.offset, greaterThan(0));
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final lastCharacter = editable
          .getBoxesForSelection(
            TextSelection(
              baseOffset: text.text.length - 1,
              extentOffset: text.text.length,
            ),
          )
          .single
          .toRect()
          .shift(editable.localToGlobal(Offset.zero));
      expect(
        lastCharacter.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(DInput)).bottom),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.all(),
  );
}
