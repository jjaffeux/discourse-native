import 'package:discourse_native/src/foundation/count_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('countLabel', () {
    test('names exactly one in the singular and every other count plural', () {
      expect(countLabel(1, CountNoun.badge), '1 badge');
      expect(countLabel(0, CountNoun.badge), '0 badges');
      expect(countLabel(2, CountNoun.badge), '2 badges');
      expect(countLabel(-1, CountNoun.badge), '-1 badges');
    });

    test('takes the plural of a noun that does not add an s', () {
      expect(countLabel(1, CountNoun.reply), '1 reply');
      expect(countLabel(2, CountNoun.reply), '2 replies');
      expect(countLabel(1, CountNoun.person), '1 person');
      expect(countLabel(3, CountNoun.person), '3 people');
    });

    test('writes the number as given while the noun follows the count', () {
      expect(countLabel(1, CountNoun.click, number: '1'), '1 click');
      expect(
        countLabel(1204, CountNoun.click, number: '1,204'),
        '1,204 clicks',
      );
      expect(countLabel(1200, CountNoun.like, number: '1.2K'), '1.2K likes');
    });
  });

  group('countNoun', () {
    test('agrees with the count without writing it', () {
      expect(countNoun(1, CountNoun.like), 'like');
      expect(countNoun(0, CountNoun.like), 'likes');
      expect(countNoun(1, CountNoun.reply), 'reply');
      expect(countNoun(4, CountNoun.reply), 'replies');
    });
  });
}
