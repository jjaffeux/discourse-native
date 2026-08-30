import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api_client.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';

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
  group('user preferences', () {
    test('loads the full user serializer for the encoded username', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'user': {
                'username': 'Sam Name/One',
                'can_edit': true,
                'can_change_tracking_preferences': true,
                'user_option': {
                  'timezone': 'Europe/Paris',
                  'like_notification_frequency': 2,
                  'notify_on_linked_posts': false,
                  'new_topic_duration_minutes': 10080,
                  'auto_track_topics_after_msecs': 120000,
                  'notification_level_when_replying': 3,
                  'bookmark_auto_delete_preference': 1,
                },
              },
            }),
            200,
          );
        }),
      );

      final result = await api.loadUserPreferences(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        clientId: 'client',
        username: 'Sam Name/One',
      );

      expect(sent.method, 'GET');
      expect(
        sent.url.toString(),
        'https://forum.example/u/Sam%20Name%2FOne.json',
      );
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(sent.headers['User-Api-Client-Id'], 'client');
      expect(
        result,
        const UserPreferences(
          username: 'Sam Name/One',
          timezone: 'Europe/Paris',
          likeNotificationFrequency: 2,
          notifyOnLinkedPosts: false,
          newTopicDurationMinutes: 10080,
          autoTrackTopicsAfterMsecs: 120000,
          notificationLevelWhenReplying: 3,
          bookmarkAutoDeletePreference:
              BookmarkAutoDeletePreference.whenReminderSent,
          canEdit: true,
          canChangeTrackingPreferences: true,
        ),
      );
    });

    test('puts selected values flat and merges a partial response', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'success': 'OK',
              'user': {
                'user_option': {'notify_on_linked_posts': false},
              },
            }),
            200,
          );
        }),
      );
      const fallback = UserPreferences(
        username: 'Sam Name',
        timezone: 'UTC',
        // The controller passes the complete draft as fallback. The response
        // may omit a field it just accepted, so that value must survive.
        likeNotificationFrequency: 2,
        notifyOnLinkedPosts: true,
        canEdit: true,
      );

      final result = await api.updateUserPreferences(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        username: 'Sam Name',
        fallback: fallback,
        values: const {
          'like_notification_frequency': 2,
          'notify_on_linked_posts': false,
        },
      );

      expect(sent.method, 'PUT');
      expect(sent.url.toString(), 'https://forum.example/u/sam%20name.json');
      expect(jsonDecode(sent.body), {
        'like_notification_frequency': 2,
        'notify_on_linked_posts': false,
      });
      expect(result, fallback.copyWith(notifyOnLinkedPosts: false));
    });

    test('keeps the fallback when a successful response omits user', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'success': 'OK'}), 200),
        ),
      );
      const fallback = UserPreferences(username: 'sam', canEdit: true);

      final result = await api.updateUserPreferences(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        username: 'sam',
        fallback: fallback,
        values: const {'timezone': 'UTC'},
      );

      expect(result, fallback);
    });

    test('does not send fields outside the supported native slice', () async {
      var calls = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.updateUserPreferences(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          username: 'sam',
          fallback: const UserPreferences(),
          values: const {'push_notification_level': 'none'},
        ),
        throwsArgumentError,
      );
      expect(calls, 0);
    });

    test('preserves server validation messages', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': ['Timezone is not a valid timezone'],
            }),
            422,
          ),
        ),
      );

      await expectLater(
        api.updateUserPreferences(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          username: 'sam',
          fallback: const UserPreferences(),
          values: const {'timezone': 'Mars/Olympus'},
        ),
        throwsA(
          isA<WriteException>()
              .having(
                (error) => error.failure,
                'failure',
                WriteFailure.validation,
              )
              .having(
                (error) => error.message,
                'message',
                'Timezone is not a valid timezone',
              ),
        ),
      );
    });
  });

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
                        'icon': 'd-chat',
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

    test(
      'resolves an installed owner alias in a generic sidebar row',
      () async {
        final api = DiscourseApi(
          models: DiscourseModelCodec(
            extensions: pluginRegistry,
            recommendationSources: pluginRegistry,
            icons: pluginRegistry,
          ),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'sidebar_sections': [
                  {
                    'id': 2,
                    'title': 'Chat links',
                    'links': [
                      {
                        'id': 20,
                        'name': 'Chat',
                        'value': '/chat',
                        'icon': 'd-chat',
                      },
                    ],
                  },
                ],
              }),
              200,
            ),
          ),
        );

        final destination = (await api.customSidebarSections(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
        )).single.destinations.single;

        expect(destination.icon, DIcons.comment);
        expect(DIcons.byName, isNot(contains('d-chat')));
      },
    );

    test('bounds custom links to the server section limit', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'sidebar_sections': [
                {
                  'id': 2,
                  'title': 'Projects',
                  'links': [
                    false,
                    for (
                      var id = 1;
                      id <= SidebarSection.maximumCustomLinks;
                      id += 1
                    )
                      {'id': id, 'name': 'Link $id', 'value': '/link-$id'},
                  ],
                },
              ],
            }),
            200,
          ),
        ),
      );

      final section = (await api.customSidebarSections(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
      )).single;

      expect(
        section.destinations,
        hasLength(SidebarSection.maximumCustomLinks - 1),
      );
      expect(section.destinations.first.label, 'Link 1');
      expect(section.destinations.last.label, 'Link 49');
      expect(
        section.destinations.map((destination) => destination.label),
        isNot(contains('Link 50')),
      );
      expect(
        () => section.destinations.add(section.destinations.first),
        throwsUnsupportedError,
      );
    });
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

    test('rejects a scheme without a host', () {
      expect(
        () => DiscourseApi.normalize('https://'),
        throwsA(isA<SiteLookupException>()),
      );
    });

    test('does not retain secrets from a rejected URL', () {
      SiteLookupException? failure;
      try {
        DiscourseApi.normalize(
          'https://reader:password@forum.example/path?api_key=secret#private',
        );
      } on SiteLookupException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.term, 'https://forum.example/path?api_key');
      expect(failure.message, isNot(contains('reader')));
      expect(failure.message, isNot(contains('password')));
      expect(failure.message, isNot(contains('secret')));
      expect(failure.message, isNot(contains('private')));
    });

    test('maps a malformed URL without retaining its source', () {
      const secret = 'must-not-survive';
      SiteLookupException? failure;
      try {
        DiscourseApi.normalize(
          'https://reader:password@[invalid?api_key=$secret#private',
        );
      } on SiteLookupException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.cause, const FormatException('Invalid forum URL.'));
      expect(failure.term, isNot(contains('reader')));
      expect(failure.term, isNot(contains('password')));
      expect(failure.term, isNot(contains(secret)));
      expect(failure.term, isNot(contains('private')));
      expect('$failure ${failure.cause}', isNot(contains(secret)));
    });

    test('bounds forum addresses without retaining oversized input', () {
      const secret = 'oversized-secret-must-not-survive';
      final oversized =
          'https://reader:$secret@forum.example/'
          "${'x' * DiscourseApi.maximumForumAddressLength}";

      SiteLookupException? failure;
      try {
        DiscourseApi.normalize(oversized);
      } on SiteLookupException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.term, 'that forum address');
      expect(
        failure.cause,
        const FormatException('Forum address is too long.'),
      );
      expect(failure.message, isNot(contains(secret)));
      expect('$failure ${failure.cause}', isNot(contains(secret)));
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

    test('preserves a login-only site from basic-info', () async {
      final api = DiscourseApi(
        client: discourseServing(
          basicInfo: {'title': 'Discourse Meetup', 'login_required': true},
        ),
      );

      final site = await api.lookup('meetup.discourse.org');

      expect(site.title, 'Discourse Meetup');
      expect(site.loginRequired, isTrue);
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
    test(
      'core reads its counters without claiming plugin wire fields',
      () async {
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
        expect(totals.unseenReviewables, 1);
        expect(totals.topicTrackingUnread, 12);
        expect(totals.topicTrackingNew, 7);
        // Addressed-to-you items only; unread topics are not in the rail badge.
        expect(totals.badge, 3 + 2 + 1);
      },
    );

    test('absent optional counters leave core totals at zero', () async {
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

      expect(totals.unreadPersonalMessages, 0);
      expect(totals.unseenReviewables, 0);
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

      expect(notifications.single.typeId, const NotificationTypeId(4242));
      expect(notifications.single.title, isEmpty);
      expect(notifications.single.topicId, 9);
      expect(notifications.single.data, {'topic_title': 'From some plugin'});
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
      final api = DiscourseApi(
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
      final api = DiscourseApi(
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
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'user_actions': [
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
        expect(page.rawItemCount, 2);
      },
    );
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
    test('rejects an oversized private query before transport', () async {
      var requestCount = 0;
      const secret = 'private-search-marker';
      final api = DiscourseApi(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );

      Object? failure;
      try {
        await api.searchPosts(
          siteUrl: 'https://example.com',
          term: '$secret${'x' * DiscourseApi.maximumSearchTermLength}',
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

    test('sends the current topic as core search context', () async {
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
      final api = DiscourseApi(
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

    test('loads, clears, and click-tracks core search state', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          if (request.method == 'GET') {
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
          }
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      final recent = await api.recentSearches(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );
      await api.resetRecentSearches(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );
      await api.logSearchClick(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        searchLogId: 22,
        resultId: 91,
        resultKind: SearchResultKind.topic,
        clientId: 'client',
      );

      expect(recent, ['one', 'two', 'three', 'four', 'five']);
      expect(sent.map((request) => (request.method, request.url.path)), [
        ('GET', '/u/recent-searches.json'),
        ('DELETE', '/u/recent-searches.json'),
        ('POST', '/search/click.json'),
      ]);
      expect(jsonDecode(sent.last.body), {
        'search_log_id': 22,
        'search_result_id': 91,
        'search_result_type': 'topic',
      });
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
    test('flattens a deeply nested category tree without recursion', () async {
      const depth = 2048;
      final payload = StringBuffer('{"category_list":{"categories":[');
      for (var id = 1; id <= depth; id++) {
        payload.write('{"id":$id,"name":"Category $id","subcategory_list":[');
      }
      for (var id = 1; id <= depth; id++) {
        payload.write(']}');
      }
      payload.write(']}}');

      final api = DiscourseApi(
        client: MockClient((_) async => http.Response(payload.toString(), 200)),
      );

      final categories = await api.categories(siteUrl: 'https://example.com');

      expect(categories, hasLength(depth));
      expect(categories.first.id, 1);
      expect(categories.last.id, depth);
    });

    test(
      'requests featured topics and flattens every category level in preorder',
      () async {
        final api = DiscourseApi(
          client: MockClient((request) async {
            expect(
              request.url.queryParameters['include_subcategories'],
              'true',
            );
            expect(request.url.queryParameters['include_topics'], 'true');
            expect(request.url.queryParameters.containsKey('page'), isFalse);
            return http.Response(
              jsonEncode({
                'category_list': {
                  'can_create_topic': true,
                  'categories': [
                    {
                      'id': 1,
                      'name': 'Feature',
                      'color': '0088CC',
                      'slug': 'feature',
                      'style_type': 'icon',
                      'icon': 'folder',
                      'read_restricted': true,
                      'topic_count': '12',
                      'position': 3,
                      'notification_level': 0,
                      'subcategory_ids': [2, 4],
                      'topics': [
                        {
                          'id': 101,
                          'title': 'Unread pinned topic',
                          'slug': 'unread-pinned-topic',
                          'pinned': true,
                          'last_read_post_number': 2,
                          'highest_post_number': 5,
                        },
                        {
                          'id': 'not-an-id',
                          'title': 'Malformed',
                          'slug': 'malformed',
                        },
                        {
                          'id': 0,
                          'title': 'Nonpositive',
                          'slug': 'nonpositive',
                        },
                        {
                          'id': 102,
                          'fancy_title': 'Closed &amp; archived',
                          'slug': 'closed-archived',
                          'closed': true,
                          'archived': true,
                          'last_read_post_number': 9,
                          'highest_post_number': 9,
                        },
                      ],
                      'subcategory_list': [
                        {
                          'id': 2,
                          'name': 'Ideas',
                          'color': 'AB9364',
                          'slug': 'ideas',
                          'permission': 1,
                          'minimum_required_tags': 2,
                          'style_type': 'emoji',
                          'emoji': 'bulb',
                          'subcategory_list': [
                            {
                              'id': 3,
                              'name': 'Experimental',
                              'color': '222222',
                              'slug': 'experimental',
                            },
                          ],
                        },
                        {'id': 4, 'name': 'Archive', 'color': '333333'},
                      ],
                    },
                    {'id': 5, 'name': 'Support', 'color': '444444'},
                  ],
                },
              }),
              200,
            );
          }),
        );

        final result = await api.loadCategories(siteUrl: 'https://example.com');
        final categories = result.categories;

        expect(categories.map((c) => c.id), [1, 2, 3, 4, 5]);
        expect(result.rootCategoryIds, [1, 5]);
        expect(result.canCreateTopic, isTrue);
        expect(result.postActionCatalog, isNull);
        expect(categories.first.colorValue, 0xFF0088CC);
        expect(categories.first.styleType, 'icon');
        expect(categories.first.icon, 'folder');
        expect(categories.first.readRestricted, isTrue);
        expect(categories.first.topicCount, 12);
        expect(categories.first.position, 3);
        expect(categories.first.notificationLevel, 0);
        expect(categories.first.subcategoryIds, [2, 4]);
        expect(categories.first.isMuted, isTrue);
        expect(categories.first.featuredTopics.map((topic) => topic.id), [
          101,
          102,
        ]);
        final unread = categories.first.featuredTopics.first;
        expect(unread.title, 'Unread pinned topic');
        expect(unread.slug, 'unread-pinned-topic');
        expect(unread.pinned, isTrue);
        expect(unread.closed, isFalse);
        expect(unread.archived, isFalse);
        expect(unread.firstUnreadPostNumber, 3);
        final read = categories.first.featuredTopics.last;
        expect(read.title, 'Closed & archived');
        expect(read.pinned, isFalse);
        expect(read.closed, isTrue);
        expect(read.archived, isTrue);
        expect(read.firstUnreadPostNumber, 9);
        expect(
          () => categories.first.featuredTopics.add(unread),
          throwsUnsupportedError,
        );
        expect(categories[1].canCreateTopic, isTrue);
        expect(categories[1].minimumRequiredTags, 2);
        expect(categories[1].styleType, 'emoji');
        expect(categories[1].emoji, 'bulb');
        expect(categories[2].styleType, 'square');
        expect(categories[2].icon, isNull);
        expect(categories[2].emoji, isNull);
        expect(categories[2].readRestricted, isFalse);
        expect(categories[2].topicCount, 0);
        expect(categories[2].position, isNull);
        expect(categories[2].isUncategorized, isFalse);
        expect(categories[2].notificationLevel, 1);
        expect(categories[2].isMuted, isFalse);
        expect(categories[2].featuredTopics, isEmpty);
      },
    );

    test('featured topics have first-unread semantics and value identity', () {
      const baseline = CategoryFeaturedTopic(
        id: 101,
        title: 'A topic',
        slug: 'a-topic',
        pinned: true,
        closed: true,
        archived: true,
        lastReadPostNumber: 4,
        highestPostNumber: 8,
      );
      const equal = CategoryFeaturedTopic(
        id: 101,
        title: 'A topic',
        slug: 'a-topic',
        pinned: true,
        closed: true,
        archived: true,
        lastReadPostNumber: 4,
        highestPostNumber: 8,
      );

      expect(equal, baseline);
      expect(equal.hashCode, baseline.hashCode);
      expect(baseline.firstUnreadPostNumber, 5);
      expect(
        const CategoryFeaturedTopic(
          id: 101,
          title: 'A topic',
          slug: 'a-topic',
          highestPostNumber: 8,
        ).firstUnreadPostNumber,
        1,
      );
      expect(
        const CategoryFeaturedTopic(
          id: 101,
          title: 'A topic',
          slug: 'a-topic',
        ).firstUnreadPostNumber,
        isNull,
      );
      expect(
        const CategoryFeaturedTopic(
          id: 101,
          title: 'A topic',
          slug: 'a-topic',
          archived: false,
          lastReadPostNumber: 4,
          highestPostNumber: 8,
        ),
        isNot(baseline),
      );
    });

    test('presentation fields participate in category value identity', () {
      TopicCategory category({
        String styleType = 'emoji',
        String? icon = 'folder',
        String? emoji = 'bulb',
        bool readRestricted = true,
        int topicCount = 12,
        int position = 3,
        bool isUncategorized = false,
        int notificationLevel = 0,
        List<int> subcategoryIds = const [2],
        List<CategoryFeaturedTopic> featuredTopics = const [
          CategoryFeaturedTopic(id: 101, title: 'A topic', slug: 'a-topic'),
        ],
      }) => TopicCategory(
        id: 1,
        name: 'Feature',
        color: '0088CC',
        styleType: styleType,
        icon: icon,
        emoji: emoji,
        readRestricted: readRestricted,
        topicCount: topicCount,
        position: position,
        isUncategorized: isUncategorized,
        notificationLevel: notificationLevel,
        subcategoryIds: subcategoryIds,
        featuredTopics: featuredTopics,
      );

      final baseline = category();
      final equal = category(
        featuredTopics: List.unmodifiable(const [
          CategoryFeaturedTopic(id: 101, title: 'A topic', slug: 'a-topic'),
        ]),
      );

      expect(equal, baseline);
      expect(equal.hashCode, baseline.hashCode);
      expect([
        category(styleType: 'square'),
        category(icon: 'lock'),
        category(emoji: 'sparkles'),
        category(readRestricted: false),
        category(topicCount: 13),
        category(position: 4),
        category(isUncategorized: true),
        category(notificationLevel: 1),
        category(subcategoryIds: const [3]),
        category(
          featuredTopics: const [
            CategoryFeaturedTopic(
              id: 102,
              title: 'Another topic',
              slug: 'another-topic',
            ),
          ],
        ),
      ], everyElement(isNot(baseline)));
    });

    test('presentation fields default safely when malformed', () {
      final category = TopicCategory.fromJson(const {
        'id': 1,
        'name': 'Feature',
        'style_type': false,
        'icon': ['folder'],
        'emoji': 7,
        'read_restricted': 'true',
        'topic_count': 'many',
        'position': false,
        'notification_level': false,
        'subcategory_ids': [null, false, 0, -1, 'oops'],
        'topics': [
          null,
          'topic',
          {'id': -1, 'title': 'Negative'},
          {'id': 'oops', 'title': 'Not numeric'},
        ],
      });

      expect(category.styleType, 'square');
      expect(category.icon, isNull);
      expect(category.emoji, isNull);
      expect(category.readRestricted, isFalse);
      expect(category.topicCount, 0);
      expect(category.position, isNull);
      expect(category.isUncategorized, isFalse);
      expect(category.notificationLevel, 1);
      expect(category.subcategoryIds, isEmpty);
      expect(category.isMuted, isFalse);
      expect(category.featuredTopics, isEmpty);
    });

    test('normalizes CSS shorthand category colors', () {
      expect(
        const TopicCategory(id: 1, name: 'Feature', color: '888').colorValue,
        0xFF888888,
      );
      expect(
        const TopicCategory(id: 1, name: 'Feature', color: '#aBc').colorValue,
        0xFFAABBCC,
      );
      expect(
        const TopicCategory(id: 1, name: 'Feature', color: 'nope').colorValue,
        0xFF888888,
      );
    });

    test(
      'supplements page one without replacing endpoint category data',
      () async {
        final requested = <String>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            requested.add(request.url.path);
            expect(request.headers['User-Api-Key'], 'key');
            expect(request.headers['User-Api-Client-Id'], 'client');
            if (request.url.path == '/categories.json') {
              return http.Response(
                jsonEncode({
                  'category_list': {
                    'categories': [
                      {
                        'id': 1,
                        'name': 'Visible from page',
                        'color': '111111',
                        'topics': [
                          {
                            'id': 11,
                            'title': 'Featured from page',
                            'slug': 'featured-from-page',
                            'highest_post_number': 1,
                          },
                        ],
                      },
                    ],
                  },
                }),
                200,
              );
            }
            expect(request.url.path, '/site.json');
            return http.Response(
              jsonEncode({
                'post_action_types': [
                  {
                    'id': 3,
                    'name_key': 'off_topic',
                    'name': 'Off-Topic',
                    'description': '<p>Not relevant</p>',
                    'is_flag': true,
                    'enabled': true,
                    'applies_to': ['Post'],
                    'system': true,
                  },
                  {
                    'id': 2,
                    'name_key': 'like',
                    'name': 'Like',
                    'is_flag': false,
                  },
                ],
                'categories': [
                  {'id': 1, 'name': 'Site duplicate', 'color': 'AAAAAA'},
                  {'id': 8, 'name': 'Parent', 'color': '222222'},
                  {
                    'id': 9,
                    'name': 'Preferred off page',
                    'color': '333333',
                    'parent_category_id': 8,
                  },
                ],
              }),
              200,
            );
          }),
        );

        final result = await api.loadCategories(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          clientId: 'client',
        );

        expect(requested, ['/categories.json', '/site.json']);
        expect(result.categories.map((category) => category.id), [1, 8, 9]);
        expect(result.rootCategoryIds, [1]);
        expect(result.categories.first.name, 'Visible from page');
        expect(result.categories.first.color, '111111');
        expect(result.categories.first.featuredTopics.single.id, 11);
        expect(result.postActionCatalog?.postFlags.single.id, 3);
      },
    );

    test(
      'dispatches both authenticated category reads before yielding',
      () async {
        final releaseCategories = Completer<void>();
        final siteStarted = Completer<void>();
        final api = DiscourseApi(
          client: MockClient((request) async {
            if (request.url.path == '/categories.json') {
              await releaseCategories.future;
              return http.Response(
                jsonEncode({
                  'category_list': {'categories': <Object?>[]},
                }),
                200,
              );
            }
            siteStarted.complete();
            return http.Response(jsonEncode({'categories': <Object?>[]}), 200);
          }),
        );

        final loading = api.loadCategories(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          clientId: 'client',
        );

        await siteStarted.future.timeout(const Duration(seconds: 1));
        releaseCategories.complete();
        final result = await loading;
        expect(result.complete, isTrue);
        expect(result.postActionCatalog, isNotNull);
        expect(result.postActionCatalog?.postFlags, isEmpty);
      },
    );

    test('finds exact category ids outside the paginated list', () async {
      final requested = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested.add(request.url);
          expect(request.headers['User-Api-Key'], 'key');
          return http.Response(
            jsonEncode({
              'categories': [
                {
                  'id': 6,
                  'name': 'Support docs',
                  'color': '00AEEF',
                  'parent_category_id': 5,
                  'permission': 1,
                },
              ],
            }),
            200,
          );
        }),
      );

      final categories = await api.findCategories(
        siteUrl: 'https://example.com',
        ids: const [6, 6],
        apiKey: 'key',
      );

      expect(requested.single.path, '/categories/find.json');
      expect(requested.single.queryParametersAll['ids[]'], ['6']);
      expect(categories.single.id, 6);
      expect(categories.single.parentCategoryId, 5);
      expect(categories.single.canCreateTopic, isTrue);
    });

    test('requests page two without reading the site supplement', () async {
      final requested = <Uri>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested.add(request.url);
          expect(request.url.path, '/categories.json');
          return http.Response(
            jsonEncode({
              'category_list': {
                'can_create_topic': false,
                'categories': [
                  {'id': 21, 'name': 'Later root', 'color': '111111'},
                  {
                    'id': 22,
                    'name': 'Later child',
                    'color': '222222',
                    'parent_category_id': 21,
                  },
                ],
              },
            }),
            200,
          );
        }),
      );

      final result = await api.loadCategories(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        page: 2,
      );

      expect(requested, hasLength(1));
      expect(requested.single.queryParameters, {
        'include_subcategories': 'true',
        'include_topics': 'true',
        'page': '2',
      });
      expect(result.categories.map((category) => category.id), [21, 22]);
      expect(result.rootCategoryIds, [21]);
      expect(result.canCreateTopic, isFalse);
      expect(result.complete, isTrue);
    });

    test('marks the Uncategorized id supplied by site.json', () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          if (request.url.path == '/categories.json') {
            return http.Response(
              jsonEncode({
                'category_list': {
                  'categories': [
                    {'id': 1, 'name': 'Support', 'color': '111111'},
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'uncategorized_category_id': 9,
              'categories': [
                {'id': 9, 'name': 'Uncategorized', 'color': '888888'},
              ],
            }),
            200,
          );
        }),
      );

      final categories = await api.categories(
        siteUrl: 'https://example.com',
        apiKey: 'key',
      );

      expect(
        categories.singleWhere((category) => category.id == 9).isUncategorized,
        isTrue,
      );
    });

    test('keeps base categories retryable when the supplement fails', () async {
      final api = DiscourseApi(
        client: MockClient((request) async {
          if (request.url.path == '/site.json') {
            return http.Response('', 503);
          }
          return http.Response(
            jsonEncode({
              'category_list': {
                'categories': [
                  {'id': 1, 'name': 'Support', 'color': '111111'},
                ],
              },
            }),
            200,
          );
        }),
      );

      final result = await api.loadCategories(
        siteUrl: 'https://example.com',
        apiKey: 'key',
      );

      expect(result.complete, isFalse);
      expect(result.categories.map((category) => category.id), [1]);
      expect(result.postActionCatalog, isNull);
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
              'tags_filter_regexp':
                  r'''[\/\?#\[\]@!\$&'\(\)\*\+,;=%\\`^\s|\{\}"<>]+''',
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
      expect(capabilities.canCreateTagNamed('mobile'), isTrue);
      expect(capabilities.canCreateTagNamed('mobile tag'), isFalse);
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
      // Core validates `limit` against `max_tag_search_results` and answers
      // 400 above it, so an unsupplied limit has to be core's own default —
      // 5 — and not this client's autocomplete ceiling.
      expect(sent.queryParameters['limit'], '5');
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
        models: installedPlugins.models,
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
      final reactions = config.plugins.get(reactionsSettingsDataKey)!;

      expect(paths, ['/site/settings.json']);
      expect(config.emojiSet, 'apple');
      expect(reactions.mainReaction, 'heart');
      expect(reactions.offeredReactions, ['heart', '+1', 'clap']);
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
    test(
      'asks with every ref and type and reads plugin-owned results',
      () async {
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
                'room': [
                  {
                    'type': 'room',
                    'ref': 'lounge',
                    'slug': 'lounge',
                    'text': 'Lounge',
                    'id': 9,
                    'relative_url': '/resenha/r/lounge',
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
        expect(found.last.relativeUrl, '/resenha/r/lounge');
        expect(found.last.icon, 'microphone-lines');
      },
    );

    test('rejects an invalid type order before transport', () async {
      var called = false;
      final api = DiscourseApi(
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

  group('emoji catalog', () {
    test(
      'preserves ordered groups, tonability, and resolved artwork',
      () async {
        final paths = <String>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(
              jsonEncode({
                'smileys_&_emotion': [
                  {
                    'name': 'smile',
                    'url': '/images/emoji/twitter/smile.png?v=2',
                    'tonable': true,
                    'ignored': 'future field',
                  },
                  {'name': 'grin', 'url': 'https://cdn.example.com/grin.png'},
                ],
                'default': [
                  {'name': 'shipit', 'url': '//cdn.example.com/shipit.png'},
                  // Malformed rows are dropped rather than read loosely.
                  {'name': 'no_url'},
                ],
                'opaque plugin/group': <Object?>[],
                'not_a_group': 'nonsense',
              }),
              200,
            );
          }),
        );

        final catalog = await api.emojiCatalog(siteUrl: 'https://example.com');

        expect(paths, ['/emojis.json']);
        expect(catalog.groups.map((group) => group.id), [
          'smileys_&_emotion',
          'default',
          'opaque plugin/group',
        ]);
        expect(catalog.all.map((emoji) => emoji.name), [
          'smile',
          'grin',
          'shipit',
        ]);
        // Site-relative urls are resolved; an absolute one is left as the site
        // wrote it, CDN and all.
        expect(
          catalog.all.first.url,
          'https://example.com/images/emoji/twitter/smile.png?v=2',
        );
        expect(catalog.all.first.tonable, isTrue);
        expect(catalog.all[1].url, 'https://cdn.example.com/grin.png');
        expect(catalog.all[2].url, 'https://cdn.example.com/shipit.png');
      },
    );

    test('an answer it cannot read is a failure, not an empty list', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      await expectLater(
        api.emojiCatalog(siteUrl: 'https://example.com'),
        throwsA(isA<SiteLookupException>()),
      );
    });

    test('reads and sanitizes localized search aliases', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'heart': ['love', ' amour ', 'love', 4, ''],
              'wave': <String>[],
              'malformed': 'not a list',
            }),
            200,
          ),
        ),
      );

      final aliases = await api.emojiSearchAliases(
        siteUrl: 'https://example.com',
      );

      expect(aliases, {
        'heart': ['love', 'amour'],
        'wave': <String>[],
      });
    });

    test('protocol-relative artwork follows the forum origin scheme', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'default': [
                {'name': 'shipit', 'url': '//cdn.example.com/shipit.png'},
              ],
            }),
            200,
          ),
        ),
      );

      final catalog = await api.emojiCatalog(siteUrl: 'http://127.0.0.1:3000');

      expect(catalog.all.single.url, 'http://cdn.example.com/shipit.png');
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
        models: DiscourseModelCodec(
          extensions: pluginRegistry,
          recommendationSources: pluginRegistry,
          icons: pluginRegistry,
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode(reacted()), 200);
        }),
      );

      final post = await ReactionsApiClient(api, api.models).toggleReaction(
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

      await ReactionsApiClient(api, api.models).toggleReaction(
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
        ReactionsApiClient(api, api.models).toggleReaction(
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
        ReactionsApiClient(api, api.models).toggleReaction(
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

      final reactors = await ReactionsApiClient(
        api,
        api.models,
      ).postReactors(siteUrl: 'https://example.com', postId: 1);

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

      final reactors = await ReactionsApiClient(
        api,
        api.models,
      ).postReactors(siteUrl: 'https://example.com', postId: 1, reaction: '+1');

      expect(seen.queryParameters['reaction_value'], '+1');
      // Kept on the record, so the filtered list does not overwrite the whole
      // one in the store.
      expect(reactors.filter, '+1');
    });
  });

  group('chatDirectMessages', () {
    test('searches core Chat’s permission-filtered DM targets', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'identifier': 'u-2',
                  'type': 'user',
                  'match_quality': 1,
                  'model': {
                    'id': 2,
                    'username': 'sam',
                    'name': 'Sam',
                    'avatar_template':
                        '/user_avatar/example.com/sam/{size}/1.png',
                    'has_chat_enabled': true,
                  },
                },
              ],
              'groups': const <Object?>[],
              'direct_message_channels': [
                {
                  'identifier': 'c-55',
                  'type': 'channel',
                  'match_quality': 2,
                  'model': {
                    'id': 55,
                    'title': 'Sam and Kris',
                    'chatable_type': 'DirectMessage',
                    'chatable': {'group': true, 'users': const <Object?>[]},
                  },
                },
              ],
              'category_channels': const <Object?>[],
            }),
            200,
          );
        }),
      );

      final results = await ChatApiClient(api).searchChatDirectMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        term: 'sam',
      );

      expect(seen.url.path, '/chat/api/chatables');
      expect(seen.url.queryParameters, {
        'term': 'sam',
        'include_users': 'true',
        'include_groups': 'false',
        'include_category_channels': 'false',
        'include_direct_message_channels': 'true',
      });
      expect(results.items, hasLength(2));
      expect(results.items.first, isA<ChatDirectMessageUser>());
      expect((results.items.first as ChatDirectMessageUser).username, 'sam');
      expect((results.items.last as ChatDirectMessageChannel).channel.id, 55);
    });

    test('upserts a DM channel for the user-card Chat action', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 55,
                'title': 'sam',
                'chatable_type': 'DirectMessage',
                'chatable': {
                  'group': false,
                  'users': [
                    {'id': 2, 'username': 'sam'},
                  ],
                },
              },
            }),
            200,
          );
        }),
      );

      final channel = await ChatApiClient(api).upsertChatDirectMessageChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        username: 'sam',
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/chat/api/direct-message-channels.json');
      expect(jsonDecode(seen.body), {
        'target_usernames': ['sam'],
        'upsert': true,
      });
      expect(channel.id, 55);
      expect(channel.isDirectMessage, isTrue);
    });
  });

  group('chatChannels', () {
    /// The two-bucket envelope `Chat::ChannelIndexSerializer` writes.
    MockClient serving(void Function(http.Request) record) => MockClient((
      request,
    ) async {
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
              'current_user_membership': {'following': true, 'starred': true},
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

        await ChatApiClient(api).chatChannels(siteUrl: 'https://example.com');

        expect(seen.path, '/chat/api/me/channels.json');
        // The route takes no parameters at all — the reader's own memberships are
        // the whole of the query.
        expect(seen.queryParameters, isEmpty);
      },
    );

    test('reads the public and the direct lists apart', () async {
      final api = DiscourseApi(client: serving((_) {}));

      final channels = await ChatApiClient(
        api,
      ).chatChannels(siteUrl: 'https://example.com');

      expect(channels.public.single.title, 'Bugs');
      expect(channels.direct.single.isDirectMessage, isTrue);
      expect(channels.public.single.tracking.unreadCount, 3);
      expect(channels.public.single.membership.starred, isTrue);
    });

    test(
      'sends the user api key, an anonymous reader having no channels',
      () async {
        late Map<String, String> headers;
        final api = DiscourseApi(client: serving((r) => headers = r.headers));

        await ChatApiClient(api).chatChannels(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          clientId: 'client',
        );

        expect(headers['User-Api-Key'], 'key');
        expect(headers['User-Api-Client-Id'], 'client');
      },
    );

    test('updates the current channel membership starred setting', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).updateChatChannelStarred(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        starred: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9/memberships/me.json');
      expect(jsonDecode(sent.body), {'starred': true});
    });

    test('updates independent channel notification settings', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'membership': {
                'following': true,
                'muted': true,
                'notification_level': 'always',
                'starred': true,
                'last_read_message_id': 44,
              },
            }),
            200,
          );
        }),
      );

      final membership = await ChatApiClient(api)
          .updateChatChannelNotifications(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 9,
            muted: true,
            notificationLevel: ChatChannelNotificationLevel.always,
          );

      expect(sent.method, 'PUT');
      expect(
        sent.url.path,
        '/chat/api/channels/9/notifications-settings/me.json',
      );
      expect(jsonDecode(sent.body), {
        'notifications_settings': {
          'muted': true,
          'notification_level': 'always',
        },
      });
      expect(membership.muted, isTrue);
      expect(membership.notificationLevel, ChatChannelNotificationLevel.always);
      expect(membership.starred, isTrue);
      expect(membership.lastReadMessageId, 44);
    });

    test('sends only the channel notification field being changed', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'membership': {
                'following': true,
                'muted': false,
                'notification_level': 'mention',
              },
            }),
            200,
          );
        }),
      );

      await ChatApiClient(api).updateChatChannelNotifications(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        muted: false,
      );

      expect(jsonDecode(sent.body), {
        'notifications_settings': {'muted': false},
      });
    });

    test('lists a filtered page of channel members', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'memberships': [
                {
                  'user': {
                    'id': 2,
                    'username': 'sam',
                    'name': 'Sam',
                    'avatar_template': '/user_avatar/sam/{size}.png',
                  },
                },
                {
                  'user': {
                    'id': 3,
                    'username': 'samantha',
                    'avatar_template': '/user_avatar/samantha/{size}.png',
                  },
                },
                {'user': null},
              ],
              'meta': {'total_rows': 42, 'load_more_url': '/next'},
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatChannelMembers(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        username: ' sam ',
        offset: 20,
        limit: 2,
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/chat/api/channels/9/memberships');
      expect(sent.url.queryParameters, {
        'offset': '20',
        'limit': '2',
        'username': 'sam',
      });
      expect(page.members.map((member) => member.username), [
        'sam',
        'samantha',
      ]);
      expect(page.members.first.avatarUrl, contains('/user_avatar/sam/90.png'));
      expect(page.totalRows, 42);
      expect(page.canLoadMore, isTrue);
    });

    test('browses a filtered page of public channels', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channels': [
                {
                  'id': 9,
                  'title': 'Bugs',
                  'slug': 'bugs',
                  'chatable_type': 'Category',
                  'chatable': {'color': '0088CC'},
                  'memberships_count': 42,
                  'meta': {'can_join_chat_channel': true},
                },
              ],
              'meta': {'load_more_url': '/chat/api/channels?offset=25'},
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).browseChatChannels(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        filter: ' bugs ',
        status: ChatChannelBrowseStatus.open,
        offset: 25,
        limit: 1,
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/chat/api/channels');
      expect(sent.url.queryParameters, {
        'status': 'open',
        'offset': '25',
        'limit': '1',
        'filter': 'bugs',
      });
      expect(page.channels.single.title, 'Bugs');
      expect(page.channels.single.membershipsCount, 42);
      expect(page.channels.single.canJoin, isTrue);
      expect(page.hasMore, isTrue);
    });

    test('joins and reversibly unfollows channel memberships', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(
            jsonEncode({
              'membership': {
                'following': request.method == 'POST',
                'notification_level': 'mention',
              },
            }),
            200,
          );
        }),
      );

      final joined = await ChatApiClient(api).followChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );
      final unfollowed = await ChatApiClient(api).unfollowChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );

      expect(sent[0].method, 'POST');
      expect(sent[0].url.path, '/chat/api/channels/9/memberships/me.json');
      expect(jsonDecode(sent[0].body), isEmpty);
      expect(joined.following, isTrue);
      expect(sent[1].method, 'DELETE');
      expect(
        sent[1].url.path,
        '/chat/api/channels/9/memberships/me/follows.json',
      );
      expect(jsonDecode(sent[1].body), isEmpty);
      expect(unfollowed.following, isFalse);
    });

    test('edits a chat message and retains its uploads', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).editChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        message: '**corrected**',
        uploadIds: const [31, 32],
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9/messages/12.json');
      expect(jsonDecode(sent.body), {
        'message': '**corrected**',
        'upload_ids': [31, 32],
      });
    });

    test('deletes and restores a chat message on core routes', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).deleteChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
      );
      await ChatApiClient(api).restoreChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
      );

      expect(sent.map((request) => request.method), ['DELETE', 'PUT']);
      expect(sent.map((request) => request.url.path), [
        '/chat/api/channels/9/messages/12.json',
        '/chat/api/channels/9/messages/12/restore.json',
      ]);
      expect(sent.map((request) => jsonDecode(request.body)), [
        <String, dynamic>{},
        <String, dynamic>{},
      ]);
    });

    test('bulk-deletes selected chat messages on the core route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).deleteChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageIds: const [12, 14],
      );

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/chat/api/channels/9/messages.json');
      expect(jsonDecode(sent.body), {
        'message_ids': [12, 14],
      });
    });

    test('moves selected messages between public channels', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'success': 'OK',
              'destination_channel_id': 10,
              'destination_channel_title': 'Support',
              'first_moved_message_id': 101,
            }),
            200,
          );
        }),
      );

      final moved = await ChatApiClient(api).moveChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        destinationChannelId: 10,
        messageIds: const [12, 14],
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/chat/api/channels/9/messages/moves.json');
      expect(jsonDecode(sent.body), {
        'move': {
          'message_ids': [12, 14],
          'destination_channel_id': 10,
        },
      });
      expect(moved.destinationChannelId, 10);
      expect(moved.firstMovedMessageId, 101);
    });

    test('queues a chat message HTML rebuild on the core route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).rebakeChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/9/12/rebake.json');
      expect(jsonDecode(sent.body), <String, dynamic>{});
    });

    test('generates canonical Markdown for selected chat messages', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({'markdown': '[chat channel="Bugs"]\nHello\n[/chat]'}),
            200,
          );
        }),
      );

      final markdown = await ChatApiClient(api).generateChatQuote(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageIds: const [12, 14],
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/chat/9/quote.json');
      expect(jsonDecode(sent.body), {
        'message_ids': [12, 14],
      });
      expect(markdown, '[chat channel="Bugs"]\nHello\n[/chat]');
    });

    test('pins and unpins a chat message with core route methods', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).updateChatMessagePinned(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        pinned: true,
      );
      await ChatApiClient(api).updateChatMessagePinned(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        pinned: false,
      );

      expect(sent.map((request) => request.method), ['POST', 'DELETE']);
      expect(sent.map((request) => request.url.path), [
        '/chat/api/channels/9/messages/12/pin.json',
        '/chat/api/channels/9/messages/12/pin.json',
      ]);
      expect(sent.map((request) => jsonDecode(request.body)), [
        <String, dynamic>{},
        <String, dynamic>{},
      ]);
    });

    test('loads pinned messages and marks their panel read', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'pinned_messages': [
                  {
                    'id': 91,
                    'chat_message_id': 12,
                    'message': {
                      'id': 12,
                      'chat_channel_id': 9,
                      'cooked': '<p>Pin</p>',
                      'user': {'id': 2, 'username': 'sam'},
                    },
                    'pinned_by': {'id': 7, 'username': 'reader'},
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      final snapshot = await ChatApiClient(api).chatPinnedMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );
      await ChatApiClient(api).markChatPinsRead(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );

      expect(snapshot.pins.single.messageId, 12);
      expect(sent.map((request) => request.method), ['GET', 'PUT']);
      expect(sent.map((request) => request.url.path), [
        '/chat/api/channels/9/pins.json',
        '/chat/api/channels/9/pins/read.json',
      ]);
      expect(jsonDecode(sent.last.body), <String, dynamic>{});
    });

    test('flags a chat message with its server-advertised reason', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).flagChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        flagTypeId: 7,
        message: 'Please review this message.',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/chat/api/channels/9/messages/12/flags.json');
      expect(jsonDecode(sent.body), {
        'flag_type_id': 7,
        'message': 'Please review this message.',
      });
    });

    test('reports a site that refuses the way every other read does', () async {
      // 403 is what a site with chat off, or a reader who may not use it, gets.
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('{}', 403)),
      );

      await expectLater(
        ChatApiClient(api).chatChannels(siteUrl: 'https://example.com'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('chatSearch', () {
    Map<String, dynamic> message(int id) => {
      'id': id,
      'chat_channel_id': 9,
      'cooked': '<p>needle</p>',
      'excerpt': 'needle',
      'created_at': '2026-08-25T10:00:00Z',
      'user': {'id': 2, 'username': 'sam'},
      'channel': {
        'id': 9,
        'title': 'Bugs',
        'chatable_type': 'Category',
        'chatable': {'color': '0088CC'},
      },
    };

    test('sends global search paging and sorting parameters', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'messages': [message(40)],
              'meta': {'has_more': true, 'limit': 20, 'offset': 20},
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).searchChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        query: '  needle  ',
        sort: ChatSearchSort.latest,
        offset: 20,
      );

      expect(seen.url.path, '/chat/api/search.json');
      expect(seen.url.queryParameters, {
        'query': 'needle',
        'sort': 'latest',
        'offset': '20',
        'limit': '20',
      });
      expect(seen.headers['User-Api-Key'], 'key');
      expect(page.hits.single.id, 40);
      expect(page.hasMore, isTrue);
    });

    test('scopes channel search and excludes thread replies', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({'messages': const <Object?>[]}),
            200,
          );
        }),
      );

      await ChatApiClient(api).searchChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        query: 'needle',
        channelId: 9,
        sort: ChatSearchSort.latest,
        excludeThreads: true,
      );

      expect(seen.queryParameters['channel_id'], '9');
      expect(seen.queryParameters['exclude_threads'], 'true');
    });

    test('rejects invalid search values before sending', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      final calls = <Future<void> Function()>[
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: ' ',
        ),
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: 'needle',
          channelId: 0,
        ),
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: 'needle',
          offset: -1,
        ),
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: 'needle',
          limit: 41,
        ),
      ];
      for (final call in calls) {
        await expectLater(call(), throwsArgumentError);
      }
      expect(requests, 0);
    });

    test('loads one full channel for result navigation', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      final channel = await ChatApiClient(api).chatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );

      expect(seen.path, '/chat/api/channels/9.json');
      expect(channel.membership.following, isTrue);
    });

    test('updates channel metadata in core’s channel envelope', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bug reports',
                'slug': 'bug-reports',
                'description': 'A better description.',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      final updated = await ChatApiClient(api).updateChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        name: '  Bug reports  ',
        slug: '  bug-reports  ',
        description: 'A better description.',
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9.json');
      expect(jsonDecode(sent.body), {
        'channel': {
          'name': 'Bug reports',
          'slug': 'bug-reports',
          'description': 'A better description.',
        },
      });
      expect(updated.title, 'Bug reports');
      expect(updated.description, 'A better description.');
    });

    test('sends an empty description so core removes it', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      await ChatApiClient(api).updateChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        description: '',
      );

      expect(jsonDecode(sent.body), {
        'channel': {'description': ''},
      });
    });

    test('toggles channel threading through the same settings route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'threading_enabled': true,
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      final updated = await ChatApiClient(api).updateChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        threadingEnabled: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9.json');
      expect(jsonDecode(sent.body), {
        'channel': {'threading_enabled': true},
      });
      expect(updated.threadingEnabled, isTrue);
    });

    test('closes a channel through core’s dedicated status route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'status': 'closed',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
              },
            }),
            200,
          );
        }),
      );

      final updated = await ChatApiClient(api).updateChatChannelStatus(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        status: ChatChannelStatus.closed,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9/status.json');
      expect(jsonDecode(sent.body), {'status': 'closed'});
      expect(updated.status, ChatChannelStatus.closed);
    });

    test('rejects archive states from the open-close route', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        ChatApiClient(api).updateChatChannelStatus(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          channelId: 9,
          status: ChatChannelStatus.archived,
        ),
        throwsArgumentError,
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

      final page = await ChatApiClient(
        api,
      ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

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
        () => ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 1,
          after: 2,
        ),
        () => ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 1,
          fromLastRead: true,
        ),
        () => ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 0),
        () => ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 9, before: 0),
        () => ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          pageSize: 0,
        ),
        () => ChatApiClient(api).chatMessages(
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

      await ChatApiClient(
        api,
      ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

      expect(seen.queryParameters, isNot(contains('target_message_id')));
      expect(seen.queryParameters, isNot(contains('direction')));
    });

    test(
      'asks for the page before a message it holds, that message excluded',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 40,
        );

        expect(seen.queryParameters['direction'], 'past');
        expect(seen.queryParameters['target_message_id'], '40');
      },
    );

    test('asks for a directionless page around an explicit message', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'messages': <Object?>[],
              'meta': {
                'target_message_id': 40,
                'can_load_more_past': true,
                'can_load_more_future': true,
              },
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatMessages(
        siteUrl: 'https://example.com',
        channelId: 9,
        targetMessageId: 40,
        pageSize: 20,
      );

      expect(seen.queryParameters['target_message_id'], '40');
      expect(seen.queryParameters['page_size'], '20');
      expect(seen.queryParameters, isNot(contains('direction')));
      expect(page.targetMessageId, 40);
    });

    test(
      'never asks to fetch from last read, there being no way to page forward',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

        expect(seen.queryParameters, isNot(contains('fetch_from_last_read')));
      },
    );

    test(
      'sends the page size the site caps at, so the code names the real one',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await ChatApiClient(api).chatMessages(
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

        final page = await ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

        expect(page.canLoadMorePast, isFalse);
      },
    );

    test('reads a channel that says there is more behind it', () async {
      final api = DiscourseApi(client: serving((_) {}, canLoadMorePast: true));

      final page = await ChatApiClient(
        api,
      ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

      expect(page.canLoadMorePast, isTrue);
    });
  });

  group('chatThreadMessages', () {
    test('requests an explicit target and bounded page size', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'messages': <Object?>[],
              'meta': {
                'target_message_id': 44,
                'can_load_more_past': true,
                'can_load_more_future': true,
              },
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatThreadMessages(
        siteUrl: 'https://example.com',
        channelId: 9,
        threadId: 22,
        targetMessageId: 44,
        pageSize: 20,
      );

      expect(seen.path, '/chat/api/channels/9/threads/22/messages.json');
      expect(seen.queryParameters['target_message_id'], '44');
      expect(seen.queryParameters['page_size'], '20');
      expect(seen.queryParameters, isNot(contains('direction')));
      expect(page.targetMessageId, 44);
    });

    test('rejects invalid identities and direction before transport', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );
      final invalidCalls = <Future<void> Function()>[
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 0,
          threadId: 2,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 0,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          before: 3,
          after: 4,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          after: -1,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          targetMessageId: 3,
          before: 4,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          pageSize: 51,
        ),
      ];

      for (final call in invalidCalls) {
        await expectLater(call(), throwsArgumentError);
      }
      expect(requests, 0);
    });
  });

  group('chat thread detail and settings', () {
    Map<String, dynamic> serializedThread({bool membership = true}) => {
      'id': 22,
      'channel_id': 9,
      'status': 'open',
      'reply_count': 4,
      'last_message_id': 108,
      'force': false,
      'meta': {
        'message_bus_last_ids': {'thread_message_bus_last_id': 456},
      },
      if (membership)
        'current_user_membership': {
          'thread_id': 22,
          'notification_level': 2,
          'last_read_message_id': 105,
          'thread_title_prompt_seen': false,
        },
      'original_message': {
        'id': 100,
        'chat_channel_id': 9,
        'message': 'Deploy?',
        'cooked': '<p>Deploy?</p>',
        'excerpt': 'Deploy?',
        'user': {'id': 2, 'username': 'sam'},
      },
      'preview': {
        'last_reply_id': 108,
        'last_reply_user': {'id': 3, 'username': 'lee'},
        'participant_count': 2,
        'participant_users': [
          {'id': 2, 'username': 'sam'},
          {'id': 3, 'username': 'lee'},
        ],
      },
    };

    test('fetches rooted thread detail', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'thread': serializedThread()}), 200);
        }),
      );

      final thread = await ChatApiClient(api).chatThread(
        siteUrl: 'https://example.com',
        channelId: 9,
        threadId: 22,
        apiKey: 'key',
      );

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/api/channels/9/threads/22.json');
      expect(thread.messageBusLastId, 456);
      expect(thread.membership?.lastReadMessageId, 105);
      expect(thread.originalMessage?.id, 100);
      expect(thread.preview?.lastReplyId, 108);
    });

    test('fetches one account thread page with core pagination', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'meta': {
                'load_more_url': '/chat/api/me/threads?limit=10&offset=20',
              },
              'tracking': {
                '22': {'unread_count': 2},
              },
              'threads': [
                {
                  ...serializedThread(),
                  'channel': {
                    'id': 9,
                    'title': 'Support',
                    'chatable_type': 'Category',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(
        api,
      ).chatThreads(siteUrl: 'https://example.com', apiKey: 'key', offset: 10);

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/api/me/threads.json');
      expect(seen.url.queryParameters, {'limit': '10', 'offset': '10'});
      expect(page.threads.single.tracking.unreadCount, 2);
      expect(page.channels.single.title, 'Support');
      expect(page.hasMore, isTrue);
    });

    test('fetches one channel thread page with core pagination', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'meta': {
                'load_more_url':
                    '/chat/api/channels/9/threads?limit=10&offset=20',
              },
              'tracking': {
                '22': {'watched_threads_unread_count': 1},
              },
              'threads': [serializedThread()],
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatChannelThreads(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        offset: 10,
      );

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/api/channels/9/threads.json');
      expect(seen.url.queryParameters, {'limit': '10', 'offset': '10'});
      expect(page.threads.single.tracking.watchedThreadsUnreadCount, 1);
      expect(page.hasMore, isTrue);
    });

    test('creates an unrooted thread from an original message', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode(serializedThread(membership: false)),
            200,
          );
        }),
      );

      final thread = await ChatApiClient(api).createChatThread(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        originalMessageId: 100,
        title: 'Deploy plan',
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/chat/api/channels/9/threads.json');
      expect(jsonDecode(seen.body), {
        'original_message_id': 100,
        'title': 'Deploy plan',
      });
      expect(thread.id, 22);
      expect(thread.membership, isNull);
    });

    test('updates and returns the current thread membership', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'membership': {
                'thread_id': 22,
                'notification_level': 3,
                'last_read_message_id': 105,
                'thread_title_prompt_seen': false,
              },
            }),
            200,
          );
        }),
      );

      final membership = await ChatApiClient(api)
          .updateChatThreadNotificationLevel(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 9,
            threadId: 22,
            notificationLevel: ChatThreadNotificationLevel.watching,
          );

      expect(seen.method, 'PUT');
      expect(
        seen.url.path,
        '/chat/api/channels/9/threads/22/notifications-settings/me.json',
      );
      expect(jsonDecode(seen.body), {'notification_level': 3});
      expect(
        membership.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
    });

    test('updates a thread title through the core thread route', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).updateChatThreadTitle(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        threadId: 22,
        title: 'Deploy plan',
      );

      expect(seen.method, 'PUT');
      expect(seen.url.path, '/chat/api/channels/9/threads/22.json');
      expect(jsonDecode(seen.body), {'title': 'Deploy plan'});
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

      await ChatApiClient(api).markChatChannelRead(
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
        ChatApiClient(api).markChatChannelRead(
          siteUrl: 'https://example.com',
          apiKey: 'the-key',
          channelId: 9,
          messageId: 44,
        ),
        throwsA(isA<WriteException>()),
      );
    });
  });

  group('setChatMessageReaction', () {
    test('puts the explicit add or remove action on the chat route', () async {
      final requests = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).setChatMessageReaction(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
        emoji: '+1',
        action: ChatReactionAction.add,
      );
      await ChatApiClient(api).setChatMessageReaction(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
        emoji: '+1',
        action: ChatReactionAction.remove,
      );

      expect(requests.map((request) => request.method), everyElement('PUT'));
      expect(
        requests.map((request) => request.url.path),
        everyElement('/chat/9/react/44.json'),
      );
      expect(jsonDecode(requests.first.body), {
        'emoji': '+1',
        'react_action': 'add',
      });
      expect(jsonDecode(requests.last.body), {
        'emoji': '+1',
        'react_action': 'remove',
      });
    });

    test('rejects invalid identities and emoji before transport', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      Future<void> react(int channelId, int messageId, String emoji) =>
          ChatApiClient(api).setChatMessageReaction(
            siteUrl: 'https://example.com',
            apiKey: 'the-key',
            channelId: channelId,
            messageId: messageId,
            emoji: emoji,
            action: ChatReactionAction.add,
          );

      await expectLater(react(0, 44, 'heart'), throwsArgumentError);
      await expectLater(react(9, 0, 'heart'), throwsArgumentError);
      await expectLater(react(9, 44, ''), throwsArgumentError);
      expect(requests, 0);
    });

    test('maps a server refusal to the shared write failure', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': ['You cannot react right now.'],
            }),
            403,
          ),
        ),
      );

      await expectLater(
        ChatApiClient(api).setChatMessageReaction(
          siteUrl: 'https://example.com',
          apiKey: 'the-key',
          channelId: 9,
          messageId: 44,
          emoji: 'heart',
          action: ChatReactionAction.add,
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.message,
            'message',
            contains('cannot react'),
          ),
        ),
      );
    });
  });

  group('chatMessageReactors', () {
    test('asks chat for one emoji and reads its users', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'id': 3,
                  'username': 'sam',
                  'name': 'Sam Saffron',
                  'reaction': 'clap',
                },
              ],
              'total_rows': 2,
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatMessageReactors(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
        reaction: '+1',
      );

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/9/44/reactions-users.json');
      expect(seen.url.queryParameters, {
        'page': '0',
        'limit': '${ChatMessageReactors.maximumPageSize}',
        'emoji': '+1',
      });
      expect(page.channelId, 9);
      expect(page.messageId, 44);
      expect(page.filter, '+1');
      expect(page.total, 2);
      expect(page.reactors.single.displayName, 'Sam Saffron');
    });

    test('rejects invalid identities, filters and page sizes', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      Future<void> load({
        int channelId = 9,
        int messageId = 44,
        String? reaction,
        int limit = ChatMessageReactors.maximumPageSize,
      }) async {
        await ChatApiClient(api).chatMessageReactors(
          siteUrl: 'https://example.com',
          apiKey: 'the-key',
          channelId: channelId,
          messageId: messageId,
          reaction: reaction,
          limit: limit,
        );
      }

      await expectLater(load(channelId: 0), throwsArgumentError);
      await expectLater(load(messageId: 0), throwsArgumentError);
      await expectLater(load(reaction: ''), throwsArgumentError);
      await expectLater(load(limit: 0), throwsRangeError);
      await expectLater(
        load(limit: ChatMessageReactors.maximumPageSize + 1),
        throwsRangeError,
      );
      expect(requests, 0);
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

    test('reads the topic by its immutable id', () async {
      final paths = <String>[];
      final topic = await DiscourseApi(
        client: serving(paths),
      ).topic(siteUrl: 'https://example.com', slug: 'a-real-topic', id: 12);

      expect(paths, ['/t/12.json']);
      expect(topic.detail.title, 'A real topic');
    });

    test('does not send a stale slug that Discourse would redirect', () async {
      final requested = <Uri>[];
      final topic =
          await DiscourseApi(
            client: MockClient((request) async {
              requested.add(request.url);
              if (request.url.path != '/t/12.json') {
                return http.Response(
                  '',
                  301,
                  headers: {'location': '/t/current-title/12.json'},
                );
              }
              return http.Response(
                jsonEncode({
                  'id': 12,
                  'title': 'Current title',
                  'post_stream': {'posts': <Object?>[], 'stream': <Object?>[]},
                }),
                200,
              );
            }),
          ).topic(
            siteUrl: 'https://example.com',
            slug: 'old-title',
            id: 12,
            apiKey: 'secret',
          );

      expect(requested, [Uri.parse('https://example.com/t/12.json')]);
      expect(topic.detail.title, 'Current title');
    });

    test(
      'does not put URL metacharacters from a slug into the request',
      () async {
        final paths = <String>[];
        await DiscourseApi(
          client: serving(paths),
        ).topic(siteUrl: 'https://example.com', slug: 'we?ird', id: 12);

        expect(paths, ['/t/12.json']);
      },
    );

    test('asks by id alone when the link carried no slug', () async {
      final paths = <String>[];
      await DiscourseApi(
        client: serving(paths),
      ).topic(siteUrl: 'https://example.com', slug: '', id: 12);

      expect(paths, ['/t/12.json']);
    });

    test('asks for the window around a requested post by id', () async {
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
        slug: 'a-real-topic',
        id: 12,
        postNumber: 37,
      );

      expect(asked.path, '/t/12.json');
      expect(asked.queryParameters['post_number'], '37');
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

    test('requests the top-replies topic projection', () async {
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
        summary: true,
      );

      expect(asked.path, '/t/12.json');
      expect(asked.queryParameters, {'post_number': '37', 'summary': 'true'});
    });

    test('rejects invalid topic coordinates before transport', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      );

      await expectLater(
        api.topic(siteUrl: 'https://example.com', slug: '', id: 0),
        throwsRangeError,
      );
      await expectLater(
        api.topic(
          siteUrl: 'https://example.com',
          slug: 'topic',
          id: 12,
          postNumber: -1,
        ),
        throwsRangeError,
      );
      expect(requests, 0);
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

    test(
      'updates a topic notification level through the web endpoint',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(jsonEncode({'success': 'OK'}), 200);
          }),
        );

        await api.updateTopicNotificationLevel(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          topicId: 12,
          notificationLevel: TopicNotificationLevel.muted,
        );

        expect(sent.method, 'POST');
        expect(sent.url.path, '/t/12/notifications');
        expect(jsonDecode(sent.body), {'notification_level': 0});
      },
    );

    test('updates a guardian-approved topic status', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await api.updateTopicStatus(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        topicId: 12,
        status: TopicStatusProperty.closed,
        enabled: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/t/12/status');
      expect(jsonDecode(sent.body), {'status': 'closed', 'enabled': true});
    });

    test('deletes and recovers a topic through core topic routes', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('', 200);
        }),
      );

      await api.deleteTopic(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        topicId: 12,
      );
      await api.recoverTopic(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        topicId: 12,
      );

      expect(sent.map((request) => request.method), ['DELETE', 'PUT']);
      expect(sent.map((request) => request.url.path), [
        '/t/12.json',
        '/t/12/recover.json',
      ]);
      expect(sent.map((request) => jsonDecode(request.body)), [
        {'context': '/t/12'},
        {'context': '/t/12'},
      ]);
    });

    test('permanently deletes a topic with force_destroy', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await api.permanentlyDeleteTopic(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        topicId: 12,
      );

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/t/12.json');
      expect(jsonDecode(sent.body), {
        'context': '/t/12',
        'force_destroy': true,
      });
    });

    test('dismisses and restores a personalized topic pin', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('', 200);
        }),
      );

      await api.updateTopicPinForUser(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        topicId: 12,
        pinned: false,
      );
      await api.updateTopicPinForUser(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        topicId: 12,
        pinned: true,
      );

      expect(sent.map((request) => request.method), everyElement('PUT'));
      expect(sent.map((request) => request.url.path), [
        '/t/12/clear-pin',
        '/t/12/re-pin',
      ]);
      expect(sent.map((request) => jsonDecode(request.body)), const [
        <String, dynamic>{},
        <String, dynamic>{},
      ]);
    });

    test('sets and clears the connected account custom status', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('', 200);
        }),
      );

      await api.setUserStatus(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        description: 'Pairing',
        emoji: ':wave:t3:',
        endsAt: DateTime.utc(2030, 2, 3, 12, 30),
      );
      await api.clearUserStatus(siteUrl: 'https://example.com', apiKey: 'key');

      expect(sent.map((request) => request.method), ['PUT', 'DELETE']);
      expect(sent.map((request) => request.url.path), [
        '/user-status.json',
        '/user-status.json',
      ]);
      expect(jsonDecode(sent.first.body), {
        'description': 'Pairing',
        'emoji': 'wave:t3',
        'ends_at': '2030-02-03T12:30:00.000Z',
      });
      expect(jsonDecode(sent.last.body), <String, dynamic>{});
    });

    test('enters and leaves Do Not Disturb with core payloads', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(
            request.method == 'DELETE'
                ? jsonEncode({'success': true})
                : jsonEncode({'ends_at': '2030-02-03T12:30:00.000Z'}),
            200,
          );
        }),
      );

      for (final option in DoNotDisturbOption.values) {
        expect(
          await api.enterDoNotDisturb(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            duration: option.duration,
          ),
          DateTime.utc(2030, 2, 3, 12, 30),
        );
      }
      await api.leaveDoNotDisturb(
        siteUrl: 'https://example.com',
        apiKey: 'key',
      );

      expect(sent.map((request) => request.method), [
        'POST',
        'POST',
        'POST',
        'POST',
        'DELETE',
      ]);
      expect(
        sent.map((request) => request.url.path),
        everyElement('/do-not-disturb.json'),
      );
      expect(sent.map((request) => jsonDecode(request.body)), [
        {'duration': 30},
        {'duration': 60},
        {'duration': 120},
        {'duration': 'tomorrow'},
        <String, dynamic>{},
      ]);
    });

    test('rejects a Do Not Disturb response without an expiration', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        api.enterDoNotDisturb(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          duration: DoNotDisturbOption.halfHour.duration,
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.failure,
            'failure',
            WriteFailure.unreachable,
          ),
        ),
      );
    });

    test('updates hide_presence through the canonical user payload', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await api.updateHidePresence(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        username: 'reader name',
        hidePresence: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/u/reader%20name.json');
      expect(jsonDecode(sent.body), {'hide_presence': true});
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
                'location': 'Paris',
                'website': 'https://example.net/about',
                'website_name': 'example.net/about',
                'created_at': '2015-03-04T10:00:00.000Z',
                'time_read': 7200,
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
      expect(card.avatarUrl, 'https://example.com/user_avatar/j/240.png');
      expect(card.location, 'Paris');
      expect(card.website, 'https://example.net/about');
      expect(card.websiteName, 'example.net/about');
      expect(card.createdAt, DateTime.utc(2015, 3, 4, 10));
      expect(card.timeRead, 7200);
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
    bool whisper = false,
  }) => api.createPost(
    siteUrl: 'https://meta.discourse.org',
    apiKey: 'the-key',
    topicId: 12,
    raw: 'hi',
    replyToPostNumber: replyToPostNumber,
    whisper: whisper,
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
        models: DiscourseModelCodec(
          extensions: pluginRegistry,
          recommendationSources: pluginRegistry,
          icons: pluginRegistry,
        ),
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
      expect(
        page.recommendations!
            .source(coreSuggestedTopicRecommendationSourceId)!
            .topics
            .single
            .id,
        30,
      );
      expect(
        page.recommendations!
            .source(discourseAiRelatedTopicRecommendationSourceId)!
            .topics
            .single
            .id,
        40,
      );
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
      'reads and persists only groups that expose message inboxes',
      () async {
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'current_user': {
                  'id': 7,
                  'username': 'sam',
                  'groups': [
                    {'name': 'team', 'has_messages': true},
                    {'name': 'ordinary-membership', 'has_messages': false},
                    {'name': 'tech-advocates', 'has_messages': true},
                    {'name': 42, 'has_messages': true},
                  ],
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
        final stored = DiscourseUser.fromJson(user.toJson());

        expect(user.groups, ['team', 'ordinary-membership', 'tech-advocates']);
        expect(user.messageGroupNames, ['team', 'tech-advocates']);
        expect(
          () => user.messageGroupNames.add('another'),
          throwsUnsupportedError,
        );
        expect(stored, user);
        expect(stored.messageGroupNames, ['team', 'tech-advocates']);
        expect(
          user,
          isNot(
            const DiscourseUser(
              id: 7,
              username: 'sam',
              groups: ['team', 'ordinary-membership', 'tech-advocates'],
            ),
          ),
        );
      },
    );

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

    test('reads the current account sidebar category ids safely', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'sidebar_category_ids': [5, '8', false, 'not-an-id'],
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

      expect(user.sidebarCategoryIds, [5, 8]);
      expect(() => user.sidebarCategoryIds.add(13), throwsUnsupportedError);
    });

    test('reads category tracking levels used by Aggregate safely', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'tracked_category_ids': [1, '2', false],
                'watched_category_ids': [3],
                'watched_first_post_category_ids': ['4', null],
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
      final stored = DiscourseUser.fromJson(user.toJson());

      expect(user.trackedCategoryIds, [1, 2]);
      expect(user.watchedCategoryIds, [3]);
      expect(user.watchedFirstPostCategoryIds, [4]);
      expect(user.followedCategoryIds, {1, 2, 3, 4});
      expect(stored, user);
      expect(stored.hashCode, user.hashCode);
      expect(
        DiscourseUser.fromJson(const {'username': 'old'}).followedCategoryIds,
        isNull,
      );
    });

    test('reads and persists the post-owner guardian', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'can_change_post_owner': true,
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
      final stored = DiscourseUser.fromJson(user.toJson());

      expect(user.canChangePostOwner, isTrue);
      expect(stored, user);
      expect(
        DiscourseUser.fromJson(const {'username': 'old'}).canChangePostOwner,
        isFalse,
      );
    });

    test('reads and persists the whisper guardian capability', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'staff': false,
                'whisperer': true,
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
      final stored = DiscourseUser.fromJson(user.toJson());

      expect(user.staff, isFalse);
      expect(user.whisperer, isTrue);
      expect(stored, user);
      expect(stored.hashCode, user.hashCode);
      expect(
        DiscourseUser.fromJson(const {'username': 'old'}).whisperer,
        isFalse,
      );
    });

    test('sidebar category ids survive storage and affect user identity', () {
      const user = DiscourseUser(username: 'sam', sidebarCategoryIds: [5, 8]);

      final stored = DiscourseUser.fromJson(user.toJson());

      expect(stored, user);
      expect(stored.hashCode, user.hashCode);
      expect(stored.sidebarCategoryIds, [5, 8]);
      expect(
        stored,
        isNot(const DiscourseUser(username: 'sam', sidebarCategoryIds: [5])),
      );
    });

    test('reads and persists the current account timezone', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'user_option': {'timezone': 'America/New_York'},
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
      final stored = DiscourseUser.fromJson(user.toJson());

      expect(user.timezone, 'America/New_York');
      expect(stored, user);
      expect(
        DiscourseUser.fromJson(const {'username': 'old'}).timezone,
        isNull,
      );
    });

    test(
      'reads and persists the current account presence preference',
      () async {
        final api = DiscourseApi(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'current_user': {
                  'id': 7,
                  'username': 'sam',
                  'user_option': {'hide_presence': true},
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
        final stored = DiscourseUser.fromJson(user.toJson());

        expect(user.hidePresence, isTrue);
        expect(stored, user);
        expect(stored.hashCode, user.hashCode);
        expect(
          DiscourseUser.fromJson(const {'username': 'old'}).hidePresence,
          isNull,
        );
        expect(
          user,
          isNot(const DiscourseUser(username: 'sam', hidePresence: false)),
        );
      },
    );

    test('reads the current account’s chat header state', () async {
      final api = DiscourseApi(
        models: DiscourseModelCodec(
          extensions: pluginRegistry,
          recommendationSources: pluginRegistry,
          icons: pluginRegistry,
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'has_chat_enabled': true,
                'do_not_disturb_until': '2027-01-02T03:04:05.000Z',
                'do_not_disturb_channel_position': 91,
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

      expect(user.chatCurrentUser?.hasChatEnabled, isTrue);
      expect(
        user.chatCurrentUser?.headerIndicatorPreference,
        ChatHeaderIndicatorPreference.onlyMentions,
      );
      expect(user.doNotDisturbUntil, DateTime.utc(2027, 1, 2, 3, 4, 5));
      expect(user.doNotDisturbChannelPosition, 91);
      expect(user.chatCurrentUser?.lastChannelId, 42);
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

  group('user summary', () {
    test('reads the authenticated side-loaded summary contract', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'topics': [
                {'id': 12, 'title': 'Native summary', 'slug': 'native-summary'},
              ],
              'user_summary': {
                'can_see_summary_stats': true,
                'days_visited': 8,
                'topic_ids': [12],
                'replies': <Object?>[],
                'links': <Object?>[],
                'most_replied_to_users': <Object?>[],
                'most_liked_by_users': <Object?>[],
                'most_liked_users': <Object?>[],
                'top_categories': <Object?>[],
              },
            }),
            200,
          );
        }),
      );

      final summary = await api.userSummary(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        username: 'sam.reader',
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/u/sam.reader/summary.json');
      expect(sent.headers['User-Api-Key'], 'the-key');
      expect(summary.daysVisited, 8);
      expect(summary.topics.single.title, 'Native summary');
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

    test('sends the core whisper flag only for a whispered reply', () async {
      late http.Request whispered;
      await create(
        DiscourseApi(client: accepting(onRequest: (r) => whispered = r)),
        whisper: true,
      );
      final whisperedBody = jsonDecode(whispered.body) as Map<String, dynamic>;
      expect(whisperedBody['whisper'], isTrue);

      late http.Request public;
      await create(
        DiscourseApi(client: accepting(onRequest: (r) => public = r)),
      );
      final publicBody = jsonDecode(public.body) as Map<String, dynamic>;
      expect(publicBody.containsKey('whisper'), isFalse);
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

    test('creates a private message for the named group', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: accepting(
          onRequest: (request) => sent = request,
          envelope: {
            'action': 'create_post',
            'post': {
              'id': 52,
              'post_number': 1,
              'username': 'joffreyj',
              'cooked': '<p>Hello team</p>',
              'topic_id': 89,
              'topic_slug': 'a-private-subject',
              'topic_title': 'A private subject',
            },
          },
        ),
      );

      await api.createTopic(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        title: 'A private subject',
        raw: 'Hello team',
        targetRecipients: ' tech-leads ',
        typingDuration: const Duration(seconds: 2),
        composerOpenDuration: const Duration(seconds: 8),
        draftKey: ComposerDraft.newPrivateMessageDraftKey,
      );

      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['archetype'], 'private_message');
      expect(body['target_recipients'], 'tech-leads');
      expect(body['draft_key'], 'new_private_message');
      expect(body['category'], isNull);
    });
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

    test('preflights and permanently deletes a reply', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'can_permanently_delete': false,
                'reason': 'Wait five minutes.',
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );

      final check = await api.checkPermanentPostDeletion(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
      );
      await api.permanentlyDeletePost(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        topicId: 7,
        postId: 42,
      );

      expect(check.allowed, isFalse);
      expect(check.reason, 'Wait five minutes.');
      expect(sent.map((request) => request.method), ['GET', 'DELETE']);
      expect(sent.map((request) => request.url.path), [
        '/posts/42/permanently_delete_check.json',
        '/posts/42.json',
      ]);
      expect(jsonDecode(sent.last.body), {
        'context': '/t/7',
        'force_destroy': true,
      });
    });
  });

  group('selected post moderation', () {
    test('sends core bulk-delete and merge contracts exactly', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('', 204);
        }),
      );

      await api.deletePosts(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postIds: const [42, 43],
      );
      await api.mergePosts(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postIds: const [44, 45],
      );

      expect(sent.map((request) => request.method), ['DELETE', 'PUT']);
      expect(sent.map((request) => request.url.path), [
        '/posts/destroy_many.json',
        '/posts/merge_posts.json',
      ]);
      expect(jsonDecode(sent[0].body), {
        'post_ids': [42, 43],
        'agree_with_first_reply_flag': true,
      });
      expect(jsonDecode(sent[1].body), {
        'post_ids': [44, 45],
      });
    });

    test('rejects empty, duplicate, and one-post merge selections', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('', 204)),
      );

      await expectLater(
        api.deletePosts(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postIds: const [],
        ),
        throwsArgumentError,
      );
      await expectLater(
        api.deletePosts(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postIds: const [42, 42],
        ),
        throwsArgumentError,
      );
      await expectLater(
        api.mergePosts(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postIds: const [42],
        ),
        throwsArgumentError,
      );
    });

    test(
      'moves posts through the source topic and reads its destination',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({'success': true, 'url': '/t/destination/99'}),
              200,
            );
          }),
        );

        final url = await api.movePosts(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          topicId: 7,
          postIds: const [42, 43],
          destinationTopicId: 99,
          chronologicalOrder: true,
        );

        expect(url, '/t/destination/99');
        expect(sent.method, 'POST');
        expect(sent.url.path, '/t/7/move-posts.json');
        expect(jsonDecode(sent.body), {
          'post_ids': [42, 43],
          'destination_topic_id': 99,
          'chronological_order': true,
        });
      },
    );

    test('sends the web topic chooser search modifiers', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );

      await api.searchPosts(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        term: 'destination',
        typeFilter: 'topic',
        searchForId: true,
        restrictToArchetype: 'regular',
      );

      expect(sent.url.path, '/search/query.json');
      expect(sent.url.queryParameters, {
        'term': 'destination',
        'type_filter': 'topic',
        'search_for_id': 'true',
        'restrict_to_archetype': 'regular',
      });
    });

    test('changes ownership through the topic route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      );

      await api.changePostOwners(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        topicId: 7,
        postIds: const [42, 43],
        username: 'kris',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/t/7/change-owner.json');
      expect(jsonDecode(sent.body), {
        'post_ids': [42, 43],
        'username': 'kris',
      });
    });
  });

  group('updatePostWiki', () {
    test('uses the dedicated post field route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await api.updatePostWiki(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
        wiki: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/posts/42/wiki.json');
      expect(jsonDecode(sent.body), {'wiki': true});
    });
  });

  group('updatePostLocked', () {
    test('uses the dedicated staff field route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await api.updatePostLocked(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
        locked: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/posts/42/locked.json');
      expect(jsonDecode(sent.body), {'locked': true});
    });
  });

  group('unhidePost', () {
    test('uses the dedicated moderation route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await api.unhidePost(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/posts/42/unhide.json');
      expect(jsonDecode(sent.body), isEmpty);
    });
  });

  group('updatePostType', () {
    test('uses the dedicated moderator-post route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await api.updatePostType(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
        postType: Post.moderatorPostType,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/posts/42/post_type.json');
      expect(jsonDecode(sent.body), {'post_type': Post.moderatorPostType});
    });
  });

  group('updatePostNotice', () {
    test(
      'adds or changes a notice through the dedicated field route',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response('', 204);
          }),
        );

        await api.updatePostNotice(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
          notice: '  Please read this carefully.  ',
        );

        expect(sent.method, 'PUT');
        expect(sent.url.path, '/posts/42/notice.json');
        expect(jsonDecode(sent.body), {
          'notice': 'Please read this carefully.',
        });
      },
    );

    test('removes a notice by omitting the field', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await api.updatePostNotice(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        postId: 42,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/posts/42/notice.json');
      expect(jsonDecode(sent.body), isEmpty);
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

  group('createPostFlag', () {
    String flaggedPost() => jsonEncode({
      'id': 42,
      'post_number': 7,
      'username': 'sam',
      'cooked': '<p>hi</p>',
      'actions_summary': [
        {'id': 3, 'acted': true},
        {'id': 2, 'count': 4, 'can_act': true},
      ],
    });

    test('posts the exact flag body and reads the unwrapped post', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(flaggedPost(), 200);
        }),
      );

      final post = await api.createPostFlag(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        clientId: 'native-client',
        postId: 42,
        postActionTypeId: 3,
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/post_actions.json');
      expect(sent.headers['User-Api-Key'], 'the-key');
      expect(sent.headers['User-Api-Client-Id'], 'native-client');
      expect(jsonDecode(sent.body), {'id': 42, 'post_action_type_id': 3});
      expect(post.actedFlagSummaries.single.id, 3);
      expect(post.likeCount, 4);
    });

    test(
      'topic flags identify the topic through core’s action bridge',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response('{}', 200);
          }),
        );

        await api.createTopicFlag(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          clientId: 'native-client',
          topicId: 7,
          postActionTypeId: 8,
          message: 'This whole topic is promotional.',
        );

        expect(sent.method, 'POST');
        expect(sent.url.path, '/post_actions.json');
        expect(sent.headers['User-Api-Key'], 'the-key');
        expect(sent.headers['User-Api-Client-Id'], 'native-client');
        expect(jsonDecode(sent.body), {
          'id': 7,
          'post_action_type_id': 8,
          'flag_topic': true,
          'message': 'This whole topic is promotional.',
        });
      },
    );

    test(
      'includes a required explanation without moderation parameters',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(flaggedPost(), 200);
          }),
        );

        await api.createPostFlag(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
          postActionTypeId: 7,
          message: 'Please review this carefully.',
        );

        expect(jsonDecode(sent.body), {
          'id': 42,
          'post_action_type_id': 7,
          'message': 'Please review this carefully.',
        });
      },
    );

    test('never accepts an empty successful response as a submitted flag', () {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('', 204)),
      );

      expect(
        api.createPostFlag(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
          postActionTypeId: 3,
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.failure,
            'failure',
            WriteFailure.unreachable,
          ),
        ),
      );
    });

    test('preserves the shared server-validation message mapping', () {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': ['Please enter at least 10 characters.'],
            }),
            422,
          ),
        ),
      );

      expect(
        api.createPostFlag(
          siteUrl: 'https://meta.discourse.org',
          apiKey: 'the-key',
          postId: 42,
          postActionTypeId: 7,
          message: 'short',
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.message,
            'message',
            'Please enter at least 10 characters.',
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
                'id': 73,
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
        expect(result.id, 73);
        expect(result.shortUrl, 'upload://abc123');
        expect(result.markdownWidth, 690);
        expect(
          result.previewUrl,
          'https://meta.discourse.org/uploads/default/optimized/photo.png',
        );
      },
    );

    test('uses the chat upload security context when requested', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'id': 74,
              'original_filename': 'chat.png',
              'url': '/uploads/default/original/chat.png',
              'short_url': 'upload://chat',
            }),
            200,
          );
        }),
      );

      final result = await api.uploadComposerImage(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'key',
        file: _uploadFile,
        uploadType: const ComposerUploadType('chat-composer'),
        onProgress: (_) {},
        abortTrigger: Completer<void>().future,
      );

      expect(result.id, 74);
      final multipart = latin1.decode(sent.bodyBytes);
      expect(multipart, contains('chat-composer'));
    });

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
