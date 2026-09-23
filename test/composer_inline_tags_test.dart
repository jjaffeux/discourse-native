import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MarkdownEditingController controller;
  const base = TextStyle(fontSize: 20, height: 1.5);

  Future<void> pump(
    WidgetTester tester,
    String source, {
    double scale = 1,
    double width = 600,
    ThemeData? theme,
  }) async {
    controller = MarkdownEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: DInput(
                borderless: true,
                controller: controller,
                maxLines: null,
                style: base,
                strutStyle: StrutStyle.fromTextStyle(
                  base,
                  forceStrutHeight: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  EditableTextState editor(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText));

  TextSpan painted(WidgetTester tester) =>
      editor(tester).renderEditable.text! as TextSpan;

  String visibleText(InlineSpan span) {
    if (span is! TextSpan) return '';
    if (span.style?.fontSize == 0) return '';
    return '${span.text ?? ''}'
        '${span.children?.map(visibleText).join() ?? ''}';
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('renders scripts, a keycap and underline at ${scale}x', (
      tester,
    ) async {
      const source =
          'x<sup>ab</sup> H<sub>cd</sub> <kbd>Esc</kbd> <ins>underlined</ins> after';
      await pump(
        tester,
        source,
        scale: scale,
        width: 320,
        theme: scale == 1 ? AppTheme.light : AppTheme.dark,
      );
      expect(controller.text, source);
      expect(
        painted(tester).toPlainText(includeSemanticsLabels: false).length,
        source.length,
      );
      expect(visibleText(painted(tester)), 'x H  underlined after');
      expect(
        painted(tester)
            .getSpanForPosition(
              TextPosition(offset: source.indexOf('underlined')),
            )!
            .style!
            .decoration,
        TextDecoration.underline,
      );
      expect(find.byType(DKbd), findsOneWidget);
      final a = tester.widget<Text>(find.text('a'));
      expect(a.style!.fontSize, 15);
      expect(a.style!.fontFeatures, isNull);
      final normal = editor(
        tester,
      ).renderEditable.getLocalRectForCaret(const TextPosition(offset: 0));
      final origin = editor(tester).renderEditable.localToGlobal(Offset.zero);
      expect(
        tester.getTopLeft(find.text('a')).dy,
        lessThan(origin.dy + normal.top),
      );
      expect(
        tester.getTopLeft(find.text('c')).dy,
        greaterThan(tester.getTopLeft(find.text('a')).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'keeps each script character editable and preserves clipboard source',
    (tester) async {
      const source = 'x<sup>ab</sup> after';
      await pump(tester, source);
      await tester.showKeyboard(find.byType(EditableText));
      final render = editor(tester).renderEditable;
      for (final offset in [6, 7, 8]) {
        final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
        expect(caret.width, greaterThan(0));
        expect(caret.height, greaterThan(0));
      }
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 8,
      );
      await tester.pump();
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(visibleText(painted(tester)), isNot(contains('<sup>')));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: source.length,
      );
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      editor(tester).copySelection(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(copied, source);

      controller.selection = const TextSelection.collapsed(offset: 7);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'x<sup>aZb</sup> after',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();
      expect(find.text('Z'), findsOneWidget);
      expect(controller.text, 'x<sup>aZb</sup> after');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renders one keycap for mixed formatting and edits its body without tags',
    (tester) async {
      const source = 'Press <kbd>**Ctrl** + K</kbd> now';
      await pump(tester, source);
      expect(find.byType(DKbd), findsOneWidget);
      expect(tester.widget<DKbd>(find.byType(DKbd)).semanticLabel, 'Ctrl + K');
      controller.selection = const TextSelection.collapsed(offset: 15);
      await tester.pump();
      expect(find.byType(DKbd), findsNothing);
      expect(visibleText(painted(tester)), isNot(contains('<kbd>')));
      expect(visibleText(painted(tester)), isNot(contains('</kbd>')));
      controller.selection = const TextSelection.collapsed(
        offset: source.length,
      );
      await tester.pump();
      expect(find.byType(DKbd), findsOneWidget);
      expect(controller.text, source);
      expect(
        painted(tester).toPlainText(includeSemanticsLabels: false).length,
        source.length,
      );
    },
  );

  testWidgets('leaves escaped, incomplete and code tags literal', (
    tester,
  ) async {
    const source =
        r'\<sup>x</sup> `<sub>y</sub>` <kbd>open '
        r'\<ins>escaped</ins> `<ins>code</ins>` <ins>open';
    await pump(tester, source);
    expect(visibleText(painted(tester)), source);
    expect(find.byType(DKbd), findsNothing);
  });

  testWidgets('retains the IME underline and source range inside scripts', (
    tester,
  ) async {
    await pump(tester, '<sup>仮</sup>');
    await tester.showKeyboard(find.byType(EditableText));
    controller.value = const TextEditingValue(
      text: '<sup>仮</sup>',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 5, end: 6),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('仮')).style!.decoration,
      TextDecoration.underline,
    );
    expect(controller.value.composing, const TextRange(start: 5, end: 6));
    expect(
      painted(tester).toPlainText(includeSemanticsLabels: false).length,
      controller.text.length,
    );
    controller.clearComposing();
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('仮')).style!.decoration,
      isNot(TextDecoration.underline),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps Unicode graphemes intact during script navigation and deletion',
    (tester) async {
      const source = '<sup>e\u0301😀</sup>';
      await pump(tester, source);
      await tester.showKeyboard(find.byType(EditableText));
      controller.selection = const TextSelection.collapsed(offset: 5);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.selection.extentOffset, 7);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.selection.extentOffset, 9);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(controller.text, '<sup>e\u0301</sup>');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(controller.text, '<sup></sup>');
      expect(tester.takeException(), isNull);
    },
  );

  for (final tag in ['sup', 'ins']) {
    testWidgets(
      'skips $tag wrappers with arrow keys and removes whole formatting at a delete boundary',
      (tester) async {
        final source = 'x<$tag>ab</$tag> after';
        await pump(tester, source);
        await tester.showKeyboard(find.byType(EditableText));
        controller.selection = const TextSelection.collapsed(offset: 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(controller.selection.extentOffset, 6);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(controller.selection.extentOffset, 7);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(controller.selection.extentOffset, 8);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(controller.selection.extentOffset, 14);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, 'xab after');
        expect(controller.selection.extentOffset, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
