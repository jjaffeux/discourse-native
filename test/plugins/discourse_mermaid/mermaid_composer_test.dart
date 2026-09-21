import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_mermaid/mermaid_composer.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = 'Before\n\n```mermaid\nflowchart TD\n  A --> B\n```\n\nAfter';

void main() {
  test(
    'preserves fences and surrounding source, skips nested and unclosed examples',
    () {
      final block = parseMermaidComposerBlocks(_source).single;
      expect(block.code, 'flowchart TD\n  A --> B');
      expect(block.source, _source.substring(block.start, block.end));
      expect(block.replaceCode(block.code), block.source);
      expect(parseMermaidComposerBlocks('````text\n$_source\n````'), isEmpty);
      expect(parseMermaidComposerBlocks('```mermaid\nA --> B'), isEmpty);
      expect(
        parseMermaidComposerBlocks('> ```mermaid\n> A --> B\n> ```'),
        isEmpty,
      );
      expect(
        parseMermaidComposerBlocks('    ```mermaid\n    A --> B\n    ```'),
        isEmpty,
      );
      const crlf = '~~~mermaid\r\nA --> B\r\n~~~';
      final tilde = parseMermaidComposerBlocks(crlf).single;
      expect(tilde.replaceCode(tilde.code), crlf);
    },
  );

  test('empty code and delimiter-like content remain editable fences', () {
    for (final source in [
      '```mermaid\n```',
      '```mermaid\n\n```',
      '~~~mermaid\r\n~~~',
    ]) {
      final block = parseMermaidComposerBlocks(source).single;
      expect(block.code, isEmpty);
      final replacement = block.replaceCode(
        'flowchart TD\n  A["``` ~~~"] --> B',
      );
      expect(
        parseMermaidComposerBlocks(replacement).single.code,
        'flowchart TD\n  A["``` ~~~"] --> B',
      );
    }
  });

  Future<ComposerController> pump(
    WidgetTester tester, {
    double width = 760,
    bool dark = false,
    String source = _source,
    double? height,
  }) async {
    late final ComposerController composer;
    composer = ComposerController(
      const ComposerTarget(
        siteUrl: 'https://example.test',
        topicId: 1,
        slug: 'topic',
        topicTitle: 'Topic',
      ),
      syntaxPolicies: [MermaidComposerPolicy(() => composer)],
    );
    addTearDown(composer.dispose);
    composer.text.value = TextEditingValue(
      text: source,
      selection: const TextSelection.collapsed(offset: 0),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ComposerEditor(
                composer: composer,
                hintText: 'Reply',
                textStyle: const TextStyle(fontSize: 16, height: 1.5),
                hintStyle: null,
              ),
            ),
          ),
        ),
      ),
    );
    // No native WebView in this fixture: DMermaid exposes its controlled platform error.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return composer;
  }

  for (final scrolled in [false, true]) {
    testWidgets('mouse places source caret after composer scroll: $scrolled', (
      tester,
    ) async {
      final source = '${scrolled ? 'Paragraph\n\n' * 20 : ''}$_source';
      final composer = await pump(tester, source: source, height: 420);
      final field = find.descendant(
        of: find.byType(DCodeEditor),
        matching: find.byType(EditableText),
      );
      final render = tester.state<EditableTextState>(field).renderEditable;
      final points = {
        for (final offset in [3, 17, 8])
          offset: render.localToGlobal(
            render.getLocalRectForCaret(TextPosition(offset: offset)).center,
          ),
      };
      final scroll = composer.text.imageScrollController!;
      if (scrolled) {
        scroll.jumpTo(
          (render.localToGlobal(Offset.zero).dy -
                  tester.getTopLeft(find.byType(ComposerEditor)).dy -
                  80)
              .clamp(0, scroll.position.maxScrollExtent),
        );
        await tester.pump();
      }
      final outerOffset = scroll.offset;
      for (final offset in [3, 17, 8]) {
        final point = points[offset]! - Offset(0, outerOffset);
        await tester.tapAt(point, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 600));
        final editable = tester.widget<EditableText>(field);
        expect(editable.focusNode.hasPrimaryFocus, isTrue);
        expect(composer.text.keyboardSelectedSyntax, isNull);
        expect(editable.controller.selection.isCollapsed, isTrue);
        expect(editable.controller.selection.extentOffset, offset);
        expect(composer.focus.hasFocus, isFalse);
        expect(scroll.offset, closeTo(outerOffset, 1));
      }
      final drag = await tester.startGesture(
        points[3]! - Offset(0, outerOffset),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(points[17]! - Offset(0, outerOffset));
      await drag.up();
      await tester.pump();
      expect(
        tester.widget<EditableText>(field).controller.selection,
        const TextSelection(baseOffset: 3, extentOffset: 17),
      );
      expect(composer.text.keyboardSelectedSyntax, isNull);
      expect(composer.raw, source);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'nested edits update Markdown immediately and preserve editor focus',
    (tester) async {
      final composer = await pump(tester);
      expect(find.byType(DMermaidEditor), findsOneWidget);
      final field = find.descendant(
        of: find.byType(DCodeEditor),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, 'flowchart LR\n  Changed --> B');
      expect(
        composer.raw,
        'Before\n\n```mermaid\nflowchart LR\n  Changed --> B\n```\n\nAfter',
      );
      await tester.pump();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      final controller = tester
          .widget<DCodeEditor>(find.byType(DCodeEditor))
          .controller;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 9,
      );
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<DMermaid>(find.byType(DMermaid)).source,
        'flowchart LR\n  Changed --> B',
      );
      expect(find.text('Copy source'), findsNothing);
      expect(find.text('View source'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow dark layout and source replacement keep canonical content',
    (tester) async {
      final composer = await pump(tester, width: 320, dark: true);
      expect(tester.takeException(), isNull);
      final before = tester.getTopLeft(find.byType(DCodeEditor));
      final preview = tester.getTopLeft(find.byType(DMermaid));
      expect(preview.dy, greaterThan(before.dy));
      composer.text.value = const TextEditingValue(
        text: '```mermaid\nA --> D\n```',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      expect(
        tester.widget<DCodeEditor>(find.byType(DCodeEditor)).controller.text,
        'A --> D',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'indentation, select-all and delete stay inside the source editor',
    (tester) async {
      final composer = await pump(tester);
      final field = find.descendant(
        of: find.byType(DCodeEditor),
        matching: find.byType(EditableText),
      );
      await tester.showKeyboard(field);
      final controller = tester
          .widget<DCodeEditor>(find.byType(DCodeEditor))
          .controller;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        parseMermaidComposerBlocks(composer.raw).single.code,
        controller.text,
      );
      expect(controller.text, endsWith('  '));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        controller.selection,
        TextSelection(baseOffset: 0, extentOffset: controller.text.length),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(composer.raw, 'Before\n\n```mermaid\n\n```\n\nAfter');
      expect(find.byType(DCodeEditor), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'matching draft rebuilds preserve IME composition and selection',
    (tester) async {
      final composer = await pump(tester);
      final controller = tester
          .widget<DCodeEditor>(find.byType(DCodeEditor))
          .controller;
      final text = controller.text;
      controller.value = TextEditingValue(
        text: text,
        selection: const TextSelection.collapsed(offset: 4),
        composing: const TextRange(start: 0, end: 4),
      );
      composer.text.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      final held = tester
          .widget<DCodeEditor>(find.byType(DCodeEditor))
          .controller;
      expect(identical(controller, held), isTrue);
      expect(held.value.composing, const TextRange(start: 0, end: 4));
      expect(held.selection.extentOffset, 4);
      expect(composer.raw, _source);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('retired editor rejects stale source callbacks', (tester) async {
    final composer = await pump(tester);
    final editor = tester.widget<DMermaidEditor>(find.byType(DMermaidEditor));
    composer.beginSubmit();
    editor.onChanged('flowchart TD\nX --> Y');
    expect(composer.raw, _source);
    await tester.pumpWidget(const SizedBox());
  });
}
