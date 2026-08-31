import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('tag lookup uses the core endpoint and count description', () async {
    late http.Request asked;
    final api = DiscourseApi(
      client: MockClient((request) async {
        asked = request;
        return http.Response(
          jsonEncode({
            'results': [
              {'name': 'bug', 'count': 4},
            ],
          }),
          200,
        );
      }),
    );

    final values = await api.searchFilterTags(
      siteUrl: 'https://example.com',
      term: 'bu',
    );

    expect(values, const [
      TopicFilterLookupValue(name: 'bug', description: '4'),
    ]);
    expect(asked.method, 'GET');
    expect(asked.url.path, '/tags/filter/search.json');
    expect(asked.url.queryParameters, {'q': 'bu', 'limit': '5'});
  });

  test('tag-group lookup describes the tags in response order', () async {
    late http.Request asked;
    final api = DiscourseApi(
      client: MockClient((request) async {
        asked = request;
        return http.Response(
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
        );
      }),
    );

    final values = await api.searchFilterTagGroups(
      siteUrl: 'https://example.com',
      term: 'release',
    );

    expect(values, const [
      TopicFilterLookupValue(
        name: 'Release train',
        description: 'beta, stable',
      ),
    ]);
    expect(asked.method, 'GET');
    expect(asked.url.path, '/tag_groups/filter/search.json');
    expect(asked.url.queryParameters, {'q': 'release', 'limit': '10'});
  });

  test('group lookup sends credentials to the core endpoint', () async {
    late http.Request asked;
    final api = DiscourseApi(
      client: MockClient((request) async {
        asked = request;
        return http.Response(
          jsonEncode([
            {'name': 'team', 'full_name': 'The Team'},
          ]),
          200,
        );
      }),
    );

    final values = await api.searchFilterGroups(
      siteUrl: 'https://example.com',
      term: 'te',
      apiKey: 'key',
      clientId: 'client-id',
    );

    expect(values, const [
      TopicFilterLookupValue(name: 'team', description: 'The Team'),
    ]);
    expect(asked.method, 'GET');
    expect(asked.url.path, '/groups/search.json');
    expect(asked.url.queryParameters, {'term': 'te', 'limit': '10'});
    expect(asked.headers['User-Api-Key'], 'key');
    expect(asked.headers['User-Api-Client-Id'], 'client-id');
  });

  test('an empty filter user lookup asks for recently seen users', () async {
    late http.Request asked;
    final api = DiscourseApi(
      client: MockClient((request) async {
        asked = request;
        return http.Response(jsonEncode({'users': <Object?>[]}), 200);
      }),
    );

    await api.searchUsers(siteUrl: 'https://example.com', term: '');

    expect(asked.method, 'GET');
    expect(asked.url.path, '/u/search/users.json');
    expect(asked.url.queryParameters, {
      'last_seen_users': 'true',
      'limit': '10',
    });
  });
}
