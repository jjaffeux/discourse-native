import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'search operators stay on the remote endpoint with excerpts and bounded pagination',
    () async {
      final requests = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'posts': [
                {
                  'id': 70,
                  'topic_id': 7,
                  'post_number': 4,
                  'username': 'sam',
                  'blurb': 'Design the keyboard flow.',
                },
              ],
              'topics': [
                {
                  'id': 7,
                  'title': 'Design keyboard',
                  'slug': 'design-keyboard',
                  'posts_count': 12,
                  'category_id': 3,
                },
              ],
              'grouped_search_result': {'more_full_page_results': true},
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.topicList(
        siteUrl: 'https://example.com',
        path: '/search.json?q=design%20keyboard%20%40sam&page=1',
      );
      expect(result.topics.single.id, 7);
      expect(result.topics.single.excerpt, 'Design the keyboard flow.');
      expect(result.topics.single.categoryId, 3);
      expect(requests.single.queryParameters['q'], 'design keyboard @sam');
      expect(Uri.parse(result.nextPagePath!).queryParameters['page'], '2');
      final last = await api.topicList(
        siteUrl: 'https://example.com',
        path: '/search.json?q=design%20keyboard%20%40sam&page=10',
      );
      expect(last.nextPagePath, isNull);
    },
  );
  for (final prefix in ['', '/forum', '/forum%20space', '/caf%C3%A9']) {
    test('search follows page two under site prefix "$prefix"', () async {
      final requests = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request.url);
          final page = int.parse(request.url.queryParameters['page']!);
          return http.Response(
            jsonEncode({
              'posts': [
                {
                  'id': 70 + page,
                  'topic_id': 7 + page,
                  'post_number': 4,
                  'username': 'sam',
                  'blurb': 'Search excerpt $page.',
                },
              ],
              'topics': [
                {
                  'id': 7 + page,
                  'title': 'Search result $page',
                  'slug': 'search-result-$page',
                  'posts_count': 12,
                  'category_id': 3,
                },
              ],
              'grouped_search_result': {'more_full_page_results': page == 1},
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final siteUrl = 'https://example.com$prefix';
      final path = Uri(
        path: '/search.json',
        queryParameters: {
          'q': 'in:messages @sam "design keyboard"',
          'page': '1',
          'search_context[type]': 'user',
          'search_context[id]': 'sam',
        },
      ).toString();
      final first = await api.topicList(siteUrl: siteUrl, path: path);

      expect(first.topics.single.id, 8);
      expect(first.topics.single.excerpt, 'Search excerpt 1.');
      expect(first.nextPagePath, isNotNull);
      final next = Uri.parse(first.nextPagePath!);
      expect(next.path, '/search.json');
      expect(next.queryParameters, {
        ...Uri.parse(path).queryParameters,
        'page': '2',
      });

      final second = await api.topicList(
        siteUrl: siteUrl,
        path: first.nextPagePath!,
      );
      expect(second.topics.single.id, 9);
      expect(second.topics.single.excerpt, 'Search excerpt 2.');
      expect(second.nextPagePath, isNull);
      expect(requests.map((uri) => uri.path), [
        '$prefix/search.json',
        '$prefix/search.json',
      ]);
      expect(requests.first.queryParameters, Uri.parse(path).queryParameters);
      expect(requests.last.queryParameters, next.queryParameters);
    });
  }
}
