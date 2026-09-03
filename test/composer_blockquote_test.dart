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
  const formatter = ComposerBlockquoteInputFormatter();

  group('quote continuation', () {
    for (final (before, after) in [
      ('> words|', '> words\n> |'),
      ('Before\n> words|', 'Before\n> words\n> |'),
      ('> one |two', '> one \n> |two'),
      ('> > nested|', '> > nested\n> > |'),
      ('> words\n> |', '> words\n|'),
      ('> |\nAfter', '|\nAfter'),
      ('>  | ', '|'),
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

    test('leaves paste, selection replacement, deletion and IME unchanged', () {
      for (final (oldValue, proposed) in [
        (_value('> words|'), _value('> words\npasted\n|')),
        (
          const TextEditingValue(
            text: '> words',
            selection: TextSelection(baseOffset: 2, extentOffset: 7),
          ),
          _value('> \n|'),
        ),
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
