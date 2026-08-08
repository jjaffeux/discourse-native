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
  });
}
