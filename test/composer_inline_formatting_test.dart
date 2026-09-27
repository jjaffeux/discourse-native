import 'package:discourse_native/src/shell/composer_inline_formatting.dart';
import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:discourse_native/src/shell/markdown_highlight.dart';
import 'package:discourse_native/src/shell/markdown_style.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scaling_benchmark.dart';

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

  group('pairs within a block, as the editor draws it', () {
    // Each prefix leaves a delimiter the highlighter pairs with nothing, since
    // a mark cannot span a paragraph or a fence. Paired across them, it takes
    // the closer of the span below and hides that span from the toolbar.
    for (final (prefix, source, mark, kind, toggled) in const [
      (
        'Pass **kwargs through.\n\n',
        'Some **bold words** here',
        ComposerMark.bold,
        '**',
        'Some **bold** words here',
      ),
      (
        'Costs 2*3 today.\n\n',
        'Some *ital words* here',
        ComposerMark.italic,
        '*',
        'Some *ital* words here',
      ),
      // No blank line: only the fence separates the two blocks.
      (
        'Pass **kwargs\n```\ncode\n```\n',
        'Some **bold words** here',
        ComposerMark.bold,
        '**',
        'Some **bold** words here',
      ),
      (
        'Costs 2~~3 today.\n\n',
        'Some ~~struck words~~ here',
        null,
        '~~',
        'Some ~~struck~~ words here',
      ),
    ]) {
      test('${prefix.trim()} / $source', () {
        final value = selection('$prefix$source', 'words');
        expect(composerSelectionHasFormat(value, kind), isTrue);

        final cleared = clearComposerInlineFormatting(value, kind: kind);
        expect(cleared.text, '$prefix$toggled');
        expect(cleared.selection.textInside(cleared.text), 'words');
        if (mark != null) {
          expect(toggleComposerInlineMark(value, mark), cleared);
        }

        final whole = source.substring(
          source.indexOf(kind),
          source.lastIndexOf(kind) + kind.length,
        );
        expect(
          clearComposerInlineFormatting(
            selection('$prefix$source', whole),
          ).text,
          '$prefix${source.replaceFirst(whole, whole.replaceAll(kind, ''))}',
        );
      });
    }

    test('an unclosed tag in an earlier paragraph does not hide a tag', () {
      final value = selection(
        'Type <ins>here.\n\nSome <ins>underlined words</ins> here',
        'words',
      );
      expect(composerSelectionHasFormat(value, 'ins'), isTrue);
      expect(
        toggleComposerTag(value, 'ins').text,
        'Type <ins>here.\n\nSome <ins>underlined </ins>words here',
      );
    });
  });

  test('finding formats grows with the draft, not its square', () {
    // The selection toolbar asks on every selection change. An 8x draft
    // separates linear growth from a lookup over every run for each pair.
    String draft(int paragraphs) => [
      for (var i = 0; i < paragraphs; i += 1)
        'Line $i has **bold**, *italic*, ~~gone~~, `code` and <ins>u</ins>.',
    ].join('\n\n');

    final smallSource = draft(150);
    final largeSource = draft(1200);
    final (:small, :large) = measureScaling(
      () => composerInlineFormats(smallSource).length,
      () => composerInlineFormats(largeSource).length,
    );
    expect(
      large,
      lessThan(small * 25),
      reason: 'eight times the draft took ${large / small} times as long',
    );
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
