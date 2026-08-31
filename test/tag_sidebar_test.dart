import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/tag_sidebar.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SidebarTag', () {
    test('parses wire fields and persists a round-trip snapshot', () {
      final tag = SidebarTag.fromJson(const {
        'id': '7',
        'name': ' priority ',
        'slug': 'priority-tag',
        'description': ' Important topics ',
        'pm_only': true,
        'topic_count': '4',
      });

      expect(
        tag,
        const SidebarTag(
          id: 7,
          name: 'priority',
          slug: 'priority-tag',
          description: 'Important topics',
          pmOnly: true,
          count: 4,
        ),
      );
      expect(tag?.toJson(), {
        'id': 7,
        'name': 'priority',
        'slug': 'priority-tag',
        'description': 'Important topics',
        'pmOnly': true,
        'count': 4,
      });
      expect(SidebarTag.fromJson(tag!.toJson()), tag);
    });

    test('requires a positive ID and nonempty name without throwing', () {
      for (final (:label, :value) in <({String label, Object? value})>[
        (label: 'null payload', value: null),
        (label: 'string payload', value: 'tag'),
        (label: 'list payload', value: const []),
        (label: 'empty object', value: const {}),
        (label: 'zero ID', value: const {'id': 0, 'name': 'zero'}),
        (label: 'negative ID', value: const {'id': -1, 'name': 'negative'}),
        (label: 'blank name', value: const {'id': 1, 'name': '   '}),
        (
          label: 'non-scalar ID',
          value: const {'id': Object(), 'name': 'object'},
        ),
      ]) {
        expect(SidebarTag.fromJson(value), isNull, reason: label);
      }
    });

    test('falls back to the name for a missing slug and clamps counts', () {
      expect(
        SidebarTag.fromJson(const {
          'id': 8,
          'name': 'quality / safety',
          'slug': ' ',
          'count': -3,
        }),
        const SidebarTag(
          id: 8,
          name: 'quality / safety',
          slug: 'quality / safety',
        ),
      );
    });
  });

  group('buildTagSidebarSection', () {
    test('builds canonical encoded public paths', () {
      final section = buildTagSidebarSection(
        display: true,
        tags: const [
          SidebarTag(
            id: 7,
            name: 'Encoded',
            slug: 'quality%20%2F%20safety',
            count: 3,
          ),
          SidebarTag(id: 8, name: 'fallback / tag', slug: 'fallback / tag'),
        ],
      )!;

      expect(section.id, 'tags');
      expect(section.title, 'Tags');
      expect(section.collapsible, isTrue);
      expect(section.destinations.map((destination) => destination.id), [
        'tag-7',
        'tag-8',
        'all-tags',
      ]);
      expect(section.destinations.map((destination) => destination.icon), [
        DIcons.tag,
        DIcons.tag,
        DIcons.list,
      ]);
      expect(section.destinations.map((destination) => destination.feedPath), [
        '/tag/quality%20%2F%20safety/7.json',
        '/tag/fallback%20%2F%20tag/8.json',
        null,
      ]);
      expect(section.destinations.first.badge, isNull);
    });

    test('builds one reusable public destination', () {
      final destination = buildTagDestination(
        const SidebarTag(id: 9, name: 'release', slug: 'release'),
      )!;

      expect(destination.id, 'tag-9');
      expect(destination.label, 'release');
      expect(destination.icon, DIcons.tag);
      expect(destination.feedPath, '/tag/release/9.json');
    });

    test('filters private-message tags without an account username', () {
      const tags = [
        SidebarTag(id: 1, name: 'public', slug: 'public'),
        SidebarTag(
          id: 2,
          name: 'priority / private',
          slug: 'private',
          pmOnly: true,
        ),
      ];

      final anonymous = buildTagSidebarSection(display: true, tags: tags)!;
      expect(buildTagDestination(tags.last), isNull);
      expect(anonymous.destinations.map((destination) => destination.id), [
        'tag-1',
        'all-tags',
      ]);

      final connected = buildTagSidebarSection(
        display: true,
        tags: tags,
        username: 'sam name',
      )!;
      expect(connected.destinations[1].id, 'pm-tag-2');
      expect(
        connected.destinations[1].feedPath,
        ('/topics/private-messages-tags/'
            'sam%20name/priority%20%2F%20private.json'),
      );
    });

    test('keeps All tags when the displayed section has no tags', () {
      final section = buildTagSidebarSection(display: true, tags: const [])!;

      expect(section.destinations, hasLength(1));
      expect(section.destinations.single.id, 'all-tags');
      expect(section.destinations.single.label, 'All tags');
      expect(section.destinations.single.icon, DIcons.list);
    });

    test('omits the whole section when display is false', () {
      expect(
        buildTagSidebarSection(
          display: false,
          tags: const [SidebarTag(id: 1, name: 'tag', slug: 'tag')],
        ),
        isNull,
      );
    });
  });
}
