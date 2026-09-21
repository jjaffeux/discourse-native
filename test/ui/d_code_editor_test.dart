import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'edits, indents, highlights and keeps borrowed controller alive',
    (tester) async {
      final controller = DCodeEditingController(
        text: 'flowchart TD\n  A --> B',
        language: 'mermaid',
      );
      addTearDown(controller.dispose);
      var changed = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 250,
              child: DCodeEditor(
                controller: controller,
                onChanged: (value) => changed = value,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'flowchart LR\n  A --> C');
      expect(changed, 'flowchart LR\n  A --> C');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: field.style,
        withComposing: true,
      );
      expect(span.toPlainText(), controller.text);
      expect(span.children, isNotEmpty);
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.text, endsWith('  '));
      expect(changed, controller.text);
      await tester.pumpWidget(const SizedBox());
      controller.text = 'still usable';
      expect(controller.text, 'still usable');
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'read-only prevents typing and indentation, including a state change',
    (tester) async {
      final controller = DCodeEditingController(
        text: 'A --> B',
        language: 'mermaid',
      );
      addTearDown(controller.dispose);
      Widget host(bool readOnly) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: DCodeEditor(controller: controller, readOnly: readOnly),
          ),
        ),
      );
      await tester.pumpWidget(host(false));
      await tester.tap(find.byType(TextField));
      await tester.pumpWidget(host(true));
      final before = controller.text;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(controller.text, before);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).readOnly,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
