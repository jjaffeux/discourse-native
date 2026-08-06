import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Stands in for a Discourse: answers the probe with an API version, then the
/// basic-info payload.
MockClient discourseServing({
  int probeStatus = 200,
  String? apiVersion = '4',
  Map<String, dynamic>? basicInfo,
  Map<String, String> redirects = const {},
}) {
  return MockClient((request) async {
    final url = request.url.toString();

    if (redirects.containsKey(url)) {
      return http.Response('', 301, headers: {'location': redirects[url]!});
    }

    if (request.url.path == '/user-api-key/new') {
      final headers = <String, String>{};
      if (apiVersion != null) {
        headers['auth-api-version'] = apiVersion;
      }
      return http.Response('', probeStatus, headers: headers);
    }

    if (request.url.path == '/site/basic-info.json') {
      return http.Response(
        jsonEncode(
          basicInfo ??
              {
                'title': 'Discourse Meta',
                'description': 'Official support',
                'apple_touch_icon_url': '/uploads/icon.png',
                'login_required': false,
              },
        ),
        200,
      );
    }

    return http.Response('not found', 404);
  });
}

void main() {
  group('normalize', () {
    test('assumes https for a bare host', () {
      expect(
        DiscourseApi.normalize('meta.discourse.org').toString(),
        'https://meta.discourse.org',
      );
    });

    test('keeps an explicit scheme and port', () {
      expect(
        DiscourseApi.normalize('http://localhost:4200').toString(),
        'http://localhost:4200',
      );
    });

    test('trims whitespace and trailing slashes', () {
      expect(
        DiscourseApi.normalize('  https://example.com///  ').toString(),
        'https://example.com',
      );
    });
  });

  group('lookup', () {
    test('returns the site described by basic-info', () async {
      final api = DiscourseApi(client: discourseServing());
      final site = await api.lookup('meta.discourse.org');

      expect(site.url, 'https://meta.discourse.org');
      expect(site.title, 'Discourse Meta');
      expect(site.description, 'Official support');
      expect(site.apiVersion, 4);
      expect(site.loginRequired, isFalse);
    });

    test('resolves a relative icon against the site', () async {
      final api = DiscourseApi(client: discourseServing());
      final site = await api.lookup('meta.discourse.org');

      expect(site.iconUrl, 'https://meta.discourse.org/uploads/icon.png');
    });

    test('rejects a 404 on the probe as not a Discourse', () async {
      final api = DiscourseApi(client: discourseServing(probeStatus: 404));

      await expectLater(
        api.lookup('example.com'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.notDiscourse,
          ),
        ),
      );
    });

    test('rejects a Discourse too old to expose the user API', () async {
      final api = DiscourseApi(client: discourseServing(apiVersion: '1'));

      await expectLater(
        api.lookup('old.example.com'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.notDiscourse,
          ),
        ),
      );
    });

    test('treats a missing version header as not a Discourse', () async {
      final api = DiscourseApi(client: discourseServing(apiVersion: null));

      await expectLater(
        api.lookup('example.com'),
        throwsA(isA<SiteLookupException>()),
      );
    });

    test('reports an unreachable host', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => throw const SocketishFailure()),
      );

      await expectLater(
        api.lookup('nope.example.com'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.unreachable,
          ),
        ),
      );
    });

    test('follows redirects and keeps where it landed', () async {
      final api = DiscourseApi(
        client: discourseServing(
          redirects: {
            'https://discourse.org/user-api-key/new':
                'https://meta.discourse.org/user-api-key/new',
          },
        ),
      );

      final site = await api.lookup('discourse.org');
      expect(site.url, 'https://meta.discourse.org');
    });

    test('keeps the port, unlike DiscourseMobile', () async {
      final api = DiscourseApi(client: discourseServing());
      final site = await api.lookup('http://localhost:4200');

      expect(site.url, 'http://localhost:4200');
    });
  });

  _authGroups();
  _feedGroups();
  _writeGroups();
}

