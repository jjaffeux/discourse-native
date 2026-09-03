import 'package:discourse_native/src/shell/composer_blockquote.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _value(String source) {
  final caret = source.indexOf('|');
  return TextEditingValue(
    text: source.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: caret),
  );
}

void main() {
  late ComposerBlockquoteInputFormatter formatter;
  var shift = false;
  setUp(() {
    shift = false;
    formatter = ComposerBlockquoteInputFormatter(isShiftPressed: () => shift);
  });

  TextEditingValue enter(TextEditingValue value) => formatter.formatEditUpdate(
    value,
    TextEditingValue(
      text: value.text.replaceRange(
        value.selection.start,
        value.selection.end,
        '\n',
      ),
      selection: TextSelection.collapsed(offset: value.selection.start + 1),
    ),
  );

  group('quote continuation', () {
    for (final (before, after) in [
      ('> words|', '> words\n> |'),
      ('Before\n> words|', 'Before\n> words\n> |'),
      ('> one |two', '> one \n> |two'),
      ('> > nested|', '> > nested\n> > |'),
      ('> words\n> |', '> words\n> \n> |'),
      ('> |\nAfter', '> \n> |\nAfter'),
      ('>  | ', '>  \n> | '),
      ('plain|', 'plain\n|'),
      ('x > words|', 'x > words\n|'),
      ('\\> escaped|', '\\> escaped\n|'),
      ('    > code|', '    > code\n|'),
      ('```\n> code|\n```', '```\n> code\n|\n```'),
      ('~~~\n> code|', '~~~\n> code\n|'),
    ]) {
      test(before, () {
        final oldValue = _value(before);
        final caret = oldValue.selection.extentOffset;
        final proposed = TextEditingValue(
          text: oldValue.text.replaceRange(caret, caret, '\n'),
          selection: TextSelection.collapsed(offset: caret + 1),
        );

        expect(formatter.formatEditUpdate(oldValue, proposed), _value(after));
      });
    }

    test('exits only after two consecutive plain Enters', () {
      final first = enter(_value('> words|'));
      expect(first, _value('> words\n> |'));
      expect(enter(first), _value('> words\n|'));
    });

    test('Shift+Enter always continues, including on empty quote lines', () {
      shift = true;
      var value = _value('> words|');
      for (var count = 1; count <= 4; count++) {
        value = enter(value);
        expect(value, _value('> words${'\n> ' * count}|'));
      }

      shift = false;
      final first = enter(value);
      expect(first, _value('> words${'\n> ' * 5}|'));
      expect(enter(first), _value('> words${'\n> ' * 4}\n|'));
    });

    test('Shift+Enter interrupts a pending double Enter', () {
      var value = enter(_value('> words|'));
      shift = true;
      value = enter(value);
      expect(value, _value('> words\n> \n> |'));
      shift = false;
      value = enter(value);
      expect(value, _value('> words\n> \n> \n> |'));
      expect(enter(value), _value('> words\n> \n> \n|'));
    });

    test('moving the caret away and back interrupts consecutive Enters', () {
      final first = enter(_value('> words|'));
      formatter.observeValue(
        first.copyWith(selection: const TextSelection.collapsed(offset: 2)),
      );
      formatter.observeValue(first);
      expect(enter(first), _value('> words\n> \n> |'));
    });

    test('typing and deleting interrupts consecutive Enters', () {
      final first = enter(_value('> words|'));
      final typed = formatter.formatEditUpdate(first, _value('> words\n> x|'));
      final deleted = formatter.formatEditUpdate(typed, first);
      expect(enter(deleted), _value('> words\n> \n> |'));
    });

    test('replacing selected quote text with a line break stays inside', () {
      shift = true;
      expect(
        enter(
          const TextEditingValue(
            text: '> words',
            selection: TextSelection(baseOffset: 2, extentOffset: 7),
          ),
        ),
        _value('> \n> |'),
      );
    });

    test('leaves paste, deletion and IME unchanged', () {
      for (final (oldValue, proposed) in [
        (_value('> words|'), _value('> words\npasted\n|')),
        (_value('> |'), _value('>|')),
        (
          _value('> words|'),
          const TextEditingValue(
            text: '> words\n',
            selection: TextSelection.collapsed(offset: 8),
            composing: TextRange(start: 2, end: 8),
          ),
        ),
      ]) {
        expect(formatter.formatEditUpdate(oldValue, proposed), proposed);
      }
    });
  });
}
