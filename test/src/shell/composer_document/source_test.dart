import 'package:discourse_native/src/shell/composer_document/source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerSourceRange', () {
    test('uses exact UTF-16 code-unit offsets', () {
      const source = '😀x';
      const emoji = ComposerSourceRange(0, 2);

      expect(source.length, 3);
      expect(emoji.capture(source), '😀');
      expect(emoji.isValidFor(source), isTrue);
    });

    test('allows unchecked parser ranges to be validated without throwing', () {
      const malformed = ComposerSourceRange(-1, 20);

      expect(malformed.isValidFor('short'), isFalse);
      expect(() => malformed.capture('short'), throwsRangeError);
    });
  });

  test('ComposerRevision is monotonic and value-comparable', () {
    const revision = ComposerRevision(4);

    expect(revision.next, const ComposerRevision(5));
    expect(revision.compareTo(revision.next), lessThan(0));
  });
}