void _authGroups() {
  group('notificationTotals', () {
    test('reads every counter the shell shows from one call', () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          expect(request.headers['User-Api-Key'], 'the-key');
          return http.Response(
            jsonEncode({
              'unread_notifications': 3,
              'unread_personal_messages': 2,
              'unseen_reviewables': 1,
              'chat_notifications': 4,
              'topic_tracking': {'unread': 12, 'new': 7},
              'username': 'joffreyj',
            }),
            200,
          );
        }),
      );

      final totals = await api.notificationTotals(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
      );

      expect(totals.unreadNotifications, 3);
      expect(totals.unreadPersonalMessages, 2);
      expect(totals.topicTrackingUnread, 12);
      expect(totals.topicTrackingNew, 7);
      expect(totals.hasChatEnabled, isTrue);
      // Addressed-to-you items only; unread topics are not in the rail badge.
      expect(totals.badge, 3 + 2 + 1 + 4);
    });

    test('a site without chat reports none enabled', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'unread_notifications': 1,
              'topic_tracking': {'unread': 0, 'new': 0},
            }),
            200,
          ),
        ),
      );

      final totals = await api.notificationTotals(
        siteUrl: 'https://example.com',
        apiKey: 'k',
      );

      expect(totals.hasChatEnabled, isFalse);
      expect(totals.chatNotifications, 0);
    });

    test('a rejected key is reported as such', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('', 403)),
      );

      await expectLater(
        api.notificationTotals(siteUrl: 'https://example.com', apiKey: 'k'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.notDiscourse,
          ),
        ),
      );
    });
  });

  group('revokeApiKey', () {
    test('posts the key back to the site', () async {
      String? path;
      String? method;
      final api = DiscourseApi(
        client: MockClient((request) async {
          path = request.url.path;
          method = request.method;
          return http.Response('', 200);
        }),
      );

      await api.revokeApiKey(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
      );

      expect(method, 'POST');
      expect(path, '/user-api-key/revoke');
    });

    test('tolerates a site too old to have the route', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('', 404)),
      );

      await expectLater(
        api.revokeApiKey(siteUrl: 'https://old.example.com', apiKey: 'k'),
        completes,
      );
    });
  });
}

