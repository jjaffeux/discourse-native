import 'package:discourse_native/src/shell/composer_inline_formatting.dart';
import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:discourse_native/src/shell/markdown_style.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue selection(
  String source,
  String selected, {
  bool reversed = false,
}) {
  final start = source.indexOf(selected);
  return TextEditingValue(
    text: source,
    selection: TextSelection(
      baseOffset: reversed ? start + selected.length : start,
      extentOffset: reversed ? start : start + selected.length,
    ),
  );
}

void main() {
  test(
    'editor displays text and background colors with combined decorations',
    () {
      const source =
          '[color=#ff0000][bgcolor=#ffff00]<ins>~~hello~~</ins>[/bgcolor][/color]';
      final at = source.indexOf('hello');
      final run = scanMarkdown(
        source,
      ).firstWhere((run) => run.start <= at && run.end > at);
      final style = markdownStyle(
        run.mask,
        run.detail,
        const TextStyle(fontSize: 14),
        AppTheme.dark,
      );
      expect(style.color, const Color(0xffff0000));
      expect(style.backgroundColor, const Color(0xffffff00));
      expect(style.decoration!.contains(TextDecoration.underline), isTrue);
      expect(style.decoration!.contains(TextDecoration.lineThrough), isTrue);
    },
  );

  test('bold can be removed without losing italic in combined emphasis', () {
    final before = selection('***hello***', 'hello');
    final after = toggleComposerInlineMark(before, ComposerMark.bold);
    expect(after.text, '*hello*');
    expect(after.selection.textInside(after.text), 'hello');
  });

  test('clearing color inside nested bold preserves valid wrappers', () {
    final before = selection('[color=red]**hello world**[/color]', 'hello');
    final after = setComposerColor(before, null);
    expect(after.text, '**hello**[color=red] **world**[/color]');
    expect(after.selection.textInside(after.text), 'hello');
  });
  test('underline preserves reversed selection and toggles off', () {
    final before = selection('hello world', 'hello', reversed: true);
    final after = toggleComposerTag(before, 'ins');
    expect(after.text, '<ins>hello</ins> world');
    expect(after.selection.baseOffset, 10);
    expect(after.selection.extentOffset, 5);
    expect(toggleComposerTag(after, 'ins'), before);
  });

  test('clear formatting strips nested formats and links in one selection', () {
    const source =
        'before **bold** <ins>*italic*</ins> [link](https://example.com) after';
    final result = clearComposerInlineFormatting(
      selection(
        source,
        '**bold** <ins>*italic*</ins> [link](https://example.com)',
      ),
    );
    expect(result.text, 'before bold italic link after');
    expect(result.selection.textInside(result.text), 'bold italic link');
  });

  test(
    'clear formatting splits surrounding emphasis and preserves direction',
    () {
      final result = clearComposerInlineFormatting(
        selection('**one two three**', 'two', reversed: true),
      );
      expect(result.text, '**one** two **three**');
      expect(result.selection.textInside(result.text), 'two');
      expect(
        result.selection.baseOffset,
        greaterThan(result.selection.extentOffset),
      );
    },
  );

  test('clear formatting preserves literal inline code contents', () {
    final result = clearComposerInlineFormatting(
      selection(
        '**before** `**literal** <ins>tag</ins>`',
        '**before** `**literal** <ins>tag</ins>`',
      ),
    );
    expect(result.text, 'before **literal** <ins>tag</ins>');
  });

  test('clear formatting preserves block syntax, images and escaped marks', () {
    const source =
        '# heading\n\n- **bold**\n\n![image](upload://file.png) \\*literal\\*';
    final result = clearComposerInlineFormatting(selection(source, source));
    expect(
      result.text,
      '# heading\n\n- bold\n\n![image](upload://file.png) \\*literal\\*',
    );
  });

  test('color replacement preserves background color and selection', () {
    var value = selection('hello world', 'hello');
    value = setComposerColor(value, '#ff0000');
    value = setComposerColor(value, '#ffff00', background: true);
    expect(
      value.text,
      '[color=#ff0000][bgcolor=#ffff00]hello[/bgcolor][/color] world',
    );
    value = setComposerColor(value, '#0000ff');
    expect(
      value.text,
      '[bgcolor=#ffff00][color=#0000ff]hello[/color][/bgcolor] world',
    );
    expect(value.selection.textInside(value.text), 'hello');
    value = clearComposerInlineFormatting(value);
    expect(value.text, 'hello world');
  });

  test('clearing one color leaves other inline formatting intact', () {
    final before = selection('[color=red]**hello**[/color]', 'hello');
    final after = setComposerColor(before, null);
    expect(after.text, '**hello**');
    expect(after.selection.textInside(after.text), 'hello');
  });

  test('collapsed selections do not insert formatting or colors', () {
    const value = TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 2),
    );
    expect(toggleComposerTag(value, 'ins'), value);
    expect(clearComposerInlineFormatting(value), value);
    expect(setComposerColor(value, '#ff0000'), value);
  });
}
