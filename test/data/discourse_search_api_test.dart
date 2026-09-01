import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('searchPosts', () {
    test('rejects an oversized private query before transport', () async {
      var requestCount = 0;
      const secret = 'private-search-marker';
      final api = _searchApi(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );

      Object? failure;
      try {
        await api.searchPosts(
          siteUrl: 'https://example.com',
          term: '$secret${'x' * DiscourseSearchApi.maximumSearchTermLength}',
        );
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<ArgumentError>());
      expect('$failure', isNot(contains(secret)));
      expect(requestCount, 0);
    });

    test("asks for facet suggestions with core's topic exclusion", () async {
      late http.Request sent;
      final api = _searchApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'topics': [
                {'id': 7, 'title': 'Search topic', 'slug': 'search-topic'},
              ],
              'posts': [
                {
                  'id': 70,
                  'topic_id': 7,
                  'post_number': 3,
                  'username': 'sam',
                  'blurb': 'A result',
                },
              ],
              'grouped_search_result': {'error': null},
            }),
            200,
          );
        }),
      );

      final result = await api.searchPosts(
        siteUrl: 'https://example.com',
        term: 'user:sam title words',
        typeFilter: 'exclude_topics',
        apiKey: 'secret',
        clientId: 'client',
      );

      expect(sent.url.path, '/search/query.json');
      expect(sent.url.queryParameters, {
        'term': 'user:sam title words',
        'type_filter': 'exclude_topics',
      });
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(sent.headers['User-Api-Client-Id'], 'client');
      expect(result, isA<SearchResults>());
      expect(result.hits.single.postNumber, 3);
    });

    test('omits the type filter for the Enter topic search', () async {
      late http.Request sent;
      final api = _searchApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'grouped_search_result': {'error': null},
            }),
            200,
          );
        }),
      );

      await api.searchPosts(siteUrl: 'https://example.com', term: '@sam test');

      expect(sent.url.queryParameters, {'term': '@sam test'});
    });

    test('sends the current topic as core search context', () async {
      late http.Request sent;
      final api = _searchApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'grouped_search_result': {'error': null},
            }),
            200,
          );
        }),
      );

      await api.searchPosts(
        siteUrl: 'https://example.com',
        term: 'needle',
        topicId: 42,
      );

      expect(sent.url.queryParameters, {
        'term': 'needle',
        'search_context[type]': 'topic',
        'search_context[id]': '42',
      });
    });
  });
  group('header search support', () {
    test('asks user search for recent people and visible groups', () async {
      late http.Request sent;
      final api = _searchApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'username': 'sam',
                  'name': 'Sam Example',
                  'avatar_template': '/user_avatar/sam/{size}/1.png',
                },
              ],
              'groups': [
                {
                  'name': 'team',
                  'full_name': 'The Team',
                  'flair_url': 'shield-halved',
                },
              ],
            }),
            200,
          );
        }),
      );

      final found = await api.searchUsersAndGroups(
        siteUrl: 'https://example.com',
        term: '',
        apiKey: 'secret',
        clientId: 'client',
      );

      expect(sent.url.path, '/u/search/users.json');
      expect(sent.url.queryParameters, {
        'last_seen_users': 'true',
        'include_groups': 'true',
        'limit': '6',
      });
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(found.users.single.username, 'sam');
      expect(found.groups.single.name, 'team');
      expect(found.groups.single.flairUrl, 'shield-halved');
    });

    test('recent searches retain the first five string values', () async {
      late http.Request sent;
      final api = _searchApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'success': 'OK',
              'recent_searches': [
                'one',
                'two',
                'three',
                'four',
                'five',
                'ignored',
                7,
              ],
            }),
            200,
          );
        }),
      );

      final recent = await api.recentSearches(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );

      expect(recent, ['one', 'two', 'three', 'four', 'five']);
      expect((sent.method, sent.url.path), ('GET', '/u/recent-searches.json'));
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(sent.headers['User-Api-Client-Id'], 'client');
    });

    test(
      'resetting recent searches deletes the authenticated endpoint',
      () async {
        late http.Request sent;
        final api = _searchApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(jsonEncode({'success': 'OK'}), 200);
          }),
        );

        await api.resetRecentSearches(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
          clientId: 'client',
        );

        expect(
          (sent.method, sent.url.path),
          ('DELETE', '/u/recent-searches.json'),
        );
        expect(sent.headers['User-Api-Key'], 'secret');
        expect(sent.headers['User-Api-Client-Id'], 'client');
      },
    );

    test('search click tracking posts the result identity', () async {
      late http.Request sent;
      final api = _searchApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await api.logSearchClick(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        searchLogId: 22,
        resultId: 91,
        resultKind: SearchResultKind.topic,
        clientId: 'client',
      );

      expect((sent.method, sent.url.path), ('POST', '/search/click.json'));
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(sent.headers['User-Api-Client-Id'], 'client');
      expect(jsonDecode(sent.body), {
        'search_log_id': 22,
        'search_result_id': 91,
        'search_result_type': 'topic',
      });
    });
  });
  group('searchUsers', () {
    test('asks with the term, the limit and the topic', () async {
      Uri? asked;
      final api = _searchApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'username': 'sam',
                  'name': 'Sam Saffron',
                  'avatar_template': '/user_avatar/x/sam/{size}/1.png',
                },
                {'username': 'sally'},
              ],
            }),
            200,
          );
        }),
      );

      final found = await api.searchUsers(
        siteUrl: 'https://example.com',
        term: 'sa',
        topicId: 7,
      );

      expect(asked!.path, '/u/search/users.json');
      expect(asked!.queryParameters, {
        'term': 'sa',
        'limit': '10',
        // Discourse ranks people already in the topic first, so leaving this
        // off would offer alphabetical strangers over the person being
        // replied to.
        'topic_id': '7',
      });
      expect(found.map((user) => user.username), ['sam', 'sally']);
      expect(found.first.name, 'Sam Saffron');
      expect(found.first.avatarUrl, contains('example.com'));
      expect(found.last.name, isNull);
    });

    test('leaves the topic out when there is not one', () async {
      Uri? asked;
      final api = _searchApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(jsonEncode({'users': const <Object?>[]}), 200);
        }),
      );

      await api.searchUsers(siteUrl: 'https://example.com', term: 'sa');

      expect(asked!.queryParameters.containsKey('topic_id'), isFalse);
    });

    test('an answer it cannot read is a failure, not an empty list', () async {
      final api = _searchApi(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      await expectLater(
        api.searchUsers(siteUrl: 'https://example.com', term: 'sa'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });
  group('searchHashtags', () {
    Map<String, dynamic> row({
      required String type,
      required String ref,
      required String slug,
      required String text,
      required int id,
      String styleType = 'square',
      String? icon,
      String? emoji,
      List<String>? colors,
      String? secondaryText,
    }) => {
      'relative_url': type == 'category' ? '/c/$slug/$id' : '/tag/$slug/$id',
      'text': text,
      'description': null,
      'style_type': styleType,
      'emoji': emoji,
      'icon': icon,
      'colors': colors,
      'type': type,
      'ref': ref,
      'slug': slug,
      'id': id,
      'secondary_text': ?secondaryText,
    };

    test('asks with the term and the type order', () async {
      Uri? asked;
      final api = _searchApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(jsonEncode({'results': const <Object?>[]}), 200);
        }),
      );

      await api.searchHashtags(siteUrl: 'https://example.com', term: 'ran');

      expect(asked!.path, '/hashtags/search.json');
      // `order` is required — the controller does `params.require(:order)`
      // and answers 400 without it. `queryParameters` collapses a repeated
      // key to its last value, so the assertion has to be on the plural.
      expect(asked!.queryParametersAll, {
        'term': ['ran'],
        'order[]': ['category', 'tag'],
      });
    });

    test('reads a category and a tag', () async {
      final api = _searchApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': 'OK',
              'results': [
                row(
                  type: 'category',
                  ref: 'random',
                  slug: 'random',
                  text: 'Random',
                  id: 5,
                  icon: 'folder',
                  colors: ['0088CC'],
                ),
                row(
                  type: 'tag',
                  ref: 'random::tag',
                  slug: 'random',
                  text: 'random',
                  id: 12,
                  styleType: 'icon',
                  icon: 'tag',
                  secondaryText: 'x0',
                ),
              ],
            }),
            200,
          ),
        ),
      );

      final found = await api.searchHashtags(
        siteUrl: 'https://example.com',
        term: 'random',
      );

      expect(found.map((f) => f.type), ['category', 'tag']);
      // The ref, not the slug, is what gets written into the post — it is the
      // only form that survives two things sharing a name.
      expect(found[1].ref, 'random::tag');
      expect(found[1].slug, 'random');
      expect(found[1].secondaryText, 'x0');
      expect(found.first.colorValues, [0xFF0088CC]);
    });

    test('reads a subcategory as parent then child', () async {
      final api = _searchApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'results': [
                row(
                  type: 'category',
                  ref: 'parent:child',
                  slug: 'child',
                  text: 'Parent > Child',
                  id: 12,
                  colors: ['FF0000', '00FF00'],
                ),
              ],
            }),
            200,
          ),
        ),
      );

      final found = await api.searchHashtags(
        siteUrl: 'https://example.com',
        term: 'child',
      );

      expect(found.single.ref, 'parent:child');
      expect(found.single.text, 'Parent > Child');
      expect(found.single.colorValues, [0xFFFF0000, 0xFF00FF00]);
    });

    test('a body that is not what we asked for is unreachable', () async {
      final api = _searchApi(
        client: MockClient((_) async => http.Response('<html>nope', 200)),
      );

      expect(
        () => api.searchHashtags(siteUrl: 'https://example.com', term: 'x'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });
  group('lookupHashtags', () {
    test(
      'asks with every ref and type and reads plugin-owned results',
      () async {
        Uri? asked;
        final api = _searchApi(
          client: MockClient((request) async {
            asked = request.url;
            return http.Response(
              jsonEncode({
                'category': [
                  {
                    'type': 'category',
                    'ref': 'bug',
                    'slug': 'bug',
                    'text': 'Bug',
                    'id': 5,
                    'colors': ['0088CC'],
                  },
                ],
                'tag': [
                  {
                    'type': 'tag',
                    'ref': 'ux::tag',
                    'slug': 'ux',
                    'text': 'ux',
                    'id': 3,
                  },
                ],
                'room': [
                  {
                    'type': 'room',
                    'ref': 'lounge',
                    'slug': 'lounge',
                    'text': 'Lounge',
                    'id': 9,
                    'relative_url': '/voice/r/lounge',
                    'style_type': 'icon',
                    'icon': 'microphone-lines',
                  },
                ],
              }),
              200,
            );
          }),
        );

        final found = await api.lookupHashtags(
          siteUrl: 'https://example.com',
          refs: ['bug', 'ux::tag', 'lounge'],
          order: const ['category', 'tag', 'room'],
        );

        expect(asked!.path, '/hashtags.json');
        expect(asked!.queryParametersAll['slugs[]'], [
          'bug',
          'ux::tag',
          'lounge',
        ]);
        expect(asked!.queryParametersAll['order[]'], [
          'category',
          'tag',
          'room',
        ]);
        expect(found.map((f) => f.ref), ['bug', 'ux::tag', 'lounge']);
        expect(found.last.type, 'room');
        expect(found.last.relativeUrl, '/voice/r/lounge');
        expect(found.last.icon, 'microphone-lines');
      },
    );

    test('rejects an invalid type order before transport', () async {
      var called = false;
      final api = _searchApi(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.lookupHashtags(
          siteUrl: 'https://example.com',
          refs: const ['bug'],
          order: const [],
        ),
        throwsRangeError,
      );
      expect(called, isFalse);
    });

    test('a ref the site does not resolve is simply absent', () async {
      final api = _searchApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'category': const <Object?>[],
              'tag': const <Object?>[],
            }),
            200,
          ),
        ),
      );

      final found = await api.lookupHashtags(
        siteUrl: 'https://example.com',
        refs: ['nothing'],
      );

      expect(found, isEmpty);
    });

    test('asks for nothing when there is nothing to ask about', () async {
      var called = false;
      final api = _searchApi(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      expect(
        await api.lookupHashtags(
          siteUrl: 'https://example.com',
          refs: const [],
        ),
        isEmpty,
      );
      expect(called, isFalse);
    });

    test('never asks about more than the site will answer', () async {
      Uri? asked;
      final api = _searchApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response('{}', 200);
        }),
      );

      await api.lookupHashtags(
        siteUrl: 'https://example.com',
        refs: [for (var i = 0; i < 50; i++) 'ref$i'],
      );

      expect(
        asked!.queryParametersAll['slugs[]'],
        hasLength(DiscourseApi.hashtagsPerRequest),
      );
    });
  });
  group('checkMentions', () {
    test('asks with the names and the topic, and folds in groups', () async {
      Uri? asked;
      final api = _searchApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'users': ['sam'],
              // A name the reader cannot notify here is still a real account,
              // and Discourse still links it — so a reason is not a refusal.
              'user_reasons': {'sam': 'private'},
              'groups': {
                'staff': {'user_count': 12},
              },
              'here_count': 42,
            }),
            200,
          );
        }),
      );

      final real = await api.checkMentions(
        siteUrl: 'https://example.com',
        names: ['sam', 'nobody', 'staff'],
        topicId: 7,
      );

      expect(asked!.path, '/composer/mentions');
      expect(asked!.queryParametersAll['names[]'], ['sam', 'nobody', 'staff']);
      expect(asked!.queryParameters['topic_id'], '7');
      expect(real, {'sam', 'staff'});
    });

    test('asks for nothing when there is nothing to ask about', () async {
      var called = false;
      final api = _searchApi(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      expect(
        await api.checkMentions(
          siteUrl: 'https://example.com',
          names: const [],
        ),
        isEmpty,
      );
      expect(called, isFalse);
    });
  });
}

DiscourseSearchApi _searchApi({http.Client? client}) {
  final transport = DiscourseTransport.create(client: client);
  addTearDown(transport.close);
  return DiscourseSearchApi(transport);
}
