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

  test('builds the same ordered result facets as core header search', () {
    final results = SearchResults.fromJson(const {
      'topics': [
        {'id': 12, 'title': 'Native search', 'slug': 'native-search'},
      ],
      'posts': [
        {
          'id': 91,
          'topic_id': 12,
          'post_number': 4,
          'username': 'sam',
          'blurb': 'A result',
        },
      ],
      'categories': [
        {'id': 3, 'name': 'Development', 'slug': 'dev', 'color': '0088CC'},
      ],
      'tags': [
        {'id': 7, 'name': 'flutter', 'slug': 'flutter'},
      ],
      'users': [
        {
          'id': 5,
          'username': 'sam',
          'name': 'Sam Example',
          'avatar_template': '/user_avatar/example.com/sam/{size}/1.png',
        },
      ],
      'groups': [
        {'id': 9, 'name': 'team', 'full_name': 'The Team'},
      ],
      'grouped_search_result': {
        'more_posts': true,
        'more_categories': false,
        'more_users': true,
      },
    }, 'https://example.com');

    expect(results.sections.map((section) => section.kind), [
      SearchResultKind.topic,
      SearchResultKind.category,
      SearchResultKind.tag,
      SearchResultKind.user,
      SearchResultKind.group,
    ]);
    expect(results.results.map((result) => result.path), [
      '/t/native-search/12/4',
      '/c/dev/3',
      '/tag/flutter/7',
      '/u/sam',
      '/g/team',
    ]);
    expect(results.sections.first.hasMore, isTrue);
    expect(results.sections[3].hasMore, isTrue);
    expect((results.results[3] as SearchUserHit).avatarUrl, contains('/sam/'));
  });

  test('drops malformed individual facets without dropping valid sections', () {
    final results = SearchResults.fromJson(const {
      'categories': [
        {'name': 'No id'},
      ],
      'tags': [
        {'name': 'valid-tag'},
        {'id': 2},
      ],
      'users': [
        {'id': 3},
      ],
      'groups': [
        {'id': 4, 'name': 'valid-group'},
      ],
    }, 'https://example.com');

    expect(results.sections.map((section) => section.kind), [
      SearchResultKind.tag,
      SearchResultKind.group,
    ]);
  });
}
