import 'dart:convert';

import 'package:discourse_native/src/models/badge_route.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://example.com/forum';
  test('reads directory, badge, and username-filtered subfolder links', () {
    expect(
      BadgeRoute.parse('$site/badges/', siteUrl: site),
      const BadgeRoute.directory(),
    );
    final route = BadgeRoute.parse(
      '$site/badges/12/premier-%C3%A9moji?username=sam',
      siteUrl: site,
    )!;
    expect(route.badgeId, 12);
    expect(route.slug, 'premier-émoji');
    expect(route.username, 'sam');
    expect(route.path, '/badges/12/premier-%C3%A9moji?username=sam');
    expect(route.id, isNot(BadgeRoute.detail(12).id));
  });

  test('rejects malformed and unrelated routes', () {
    for (final path in [
      '/badges/1',
      '/forum/badges/0',
      '/forum/badges/nope',
      '/forum/badges/1/name/extra',
      '/forum/badges/1/%FF',
      '/forum/badges/1/a%2Fb',
      '/forum/badges/1?username=a%2Fb',
      '/forum/badges/${'9' * 100}',
      '/forum/g/staff',
    ]) {
      expect(
        BadgeRoute.parse('https://example.com$path', siteUrl: site),
        isNull,
        reason: path,
      );
    }
    expect(BadgeRoute.parse('javascript:badges/1', siteUrl: site), isNull);
  });

  test(
    'saved badge tabs retain filters and reject conflicting route fields',
    () {
      final content = ContentRoute.badges(
        BadgeRoute.detail(12, slug: 'reader', username: 'sam'),
        title: 'Reader',
      );
      final wire =
          jsonDecode(jsonEncode(content.toJson())) as Map<String, dynamic>;
      final restored = ContentRoute.fromJson(wire);
      expect(restored, content);
      expect(restored.badgeRoute, content.badgeRoute);
      expect(restored.isBadges, isTrue);
      for (final changed in [
        {...wire, 'topic_id': 1},
        {...wire, 'id': 'users'},
        {...wire, 'feed_path': '/latest.json'},
        {
          ...wire,
          'badge_route': {'badge_id': -1},
        },
      ]) {
        expect(() => ContentRoute.fromJson(changed), throwsFormatException);
      }
    },
  );
}
