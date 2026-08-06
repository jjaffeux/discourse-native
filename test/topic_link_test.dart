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

    test('ignores what follows the id', () {
      // A post number, and the suffixed routes that name a position.
      expect(parse('https://meta.discourse.org/t/a/12/34')?.topicId, 12);
      expect(parse('https://meta.discourse.org/t/a/12/last')?.topicId, 12);
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
        // The id is what makes it a topic link.
        'https://meta.discourse.org/t/a-real-topic',
        'https://meta.discourse.org/t/a-real-topic/none',
        'https://meta.discourse.org/t/a-real-topic/0',
      ]) {
        expect(parse(url), isNull, reason: url);
      }
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

    test('tells two development forums apart by their port', () {
      expect(dev.serves(Uri.parse('http://localhost:4200/t/a/1')), isTrue);
      expect(dev.serves(Uri.parse('http://localhost:3000/t/a/1')), isFalse);
    });

    test('cannot claim a link that names no site at all', () {
      expect(meta.serves(Uri.parse('/t/a/1')), isFalse);
    });
  });
}
