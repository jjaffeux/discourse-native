import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removing a forum prefix preserves encoded segment boundaries', () {
    const instance = DiscourseInstance(
      url: 'https://example.com/my%20forum',
      title: 'Forum',
    );
    for (final segment in ['café', 'qa?review#notes', 'a/b', '100%']) {
      final source = Uri(
        scheme: 'https',
        host: 'example.com',
        pathSegments: ['my forum', 'tag', segment],
      );
      final path = Uri.parse(instance.pathWithin(source)!);

      expect(path.hasQuery, isFalse);
      expect(path.hasFragment, isFalse);
      expect(path.pathSegments, ['tag', segment]);
    }
  });

  group('DiscourseInstance.monogram', () {
    String monogram(String title) =>
        DiscourseInstance(url: 'https://example.com', title: title).monogram;

    test('preserves empty, single-word, and multiword initials', () {
      expect(monogram(''), '?');
      expect(monogram(' \t\n '), '?');
      expect(monogram('D'), 'D');
      expect(monogram('Discourse'), 'DI');
      expect(monogram('  Discourse\tMeta\nForum  '), 'DM');
    });

    test('only observes the first two words of an oversized title', () {
      final title = 'Alpha Beta ${List.filled(200000, 'ignored').join(' ')}';

      expect(monogram(title), 'AB');
    });
  });

  group('DiscourseInstance.sections', () {
    test('keeps Users and Filter visible and Groups in More', () {
      final section = const DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
      ).sections.single;

      expect(section.destinations.map((destination) => destination.id), [
        'latest',
        'users',
        'filter',
      ]);
      expect(section.moreDestinations.map((destination) => destination.id), [
        'groups',
        'badges',
      ]);
    });

    test('removes Groups from More when the directory is disabled', () {
      final section = const DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        config: SiteConfig(groupDirectoryEnabled: false),
      ).sections.single;

      expect(section.destinations.map((destination) => destination.id), [
        'latest',
        'users',
        'filter',
      ]);
      expect(section.moreDestinations.map((destination) => destination.id), [
        'badges',
      ]);
    });

    test('keeps Filter visible for connected accounts', () {
      final section = const DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        user: DiscourseUser(id: 1, username: 'reader'),
      ).sections.single;

      expect(section.destinations.map((destination) => destination.id), [
        'latest',
        'messages',
        'drafts',
        'users',
        'filter',
      ]);
      expect(section.moreDestinations.map((destination) => destination.id), [
        'groups',
        'badges',
      ]);
    });

    test(
      'keeps Users prominent and removes it when its directory is disabled',
      () {
        final connected = const DiscourseInstance(
          url: 'https://example.com',
          title: 'Example',
          config: SiteConfig(userDirectoryEnabled: false),
        ).sections.single;

        expect(connected.destinations.map((destination) => destination.id), [
          'latest',
          'filter',
        ]);
      },
    );
  });

  group('DiscourseInstance.sectionsWithCustomSections', () {
    final configured = SidebarSection.customFromJson({
      'id': 1,
      'title': 'Community',
      'section_type': 'community',
      'links': [
        for (final (index, link) in const [
          ('About us', '/about'),
          ('Members', '/u'),
          ('Teams', '/g'),
          ('Guidelines', '/faq'),
          ('Badges', '/badges'),
          ('Review', '/review'),
          ('Invite', '/new-invite'),
          ('Administration', '/admin'),
          ('Topics', '/latest'),
          ('Messages', '/my/messages'),
          ('My posts', '/my/activity'),
          ('Filter', '/filter'),
          ('Documentation', 'https://docs.example.com'),
        ].indexed)
          {
            'id': index,
            'name': link.$1,
            'value': link.$2,
            'icon': 'fire',
            'segment': 'secondary',
          },
      ],
    }, index: 0)!;

    test(
      'merges ordered More links with native routes and custom sections',
      () {
        const site = DiscourseInstance(
          url: 'https://example.com/forum',
          title: 'Example',
          user: DiscourseUser(id: 1, username: 'staff', staff: true),
        );
        const projects = SidebarSection(
          id: 'custom-2',
          title: 'Projects',
          destinations: [],
        );

        final sections = site.sectionsWithCustomSections([
          configured,
          projects,
        ]);

        expect(sections.map((section) => section.id), [
          'community',
          'custom-2',
        ]);
        expect(sections.last, same(projects));
        expect(
          sections.first.destinations,
          same(site.sections.first.destinations),
        );
        expect(
          sections.first.moreDestinations.map(
            (destination) => destination.label,
          ),
          [
            'About us',
            'Teams',
            'Guidelines',
            'Badges',
            'Administration',
            'Documentation',
          ],
        );
        final groups = sections.first.moreDestinations[1];
        expect(groups.id, 'groups');
        expect(groups.url, isNull);
        expect(groups.icon, DIcons.fire);
        final badges = sections.first.moreDestinations[3];
        expect(badges.id, 'badges');
        expect(badges.url, isNull);
        expect(
          sections.first.moreDestinations.first.url,
          'https://example.com/forum/about',
        );
        expect(
          sections.first.moreDestinations[2].url,
          'https://example.com/forum/faq',
        );
        expect(
          sections.first.moreDestinations.last.url,
          'https://docs.example.com',
        );
      },
    );

    test('applies site and account visibility to configured More links', () {
      const models = DiscourseModelCodec.core();
      final reviewer = models.currentUser({
        'username': 'reviewer',
        'can_review': true,
        'can_invite_to_forum': true,
      }, 'https://example.com');
      final site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        config: const SiteConfig(
          groupDirectoryEnabled: false,
          badgesEnabled: false,
        ),
        user: DiscourseUser.fromJson(reviewer.toJson()).withDraftCount(3),
      );

      expect(
        site
            .sectionsWithCustomSections([configured])
            .single
            .moreDestinations
            .map((destination) => destination.label),
        ['About us', 'Guidelines', 'Review', 'Invite', 'Documentation'],
      );
      expect(
        site
            .copyWith(clearUser: true)
            .sectionsWithCustomSections([configured])
            .single
            .moreDestinations
            .map((destination) => destination.label),
        ['About us', 'Guidelines', 'Documentation'],
      );
    });

    test('retains native More destinations absent from the server section', () {
      const site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        user: DiscourseUser(id: 1, username: 'staff', staff: true),
      );
      const configured = SidebarSection(
        id: 'community',
        title: 'Community',
        destinations: [],
        moreDestinations: [
          SidebarDestination(
            id: 'community-1-1',
            label: 'About',
            icon: DIcons.circleInfo,
            url: '/about',
          ),
        ],
      );

      expect(
        site
            .sectionsWithCustomSections([configured])
            .single
            .moreDestinations
            .map((destination) => destination.label),
        ['About', 'Groups', 'Badges', 'Admin'],
      );
    });
  });
}
