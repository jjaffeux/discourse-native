import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    test('keeps core secondary community links in More', () {
      final section = const DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
      ).sections.single;

      expect(section.destinations.map((destination) => destination.id), [
        'latest',
      ]);
      expect(section.moreDestinations.map((destination) => destination.id), [
        'groups',
        'filter',
      ]);
    });

    test('removes Groups from More when the directory is disabled', () {
      final section = const DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        config: SiteConfig(groupDirectoryEnabled: false),
      ).sections.single;

      expect(section.moreDestinations.map((destination) => destination.id), [
        'filter',
      ]);
    });
  });
}
