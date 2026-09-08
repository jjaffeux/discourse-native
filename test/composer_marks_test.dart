import 'dart:convert';
import 'dart:math';

import 'package:discourse_native/src/shell/composer_marks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expectToggle('say [hello] there', '**', 'say **[hello]** there');
      expectToggle('say [hello] there', '*', 'say *[hello]* there');
      expectToggle('say [hello] there', '`', 'say `[hello]` there');
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
      expectToggle('say [**hello**] there', '*', 'say *[**hello**]* there');
      expectToggle('say **[hello]** there', '*', 'say ***[hello]*** there');
    });

    test('appends at the end when there is no selection at all', () {
      for (final marker in ['**', '*']) {
        final result = toggleMarkdownMark(
          const TextEditingValue(text: 'say'),
          marker,
        );
        expect(result.text, 'say$marker$marker');
        expect(
          result.selection,
          TextSelection.collapsed(offset: 3 + marker.length),
        );
      }
    });

    test('is its own inverse', () {
      for (final marker in ['**', '*', '`']) {
        const start = 'say [hello] there';
        final once = toggleMarkdownMark(selected(start), marker);
        expect(showSelection(toggleMarkdownMark(once, marker)), start);
      }
    });

    for (final marker in ['**', '*']) {
      group('$marker emphasis', () {
        for (final (leading, trailing) in [
          (' ', ''),
          ('', ' '),
          ('  ', '  '),
          ('\t', ''),
          ('', '\t'),
          ('\t', '\t'),
          ('\n', ''),
          ('', '\n'),
          ('\r\n', '\r\n'),
          (' \t\n', '\n\t '),
        ]) {
          test(
            'keeps boundary ${jsonEncode([leading, trailing])} outside toggles',
            () {
              final original = selected('say [${leading}hello$trailing] there');

              final once = toggleMarkdownMark(original, marker);

              expect(
                showSelection(once),
                'say $leading$marker[hello]$marker$trailing there',
              );
              expect(
                showSelection(toggleMarkdownMark(once, marker)),
                'say $leading[hello]$trailing there',
              );
            },
          );
        }

        test('preserves whitespace inside the selected prose', () {
          expectToggle(
            'say [\nhello \tworld🙂\n] there',
            marker,
            'say \n$marker[hello \tworld🙂]$marker\n there',
          );
        });

        test('unwraps selected markers with whitespace around them', () {
          expectToggle(
            'say [ \t${marker}hello$marker\n] there',
            marker,
            'say  \t[hello]\n there',
          );
        });

        test(
          'still unwraps markers immediately around selected whitespace',
          () {
            expectToggle(
              'say $marker[ \thello\n]$marker there',
              marker,
              'say [ \thello\n] there',
            );
          },
        );

        test('uses an empty span before an all-whitespace selection', () {
          final once = toggleMarkdownMark(
            selected('say [ \t\n] there'),
            marker,
          );

          expect(showSelection(once), 'say $marker[]$marker \t\n there');
          expect(
            showSelection(toggleMarkdownMark(once, marker)),
            'say [] \t\n there',
          );
        });

        test(
          'keeps the caret between empty markers through repeated toggles',
          () {
            for (final source in ['[]', 'say [] there']) {
              final original = selected(source);
              final once = toggleMarkdownMark(original, marker);

              expect(
                showSelection(once),
                source.replaceFirst('[]', '$marker[]$marker'),
              );
              expect(toggleMarkdownMark(once, marker), original);
            }
          },
        );
      });
    }

    group('inline code', () {
      final literalCases = <String, String>{
        'a`b': '``a`b``',
        'a``b`c': '```a``b`c```',
        r'a\`b': r'``a\`b``',
        '`hello': '`` `hello ``',
        'hello`': '`` hello` ``',
        '`hello``': '``` `hello`` ```',
        '`': '`` ` ``',
        '``': '``` `` ```',
        ' hello': '` hello`',
        'hello ': '`hello `',
        ' hello ': '`  hello  `',
        '  hello  ': '`   hello   `',
        ' ': '`   `',
        '  ': '`    `',
        '   ': '`     `',
      };

      for (final entry in literalCases.entries) {
        test('preserves literal ${jsonEncode(entry.key)} through toggles', () {
          final original = selected('say [${entry.key}] there');

          final once = toggleMarkdownMark(original, '`');

          expect(once.text, 'say ${entry.value} there');
          expect(once.selection.textInside(once.text), entry.key);
          expect(toggleMarkdownMark(once, '`'), original);
        });
      }

      test('unwraps complete existing spans with any delimiter length', () {
        expectToggle('say [`hello`] there', '`', 'say [hello] there');
        expectToggle('say [``a`b``] there', '`', 'say [a`b] there');
        expectToggle('say [```a``b`c```] there', '`', 'say [a``b`c] there');
        expectToggle('say [`a``b`] there', '`', 'say [a``b] there');
      });

      test('removes only the boundary spaces stripped by Discourse', () {
        expectToggle('say [`` `hello` ``] there', '`', 'say [`hello`] there');
        expectToggle('say [`  hello  `] there', '`', 'say [ hello ] there');
        expectToggle('say [` `] there', '`', 'say [ ] there');
        expectToggle('say [`  `] there', '`', 'say [  ] there');
        expectToggle('say [`   `] there', '`', 'say [ ] there');
      });

      test('unwraps surrounding spans before considering selected ticks', () {
        expectToggle('say ``[a`b]`` there', '`', 'say [a`b] there');
        expectToggle('say ```[a``b`c]``` there', '`', 'say [a``b`c] there');
        expectToggle('say `` [`hello`] `` there', '`', 'say [`hello`] there');
        expectToggle('say ` [ hello ] ` there', '`', 'say [ hello ] there');
        expectToggle('say `[  hello  ]` there', '`', 'say [ hello ] there');
        expectToggle('say ` [hello]` there', '`', 'say  [hello] there');
      });

      test('does not unwrap unmatched ticks or separate code spans', () {
        expectToggle(
          'say [``hello`] there',
          '`',
          'say ``` [``hello`] ``` there',
        );
        expectToggle('say [`a`b`] there', '`', 'say `` [`a`b`] `` there');
        expectToggle(
          'say [`a` and `b`] there',
          '`',
          'say `` [`a` and `b`] `` there',
        );
      });

      test('keeps reversed UTF-16 selection offsets and clears composing', () {
        const original = TextEditingValue(
          text: 'say 🙂`b now',
          selection: TextSelection(
            baseOffset: 8,
            extentOffset: 4,
            affinity: TextAffinity.upstream,
            isDirectional: true,
          ),
          composing: TextRange(start: 4, end: 8),
        );

        final once = toggleMarkdownMark(original, '`');

        expect(once.text, 'say ``🙂`b`` now');
        expect(
          once.selection,
          original.selection.copyWith(baseOffset: 10, extentOffset: 6),
        );
        expect(once.composing, TextRange.empty);
        expect(
          toggleMarkdownMark(once, '`'),
          original.copyWith(composing: TextRange.empty),
        );
      });
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
        // selection and the characters against it are prose. Boundary
        // whitespace stays in the document but outside the returned selection.
        final edges = text.substring(
          start == 0 ? 0 : start - 1,
          end == text.length ? end : end + 1,
        );
        if (edges.contains('*')) continue;
        final back = toggleMarkdownMark(next, marker);
        expect(back.text, text, reason: 'not its own inverse: $where');
        expect(
          back.selection.start,
          inInclusiveRange(start, end),
          reason: 'selection: $where',
        );
        expect(
          back.selection.end,
          inInclusiveRange(start, end),
          reason: 'selection: $where',
        );
        expect(
          back.selection.textInside(text),
          text.substring(start, end).trim(),
          reason: 'selected prose: $where',
        );
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
