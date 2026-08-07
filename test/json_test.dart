import 'package:discourse_native/src/models/json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('jsonInt', () {
    test('passes numbers through, rounding down a double', () {
      expect(jsonInt(7), 7);
      expect(jsonInt(7.9), 7);
    });

    test('parses the strings Discourse sends for some counts', () {
      expect(jsonInt('7'), 7);
      expect(jsonInt('not a number'), 0);
    });

    test('answers silence with zero', () {
      expect(jsonInt(null), 0);
      expect(jsonInt(true), 0);
      expect(jsonInt(const <String, dynamic>{}), 0);
    });
  });

  group('jsonIntOrNull', () {
    test('parses like jsonInt, but answers silence with null', () {
      expect(jsonIntOrNull(7), 7);
      expect(jsonIntOrNull('7'), 7);
      expect(jsonIntOrNull('not a number'), isNull);
      expect(jsonIntOrNull(null), isNull);
    });
  });

  group('jsonText', () {
    test('trims what is there', () {
      expect(jsonText('  sam  '), 'sam');
    });

    test('answers null for what is not worth keeping', () {
      expect(jsonText(null), isNull);
      expect(jsonText(''), isNull);
      expect(jsonText('   '), isNull);
      expect(jsonText(7), isNull);
    });
  });

  group('jsonDate', () {
    test('parses what Discourse sends', () {
      expect(jsonDate('2026-08-07T09:30:00.000Z'),
          DateTime.parse('2026-08-07T09:30:00.000Z'));
    });

    test('answers null for what is not a date', () {
      expect(jsonDate(null), isNull);
      expect(jsonDate('someday'), isNull);
      expect(jsonDate(7), isNull);
    });
  });

  group('jsonTitle', () {
    test('prefers the plain one', () {
      expect(jsonTitle('A topic', 'A&nbsp;topic'), 'A topic');
    });

    test('unescapes the fancy one when it is all there is', () {
      // `fancy_title` is HTML — smart quotes as entities, ampersands escaped —
      // and widgets are owed the text behind it, not the entities.
      expect(jsonTitle(null, '&ldquo;quoted&rdquo; &amp; more'),
          '\u201cquoted\u201d & more');
    });

    test('falls past a blank plain one', () {
      expect(jsonTitle('', '&amp;'), '&');
    });

    test('answers empty when the site sent neither', () {
      expect(jsonTitle(null, null), '');
      expect(jsonTitle('', ''), '');
    });
  });
}
