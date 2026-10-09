import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card banner and role come from the forum response', () {
    final card = UserCard.fromJson(const {
      'username': 'reader',
      'admin': true,
      'card_background_upload_url': '/uploads/card.png',
    }, 'https://forum.example');
    expect(card.cardBackgroundUrl, 'https://forum.example/uploads/card.png');
    expect(card.isAdmin, isTrue);
    expect(card.isStaff, isTrue);
    expect(
      UserCard.fromJson(const {
        'username': 'reader',
        'card_background_upload_url': 'javascript:bad',
      }, 'https://forum.example').cardBackgroundUrl,
      isNull,
    );
  });

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
      expect(
        usernameFromProfileUrl(
          Uri.parse('https://example.com/t/u/42'),
          siteUrl: 'https://example.com',
        ),
        isNull,
      );
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
