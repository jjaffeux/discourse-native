import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';

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
                  'chat_separate_sidebar_mode': 'fullscreen',
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
          chatSeparateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
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

    test('puts the chat sidebar mode as a flat user option', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'user': {
                'user_option': {'chat_separate_sidebar_mode': 'always'},
              },
            }),
            200,
          );
        }),
      );
      const fallback = UserPreferences(
        username: 'Sam Name',
        chatSeparateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
        canEdit: true,
      );

      final result = await api.updateUserPreferences(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        username: 'Sam Name',
        fallback: fallback,
        values: const {'chat_separate_sidebar_mode': 'always'},
      );

      expect(sent.method, 'PUT');
      expect(sent.url.toString(), 'https://forum.example/u/sam%20name.json');
      expect(jsonDecode(sent.body), {'chat_separate_sidebar_mode': 'always'});
      expect(
        result.chatSeparateSidebarMode,
        ChatSeparateSidebarPreference.always,
      );
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
    test('assumes HTTPS for a bare host', () {
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
        path: '/voice/rooms.json?limit=20',
        apiKey: 'secret',
      );
      await api.pluginWriteJson(
        siteUrl: 'https://example.com',
        path: 'voice/rooms/1.json',
        method: 'PUT',
        apiKey: 'secret',
        body: const {'name': 'Room'},
      );

      expect(requests.map((request) => request.url), [
        Uri.parse('https://example.com/voice/rooms.json?limit=20'),
        Uri.parse('https://example.com/voice/rooms/1.json'),
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

  _feedGroups();
  _writeGroups();
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
                  'can_create_topic': true,
                  'more_topics_url': '/latest?page=1',
                  'categories': [
                    {
                      'id': 5,
                      'name': 'Support docs',
                      'color': '00AEEF',
                      'parent_category_id': 2,
                    },
                  ],
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
        expect(list.categories.single.id, 5);
        expect(list.categories.single.name, 'Support docs');
        expect(list.categories.single.parentCategoryId, 2);

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

    test('reads public navigation tag metadata from site.json', () async {
      final requested = <String>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested.add(request.url.path);
          if (request.url.path == '/categories.json') {
            return http.Response(
              jsonEncode({
                'category_list': {'categories': <Object?>[]},
              }),
              200,
            );
          }
          expect(request.url.path, '/site.json');
          expect(request.headers.containsKey('User-Api-Key'), isFalse);
          return http.Response(
            jsonEncode({
              'navigation_menu_site_top_tags': [
                {
                  'id': 8,
                  'name': 'popular',
                  'slug': 'most-popular',
                  'description': 'Frequently used',
                  'pm_only': false,
                },
                {'id': 0, 'name': 'not-a-tag'},
              ],
              'anonymous_default_navigation_menu_tags': [
                {
                  'id': 12,
                  'name': 'private-priority',
                  'slug': 'private-priority',
                  'pm_only': true,
                },
                {'id': '13', 'name': 'announcements'},
                {'name': 'missing-id'},
              ],
            }),
            200,
          );
        }),
      );

      final result = await api.loadCategories(siteUrl: 'https://example.com');

      expect(requested, ['/categories.json', '/site.json']);
      expect(result.siteTopTags, const [
        SidebarTag(
          id: 8,
          name: 'popular',
          slug: 'most-popular',
          description: 'Frequently used',
        ),
      ]);
      expect(result.anonymousDefaultTags, const [
        SidebarTag(
          id: 12,
          name: 'private-priority',
          slug: 'private-priority',
          pmOnly: true,
        ),
        SidebarTag(id: 13, name: 'announcements', slug: 'announcements'),
      ]);
      expect(
        () => result.siteTopTags!.add(
          const SidebarTag(id: 14, name: 'later', slug: 'later'),
        ),
        throwsUnsupportedError,
      );
    });

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

        await Future<void>.delayed(Duration.zero);
        expect(
          siteStarted.isCompleted,
          isTrue,
          reason: 'the site request must start while categories are held',
        );
        releaseCategories.complete();
        final result = await loading;
        expect(result.complete, isTrue);
        expect(result.postActionCatalog, isNotNull);
        expect(result.postActionCatalog?.postFlags, isEmpty);
      },
    );

    test('finds exact category IDs outside the paginated list', () async {
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

    test('server-searches a bounded lazy category chooser page', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
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

      final categories = await api.searchCategories(
        siteUrl: 'https://example.com',
        term: '  support docs  ',
        includeUncategorized: false,
        apiKey: 'key',
        clientId: 'client',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/categories/search.json');
      expect(sent.headers['User-Api-Key'], 'key');
      expect(sent.headers['User-Api-Client-Id'], 'client');
      expect(jsonDecode(sent.body), {
        'term': 'support docs',
        'include_uncategorized': false,
        'include_subcategories': true,
        'limit': 25,
      });
      expect(categories.single.id, 6);
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

    test('marks the Uncategorized ID supplied by site.json', () async {
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

  group('tags', () {
    test('flattens, deduplicates, and orders the tag directory', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'tags': [
                {
                  'id': 30,
                  'name': 'Zulu',
                  'slug': 'zulu',
                  'count': 2,
                  'description': 'Root record wins',
                },
              ],
              'extras': {
                'tag_groups': [
                  {
                    'id': 4,
                    'name': 'Priorities',
                    'tags': [
                      {
                        'id': 20,
                        'name': 'Beta',
                        'slug': 'beta',
                        'count': 0,
                        'pm_count': '4',
                        'pm_only': true,
                      },
                      {'id': -1, 'name': 'invalid'},
                    ],
                  },
                ],
                'categories': [
                  {
                    'id': 9,
                    'tags': [
                      {
                        'id': 30,
                        'name': 'Duplicate Zulu',
                        'slug': 'duplicate-zulu',
                        'count': 99,
                      },
                      {
                        'id': 10,
                        'name': 'alpha',
                        'slug': 'alpha',
                        'topic_count': 7,
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

      final tags = await api.tags(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/tags.json');
      expect(sent.headers['User-Api-Key'], 'key');
      expect(sent.headers['User-Api-Client-Id'], 'client');
      expect(tags, const [
        SidebarTag(id: 10, name: 'alpha', slug: 'alpha', count: 7),
        SidebarTag(id: 20, name: 'Beta', slug: 'beta', pmOnly: true, count: 4),
        SidebarTag(
          id: 30,
          name: 'Zulu',
          slug: 'zulu',
          description: 'Root record wins',
          count: 2,
        ),
      ]);
      expect(
        () => tags.add(const SidebarTag(id: 40, name: 'later', slug: 'later')),
        throwsUnsupportedError,
      );
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

        expect(
          () => api.siteConfig(siteUrl: 'https://example.com'),
          throwsA(isA<SiteLookupException>()),
        );
      },
    );
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
    test('reads a payload shaped as an object of name to URL', () async {
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

  group('topic', () {
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

    test('reads the topic by its immutable ID', () async {
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

    test('asks by ID alone when the link carried no slug', () async {
      final paths = <String>[];
      await DiscourseApi(
        client: serving(paths),
      ).topic(siteUrl: 'https://example.com', slug: '', id: 12);

      expect(paths, ['/t/12.json']);
    });

    test('asks for the window around a requested post by ID', () async {
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

    test('reads and persists the account-level topic guardian', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'can_create_topic': true,
                'can_create_group': true,
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

      expect(user.canCreateTopic, isTrue);
      expect(user.canCreateGroup, isTrue);
      expect(stored, user);
      expect(stored.hashCode, user.hashCode);
      expect(
        DiscourseUser.fromJson(const {'username': 'old'}).canCreateTopic,
        isFalse,
      );
      expect(
        DiscourseUser.fromJson(const {'username': 'old'}).canCreateGroup,
        isFalse,
      );
    });

    test('reads the current account sidebar category IDs safely', () async {
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

    test('reads the current account sidebar count modes', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'unified_new_enabled': true,
                'user_option': {'sidebar_show_count_of_new_items': true},
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

      expect(user.unifiedNewEnabled, isTrue);
      expect(user.sidebarShowCountOfNewItems, isTrue);
      expect(stored, user);
    });

    test('loads the per-topic sidebar tracking snapshot', () async {
      Uri? requested;
      final api = DiscourseApi(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode([
              {
                'topic_id': 42,
                'highest_post_number': 4,
                'last_read_post_number': 2,
                'category_id': 5,
                'notification_level': 2,
                'tags': [
                  {'id': 9},
                ],
              },
            ]),
            200,
          );
        }),
      );

      final tracking = await api.topicTrackingState(
        siteUrl: 'https://meta.discourse.org',
        apiKey: 'the-key',
        username: 'Sam Name',
      );

      expect(requested?.path, '/u/Sam%20Name/topic-tracking-state.json');
      expect(
        tracking.tagBadge(tagId: 9, unifiedNew: false, showCount: true),
        const SidebarBadge.count(1),
      );
    });

    test('reads and persists the current account sidebar tags', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current_user': {
                'id': 7,
                'username': 'sam',
                'display_sidebar_tags': true,
                'sidebar_tags': [
                  {
                    'id': 11,
                    'name': 'priority-high',
                    'slug': 'priority-high',
                    'description': 'High priority topics',
                    'pm_only': false,
                  },
                  {'id': '12', 'name': 'private-work', 'pm_only': true},
                  {'id': 0, 'name': 'invalid'},
                  {'name': 'missing-id'},
                  false,
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

      expect(user.displaySidebarTags, isTrue);
      expect(user.sidebarTags, const [
        SidebarTag(
          id: 11,
          name: 'priority-high',
          slug: 'priority-high',
          description: 'High priority topics',
        ),
        SidebarTag(
          id: 12,
          name: 'private-work',
          slug: 'private-work',
          pmOnly: true,
        ),
      ]);
      expect(() => user.sidebarTags.clear(), throwsUnsupportedError);
      expect(stored, user);
      expect(stored.hashCode, user.hashCode);
      expect(stored.displaySidebarTags, isTrue);
      expect(stored.sidebarTags, user.sidebarTags);
      expect(
        DiscourseUser.fromJson(const {'username': 'old'}).displaySidebarTags,
        isFalse,
      );
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

    test('sidebar category IDs survive storage and affect user identity', () {
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

    test('addresses the reply by post number, not by post ID', () async {
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
