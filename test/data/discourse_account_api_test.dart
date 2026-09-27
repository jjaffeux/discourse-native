import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('notificationTotals', () {
    test(
      'core reads its counters without claiming plugin wire fields',
      () async {
        final api = _accountApi(
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
        expect(totals.unseenReviewables, 1);
        expect(totals.topicTrackingUnread, 12);
        expect(totals.topicTrackingNew, 7);
        expect(totals.badge, 3 + 2 + 1);
      },
    );

    test('absent optional counters leave core totals at zero', () async {
      final api = _accountApi(
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

      expect(totals.unreadPersonalMessages, 0);
      expect(totals.unseenReviewables, 0);
    });

    test('a rejected key is reported as such', () async {
      final api = _accountApi(
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

  group('notifications', () {
    test('reads the list the user menu shows', () async {
      Uri? url;
      final api = _accountApi(
        client: MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 12,
                  'notification_type': 2,
                  'read': false,
                  'created_at': '2026-08-06T09:00:00.000Z',
                  'post_number': 4,
                  'topic_id': 77,
                  'slug': 'better-image-handling',
                  'fancy_title': 'Better &ldquo;image&rdquo; handling',
                  'data': {
                    'topic_title': 'Better “image” handling',
                    'display_username': 'sam',
                  },
                },
                {
                  'id': 13,
                  'notification_type': 19,
                  'read': true,
                  'data': {'username': 'david', 'count': 3},
                },
              ],
              'seen_notification_id': 12,
            }),
            200,
            // Titles carry whatever the site's typographer did to them, which
            // does not survive the latin-1 a response defaults to.
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final notifications = await api.notifications(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
      );

      expect(url?.path, '/notifications.json');
      expect(url?.queryParameters['recent'], 'true');
      expect(url?.queryParameters['limit'], '30');
      expect(url?.queryParameters, isNot(contains('filter_by_types')));
      expect(url?.queryParameters, isNot(contains('silent')));

      expect(notifications.first.typeId, const NotificationTypeId(2));
      expect(notifications.first.topicId, 77);
      expect(notifications.first.postNumber, 4);
      expect(notifications.first.data['display_username'], 'sam');
      expect(notifications.first.title, 'Better “image” handling');
      expect(notifications.first.isUnread, isTrue);

      // Type-owned payload keys remain opaque at the API boundary.
      expect(notifications.last.typeId, const NotificationTypeId(19));
      expect(notifications.last.data['username'], 'david');
      expect(notifications.last.data['count'], 3);
      expect(notifications.last.isUnread, isFalse);
    });

    test('falls back to the title Discourse wrote for a browser', () async {
      final api = _accountApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 1,
                  'notification_type': 5,
                  'fancy_title': 'Tea &amp; biscuits &hellip;',
                  'data': {'display_username': 'sam'},
                },
              ],
            }),
            200,
          ),
        ),
      );

      final notifications = await api.notifications(
        siteUrl: 'https://example.com',
        apiKey: 'k',
      );

      // Entities and all: `fancy_title` is HTML, and only a browser reads it
      // as the string it stands for.
      expect(notifications.single.title, 'Tea & biscuits …');
    });

    test('a kind we have never heard of is still a row', () async {
      final api = _accountApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 1,
                  'notification_type': 4242,
                  'topic_id': 9,
                  'data': {'topic_title': 'From some plugin'},
                },
              ],
            }),
            200,
          ),
        ),
      );

      final notifications = await api.notifications(
        siteUrl: 'https://example.com',
        apiKey: 'k',
      );

      expect(notifications.single.typeId, const NotificationTypeId(4242));
      expect(notifications.single.title, isEmpty);
      expect(notifications.single.topicId, 9);
      expect(notifications.single.data, {'topic_title': 'From some plugin'});
    });

    test('reads Replies as a silent server-filtered list', () async {
      Uri? url;
      final api = _accountApi(
        client: MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 12,
                  'notification_type': 2,
                  'data': {
                    'display_username': 'sam',
                    'topic_title': 'Better image handling',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final replies = await api.notifications(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        filterByTypes: userMenuReplyNotificationTypes,
      );

      expect(url?.path, '/notifications.json');
      expect(url?.queryParameters, {
        'recent': 'true',
        'limit': '30',
        'filter_by_types': 'mentioned,group_mentioned,posted,quoted,replied',
        'silent': 'true',
      });
      expect(replies.single.typeId, const NotificationTypeId(2));
      expect(replies.single.data['display_username'], 'sam');
    });

    test('preserves arbitrary filter names in a silent request', () async {
      Uri? url;
      final api = _accountApi(
        client: MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 13,
                  'notification_type': 4243,
                  'data': {'plugin_value': 'opaque'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final notifications = await api.notifications(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        filterByTypes: const [
          NotificationTypeName('future_alert'),
          NotificationTypeName('plugin_ping'),
        ],
      );

      expect(url?.path, '/notifications.json');
      expect(url?.queryParameters, {
        'recent': 'true',
        'limit': '30',
        'filter_by_types': 'future_alert,plugin_ping',
        'silent': 'true',
      });
      expect(notifications.single.typeId, const NotificationTypeId(4243));
      expect(notifications.single.data['plugin_value'], 'opaque');
    });
  });

  group('user activity', () {
    test('requests the web default contribution stream contract', () async {
      Uri? url;
      String? apiKey;
      final api = _accountApi(
        client: MockClient((request) async {
          url = request.url;
          apiKey = request.headers['User-Api-Key'];
          return http.Response(
            jsonEncode({
              'user_actions': [
                {
                  'action_type': 4,
                  'created_at': '2026-08-27T10:00:00.000Z',
                  'avatar_template': '/user_avatar/meta/sam/{size}/1.png',
                  'slug': 'native-client',
                  'topic_id': 71,
                  'post_number': 1,
                  'post_id': 901,
                  'username': 'sam',
                  'title': 'A native client',
                  'category_id': 3,
                  'closed': true,
                  'excerpt': '<p>The opening post</p>',
                },
                {
                  'action_type': 5,
                  'created_at': '2026-08-26T10:00:00.000Z',
                  'avatar_template': '/user_avatar/meta/sam/{size}/1.png',
                  'slug': 'another-topic',
                  'topic_id': 72,
                  'post_number': 4,
                  'post_id': 902,
                  'username': 'sam',
                  'title': 'Another topic',
                  'category_id': 3,
                  'hidden': true,
                  'excerpt': '<p>A useful reply &amp; follow-up</p>',
                },
              ],
              'categories': [
                {'id': 3, 'name': 'Support', 'color': '0088CC'},
              ],
            }),
            200,
          );
        }),
      );

      final page = await api.userActivity(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        username: 'sam',
        offset: 30,
        limit: 30,
      );

      expect(url?.path, '/user_actions.json');
      expect(url?.queryParameters, {
        'offset': '30',
        'username': 'sam',
        // Core maps the unfiltered userActivity.index route to topics and
        // replies. Summary, drafts, likes, reads, and bookmarks are separate.
        'filter': '4,5',
        'limit': '30',
      });
      expect(apiKey, 'the-key');
      expect(page.rawItemCount, 2);
      expect(page.items, hasLength(2));
      expect(page.items.first.isTopic, isTrue);
      expect(page.items.first.topicId, 71);
      expect(page.items.first.closed, isTrue);
      expect(
        page.items.first.avatarUrl,
        'https://meta.discourse.org/user_avatar/meta/sam/90/1.png',
      );
      expect(page.items.last.isReply, isTrue);
      expect(page.items.last.postNumber, 4);
      expect(page.items.last.hidden, isTrue);
      expect(page.items.last.plainExcerpt, 'A useful reply & follow-up');
      expect(page.categories.single.name, 'Support');
    });

    test(
      'counts malformed server rows when advancing the raw offset',
      () async {
        final api = _accountApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'user_actions': [
                  null,
                  'malformed',
                  <Object?>[],
                  42,
                  true,
                  {
                    'action_type': 99,
                    'topic_id': 1,
                    'post_number': 1,
                    'title': 'A future action kind',
                  },
                  {
                    'action_type': 5,
                    'topic_id': 2,
                    'post_number': 0,
                    'title': 'Broken reply',
                  },
                ],
              }),
              200,
            ),
          ),
        );

        final page = await api.userActivity(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          username: 'sam',
        );

        expect(page.items, isEmpty);
        expect(page.rawItemCount, 7);
      },
    );

    for (final limit in [1, 3, DiscourseApi.maximumUserActivityPageSize]) {
      test(
        'caps raw activity slots before filtering at limit $limit',
        () async {
          final api = _accountApi(
            client: MockClient((request) async {
              expect(request.url.queryParameters['limit'], '$limit');
              return http.Response(
                jsonEncode({
                  'user_actions': [
                    null,
                    for (var id = 1; id <= limit + 1; id++)
                      {
                        'action_type': 4,
                        'topic_id': id,
                        'post_number': 1,
                        'title': 'Topic $id',
                      },
                  ],
                }),
                200,
              );
            }),
          );

          final page = await api.userActivity(
            siteUrl: 'https://example.com',
            apiKey: 'k',
            username: 'sam',
            limit: limit,
          );

          expect(page.rawItemCount, limit);
          expect(page.items.map((item) => item.topicId), [
            for (var id = 1; id < limit; id++) id,
          ]);
        },
      );
    }
  });

  group('bookmarks', () {
    test('reads both lists the bookmarks tab is made of', () async {
      Uri? url;
      final api = _accountApi(
        client: MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 41,
                  'notification_type': 24,
                  'read': false,
                  'topic_id': 77,
                  'slug': 'better-image-handling',
                  'data': {'topic_title': 'Better image handling'},
                },
              ],
              'bookmarks': [
                {
                  'id': 8,
                  'name': 'read this properly',
                  'reminder_at': '2026-08-09T09:00:00.000Z',
                  'title': 'Thinking about the next project',
                  'fancy_title': 'Thinking about the next project',
                  'bookmarkable_id': 300,
                  'bookmarkable_type': 'Post',
                  'bookmarkable_url':
                      'https://meta.discourse.org/t/next-project/91/3',
                  'topic_id': 91,
                  'user': {'id': 5, 'username': 'sam', 'name': 'Sam'},
                },
                {
                  'id': 9,
                  'name': null,
                  'fancy_title': 'Tea &amp; biscuits &hellip;',
                  'bookmarkable_type': 'Topic',
                  'bookmarkable_url': 'https://meta.discourse.org/t/tea/92/1',
                  'user': {'id': 6, 'username': 'david'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final payload = await api.bookmarks(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        username: 'joffreyj',
      );

      // The menu's own route, which is the account's own: Discourse refuses
      // anybody else's username here.
      expect(url?.path, '/u/joffreyj/user-menu-bookmarks.json');

      expect(payload.reminders.single.typeId, const NotificationTypeId(24));
      expect(payload.reminders.single.topicId, 77);
      expect(payload.reminders.single.slug, 'better-image-handling');

      final first = payload.bookmarks.first;
      expect(first.title, 'Thinking about the next project');
      expect(first.name, 'read this properly');
      expect(first.author, 'sam');
      // Site-relative, so the shell resolves it against the site being read
      // rather than against whatever `Discourse.base_url` happens to say.
      expect(first.path, '/t/next-project/91/3');
      expect(first.reminderAt, DateTime.utc(2026, 8, 9, 9));

      // No plain title, so the one Discourse wrote for a browser is unescaped.
      expect(payload.bookmarks.last.title, 'Tea & biscuits …');
      expect(payload.bookmarks.last.name, isNull);
      expect(payload.bookmarks.last.reminderAt, isNull);
    });

    test(
      'a bookmark on something we have never heard of is still a row',
      () async {
        final api = _accountApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'bookmarks': [
                  {
                    'id': 3,
                    'bookmarkable_type': 'SomePluginThing',
                    'bookmarkable_url': 'https://example.com/plugin/thing/1',
                    'title': 'Something a plugin keeps',
                  },
                ],
              }),
              200,
            ),
          ),
        );

        final payload = await api.bookmarks(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          username: 'joffreyj',
        );

        expect(payload.reminders, isEmpty);
        expect(payload.bookmarks.single.title, 'Something a plugin keeps');
        expect(payload.bookmarks.single.author, isNull);
        expect(
          payload.bookmarks.single.path,
          'https://example.com/plugin/thing/1',
        );
      },
    );

    test(
      'a topic keeps its path, not the host the site wrote it against',
      () async {
        final api = _accountApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'bookmarks': [
                  {
                    'id': 1,
                    'title': 'Yelling topic title',
                    'bookmarkable_type': 'Post',
                    // What a development site writes: `Discourse.base_url` is
                    // the site's own idea of where it lives, and the app is
                    // connected to a different one of its ports.
                    'bookmarkable_url':
                        'http://localhost:4200/t/yelling-topic-title/119/3',
                  },
                ],
              }),
              200,
            ),
          ),
        );

        final payload = await api.bookmarks(
          siteUrl: 'http://localhost:3000',
          apiKey: 'k',
          username: 'eviltrout',
        );

        expect(payload.bookmarks.single.path, '/t/yelling-topic-title/119/3');
      },
    );
  });

  group('bookmark list', () {
    test('pages the list behind the web bookmarks page', () async {
      Uri? url;
      final api = _accountApi(
        client: MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'user_bookmark_list': {
                'more_bookmarks_url': '/u/joffreyj/bookmarks.json?page=3',
                'bookmarks': [
                  {
                    'id': 8,
                    'title': 'Thinking about the next project',
                    'bookmarkable_type': 'Post',
                    'linked_post_number': 3,
                    'bookmarkable_url':
                        'https://meta.discourse.org/t/next-project/91/3',
                    'reminder_at': '2026-08-09T09:00:00.000Z',
                    'user': {'id': 5, 'username': 'sam'},
                  },
                  {
                    'id': 9,
                    'title': 'Tea',
                    'bookmarkable_type': 'Topic',
                    'bookmarkable_url': 'https://meta.discourse.org/t/tea/92',
                  },
                ],
                'categories': [
                  {'id': 1, 'name': 'Support'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final page = await api.bookmarkListPage(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        username: 'joffreyj',
        page: 2,
      );

      // Not the menu's twenty-row route: core's paged list, zero-based.
      expect(url?.path, '/u/joffreyj/bookmarks.json');
      expect(url?.queryParameters, {'page': '2'});
      expect(page.hasMore, isTrue);
      expect(page.bookmarks.map((bookmark) => bookmark.id), [8, 9]);
      expect(page.bookmarks.first.postNumber, 3);
      expect(page.bookmarks.first.path, '/t/next-project/91/3');
      expect(page.bookmarks.first.reminderAt, DateTime.utc(2026, 8, 9, 9));
      expect(page.bookmarks.last.path, '/t/tea/92');
    });

    test('the last page carries no next-page link', () async {
      final api = _accountApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'user_bookmark_list': {
                'bookmarks': [
                  {'id': 3, 'title': 'Last one'},
                ],
              },
            }),
            200,
          ),
        ),
      );

      final page = await api.bookmarkListPage(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        username: 'joffreyj',
      );

      expect(page.bookmarks.single.title, 'Last one');
      expect(page.hasMore, isFalse);
    });

    test('an empty list is answered without its root', () async {
      Uri? url;
      final api = _accountApi(
        client: MockClient((request) async {
          url = request.url;
          return http.Response(jsonEncode({'bookmarks': <Object>[]}), 200);
        }),
      );

      final page = await api.bookmarkListPage(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        username: 'joffreyj',
      );

      expect(url?.queryParameters, {'page': '0'});
      expect(page.bookmarks, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('a negative page is refused before sending', () async {
      var requests = 0;
      final api = _accountApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.bookmarkListPage(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          username: 'joffreyj',
          page: -1,
        ),
        throwsRangeError,
      );
      expect(requests, 0);
    });
  });

  group('markNotificationRead', () {
    test('names the one notification to mark', () async {
      String? method;
      String? path;
      String? body;
      final api = _accountApi(
        client: MockClient((request) async {
          method = request.method;
          path = request.url.path;
          body = request.body;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await api.markNotificationRead(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        id: 12,
      );

      expect(method, 'PUT');
      expect(path, '/notifications/mark-read.json');
      expect(jsonDecode(body!), {'id': 12});
    });

    test(
      'names the notification types to mark in one typed dismissal',
      () async {
        String? method;
        String? path;
        String? body;
        final api = _accountApi(
          client: MockClient((request) async {
            method = request.method;
            path = request.url.path;
            body = request.body;
            return http.Response(jsonEncode({'success': 'OK'}), 200);
          }),
        );

        await api.markNotificationsRead(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          types: const [
            NotificationTypeName('assigned'),
            NotificationTypeName('assigned_reminder'),
          ],
        );

        expect(method, 'PUT');
        expect(path, '/notifications/mark-read.json');
        expect(jsonDecode(body!), {
          'dismiss_types': 'assigned,assigned_reminder',
        });
      },
    );

    test('rejects an empty typed dismissal before sending', () async {
      var requests = 0;
      final api = _accountApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.markNotificationsRead(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          types: const [],
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
    });
  });

  group('currentUser', () {
    test('recognizes a key the site refuses before the action runs', () async {
      String? path;
      final api = _accountApi(
        client: MockClient((request) async {
          path = request.url.path;
          return _invalidAccess();
        }),
      );

      await expectLater(
        api.currentUser(siteUrl: 'https://meta.discourse.org', apiKey: 'k'),
        throwsA(
          isA<ApiKeyRejectedException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having(
                (error) => error.failure,
                'failure',
                SiteLookupFailure.notDiscourse,
              ),
        ),
      );
      expect(path, '/session/current.json');
    });

    test('does not mistake another failure for a refused key', () async {
      final failures = <String, Future<http.Response> Function()>{
        'web application firewall page': () async => http.Response(
          '<html><body>Access denied</body></html>',
          403,
          headers: {'content-type': 'text/html'},
        ),
        'empty refusal': () async => http.Response('', 403),
        'refusal that does not decode in its charset': () async =>
            http.Response.bytes(
              [0xff, 0xfe],
              403,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
        'request without an account': () async => http.Response(
          jsonEncode({
            'errors': ['You need to be logged in to do that.'],
            'error_type': 'not_logged_in',
          }),
          403,
        ),
        'unauthorized without a body': () async => http.Response('', 401),
        'refused key behind an unauthorized status': () async =>
            _invalidAccess(statusCode: 401),
        'refused key behind a server error': () async =>
            _invalidAccess(statusCode: 500),
        'unavailable site': () async => http.Response('', 503),
        'rate limit': () async => http.Response('', 429),
        'missing route': () async => http.Response('', 404),
        'unreachable site': () async =>
            throw http.ClientException('Connection timed out'),
      };

      for (final MapEntry(key: name, value: respond) in failures.entries) {
        final api = _accountApi(client: MockClient((_) => respond()));

        await expectLater(
          api.currentUser(siteUrl: 'https://meta.discourse.org', apiKey: 'k'),
          throwsA(
            allOf(
              isA<SiteLookupException>(),
              isNot(isA<ApiKeyRejectedException>()),
            ),
          ),
          reason: name,
        );
      }
    });
  });

  group('revokeApiKey', () {
    test('posts the key back to the site', () async {
      String? path;
      String? method;
      final api = _accountApi(
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

    test('reports a site too old to revoke its notification key', () async {
      final api = _accountApi(
        client: MockClient((_) async => http.Response('', 404)),
      );

      await expectLater(
        api.revokeApiKey(siteUrl: 'https://old.example.com', apiKey: 'k'),
        throwsA(
          isA<SiteLookupException>().having(
            (error) => error.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });

    test('does not mistake a redirect for a completed revocation', () async {
      var requests = 0;
      final api = _accountApi(
        client: MockClient((request) async {
          requests += 1;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://meta.discourse.org/login'},
          );
        }),
      );

      await expectLater(
        api.revokeApiKey(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
        ),
        throwsA(
          isA<SiteLookupException>().having(
            (error) => error.statusCode,
            'statusCode',
            302,
          ),
        ),
      );
      expect(requests, 1);
    });

    test('accepts a key the site already refuses as revoked', () async {
      String? accept;
      final api = _accountApi(
        client: MockClient((request) async {
          accept = request.headers['Accept'];
          // Without a JSON Accept header Discourse answers this refusal as
          // plain text, which is indistinguishable from any other 403.
          if (accept != 'application/json') return http.Response('No', 403);
          return _invalidAccess();
        }),
      );

      await api.revokeApiKey(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'revoked-key',
      );

      expect(accept, 'application/json');
    });

    test('does not mistake another refusal for a revoked key', () async {
      final refusals = {
        'web application firewall page': http.Response(
          '<html><body>Access denied</body></html>',
          403,
          headers: {'content-type': 'text/html'},
        ),
        'request without an account': http.Response(
          jsonEncode({
            'errors': ['You need to be logged in to do that.'],
            'error_type': 'not_logged_in',
          }),
          403,
        ),
        'refused key behind another status': _invalidAccess(statusCode: 404),
      };

      for (final MapEntry(key: name, value: response) in refusals.entries) {
        final api = _accountApi(client: MockClient((_) async => response));

        await expectLater(
          api.revokeApiKey(
            siteUrl: 'https://meta.discourse.org',
            apiKey: 'the-key',
          ),
          throwsA(
            isA<SiteLookupException>().having(
              (error) => error.statusCode,
              'statusCode',
              response.statusCode,
            ),
          ),
          reason: name,
        );
      }
    });
  });
}

/// Core's `Discourse::InvalidAccess` answer, as rendered for a JSON request
/// carrying a user API key the site no longer accepts.
http.Response _invalidAccess({int statusCode = 403}) => http.Response(
  jsonEncode({
    'errors': ['You are not permitted to view the requested resource.'],
    'error_type': 'invalid_access',
  }),
  statusCode,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

DiscourseAccountApi _accountApi({http.Client? client}) {
  final transport = DiscourseTransport.create(client: client);
  addTearDown(transport.close);
  return DiscourseAccountApi(transport, const DiscourseModelCodec.core());
}