void _feedGroups() {
  group('topicList', () {
    test(
      'parses topics and resolves poster avatars from the users array',
      () async {
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'users': [
                  {
                    'id': 7,
                    'username': 'joffreyj',
                    'avatar_template':
                        '/user_avatar/meta/joffreyj/{size}/1.png',
                  },
                  {
                    'id': 9,
                    'username': 'sam',
                    'avatar_template': 'https://cdn.example/{size}/2.png',
                  },
                ],
                'topic_list': {
                  'more_topics_url': '/latest?page=1',
                  'topics': [
                    {
                      'id': 42,
                      'fancy_title': 'A &amp; B',
                      'title': 'A & B',
                      'slug': 'a-and-b',
                      'category_id': 5,
                      'reply_count': 3,
                      'views': 1200,
                      'bumped_at': '2026-08-01T10:00:00.000Z',
                      'pinned': true,
                      'unread_posts': 2,
                      'posters': [
                        {'user_id': 7},
                        {'user_id': 9},
                        {'user_id': 999},
                      ],
                    },
                  ],
                },
              }),
              200,
            ),
          ),
        );

        final list = await api.topicList(
          siteUrl: 'https://meta.discourse.org',
          path: '/latest.json',
        );

        final topic = list.topics.single;
        expect(topic.id, 42);
        // Plain title wins: fancy_title is HTML and would render as entities.
        expect(topic.title, 'A & B');
        expect(topic.categoryId, 5);
        expect(topic.views, 1200);
        expect(topic.pinned, isTrue);
        expect(topic.hasUnread, isTrue);
        expect(topic.path, '/t/a-and-b/42');
        expect(list.moreTopicsUrl, '/latest?page=1');

        // Site-relative templates are absolutised, absolute ones left alone, and
        // a poster with no matching user is dropped rather than crashing.
        expect(topic.posterAvatars, [
          'https://meta.discourse.org/user_avatar/meta/joffreyj/90/1.png',
          'https://cdn.example/90/2.png',
        ]);
      },
    );

    test('an unauthenticated list omits unread state', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'topic_list': {
                'topics': [
                  {'id': 1, 'title': 'T', 'slug': 't'},
                ],
              },
            }),
            200,
          ),
        ),
      );

      final list = await api.topicList(
        siteUrl: 'https://example.com',
        path: '/latest.json',
      );

      expect(list.topics.single.hasUnread, isFalse);
      expect(list.topics.single.posterAvatars, isEmpty);
    });
  });

  group('categories', () {
    test('flattens subcategories so any id can be looked up', () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          expect(request.url.queryParameters['include_subcategories'], 'true');
          return http.Response(
            jsonEncode({
              'category_list': {
                'categories': [
                  {
                    'id': 1,
                    'name': 'Feature',
                    'color': '0088CC',
                    'slug': 'feature',
                    'subcategory_list': [
                      {
                        'id': 2,
                        'name': 'Ideas',
                        'color': 'AB9364',
                        'slug': 'ideas',
                      },
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }),
      );

      final categories = await api.categories(siteUrl: 'https://example.com');

      expect(categories.map((c) => c.id), [1, 2]);
      expect(categories.first.colorValue, 0xFF0088CC);
    });
  });

  group('topic', () {
    /// Answers any topic route with a single-post topic.
    MockClient serving(List<String> paths) => MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(
        jsonEncode({
          'id': 12,
          'title': 'A real topic',
          'post_stream': {
            'posts': [
              {
                'id': 1,
                'post_number': 1,
                'username': 'sam',
                'cooked': '<p>x</p>',
              },
            ],
            'stream': [1],
          },
        }),
        200,
      );
    });

    test('reads the topic by slug and id', () async {
      final paths = <String>[];
      final topic = await DiscourseApi(
        client: serving(paths),
      ).topic(siteUrl: 'https://example.com', slug: 'a-real-topic', id: 12);

      expect(paths, ['/t/a-real-topic/12.json']);
      expect(topic.title, 'A real topic');
    });

    test('asks by id alone when the link carried no slug', () async {
      final paths = <String>[];
      await DiscourseApi(
        client: serving(paths),
      ).topic(siteUrl: 'https://example.com', slug: '', id: 12);

      expect(paths, ['/t/12.json']);
    });
  });

  group('userCard', () {
    test('reads the card endpoint for the username', () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          expect(request.url.path, '/u/joffrey%20j/card.json');
          return http.Response(
            jsonEncode({
              'user': {
                'username': 'joffreyj',
                'name': 'Joffrey',
                'title': 'Team',
                'bio_excerpt': '<p>Hello</p>',
                'avatar_template': '/user_avatar/j/{size}.png',
                'created_at': '2015-03-04T10:00:00.000Z',
                'badge_count': 12,
                'moderator': true,
              },
            }),
            200,
          );
        }),
      );

      final card = await api.userCard(
        siteUrl: 'https://example.com',
        username: 'joffrey j',
      );

      expect(card.username, 'joffreyj');
      expect(card.displayName, 'Joffrey');
      expect(card.title, 'Team');
      expect(card.avatarUrl, 'https://example.com/user_avatar/j/90.png');
      expect(card.createdAt, DateTime.utc(2015, 3, 4, 10));
      expect(card.badgeCount, 12);
      expect(card.isStaff, isTrue);
      expect(card.isSuspended, isFalse);
    });

    test('a payload without a user is not something we can show', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        api.userCard(siteUrl: 'https://example.com', username: 'ghost'),
        throwsA(isA<SiteLookupException>()),
      );
    });

    test('a suspension still in the future is reported', () async {
      final until = DateTime.now().toUtc().add(const Duration(days: 3));
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'user': {
                'username': 'banned',
                'suspended_till': until.toIso8601String(),
              },
            }),
            200,
          ),
        ),
      );

      final card = await api.userCard(
        siteUrl: 'https://example.com',
        username: 'banned',
      );

      expect(card.isSuspended, isTrue);
    });
  });
}

