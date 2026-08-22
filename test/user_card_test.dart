import 'package:discourse_native/src/shell/user_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('usernameFromProfileUrl', () {
    test('reads the username from a profile root', () {
      expect(usernameFromProfileUrl(Uri.parse('https://site/u/sam')), 'sam');
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://site/u/sam'),
          siteUrl: 'https://site',
        ),
        'sam',
      );
    });

    test('leaves profile subpages to the browser', () {
      // `/u/someone/messages` is a page of its own, not a person.
      expect(
        usernameFromProfileUrl(Uri.parse('https://site/u/sam/messages')),
        isNull,
      );
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://site/u/sam/summary'),
          siteUrl: 'https://site',
        ),
        isNull,
      );
    });

    test('reads the username from a subfolder profile root', () {
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://example.com/forum/u/sam'),
          siteUrl: 'https://example.com/forum',
        ),
        'sam',
      );
    });

    test('leaves subfolder profile subpages to the browser', () {
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://example.com/forum/u/sam/messages'),
          siteUrl: 'https://example.com/forum',
        ),
        isNull,
      );
    });

    test('the leading segments must be the site base path', () {
      // `/t/u/42` is a topic whose slug happens to be `u`; a match here would
      // hijack the tap away from the topic view.
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://example.com/t/u/42'),
          siteUrl: 'https://example.com',
        ),
        isNull,
      );
      // A root-level profile URL is not a page a subfolder site serves.
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://example.com/u/sam'),
          siteUrl: 'https://example.com/forum',
        ),
        isNull,
      );
    });

    test('answers nothing for an empty or missing username', () {
      expect(usernameFromProfileUrl(Uri.parse('https://site/u')), isNull);
      expect(usernameFromProfileUrl(Uri.parse('https://site/u/')), isNull);
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://example.com/forum/u/'),
          siteUrl: 'https://example.com/forum',
        ),
        isNull,
      );
    });
  });
}
