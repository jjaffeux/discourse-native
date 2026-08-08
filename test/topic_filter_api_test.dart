import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'filter lookups use core endpoints and parse their descriptions',
    () async {
      final asked = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          asked.add(request.url);
          return switch (request.url.path) {
            '/tags/filter/search.json' => http.Response(
              jsonEncode({
                'results': [
                  {'name': 'bug', 'count': 4},
                ],
              }),
              200,
            ),
            '/tag_groups/filter/search.json' => http.Response(
              jsonEncode({
                'results': [
                  {
                    'name': 'Release train',
                    'tags': [
                      {'name': 'beta'},
                      {'name': 'stable'},
                    ],
                  },
                ],
              }),
              200,
            ),
            '/groups/search.json' => http.Response(
              jsonEncode([
                {'name': 'team', 'full_name': 'The Team'},
              ]),
              200,
            ),
            _ => http.Response('{}', 404),
          };
        }),
      );

      final tags = await api.searchFilterTags(
        siteUrl: 'https://example.com',
        term: 'bu',
      );
      final tagGroups = await api.searchFilterTagGroups(
        siteUrl: 'https://example.com',
        term: 'release',
      );
      final groups = await api.searchFilterGroups(
        siteUrl: 'https://example.com',
        term: 'te',
        apiKey: 'key',
      );

      expect(tags.single.description, '4');
      expect(tagGroups.single.description, 'beta, stable');
      expect(groups.single.description, 'The Team');
      expect(asked.map((uri) => uri.path), [
        '/tags/filter/search.json',
        '/tag_groups/filter/search.json',
        '/groups/search.json',
      ]);
      expect(asked[0].queryParameters, {'q': 'bu', 'limit': '5'});
      expect(asked[1].queryParameters, {'q': 'release', 'limit': '10'});
      expect(asked[2].queryParameters, {'term': 'te', 'limit': '10'});
    },
  );

  test('an empty filter user lookup asks for recently seen users', () async {
    late Uri asked;
    final api = DiscourseApi(
      client: MockClient((request) async {
        asked = request.url;
        return http.Response(jsonEncode({'users': <Object?>[]}), 200);
      }),
    );

    await api.searchUsers(siteUrl: 'https://example.com', term: '');

    expect(asked.path, '/u/search/users.json');
    expect(asked.queryParameters['last_seen_users'], 'true');
    expect(asked.queryParameters.containsKey('term'), isFalse);
  });
}
