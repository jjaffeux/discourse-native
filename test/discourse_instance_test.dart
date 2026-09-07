import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
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
      expect(section.moreDestinations, isEmpty);
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
}