void _writeGroups() {
  /// A site that accepts the post and answers with the envelope `nested_post`
  /// asks for.
  MockClient accepting({
    Map<String, dynamic>? envelope,
    void Function(http.Request request)? onRequest,
  }) {
    return MockClient((request) async {
      onRequest?.call(request);
      return http.Response(
        jsonEncode(
          envelope ??
              {
                'success': true,
                'action': 'create_post',
                'post': {
                  'id': 42,
                  'post_number': 7,
                  'username': 'joffreyj',
                  'cooked': '<p>hi</p>',
                  'draft_sequence': 3,
                },
              },
        ),
        200,
      );
    });
  }

  Future<PostCreation> create(
    DiscourseApi api, {
    int? replyToPostNumber = 3,
    String? draftKey = 'topic_12',
    Duration typing = const Duration(seconds: 9),
  }) => api.createPost(
    siteUrl: 'https://meta.discourse.org',
    apiKey: 'the-key',
    topicId: 12,
    raw: 'hi',
    replyToPostNumber: replyToPostNumber,
    draftKey: draftKey,
    typingDuration: typing,
    composerOpenDuration: const Duration(seconds: 30),
  );

  group('posts', () {
    test('asks for the markdown only when it is wanted', () async {
      late Uri asked;
      MockClient serving() => MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({
            'post_stream': {
              'posts': [
                {
                  'id': 2,
                  'post_number': 2,
                  'username': 'joffreyj',
                  'cooked': '<p>hi</p>',
                  'raw': 'hi',
                },
              ],
            },
          }),
          200,
        );
      });

      await DiscourseApi(client: serving()).posts(
        siteUrl: 'https://meta.discourse.org',
        topicId: 12,
        ids: [2],
      );
      expect(asked.query, isNot(contains('include_raw')));

      final posts = await DiscourseApi(client: serving()).posts(
        siteUrl: 'https://meta.discourse.org',
        topicId: 12,
        ids: [2],
        includeRaw: true,
      );

      // Uri percent-encodes the brackets on the way out.
      expect(Uri.decodeFull(asked.query), contains('post_ids[]=2'));
      expect(asked.query, contains('include_raw=true'));
      // Which is the point: comparing what was posted against what was typed
      // needs the source, not the cooked HTML.
      expect(posts.single.raw, 'hi');
    });
  });

  group('saveDraft', () {
    test('sends the blob as a string and reads the new sequence back', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({'success': 'OK', 'draft_sequence': 5}),
            200,
          );
        }),
      );

      final sequence = await api.saveDraft(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        draftKey: 'topic_12',
        sequence: 4,
        data: '{"reply":"hi"}',
        owner: 'this-client',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/drafts.json');

      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['draft_key'], 'topic_12');
      expect(body['sequence'], 4);
      expect(body['owner'], 'this-client');
      // A String, not an object: the controller rejects anything else outright.
      expect(body['data'], isA<String>());
      expect(body.containsKey('force_save'), isFalse);

      expect(sequence, 5);
    });

    test('forces the save when the sequence moved under it', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (bodies.length == 1) {
            return http.Response(
              jsonEncode({
                'errors': ['Draft has been updated elsewhere'],
              }),
              409,
            );
          }
          return http.Response(jsonEncode({'draft_sequence': 9}), 200);
        }),
      );

      final sequence = await api.saveDraft(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        draftKey: 'topic_12',
        sequence: 4,
        data: '{"reply":"hi"}',
      );

      // The text in front of the user is the one they are looking at, so it
      // wins — the same thing the web composer does.
      expect(bodies, hasLength(2));
      expect(bodies.first.containsKey('force_save'), isFalse);
      expect(bodies.last['force_save'], true);
      expect(sequence, 9);
    });

    test('does not force a save past any other refusal', () async {
      var calls = 0;
      final api = DiscourseApi(
        client: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'errors': ['You have too many drafts.'],
            }),
            403,
          );
        }),
      );

      await expectLater(
        api.saveDraft(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          draftKey: 'topic_12',
          sequence: 4,
          data: '{"reply":"hi"}',
        ),
        throwsA(
          isA<WriteException>().having(
            (e) => e.failure,
            'failure',
            WriteFailure.forbidden,
          ),
        ),
      );
      expect(calls, 1);
    });
  });

  group('createPost', () {
    test('sends raw to /posts.json and reads the created post back', () async {
      late http.Request sent;
      final creation = await create(
        DiscourseApi(client: accepting(onRequest: (r) => sent = r)),
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/posts.json');
      expect(sent.headers['User-Api-Key'], 'the-key');
      expect(sent.headers['content-type'], startsWith('application/json'));

      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['raw'], 'hi');
      expect(body['topic_id'], 12);
      expect(body['draft_key'], 'topic_12');
      // Without this the envelope is dropped and `action` with it, so an
      // enqueued post would read as a published one.
      expect(body['nested_post'], true);

      expect(creation.outcome, PostOutcome.created);
      expect(creation.post?.id, 42);
      expect(creation.post?.postNumber, 7);
      // Creating the post already bumped it; keeping the old one 409s the next
      // draft save.
      expect(creation.draftSequence, 3);
    });

    test('addresses the reply by post number, not by post id', () async {
      late http.Request sent;
      await create(DiscourseApi(client: accepting(onRequest: (r) => sent = r)));

      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['reply_to_post_number'], 3);
      expect(body.containsKey('reply_to_post_id'), isFalse);
    });

    test('omits the reply target when replying to the topic', () async {
      late http.Request sent;
      await create(
        DiscourseApi(client: accepting(onRequest: (r) => sent = r)),
        replyToPostNumber: null,
        draftKey: null,
      );

      // Absent, not null: Rails reads a missing parameter and an explicit null
      // differently.
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body.containsKey('reply_to_post_number'), isFalse);
      expect(body.containsKey('draft_key'), isFalse);
    });

    test('always sends the typing durations', () async {
      late http.Request sent;
      await create(
        DiscourseApi(client: accepting(onRequest: (r) => sent = r)),
        typing: const Duration(seconds: 9),
      );

      // Discourse reads this with to_i, so an absent one is zero — under every
      // fast_typing_threshold, which silences a user on their first post
      // rather than merely queueing it.
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['typing_duration_msecs'], 9000);
      expect(body['composer_open_duration_msecs'], 30000);
    });

    test('reports an enqueued post as enqueued rather than as posted', () async {
      final creation = await create(
        DiscourseApi(
          client: accepting(
            envelope: {
              'success': true,
              'action': 'enqueued',
              'pending_count': 1,
              'message': 'Your post is in the queue.',
            },
          ),
        ),
      );

      // Success, 200, and nothing to put in the stream.
      expect(creation.isEnqueued, isTrue);
      expect(creation.post, isNull);
      expect(creation.message, 'Your post is in the queue.');
    });

    test('reads a refusal off the status, since success is absent', () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response(
            // The serializer only includes `success` when the post succeeded,
            // so branching on success == false never fires.
            jsonEncode({
              'action': 'create_post',
              'errors': ['Body is too short (minimum is 20 characters)'],
            }),
            422,
          ),
        ),
      );

      await expectLater(
        create(api),
        throwsA(
          isA<WriteException>()
              .having((e) => e.failure, 'failure', WriteFailure.validation)
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.message,
                'message',
                'Body is too short (minimum is 20 characters)',
              ),
        ),
      );
    });

    test('carries how long to wait when rate limited', () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'errors': ['You are posting too quickly.'],
              'error_type': 'rate_limit',
              'extras': {'wait_seconds': 42},
            }),
            429,
          ),
        ),
      );

      await expectLater(
        create(api),
        throwsA(
          isA<WriteException>()
              .having((e) => e.failure, 'failure', WriteFailure.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 42),
              ),
        ),
      );
    });

    test('prefers the Retry-After header to the body', () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'errors': ['Slow down.'],
              'extras': {'wait_seconds': 42},
            }),
            429,
            headers: {'retry-after': '10'},
          ),
        ),
      );

      await expectLater(
        create(api),
        throwsA(
          isA<WriteException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 10),
          ),
        ),
      );
    });

    test('tells being refused apart from being unable to reach', () async {
      Future<void> expectFailure(int status, WriteFailure failure) async {
        final api = DiscourseApi(
          client: MockClient(
            (request) async => http.Response(jsonEncode(const {}), status),
          ),
        );
        await expectLater(
          create(api),
          throwsA(
            isA<WriteException>().having((e) => e.failure, 'failure', failure),
          ),
        );
      }

      // A read maps 401/403 to "this is not a Discourse". A write must not:
      // the site is fine, the post is not allowed.
      await expectFailure(403, WriteFailure.forbidden);
      await expectFailure(401, WriteFailure.forbidden);
      await expectFailure(409, WriteFailure.conflict);
      await expectFailure(500, WriteFailure.unreachable);
    });

    test('survives an error body that is not JSON', () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response('<html>502 Bad Gateway</html>', 502),
        ),
      );

      await expectLater(
        create(api),
        throwsA(
          isA<WriteException>()
              .having((e) => e.failure, 'failure', WriteFailure.unreachable)
              .having((e) => e.errors, 'errors', isEmpty),
        ),
      );
    });

    test('does not resend after a timeout', () async {
      var calls = 0;
      final api = DiscourseApi(
        timeout: const Duration(milliseconds: 20),
        client: MockClient((request) async {
          calls++;
          return Completer<http.Response>().future;
        }),
      );

      await expectLater(
        create(api),
        throwsA(
          isA<WriteException>().having(
            (e) => e.failure,
            'failure',
            WriteFailure.unreachable,
          ),
        ),
      );

      // A user API key gets no idempotency from Discourse, so a retry after an
      // ambiguous timeout publishes the post twice.
      expect(calls, 1);
    });
  });
}

class SocketishFailure implements Exception {
  const SocketishFailure();
}
