import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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
  group('custom sidebar sections', () {
    test(
      'reads custom links and excludes Discourse built-in sections',
      () async {
        final api = DiscourseApi(
          client: MockClient((request) async {
            expect(request.url.path, '/sidebar_sections.json');
            expect(request.headers['User-Api-Key'], 'secret');
            return http.Response(
              jsonEncode({
                'sidebar_sections': [
                  {
                    'id': 1,
                    'title': 'Community',
                    'section_type': 'community',
                    'links': [
                      {
                        'id': 10,
                        'name': 'Topics',
                        'value': '/latest',
                        'icon': 'layer-group',
                      },
                    ],
                  },
                  {
                    'id': 2,
                    'title': 'Projects',
                    'section_type': null,
                    'links': [
                      {
                        'id': 20,
                        'name': 'Roadmap',
                        'value': '/c/roadmap/4',
                        'icon': 'fire',
                      },
                      {
                        'id': 21,
                        'name': 'Design files',
                        'value': 'https://example.com/design',
                        'icon': 'not-installed',
                      },
                      {'id': 22, 'name': '', 'value': '/broken'},
                    ],
                  },
                ],
              }),
              200,
            );
          }),
        );

        final sections = await api.customSidebarSections(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
        );

        expect(sections, hasLength(1));
        expect(sections.single.title, 'Projects');
        expect(
          sections.single.destinations.map((destination) => destination.label),
          ['Roadmap', 'Design files'],
        );
        expect(sections.single.destinations.first.icon, DIcons.fire);
        expect(sections.single.destinations.last.icon, DIcons.link);
        expect(sections.single.destinations.first.url, '/c/roadmap/4');
      },
    );
  });

  group('normalize', () {
    test('assumes https for a bare host', () {
      expect(
        DiscourseApi.normalize('meta.discourse.org').toString(),
        'https://meta.discourse.org',
      );
    });

    test('keeps explicit HTTP for loopback development hosts', () {
      expect(
        DiscourseApi.normalize('http://localhost:4200').toString(),
        'http://localhost:4200',
      );
      expect(
        DiscourseApi.normalize('http://127.0.0.1:4200').toString(),
        'http://127.0.0.1:4200',
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

    test('rejects remote HTTP before making a request', () async {
      var requestCount = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('', 500);
        }),
      );

      await expectLater(
        api.lookup('http://example.com'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.unreachable,
          ),
        ),
      );
      expect(requestCount, 0);
    });

    test('rejects site credentials before making a request', () async {
      var requestCount = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('', 500);
        }),
      );

      await expectLater(
        api.lookup('https://reader:password@example.com'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.unreachable,
          ),
        ),
      );
      expect(requestCount, 0);
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

    test('rejects an HTTPS to HTTP redirect before following it', () async {
      final requested = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.url ==
              Uri.parse('https://discourse.org/user-api-key/new')) {
            return http.Response(
              '',
              301,
              headers: {
                'location': 'http://meta.discourse.org/user-api-key/new',
              },
            );
          }
          if (request.url.path == '/user-api-key/new') {
            return http.Response('', 200, headers: {'auth-api-version': '4'});
          }
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.lookup('discourse.org'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.unreachable,
          ),
        ),
      );
      expect(requested, [Uri.parse('https://discourse.org/user-api-key/new')]);
    });

    test('rejects redirect credentials before following them', () async {
      final requested = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response(
            '',
            301,
            headers: {
              'location':
                  'https://reader:password@meta.discourse.org/'
                  'user-api-key/new',
            },
          );
        }),
      );

      await expectLater(
        api.lookup('discourse.org'),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.failure,
            'failure',
            SiteLookupFailure.unreachable,
          ),
        ),
      );
      expect(requested, [Uri.parse('https://discourse.org/user-api-key/new')]);
    });

    test('follows redirects between loopback development hosts', () async {
      final api = DiscourseApi(
        client: discourseServing(
          redirects: {
            'http://localhost:4200/user-api-key/new':
                'http://127.0.0.1:4300/user-api-key/new',
          },
        ),
      );

      final site = await api.lookup('http://localhost:4200');
      expect(site.url, 'http://127.0.0.1:4300');
    });

    test('keeps the port, unlike DiscourseMobile', () async {
      final api = DiscourseApi(client: discourseServing());
      final site = await api.lookup('http://localhost:4200');

      expect(site.url, 'http://localhost:4200');
    });
  });

  group('transport safety', () {
    test('authenticated reads reject remote HTTP before sending', () async {
      var requestCount = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.notifications(siteUrl: 'http://example.com', apiKey: 'secret'),
        throwsA(isA<SiteLookupException>()),
      );
      expect(requestCount, 0);
    });

    test('authenticated writes reject remote HTTP before sending', () async {
      var requestCount = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.markNotificationRead(
          siteUrl: 'http://example.com',
          apiKey: 'secret',
          id: 1,
        ),
        throwsA(isA<WriteException>()),
      );
      expect(requestCount, 0);
    });

    test('authenticated reads never follow redirects', () async {
      final requested = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested.add(request.url);
          expect(request.followRedirects, isFalse);
          expect(request.headers['User-Api-Key'], 'secret');
          return http.Response(
            '',
            302,
            headers: {'location': 'http://attacker.example/notifications.json'},
          );
        }),
      );

      await expectLater(
        api.notifications(siteUrl: 'https://example.com', apiKey: 'secret'),
        throwsA(isA<SiteLookupException>()),
      );
      expect(requested, [
        Uri.parse(
          'https://example.com/notifications.json?recent=true&limit=30',
        ),
      ]);
    });

    test('authenticated writes never follow redirects', () async {
      final requested = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested.add(request.url);
          expect(request.followRedirects, isFalse);
          expect(request.headers['User-Api-Key'], 'secret');
          return http.Response(
            '',
            307,
            headers: {'location': 'https://attacker.example/write'},
          );
        }),
      );

      await expectLater(
        api.markNotificationRead(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
          id: 1,
        ),
        throwsA(isA<WriteException>()),
      );
      expect(requested, [
        Uri.parse('https://example.com/notifications/mark-read.json'),
      ]);
    });

    test(
      'plugin reads reject absolute cross-origin paths before sending',
      () async {
        var requestCount = 0;
        final api = DiscourseApi(
          client: MockClient((_) async {
            requestCount += 1;
            return http.Response('{}', 200);
          }),
        );

        await expectLater(
          api.pluginGetJson(
            siteUrl: 'https://example.com',
            path: 'https://attacker.example/steal-key.json',
            apiKey: 'secret',
          ),
          throwsArgumentError,
        );
        expect(requestCount, 0);
      },
    );

    test(
      'plugin writes reject scheme-relative cross-origin paths before sending',
      () async {
        var requestCount = 0;
        final api = DiscourseApi(
          client: MockClient((_) async {
            requestCount += 1;
            return http.Response('{}', 200);
          }),
        );

        await expectLater(
          api.pluginWriteJson(
            siteUrl: 'https://example.com',
            path: '//attacker.example/steal-key.json',
            method: 'POST',
            apiKey: 'secret',
            body: const {},
          ),
          throwsArgumentError,
        );
        expect(requestCount, 0);
      },
    );

    test('plugin transport keeps relative routes on the site origin', () async {
      final requests = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      );

      await api.pluginGetJson(
        siteUrl: 'https://example.com',
        path: '/resenha/rooms.json?limit=20',
        apiKey: 'secret',
      );
      await api.pluginWriteJson(
        siteUrl: 'https://example.com',
        path: 'resenha/rooms/1.json',
        method: 'PUT',
        apiKey: 'secret',
        body: const {'name': 'Room'},
      );

      expect(requests.map((request) => request.url), [
        Uri.parse('https://example.com/resenha/rooms.json?limit=20'),
        Uri.parse('https://example.com/resenha/rooms/1.json'),
      ]);
      expect(
        requests,
        everyElement(
          isA<http.Request>().having(
            (request) => request.headers['User-Api-Key'],
            'User-Api-Key',
            'secret',
          ),
        ),
      );
    });

    test('authenticated reads reject oversized API responses', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('12345', 200)),
        maxResponseBytes: 4,
      );

      await expectLater(
        api.notifications(siteUrl: 'https://example.com', apiKey: 'secret'),
        throwsA(
          isA<SiteLookupException>().having(
            (error) => error.failure,
            'failure',
            SiteLookupFailure.unreachable,
          ),
        ),
      );
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

  group('notifications', () {
    test('reads the list the user menu shows', () async {
      Uri? url;
      final api = DiscourseApi(
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

      // The menu's own view of the list, not the paged history.
      expect(url?.path, '/notifications.json');
      expect(url?.queryParameters['recent'], 'true');
      expect(url?.queryParameters['limit'], '30');
      expect(url?.queryParameters, isNot(contains('filter_by_types')));
      expect(url?.queryParameters, isNot(contains('silent')));

      expect(notifications.first.kind, NotificationKind.replied);
      expect(notifications.first.topicId, 77);
      expect(notifications.first.postNumber, 4);
      expect(notifications.first.actor, 'sam');
      expect(notifications.first.title, 'Better “image” handling');
      expect(notifications.first.isUnread, isTrue);

      // The consolidated kinds name the actor in `username` instead.
      expect(notifications.last.kind, NotificationKind.likedConsolidated);
      expect(notifications.last.actor, 'david');
      expect(notifications.last.count, 3);
      expect(notifications.last.isUnread, isFalse);
    });

    test('falls back to the title Discourse wrote for a browser', () async {
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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

      expect(notifications.single.kind, NotificationKind.unknown);
      expect(notifications.single.title, 'From some plugin');
      expect(notifications.single.path, '/t/topic/9');
    });

    test('reads Replies as a silent server-filtered list', () async {
      Uri? url;
      final api = DiscourseApi(
        client: MockClient((request) async {
          url = request.url;
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 12,
                  'notification_type': NotificationKind.replied.id,
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
        filterByTypes: userMenuReplyNotificationKinds,
      );

      expect(url?.path, '/notifications.json');
      expect(url?.queryParameters, {
        'recent': 'true',
        'limit': '30',
        'filter_by_types': 'mentioned,group_mentioned,posted,quoted,replied',
        'silent': 'true',
      });
      expect(replies.single.kind, NotificationKind.replied);
      expect(replies.single.actor, 'sam');
    });
  });

  group('bookmarks', () {
    test('reads both lists the bookmarks tab is made of', () async {
      Uri? url;
      final api = DiscourseApi(
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

      // A reminder is a notification, and reads as one.
      expect(payload.reminders.single.kind, NotificationKind.bookmarkReminder);
      expect(payload.reminders.single.path, '/t/better-image-handling/77');

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
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'bookmarks': [
                  {
                    'id': 3,
                    // A plugin's own bookmarkable, with none of the keys a post
                    // or a topic carries.
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
        // Left exactly as it came: a plugin's bookmarkable can point anywhere,
        // and this app has nowhere but the browser to open it either way.
        expect(
          payload.bookmarks.single.path,
          'https://example.com/plugin/thing/1',
        );
      },
    );

    test(
      'a topic keeps its path, not the host the site wrote it against',
      () async {
        final api = DiscourseApi(
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

  group('markNotificationRead', () {
    test('names the one notification to mark', () async {
      String? method;
      String? path;
      String? body;
      final api = DiscourseApi(
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
      // An id, and only an id: the same route with none dismisses the lot.
      expect(jsonDecode(body!), {'id': 12});
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

    test('does not mistake a redirect for a completed revocation', () async {
      var requests = 0;
      final api = DiscourseApi(
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
  });
}

void _feedGroups() {
  group('searchPosts', () {
    test("asks for facet suggestions with core's topic exclusion", () async {
      late http.Request sent;
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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
  });

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
                  'can_create_topic': true,
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
                      'tags': [
                        {'id': 11, 'name': 'feature', 'slug': 'feature'},
                        {'id': 12, 'name': 'ux', 'slug': 'user-experience'},
                      ],
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
        expect(topic.tags, const [
          TopicTag(id: 11, name: 'feature', slug: 'feature'),
          TopicTag(id: 12, name: 'ux', slug: 'user-experience'),
        ]);
        expect(list.moreTopicsUrl, '/latest?page=1');
        expect(list.canCreateTopic, isTrue);

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
                        'permission': 1,
                        'minimum_required_tags': 2,
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
      expect(categories.last.canCreateTopic, isTrue);
      expect(categories.last.minimumRequiredTags, 2);
    });
  });

  group('topic composer metadata', () {
    test('reads fresh tag capabilities from site.json', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'can_tag_topics': true,
              'can_create_tag': true,
              'tags_filter_regexp': r'[a-z-]+',
              'uncategorized_category_id': 1,
              'max_tag_length': 20,
            }),
            200,
          ),
        ),
      );

      final capabilities = await api.topicComposerCapabilities(
        siteUrl: 'https://example.com',
        apiKey: 'k',
      );

      expect(capabilities.canTagTopics, isTrue);
      expect(capabilities.canCreateTag, isTrue);
      expect(capabilities.maxTagLength, 20);
    });

    test('searches tags in category and preserves disabled reasons', () async {
      late Uri sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request.url;
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 7,
                  'name': 'restricted',
                  'disabled': true,
                  'title': 'Not allowed in this category',
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await api.searchTopicTags(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        term: 'res',
        categoryId: 4,
        selectedTagIds: const [2, 3],
      );

      expect(sent.path, '/tags/filter/search.json');
      expect(sent.queryParameters['categoryId'], '4');
      expect(sent.queryParametersAll['selected_tag_ids[]'], ['2', '3']);
      expect(
        result.results.single.disabledReason,
        'Not allowed in this category',
      );
    });
  });

  group('siteConfig', () {
    test('reads the client settings route rather than /site.json', () async {
      // `/site.json` carries no site settings and no plugin list at all —
      // SiteSerializer is categories, groups, archetypes and themes. This is
      // the only public payload a plugin's own configuration reaches a client
      // through.
      final paths = <String>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'emoji_set': 'apple',
              'external_emoji_url': '',
              'discourse_reactions_enabled': true,
              'discourse_reactions_reaction_for_like': 'heart',
              'discourse_reactions_enabled_reactions': '+1|clap',
            }),
            200,
          );
        }),
      );

      final config = await api.siteConfig(siteUrl: 'https://example.com');

      expect(paths, ['/site/settings.json']);
      expect(config.emojiSet, 'apple');
      expect(config.mainReaction, 'heart');
      expect(config.offeredReactions, ['heart', '+1', 'clap']);
    });

    test(
      'refuses rather than inventing an answer for a site that will not',
      () async {
        final api = DiscourseApi(
          client: MockClient((_) async => http.Response('nope', 403)),
        );

        // The caller swallows this; what matters is that it does not come back
        // as a SiteConfig claiming things about the site.
        expect(
          () => api.siteConfig(siteUrl: 'https://example.com'),
          throwsA(isA<SiteLookupException>()),
        );
      },
    );
  });

  group('searchUsers', () {
    test('asks with the term, the limit and the topic', () async {
      Uri? asked;
      final api = DiscourseApi(
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
      // Absent on a site with `enable_names` off.
      expect(found.last.name, isNull);
    });

    test('leaves the topic out when there is not one', () async {
      Uri? asked;
      final api = DiscourseApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(jsonEncode({'users': const <Object?>[]}), 200);
        }),
      );

      await api.searchUsers(siteUrl: 'https://example.com', term: 'sa');

      expect(asked!.queryParameters.containsKey('topic_id'), isFalse);
    });

    test('an answer it cannot read is a failure, not an empty list', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      await expectLater(
        api.searchUsers(siteUrl: 'https://example.com', term: 'sa'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('searchHashtags', () {
    /// One row of what `/hashtags/search.json` answers with.
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
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('<html>nope', 200)),
      );

      expect(
        () => api.searchHashtags(siteUrl: 'https://example.com', term: 'x'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('lookupHashtags', () {
    test('asks with every ref and reads the reply keyed by type', () async {
      Uri? asked;
      final api = DiscourseApi(
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
            }),
            200,
          );
        }),
      );

      final found = await api.lookupHashtags(
        siteUrl: 'https://example.com',
        refs: ['bug', 'ux::tag'],
      );

      expect(asked!.path, '/hashtags.json');
      expect(asked!.queryParametersAll['slugs[]'], ['bug', 'ux::tag']);
      expect(asked!.queryParametersAll['order[]'], ['category', 'tag']);
      expect(found.map((f) => f.ref), containsAll(['bug', 'ux::tag']));
    });

    test('a ref the site does not resolve is simply absent', () async {
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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

  group('emojis', () {
    test('flattens the groups the site lists them in', () async {
      final paths = <String>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'smileys_&_emotion': [
                {'name': 'smile', 'url': '/images/emoji/twitter/smile.png'},
                {'name': 'grin', 'url': 'https://cdn.example.com/grin.png'},
              ],
              'default': [
                {'name': 'shipit', 'url': '/uploads/shipit.png'},
                // Malformed rows are dropped rather than read loosely.
                {'name': 'no_url'},
              ],
              'not_a_group': 'nonsense',
            }),
            200,
          );
        }),
      );

      final emojis = await api.emojis(siteUrl: 'https://example.com');

      expect(paths, ['/emojis.json']);
      expect(emojis.map((e) => e.name), ['smile', 'grin', 'shipit']);
      // Site-relative urls are resolved; an absolute one is left as the site
      // wrote it, CDN and all.
      expect(
        emojis.first.url,
        'https://example.com/images/emoji/twitter/smile.png',
      );
      expect(emojis[1].url, 'https://cdn.example.com/grin.png');
    });

    test('an answer it cannot read is a failure, not an empty list', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      await expectLater(
        api.emojis(siteUrl: 'https://example.com'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('customEmojis', () {
    test('reads a payload shaped as an object of name to url', () async {
      final paths = <String>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'party_blob': 'https://example.com/uploads/party.png',
              'shipit': '/uploads/default/shipit.png',
            }),
            200,
          );
        }),
      );

      final emojis = await api.customEmojis(siteUrl: 'https://example.com');

      expect(paths, ['/site/emoji.json']);
      expect(emojis, {
        'party_blob': 'https://example.com/uploads/party.png',
        'shipit': '/uploads/default/shipit.png',
      });
    });

    test('reads a payload shaped as a list of entries', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'name': 'party_blob', 'url': 'https://example.com/u/p.png'},
              // Malformed rows are dropped rather than read loosely.
              {'name': 'no_url'},
              'not a row',
            ]),
            200,
          ),
        ),
      );

      final emojis = await api.customEmojis(siteUrl: 'https://example.com');

      expect(emojis, {'party_blob': 'https://example.com/u/p.png'});
    });

    test('an answer it cannot read is a failure, not an empty map', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('nope', 500)),
      );

      expect(
        () => api.customEmojis(siteUrl: 'https://example.com'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('toggleReaction', () {
    Map<String, dynamic> reacted() => {
      'id': 1,
      'post_number': 1,
      'username': 'sam',
      'cooked': '<p>Hi</p>',
      'reactions': [
        {'id': 'clap', 'type': 'emoji', 'count': 1},
      ],
      'current_user_reaction': {
        'id': 'clap',
        'type': 'emoji',
        'can_undo': true,
      },
      'reaction_users_count': 1,
    };

    test('puts to the toggle route with no body at all', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode(reacted()), 200);
        }),
      );

      final post = await api.toggleReaction(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        postId: 1,
        reaction: 'clap',
      );

      expect(seen.method, 'PUT');
      expect(
        seen.url.path,
        '/discourse-reactions/posts/1/custom-reactions/clap/toggle.json',
      );
      expect(seen.body, '{}');
      // Answered unwrapped, the way the like routes are.
      expect(post?.reactions?.mine?.id, 'clap');
    });

    test('encodes a reaction that is not url-safe', () async {
      // `+1` is a perfectly ordinary reaction id, and it is a path segment.
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(reacted()), 200);
        }),
      );

      await api.toggleReaction(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        postId: 1,
        reaction: '+1',
      );

      expect(seen.toString(), contains('custom-reactions/%2B1/toggle.json'));
      expect(seen.pathSegments, contains('+1'));
    });

    test('surfaces the status, so a 404 can be told from a refusal', () async {
      // A 404 means the plugin went away *or* the post did — the same bytes for
      // both — and the caller repairs one post rather than a site.
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('not found', 404)),
      );

      await expectLater(
        api.toggleReaction(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          postId: 1,
          reaction: 'clap',
        ),
        throwsA(
          isA<WriteException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('reports a rate limit as one', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response('slow down', 429, headers: const {}),
        ),
      );

      await expectLater(
        api.toggleReaction(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          postId: 1,
          reaction: 'clap',
        ),
        throwsA(
          isA<WriteException>().having(
            (e) => e.failure,
            'failure',
            WriteFailure.rateLimited,
          ),
        ),
      );
    });
  });

  group('postReactors', () {
    test('asks the list route and reads its envelope', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'users': [
                {'id': 3, 'username': 'sam', 'reaction': 'clap'},
              ],
              'total_rows': 4,
            }),
            200,
          );
        }),
      );

      final reactors = await api.postReactors(
        siteUrl: 'https://example.com',
        postId: 1,
      );

      expect(
        seen.path,
        '/discourse-reactions/posts/1/reactions-users-list.json',
      );
      expect(seen.queryParameters['limit'], '30');
      expect(seen.queryParameters, isNot(contains('reaction_value')));
      expect(reactors.reactors.single.username, 'sam');
      expect(reactors.total, 4);
    });

    test('narrows to one emoji when asked to', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({'users': const <Object?>[], 'total_rows': 0}),
            200,
          );
        }),
      );

      final reactors = await api.postReactors(
        siteUrl: 'https://example.com',
        postId: 1,
        reaction: '+1',
      );

      expect(seen.queryParameters['reaction_value'], '+1');
      // Kept on the record, so the filtered list does not overwrite the whole
      // one in the store.
      expect(reactors.filter, '+1');
    });
  });

  group('chatChannels', () {
    /// The two-bucket envelope `Chat::ChannelIndexSerializer` writes.
    MockClient serving(void Function(http.Request) record) =>
        MockClient((request) async {
          record(request);
          return http.Response(
            jsonEncode({
              'public_channels': [
                {
                  'id': 9,
                  'title': 'Bugs',
                  'slug': 'bugs',
                  'chatable_type': 'Category',
                  'chatable': {'name': 'Bug', 'color': '0088CC'},
                },
              ],
              'direct_message_channels': [
                {
                  'id': 12,
                  'title': 'hawk',
                  'chatable_type': 'DirectMessage',
                  'chatable': {
                    'group': false,
                    'users': [
                      {'id': 2, 'username': 'hawk'},
                    ],
                  },
                },
              ],
              'tracking': {
                'channel_tracking': {
                  '9': {'unread_count': 3, 'mention_count': 1},
                },
              },
              'meta': {'message_bus_last_ids': <String, dynamic>{}},
            }),
            200,
          );
        });

    test(
      'asks the route that answers with only the channels a reader follows',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await api.chatChannels(siteUrl: 'https://example.com');

        expect(seen.path, '/chat/api/me/channels.json');
        // The route takes no parameters at all — the reader's own memberships are
        // the whole of the query.
        expect(seen.queryParameters, isEmpty);
      },
    );

    test('reads the public and the direct lists apart', () async {
      final api = DiscourseApi(client: serving((_) {}));

      final channels = await api.chatChannels(siteUrl: 'https://example.com');

      expect(channels.public.single.title, 'Bugs');
      expect(channels.direct.single.isDirectMessage, isTrue);
      expect(channels.public.single.tracking.unreadCount, 3);
    });

    test(
      'sends the user api key, an anonymous reader having no channels',
      () async {
        late Map<String, String> headers;
        final api = DiscourseApi(client: serving((r) => headers = r.headers));

        await api.chatChannels(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          clientId: 'client',
        );

        expect(headers['User-Api-Key'], 'key');
        expect(headers['User-Api-Client-Id'], 'client');
      },
    );

    test('reports a site that refuses the way every other read does', () async {
      // 403 is what a site with chat off, or a reader who may not use it, gets.
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('{}', 403)),
      );

      await expectLater(
        api.chatChannels(siteUrl: 'https://example.com'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('chatMessages', () {
    MockClient serving(
      void Function(http.Request) record, {
      Object? canLoadMorePast,
    }) => MockClient((request) async {
      record(request);
      return http.Response(
        jsonEncode({
          'messages': [
            {
              'id': 40,
              'chat_channel_id': 9,
              'cooked': '<p>hi</p>',
              'created_at': '2026-05-05T10:00:00.000Z',
              'user': {'id': 2, 'username': 'sam'},
            },
          ],
          'meta': {
            'can_load_more_past': canLoadMorePast,
            'can_load_more_future': null,
          },
        }),
        200,
      );
    });

    test('asks for the newest page when no message is named', () async {
      late Uri seen;
      final api = DiscourseApi(client: serving((r) => seen = r.url));

      final page = await api.chatMessages(
        siteUrl: 'https://example.com',
        channelId: 9,
      );

      expect(seen.path, '/chat/api/channels/9/messages.json');
      expect(seen.queryParameters['page_size'], '50');
      expect(page.messages.single.id, 40);
    });

    test('rejects invalid pagination before sending a request', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );
      final invalidCalls = <Future<void> Function()>[
        () => api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 1,
          after: 2,
        ),
        () => api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 1,
          fromLastRead: true,
        ),
        () => api.chatMessages(siteUrl: 'https://example.com', channelId: 0),
        () => api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 0,
        ),
        () => api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          pageSize: 0,
        ),
        () => api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          pageSize: 51,
        ),
      ];

      for (final call in invalidCalls) {
        await expectLater(call(), throwsArgumentError);
      }
      expect(requests, 0);
    });

    test('omits the target message rather than sending an empty one', () async {
      // `target_message_id=` reads as 0 server side and 404s for a message
      // that cannot exist.
      late Uri seen;
      final api = DiscourseApi(client: serving((r) => seen = r.url));

      await api.chatMessages(siteUrl: 'https://example.com', channelId: 9);

      expect(seen.queryParameters, isNot(contains('target_message_id')));
      expect(seen.queryParameters, isNot(contains('direction')));
    });

    test(
      'asks for the page before a message it holds, that message excluded',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 40,
        );

        expect(seen.queryParameters['direction'], 'past');
        expect(seen.queryParameters['target_message_id'], '40');
      },
    );

    test(
      'never asks to fetch from last read, there being no way to page forward',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await api.chatMessages(siteUrl: 'https://example.com', channelId: 9);

        expect(seen.queryParameters, isNot(contains('fetch_from_last_read')));
      },
    );

    test(
      'sends the page size the site caps at, so the code names the real one',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          pageSize: 20,
        );

        expect(seen.queryParameters['page_size'], '20');
      },
    );

    test(
      'reads a null can_load_more_past as no more rather than as unknown',
      () async {
        // Ruby leaves the flag for the direction it did not paginate unassigned.
        final api = DiscourseApi(
          client: serving((_) {}, canLoadMorePast: null),
        );

        final page = await api.chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
        );

        expect(page.canLoadMorePast, isFalse);
      },
    );

    test('reads a channel that says there is more behind it', () async {
      final api = DiscourseApi(client: serving((_) {}, canLoadMorePast: true));

      final page = await api.chatMessages(
        siteUrl: 'https://example.com',
        channelId: 9,
      );

      expect(page.canLoadMorePast, isTrue);
    });
  });

  group('chatThreadMessages', () {
    test('rejects invalid identities and direction before transport', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );
      final invalidCalls = <Future<void> Function()>[
        () => api.chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 0,
          threadId: 2,
        ),
        () => api.chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 0,
        ),
        () => api.chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          before: 3,
          after: 4,
        ),
        () => api.chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          after: -1,
        ),
      ];

      for (final call in invalidCalls) {
        await expectLater(call(), throwsArgumentError);
      }
      expect(requests, 0);
    });
  });

  group('markChatChannelRead', () {
    test('names the message the reader has got to, in the query', () async {
      String? method;
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          method = request.method;
          seen = request.url;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await api.markChatChannelRead(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
      );

      expect(method, 'PUT');
      expect(seen.path, '/chat/api/channels/9/read.json');
      // In the query string, which is where Discourse's own client puts it.
      expect(seen.queryParameters['message_id'], '44');
    });

    test('reports a refusal rather than swallowing it', () async {
      // The controller swallows it; the route does not get to decide that.
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('', 404)),
      );

      await expectLater(
        api.markChatChannelRead(
          siteUrl: 'https://example.com',
          apiKey: 'the-key',
          channelId: 9,
          messageId: 44,
        ),
        throwsA(isA<WriteException>()),
      );
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
      expect(topic.detail.title, 'A real topic');
    });

    test('asks by id alone when the link carried no slug', () async {
      final paths = <String>[];
      await DiscourseApi(
        client: serving(paths),
      ).topic(siteUrl: 'https://example.com', slug: '', id: 12);

      expect(paths, ['/t/12.json']);
    });

    test('asks for the window around a requested post', () async {
      final paths = <String>[];
      await DiscourseApi(client: serving(paths)).topic(
        siteUrl: 'https://example.com',
        slug: 'a-real-topic',
        id: 12,
        postNumber: 37,
      );

      expect(paths, ['/t/a-real-topic/12/37.json']);
    });

    test('uses an unambiguous query for a slugless requested post', () async {
      late Uri asked;
      final api = DiscourseApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'id': 12,
              'post_stream': {'posts': <Object?>[], 'stream': <Object?>[]},
            }),
            200,
          );
        }),
      );

      await api.topic(
        siteUrl: 'https://example.com',
        slug: '',
        id: 12,
        postNumber: 37,
      );

      expect(asked.path, '/t/12.json');
      expect(asked.queryParameters['post_number'], '37');
    });

    test('records the post a reader had on screen as a topic timing', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 200);
        }),
      );

      await api.recordTopicRead(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        topicId: 12,
        postNumber: 37,
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/topics/timings.json');
      expect(jsonDecode(sent.body), {
        'topic_id': 12,
        'topic_time': 500,
        'timings': {'37': 500},
      });
    });

    test('preserves a failed response status for diagnostics', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('', 503)),
      );

      await expectLater(
        api.topic(siteUrl: 'https://example.com', slug: 'a-topic', id: 12),
        throwsA(
          isA<SiteLookupException>()
              .having(
                (error) => error.failure,
                'failure',
                SiteLookupFailure.unreachable,
              )
              .having((error) => error.statusCode, 'statusCode', 503),
        ),
      );
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

      await DiscourseApi(
        client: serving(),
      ).posts(siteUrl: 'https://meta.discourse.org', topicId: 12, ids: [2]);
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

    test('asks for and parses more topics on a final post window', () async {
      late Uri asked;
      final api = DiscourseApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'post_stream': {
                'posts': [
                  {
                    'id': 20,
                    'post_number': 20,
                    'username': 'sam',
                    'cooked': '<p>the end</p>',
                  },
                ],
              },
              'suggested_topics': [
                {'id': 30, 'title': 'Suggested', 'slug': 'suggested'},
              ],
              'related_topics': [
                {'id': 40, 'title': 'Related', 'slug': 'related'},
              ],
            }),
            200,
          );
        }),
      );

      final page = await api.topicPosts(
        siteUrl: 'https://meta.discourse.org',
        topicId: 12,
        ids: [20],
      );

      expect(asked.query, contains('include_suggested=true'));
      expect(page.posts.single.id, 20);
      expect(page.recommendations!.suggested.single.id, 30);
      expect(page.recommendations!.related.single.id, 40);
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

  group('user drafts', () {
    test(
      'reads the current account draft count for navigation badges',
      () async {
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'current_user': {'id': 7, 'username': 'sam', 'draft_count': 3},
              }),
              200,
            ),
          ),
        );

        final user = await api.currentUser(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
        );

        expect(user.draftCount, 3);
      },
    );

    test('reads the current account’s chat header state', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'has_chat_enabled': true,
                'do_not_disturb_until': '2027-01-02T03:04:05.000Z',
                'custom_fields': {'last_chat_channel_id': '42'},
                'user_option': {
                  'chat_header_indicator_preference': 'only_mentions',
                },
              },
            }),
            200,
          ),
        ),
      );

      final user = await api.currentUser(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
      );

      expect(user.hasChatEnabled, isTrue);
      expect(
        user.chatHeaderIndicatorPreference,
        ChatHeaderIndicatorPreference.onlyMentions,
      );
      expect(user.doNotDisturbUntil, DateTime.utc(2027, 1, 2, 3, 4, 5));
      expect(user.lastChatChannelId, 42);
    });

    test('reads a page of portable composer drafts', () async {
      late Uri asked;
      final api = DiscourseApi(
        client: MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'drafts': [
                {
                  'created_at': '2026-08-08T17:30:00.000Z',
                  'draft_key': 'topic_12',
                  'sequence': 4,
                  'data': '{"reply":"Half a thought","action":"reply"}',
                  'topic_id': 12,
                  'title': 'Native drafts',
                  'slug': 'native-drafts',
                },
              ],
            }),
            200,
          );
        }),
      );

      final drafts = await api.userDrafts(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        offset: 30,
        limit: 15,
      );

      expect(asked.path, '/drafts.json');
      expect(asked.queryParameters, {'offset': '30', 'limit': '15'});
      expect(drafts.single.key, 'topic_12');
      expect(drafts.single.data?.reply, 'Half a thought');
      expect(drafts.single.displayTitle, 'Native drafts');
    });

    test('deletes the named draft at its current sequence', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await api.deleteUserDraft(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        draftKey: 'topic 12',
        sequence: 7,
      );

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/drafts/topic%2012.json');
      expect(sent.url.queryParameters['sequence'], '7');
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

    test(
      'reports an enqueued post as enqueued rather than as posted',
      () async {
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
      },
    );

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

    test(
      'ignores a negative Retry-After header and uses the valid body',
      () async {
        final api = DiscourseApi(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'errors': ['Slow down.'],
                'extras': {'wait_seconds': 42},
              }),
              429,
              headers: {'retry-after': '-5'},
            ),
          ),
        );

        await expectLater(
          create(api),
          throwsA(
            isA<WriteException>().having(
              (error) => error.retryAfter,
              'retryAfter',
              const Duration(seconds: 42),
            ),
          ),
        );
      },
    );

    test('caps an excessive retry delay from an untrusted response', () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'errors': ['Slow down.'],
              'extras': {'wait_seconds': 999999},
            }),
            429,
          ),
        ),
      );

      await expectLater(
        create(api),
        throwsA(
          isA<WriteException>().having(
            (error) => error.retryAfter,
            'retryAfter',
            const Duration(hours: 1),
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
        timeout: const Duration(milliseconds: 100),
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

  group('createTopic', () {
    test(
      'sends current tag objects and reads the canonical topic identity',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: accepting(
            onRequest: (request) => sent = request,
            envelope: {
              'action': 'create_post',
              'post': {
                'id': 51,
                'post_number': 1,
                'username': 'joffreyj',
                'cooked': '<p>Body</p>',
                'topic_id': 88,
                'topic_slug': 'hello-world',
                'topic_title': 'Hello world',
              },
            },
          ),
        );

        final creation = await api.createTopic(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          title: 'Hello world',
          raw: 'Body',
          categoryId: 4,
          tags: const [
            TopicTag(id: 7, name: 'existing'),
            TopicTag(name: 'new-tag'),
          ],
          typingDuration: const Duration(seconds: 2),
          composerOpenDuration: const Duration(seconds: 8),
        );

        final body = jsonDecode(sent.body) as Map<String, dynamic>;
        expect(body.containsKey('topic_id'), isFalse);
        expect(body['draft_key'], 'new_topic');
        expect(body['tags'], [
          {'id': 7, 'name': 'existing'},
          {'name': 'new-tag'},
        ]);
        expect(creation.topicId, 88);
        expect(creation.topicSlug, 'hello-world');
      },
    );
  });

  group('updatePost', () {
    test('nests raw under post, and reads the rewritten post back', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'post': {
                'id': 42,
                'post_number': 7,
                'username': 'sam',
                'cooked': '<p>changed</p>',
                'can_edit': true,
              },
            }),
            200,
          );
        }),
      );

      final post = await api.updatePost(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
        raw: 'changed',
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/posts/42.json');

      // A top-level `raw` is ignored by the controller, and the post comes
      // back unchanged with nothing to say it was.
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['post'], {'raw': 'changed'});

      expect(post.id, 42);
      expect(post.cooked, '<p>changed</p>');
      expect(post.canEdit, isTrue);
    });

    test('refuses to invent a post when the answer carries none', () async {
      final api = DiscourseApi(
        client: MockClient((request) async => http.Response('{}', 200)),
      );

      await expectLater(
        api.updatePost(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
          raw: 'changed',
        ),
        throwsA(isA<WriteException>()),
      );
    });
  });

  group('topic metadata writes', () {
    test('updates taxonomy with object tags and conflict baselines', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );

      await api.updateTopic(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        topicId: 88,
        title: 'Changed',
        originalTitle: 'Original',
        categoryId: 5,
        tags: const [TopicTag(id: 7, name: 'feature')],
        originalTags: const [TopicTag(id: 6, name: 'old')],
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/t/88.json');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['category_id'], 5);
      expect(body['tags'], [
        {'id': 7, 'name': 'feature'},
      ]);
      expect(body['original_tags'], [
        {'id': 6, 'name': 'old'},
      ]);
    });

    test('uses the dedicated tags-only endpoint', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );

      await api.updateTopicTags(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        topicId: 88,
        tags: const [TopicTag(name: 'mobile')],
      );

      expect(sent.url.path, '/t/88/tags.json');
      expect(jsonDecode(sent.body), {
        'tags': [
          {'name': 'mobile'},
        ],
      });
    });
  });

  group('deletePost and recoverPost', () {
    test('take the empty answers those routes give', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          // No content, which is what a delete answers with — and why success
          // cannot be read as "200 with a JSON body".
          return http.Response('', 204);
        }),
      );

      await api.deletePost(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
      );
      await api.recoverPost(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
      );

      expect(sent.map((r) => r.method), ['DELETE', 'PUT']);
      expect(sent.map((r) => r.url.path), [
        '/posts/42.json',
        '/posts/42/recover.json',
      ]);
    });

    test('report a refusal the way every other write does', () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'errors': [
                'You are not permitted to view the requested resource.',
              ],
            }),
            403,
          ),
        ),
      );

      await expectLater(
        api.deletePost(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
        ),
        throwsA(
          isA<WriteException>().having(
            (e) => e.failure,
            'failure',
            WriteFailure.forbidden,
          ),
        ),
      );
    });
  });

  group('likePost and unlikePost', () {
    /// What the routes answer with: the post itself, unwrapped.
    String likedPost({required int count, required bool acted}) => jsonEncode({
      'id': 42,
      'post_number': 7,
      'username': 'sam',
      'cooked': '<p>hi</p>',
      'actions_summary': [
        {
          'id': 2,
          'count': count,
          if (acted) 'acted': true,
          if (acted) 'can_undo': true,
          if (!acted) 'can_act': true,
        },
      ],
    });

    test(
      'names the post and the action type, and reads the post back',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(likedPost(count: 4, acted: true), 200);
          }),
        );

        final post = await api.likePost(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
        );

        expect(sent.method, 'POST');
        expect(sent.url.path, '/post_actions.json');
        // `id` is the post, and 2 is the like among Discourse's post actions —
        // the rest of that table is flags.
        expect(jsonDecode(sent.body), {'id': 42, 'post_action_type_id': 2});

        expect(post?.likeCount, 4);
        expect(post?.liked, isTrue);
      },
    );

    test('undoes against the post, with the type in the query', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(likedPost(count: 3, acted: false), 200);
        }),
      );

      final post = await api.unlikePost(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
      );

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/post_actions/42.json');
      // In the query rather than the body: a DELETE is the one request whose
      // body nothing in between is obliged to carry.
      expect(sent.url.queryParameters['post_action_type_id'], '2');

      expect(post?.liked, isFalse);
      expect(post?.likeCount, 3);
    });

    test('takes the empty answer undoing can give as a success', () async {
      // 204, which is what the route answers when the post has stopped being
      // visible to the reader. It worked; there is simply nothing to draw.
      final api = DiscourseApi(
        client: MockClient((request) async => http.Response('', 204)),
      );

      expect(
        await api.unlikePost(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
        ),
        isNull,
      );
    });

    test('reports a refusal the way every other write does', () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'errors': ["You can't like your own post"],
            }),
            403,
          ),
        ),
      );

      await expectLater(
        api.likePost(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
        ),
        throwsA(
          isA<WriteException>().having(
            (e) => e.message,
            'message',
            "You can't like your own post",
          ),
        ),
      );
    });
  });

  group('postLikers', () {
    test('asks the post action route for the like, capped', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'post_action_users': [
                {
                  'id': 3,
                  'username': 'sam',
                  'name': 'Sam Saffron',
                  'avatar_template': '/user_avatar/meta/sam/{size}/1.png',
                },
              ],
            }),
            200,
          );
        }),
      );

      final likers = await api.postLikers(
        siteUrl: 'https://meta.discourse.org',
        postId: 42,
        apiKey: 'the-key',
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/post_action_users.json');
      expect(sent.url.queryParameters, {
        'id': '42',
        'post_action_type_id': '2',
        // The route would answer with up to 200 accounts, which is a payload
        // no popup has any use for.
        'limit': '25',
      });

      expect(likers.postId, 42);
      expect(likers.likers.single.displayName, 'Sam Saffron');
    });

    test('fails the way every other read does', () async {
      final api = DiscourseApi(
        client: MockClient((request) async => http.Response('', 500)),
      );

      await expectLater(
        api.postLikers(siteUrl: 'https://meta.discourse.org', postId: 42),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('composer images', () {
    test(
      'uploads multipart bytes with user API headers and monotonic progress',
      () async {
        late http.Request sent;
        final progress = <double>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'original_filename': 'photo.png',
                'url': '/uploads/default/original/photo.png',
                'short_url': 'upload://abc123',
                'width': 1200,
                'height': 900,
                'thumbnail_width': 690,
                'thumbnail_height': 518,
                'thumbnail': {'url': '/uploads/default/optimized/photo.png'},
              }),
              200,
            );
          }),
        );

        final result = await api.uploadComposerImage(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          clientId: 'the-client',
          file: ComposerUploadFile(
            name: 'photo.png',
            length: () => Future.value(4),
            openRead: () => Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
          ),
          onProgress: progress.add,
          abortTrigger: Completer<void>().future,
        );

        expect(sent.method, 'POST');
        expect(sent.url.path, '/uploads.json');
        expect(sent.headers['user-api-key'], 'the-key');
        expect(sent.headers['user-api-client-id'], 'the-client');
        expect(
          sent.headers['content-type'],
          startsWith('multipart/form-data;'),
        );
        final multipart = latin1.decode(sent.bodyBytes);
        expect(multipart, contains('name="upload_type"'));
        expect(multipart, contains('composer'));
        expect(multipart, contains('name="file"; filename="photo.png"'));
        expect(progress, orderedEquals([0.5, 1.0, 1.0]));
        expect(result.shortUrl, 'upload://abc123');
        expect(result.markdownWidth, 690);
        expect(
          result.previewUrl,
          'https://meta.discourse.org/uploads/default/optimized/photo.png',
        );
      },
    );

    test('surfaces a 422 server message', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': ['Image is too large.'],
            }),
            422,
          ),
        ),
      );

      await expectLater(
        api.uploadComposerImage(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'key',
          file: _uploadFile,
          onProgress: (_) {},
          abortTrigger: Completer<void>().future,
        ),
        throwsA(
          isA<ComposerUploadException>()
              .having((error) => error.statusCode, 'status', 422)
              .having(
                (error) => error.message,
                'message',
                'Image is too large.',
              ),
        ),
      );
    });

    test('bounds oversized upload error bodies', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(List.filled(32, 'x').join(), 500),
        ),
        maxResponseBytes: 8,
      );

      await expectLater(
        api.uploadComposerImage(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'key',
          file: _uploadFile,
          onProgress: (_) {},
          abortTrigger: Completer<void>().future,
        ),
        throwsA(
          isA<ComposerUploadException>().having(
            (error) => error.message,
            'message',
            "Couldn't upload photo.png.",
          ),
        ),
      );
    });

    test('cancels an active upload', () async {
      final abort = Completer<void>();
      final api = DiscourseApi(
        client: MockClient.streaming((request, body) async {
          final trigger = (request as http.Abortable).abortTrigger!;
          await trigger;
          throw http.RequestAbortedException(request.url);
        }),
      );
      final upload = api.uploadComposerImage(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'key',
        file: _uploadFile,
        onProgress: (_) {},
        abortTrigger: abort.future,
      );

      abort.complete();

      await expectLater(
        upload,
        throwsA(
          isA<ComposerUploadException>().having(
            (error) => error.message,
            'message',
            'Upload cancelled.',
          ),
        ),
      );
    });

    test(
      'resolves upload short URLs and makes relative URLs absolute',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode([
                {
                  'short_url': 'upload://abc',
                  'url': '/uploads/default/original/image.png',
                },
              ]),
              200,
            );
          }),
        );

        final result = await api.lookupUploadUrls(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'key',
          shortUrls: const ['upload://abc'],
        );

        expect(sent.url.path, '/uploads/lookup-urls');
        expect(jsonDecode(sent.body), {
          'short_urls': ['upload://abc'],
        });
        expect(
          result['upload://abc'],
          'https://meta.discourse.org/uploads/default/original/image.png',
        );
      },
    );
  });
}

final _uploadFile = ComposerUploadFile(
  name: 'photo.png',
  length: () => Future.value(3),
  openRead: () => Stream.value([1, 2, 3]),
);

class SocketishFailure implements Exception {
  const SocketishFailure();
}
