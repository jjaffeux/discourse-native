import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a selection as `text` with the selected part between brackets, so a
/// failure reads as what someone would see rather than as a pair of offsets.
String showSelection(TextEditingValue value) {
  final s = value.selection;
  if (!s.isValid) return value.text;
  return '${value.text.substring(0, s.start)}[${value.text.substring(s.start, s.end)}]'
      '${value.text.substring(s.end)}';
}

TextEditingValue selected(String annotated) {
  final start = annotated.indexOf('[');
  final end = annotated.indexOf(']') - 1;
  final text = annotated.replaceAll('[', '').replaceAll(']', '');
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

void main() {
  group('toggleMarkdownMark', () {
    void expectToggle(String before, String marker, String after) {
      expect(
        showSelection(toggleMarkdownMark(selected(before), marker)),
        after,
        reason: '$before + "$marker"',
      );
    }

    test('wraps a selection, keeping the selection on the text', () {
      // Markers land outside the selection so a second mark composes onto the
      // same words rather than onto the first mark's asterisks.
      expectToggle('say [hello] there', '**', 'say **[hello]** there');
      expectToggle('say [hello] there', '*', 'say *[hello]* there');
    });

    test('unwraps when the markers are inside the selection', () {
      expectToggle('say [**hello**] there', '**', 'say [hello] there');
    });

    test(
      'unwraps when the markers are outside it, as a double-click gives',
      () {
        expectToggle('say **[hello]** there', '**', 'say [hello] there');
      },
    );

    test('puts the caret between the markers when nothing is selected', () {
      final result = toggleMarkdownMark(
        const TextEditingValue(
          text: 'say ',
          selection: TextSelection.collapsed(offset: 4),
        ),
        '**',
      );
      expect(result.text, 'say ****');
      expect(result.selection.baseOffset, 6);
      expect(result.selection.isCollapsed, isTrue);
    });

    test('does not mistake bold for a pair of italics', () {
      // Pressing italic on bold text adds a mark; it does not peel one off.
      expectToggle('say [**hello**] there', '*', 'say *[**hello**]* there');
      // Which is what makes bold-then-italic reach ***hello***.
      expectToggle('say **[hello]** there', '*', 'say ***[hello]*** there');
    });

    test('appends at the end when there is no selection at all', () {
      final result = toggleMarkdownMark(
        const TextEditingValue(text: 'say'),
        '**',
      );
      expect(result.text, 'say****');
    });

    test('is its own inverse', () {
      for (final marker in ['**', '*']) {
        const start = 'say [hello] there';
        final once = toggleMarkdownMark(selected(start), marker);
        expect(showSelection(toggleMarkdownMark(once, marker)), start);
      }
    });

    // The example above is one selection over one document. The toolbar is
    // pointed at whatever is on screen, which includes documents made mostly
    // of asterisks — a code block being written, a row of separators, a paste.
    // Two things have to hold over all of them: whatever the toggle decides,
    // it hands back a selection the field can hold, and where the selection
    // and its edges are ordinary prose it is still its own inverse.
    test('over any document and any selection', () {
      const pieces = [
        '**',
        '*',
        'a',
        'b',
        ' ',
        '\n',
        '\n\n',
        '`',
        '_',
        '~~',
        'x',
        'y',
        '***',
        '****',
        '**a**',
        '*a*',
      ];
      final random = Random(1234);
      var wrapped = 0;
      var unwrapped = 0;
      var inverses = 0;

      for (var round = 0; round < 40000; round++) {
        final buffer = StringBuffer();
        for (var piece = 0; piece < random.nextInt(10); piece++) {
          buffer.write(pieces[random.nextInt(pieces.length)]);
        }
        final text = buffer.toString();
        final first = random.nextInt(text.length + 1);
        final second = random.nextInt(text.length + 1);
        final start = min(first, second);
        final end = max(first, second);
        final marker = random.nextBool() ? '**' : '*';

        final next = toggleMarkdownMark(
          TextEditingValue(
            text: text,
            selection: TextSelection(baseOffset: start, extentOffset: end),
          ),
          marker,
        );
        final where =
            '${jsonEncode(text)} [$start,$end] "$marker" -> '
            '${jsonEncode(next.text)} '
            '[${next.selection.start},${next.selection.end}]';

        expect(next.selection.isValid, isTrue, reason: where);
        expect(
          next.selection.start,
          inInclusiveRange(0, next.text.length),
          reason: where,
        );
        expect(
          next.selection.end,
          inInclusiveRange(0, next.text.length),
          reason: where,
        );
        expect(next.composing, TextRange.empty, reason: where);

        if (next.text.length > text.length) {
          wrapped++;
        } else if (next.text.length < text.length) {
          unwrapped++;
        }

        // Whether a run of asterisks is already wrapped is genuinely
        // ambiguous, and unwrapping one leaves a selection that is no longer
        // what was toggled — so the inverse is claimed only where the
        // selection and the characters against it are prose.
        final edges = text.substring(
          start == 0 ? 0 : start - 1,
          end == text.length ? end : end + 1,
        );
        if (edges.contains('*')) continue;
        final back = toggleMarkdownMark(next, marker);
        expect(back.text, text, reason: 'not its own inverse: $where');
        expect(back.selection.start, start, reason: 'selection: $where');
        expect(back.selection.end, end, reason: 'selection: $where');
        inverses++;
      }

      // A corpus that stopped reaching either branch, or the inverse, would
      // pass while testing a third of what it says. The seed is fixed.
      expect(wrapped, greaterThan(1000));
      expect(unwrapped, greaterThan(1000));
      expect(inverses, greaterThan(1000));
    });
  });
}
