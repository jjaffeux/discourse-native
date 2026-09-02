import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/topic_link.dart';
import 'package:flutter_test/flutter_test.dart';

TopicLink? parse(String url) => TopicLink.parse(url);

void main() {
  group('TopicLink.parse', () {
    test('reads the shape Discourse writes', () {
      final link = parse('https://meta.discourse.org/t/a-real-topic/12345')!;

      expect(link.topicId, 12345);
      expect(link.slug, 'a-real-topic');
      expect(link.uri.host, 'meta.discourse.org');
    });

    test('reads a numbered post and ignores named positions', () {
      final numbered = parse('https://meta.discourse.org/t/a/12/34');
      expect(numbered?.topicId, 12);
      expect(numbered?.postNumber, 34);

      final named = parse('https://meta.discourse.org/t/a/12/last');
      expect(named?.topicId, 12);
      expect(named?.postNumber, isNull);
    });

    test('ignores the query and fragment', () {
      expect(
        parse('https://meta.discourse.org/t/a/12?u=sam#reply')?.topicId,
        12,
      );
    });

    test('reads a slugless permalink', () {
      final link = parse('https://meta.discourse.org/t/12345')!;

      expect(link.topicId, 12345);
      expect(link.slug, isEmpty);
    });

    test('resolves a site-relative link, which is how posts are written', () {
      expect(parse('/t/a-real-topic/12345')?.topicId, 12345);
    });

    test('claims nothing but topics', () {
      for (final url in const [
        'https://meta.discourse.org',
        'https://meta.discourse.org/latest',
        'https://meta.discourse.org/u/someone',
        'https://meta.discourse.org/c/bug/5',
        'https://meta.discourse.org/tag/topics',
        'https://meta.discourse.org/t/a-real-topic',
        'https://meta.discourse.org/t/a-real-topic/none',
        'https://meta.discourse.org/t/a-real-topic/0',
      ]) {
        expect(parse(url), isNull, reason: url);
      }
    });

    test('reads a link under the forum\'s subfolder, and no other', () {
      final link = TopicLink.parse(
        'https://example.com/forum/t/a-topic/7/2',
        siteUrl: 'https://example.com/forum',
      );

      expect(link?.topicId, 7);
      expect(link?.slug, 'a-topic');
      expect(link?.postNumber, 2);
      expect(
        TopicLink.parse(
          'https://example.com/t/a-topic/7',
          siteUrl: 'https://example.com/forum',
        ),
        isNull,
      );
      expect(
        TopicLink.parse(
          'https://meta.discourse.org/t/a-topic/7',
          siteUrl: 'https://meta.discourse.org',
        )?.topicId,
        7,
      );
    });

    test('rejects oversized and credential-bearing links', () {
      expect(parse('/t/${'a' * TopicLink.maximumUrlLength}/1'), isNull);
      expect(parse('https://user:secret@meta.discourse.org/t/a/1'), isNull);
    });

    test('names the topic after its slug until the real title lands', () {
      expect(
        parse('https://meta.discourse.org/t/a-real-topic/1')?.placeholderTitle,
        'A real topic',
      );
      expect(
        parse('https://meta.discourse.org/t/1')?.placeholderTitle,
        'Topic',
      );
    });
  });

  group('DiscourseInstance.serves', () {
    const meta = DiscourseInstance(
      url: 'https://meta.discourse.org',
      title: 'Discourse Meta',
    );
    const dev = DiscourseInstance(
      url: 'http://localhost:4200',
      title: 'Development',
    );

    test('claims its own pages', () {
      expect(
        meta.serves(Uri.parse('https://meta.discourse.org/t/a/1')),
        isTrue,
      );
    });

    test('does not care which scheme the link was written with', () {
      // Posts written years ago still link to http.
      expect(meta.serves(Uri.parse('http://meta.discourse.org/t/a/1')), isTrue);
    });

    test('leaves another site alone', () {
      expect(meta.serves(Uri.parse('https://example.com/t/a/1')), isFalse);
      expect(
        meta.serves(Uri.parse('https://team.discourse.org/t/a/1')),
        isFalse,
      );
    });

    test('claims only the pages under its subfolder', () {
      const sub = DiscourseInstance(
        url: 'https://example.com/forum',
        title: 'Subfolder',
      );

      expect(sub.serves(Uri.parse('https://example.com/forum/t/a/1')), isTrue);
      expect(sub.serves(Uri.parse('https://example.com/forum')), isTrue);
      expect(sub.serves(Uri.parse('https://example.com/t/a/1')), isFalse);
      expect(
        sub.serves(Uri.parse('https://example.com/forums/t/a/1')),
        isFalse,
      );
      expect(sub.basePathSegments, ['forum']);
      expect(meta.basePathSegments, isEmpty);
    });

    test('tells two development forums apart by their port', () {
      expect(dev.serves(Uri.parse('http://localhost:4200/t/a/1')), isTrue);
      expect(dev.serves(Uri.parse('http://localhost:3000/t/a/1')), isFalse);
    });

    test('cannot claim a link that names no site at all', () {
      expect(meta.serves(Uri.parse('/t/a/1')), isFalse);
    });
  });
}
