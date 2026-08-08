import 'package:discourse_native/src/models/search_results.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('associates posts with topics and resolves transient presentation', () {
    final results = SearchResults.fromJson(const {
      'topics': [
        {'id': 12, 'title': 'A useful & safe topic', 'slug': 'useful-topic'},
      ],
      'posts': [
        {
          'id': 91,
          'topic_id': 12,
          'post_number': 4,
          'username': 'sam',
          'name': 'Sam Example',
          'avatar_template': '/user_avatar/example.com/sam/{size}/1.png',
          'created_at': '2026-08-08T10:00:00Z',
          'blurb':
              'A <span class="search-highlight">useful &amp; safe</span> answer',
        },
      ],
      'grouped_search_result': {'error': null},
    }, 'https://example.com');

    expect(results.hits, hasLength(1));
    final hit = results.hits.single;
    expect(hit.topicId, 12);
    expect(hit.postNumber, 4);
    expect(hit.topicTitle, 'A useful & safe topic');
    expect(hit.displayName, 'Sam Example');
    expect(hit.avatarUrl, contains('/user_avatar/example.com/sam/'));
    expect(hit.excerpt.plainText, 'A useful & safe answer');
    expect(
      hit.excerpt.segments
          .where((segment) => segment.highlighted)
          .map((segment) => segment.text),
      ['useful & safe'],
    );
  });

  test('skips malformed and orphaned posts without losing server errors', () {
    final results = SearchResults.fromJson(const {
      'topics': [
        {'id': 12, 'fancy_title': 'A &amp; B', 'slug': 'a-b'},
      ],
      'posts': [
        {'id': 1, 'topic_id': 999, 'post_number': 1},
        {'id': 2, 'topic_id': 12, 'post_number': 0},
        'not an object',
      ],
      'grouped_search_result': {'error': 'Search is overloaded.'},
    }, 'https://example.com');

    expect(results.hits, isEmpty);
    expect(results.error, 'Search is overloaded.');
  });

  test('collapses cooked whitespace while retaining highlight boundaries', () {
    final excerpt = SearchExcerpt.fromHtml(
      '<p>First\n <span class="search-highlight">match</span></p>'
      '<div>then <strong>more</strong></div>',
    );

    expect(excerpt.plainText, 'First match then more');
    expect(
      excerpt.segments.singleWhere((part) => part.highlighted).text,
      'match',
    );
  });
}
