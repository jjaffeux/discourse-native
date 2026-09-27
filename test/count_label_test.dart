import 'package:discourse_native/src/foundation/count_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('countLabel', () {
    test('names exactly one in the singular and every other count plural', () {
      expect(countLabel(1, 'badge'), '1 badge');
      expect(countLabel(0, 'badge'), '0 badges');
      expect(countLabel(2, 'badge'), '2 badges');
      expect(countLabel(-1, 'badge'), '-1 badges');
    });

    test('takes the plural of a noun that does not add an s', () {
      expect(countLabel(1, 'reply', plural: 'replies'), '1 reply');
      expect(countLabel(2, 'reply', plural: 'replies'), '2 replies');
      expect(countLabel(1, 'person', plural: 'people'), '1 person');
      expect(countLabel(3, 'person', plural: 'people'), '3 people');
    });

    test('writes the number as given while the noun follows the count', () {
      expect(countLabel(1, 'click', number: '1'), '1 click');
      expect(countLabel(1204, 'click', number: '1,204'), '1,204 clicks');
      expect(countLabel(1200, 'like', number: '1.2K'), '1.2K likes');
    });
  });

  group('countNoun', () {
    test('agrees with the count without writing it', () {
      expect(countNoun(1, 'like'), 'like');
      expect(countNoun(0, 'like'), 'likes');
      expect(countNoun(1, 'reply', plural: 'replies'), 'reply');
      expect(countNoun(4, 'reply', plural: 'replies'), 'replies');
    });
  });
}
