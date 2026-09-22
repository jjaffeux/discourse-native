import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reset-new uses core scope and omits false flags', () async {
    final api = DiscourseApi(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/topics/reset-new');
        expect(jsonDecode(request.body), {
          'tracked': false,
          'dismiss_topics': true,
          'category_id': 4,
          'include_subcategories': true,
          'tag_name': 'support',
        });
        return http.Response('{"topic_ids":[1,2,3]}', 200);
      }),
    );
    expect(
      await api.dismissNewTopics(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        dismissTopics: true,
        dismissPosts: false,
        categoryId: 4,
        tagName: 'support',
      ),
      [1, 2, 3],
    );
  });

  test('empty explicit intersection never becomes a global reset', () async {
    final api = DiscourseApi(
      client: MockClient((_) async {
        fail('Empty intersections must not send a write.');
      }),
    );
    expect(
      await api.dismissNewTopics(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        dismissTopics: true,
        dismissPosts: true,
        topicIds: [],
      ),
      isEmpty,
    );
  });
}
