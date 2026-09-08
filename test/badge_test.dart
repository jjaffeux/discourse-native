import 'package:discourse_native/src/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/badge_fixtures.dart';

void main() {
  const site = 'https://example.com/forum';

  test(
    'catalog filters, deduplicates, and follows core grouping and tier order',
    () {
      final catalog = BadgeCatalog.fromJson({
        ...badgeCatalogWire,
        'badges': [
          {...badgeWire, 'id': 4, 'name': 'Gold', 'badge_type_id': 1},
          {...badgeWire, 'id': 2, 'name': 'Zebra'},
          {...badgeWire, 'id': 3, 'name': 'Silver', 'badge_type_id': 2},
          badgeWire,
          badgeWire,
          {...badgeWire, 'id': 5, 'enabled': false},
          {...badgeWire, 'id': 6, 'listable': false},
          {...badgeWire, 'id': 7, 'name': 'Custom', 'badge_grouping_id': 100},
        ],
      }, site);
      expect(catalog.groups.map((group) => group.name), [
        'Getting Started',
        'Other',
      ]);
      expect(catalog.groups.first.badges.map((badge) => badge.name), [
        'Autobiographer',
        'Zebra',
        'Silver',
        'Gold',
      ]);
      expect(catalog.total, 5);
      expect(catalog.earned, 5);
      expect(() => catalog.groups.clear(), throwsUnsupportedError);
      expect(() => catalog.groups.first.badges.clear(), throwsUnsupportedError);
    },
  );

  test(
    'preserves authored descriptions, custom artwork, and anonymous state',
    () {
      final json = {...badgeWire, 'image_url': '/forum/uploads/badge.svg'}
        ..remove('has_badge');
      final badge = DiscourseBadge.fromJson(json, site);
      expect(badge.description, contains('<a href='));
      expect(badge.longDescription, contains('<p>'));
      expect(badge.imageUrl, '$site/uploads/badge.svg');
      expect(badge.hasBadge, isNull);
      final catalog = BadgeCatalog.fromJson({
        'badges': [json],
      }, site);
      expect(catalog.hasPersonalState, isFalse);
      expect(
        DiscourseBadge.fromJson({
          ...json,
          'image_url': '//cdn.example.com/art.png',
        }, site).imageUrl,
        'https://cdn.example.com/art.png',
      );
    },
  );

  test('resolves sideloaded recipients and only links visible topics', () {
    final payload = badgeGrantsWire();
    final page = BadgeGrantPage.fromJson(payload, site);
    expect(page.grants.single.username, 'sam');
    expect(page.grants.single.postPath, '/t/welcome/100/3');
    expect(page.grants.single.grantedAt, DateTime.utc(2026, 9, 8, 9, 15));
    expect(
      BadgeGrantPage.fromJson({
        ...payload,
        'topics': const <Map<String, dynamic>>[],
      }, site).grants.single.postPath,
      isNull,
    );
  });

  test(
    'supports embedded recipients while retaining raw pagination offsets',
    () {
      final page = BadgeGrantPage.fromJson(const {
        'user_badge_info': {
          'grant_count': 2,
          'user_badges': [
            {
              'id': 1,
              'user': {
                'id': 42,
                'username': 'sam',
                'avatar_template': '/forum/avatar/{size}.png',
              },
            },
            {'id': 2, 'user_id': 99},
          ],
        },
      }, site);
      expect(page.rawCount, 2);
      expect(page.grants.length, 1);
      expect(page.total, 2);
      expect(page.grants.single.avatarUrl, '$site/avatar/90.png');
    },
  );
}
