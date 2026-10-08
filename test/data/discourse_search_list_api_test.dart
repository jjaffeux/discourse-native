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
}
