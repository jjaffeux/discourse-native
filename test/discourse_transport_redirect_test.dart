import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/manual_scheduler.dart';

void main() {
  group('GET redirects', () {
    for (final apiKey in [null, 'secret']) {
      test('loads a category feed after a 301 with '
          '${apiKey == null ? 'anonymous' : 'authenticated'} access', () async {
        final requested = <Uri>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            requested.add(request.url);
            expect(request.method, 'GET');
            expect(request.followRedirects, isFalse);
            expect(request.headers['User-Api-Key'], apiKey);
            expect(
              request.headers['User-Api-Client-Id'],
              apiKey == null ? isNull : 'client',
            );
            if (request.url.path == '/forum/c/old-name/7.json') {
              return http.Response(
                '',
                301,
                headers: {'location': '/forum/c/current-name/7.json?page=2'},
              );
            }
            return http.Response(
              jsonEncode({
                'topic_list': {
                  'topics': [
                    {'id': 42, 'title': 'A topic', 'slug': 'a-topic'},
                  ],
                  'more_topics_url': '/forum/c/current-name/7?page=3',
                },
              }),
              200,
            );
          }),
        );
        addTearDown(api.close);

        final list = await api.topicList(
          siteUrl: 'https://example.com/forum',
          path: '/c/old-name/7.json?page=2',
          apiKey: apiKey,
          clientId: 'client',
        );

        expect(requested, [
          Uri.parse('https://example.com/forum/c/old-name/7.json?page=2'),
          Uri.parse('https://example.com/forum/c/current-name/7.json?page=2'),
        ]);
        expect(list.topics.single.id, 42);
        expect(list.moreTopicsUrl, '/forum/c/current-name/7?page=3');
      });
    }

    for (final statusCode in [301, 302, 303, 307, 308]) {
      test('follows a relative $statusCode and preserves headers', () async {
        final requested = <Uri>[];
        final transport = DiscourseTransport.create(
          client: MockClient((request) async {
            requested.add(request.url);
            expect(request.followRedirects, isFalse);
            expect(request.headers['Accept'], 'application/json');
            expect(request.headers['User-Api-Key'], 'secret');
            expect(request.headers['User-Api-Client-Id'], 'client');
            return requested.length == 1
                ? http.Response(
                    '',
                    statusCode,
                    headers: {'location': 'current/7.json?page=2'},
                  )
                : http.Response('{}', 200);
          }),
        );
        addTearDown(transport.close);

        final response = await transport.get(
          Uri.parse('https://example.com/forum/tag/old.json'),
          siteUrl: 'https://example.com/forum',
          apiKey: 'secret',
          clientId: 'client',
          accept: 'application/json',
        );

        expect(response.statusCode, 200);
        expect(requested, [
          Uri.parse('https://example.com/forum/tag/old.json'),
          Uri.parse('https://example.com/forum/tag/current/7.json?page=2'),
        ]);
      });
    }

    for (final location in [
      'https://attacker.example/latest.json',
      '//attacker.example/latest.json',
      'https://example.com:8443/latest.json',
      'http://example.com/latest.json',
      'http://localhost/latest.json',
      'https://reader:password@example.com/latest.json',
      'file:///latest.json',
    ]) {
      test('rejects $location before forwarding credentials', () async {
        final requested = <Uri>[];
        final transport = DiscourseTransport.create(
          client: MockClient((request) async {
            requested.add(request.url);
            return http.Response('', 301, headers: {'location': location});
          }),
        );
        addTearDown(transport.close);

        await expectLater(
          transport.get(
            Uri.parse('https://example.com/latest.json'),
            siteUrl: 'https://example.com',
            apiKey: 'secret',
            clientId: 'client',
          ),
          throwsA(
            isA<SiteLookupException>().having(
              (error) => error.diagnosticCause,
              'diagnosticCause',
              isA<UnsafeHttpTransportException>(),
            ),
          ),
        );
        expect(requested, [Uri.parse('https://example.com/latest.json')]);
      });
    }

    test('checks the origin of every redirect in a chain', () async {
      final requested = <Uri>[];
      final transport = DiscourseTransport.create(
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response(
            '',
            302,
            headers: {
              'location': requested.length == 1
                  ? 'https://example.com/c/current/7.json'
                  : 'https://attacker.example/c/current/7.json',
            },
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.get(
          Uri.parse('https://example.com/c/old/7.json'),
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        ),
        throwsA(isA<SiteLookupException>()),
      );
      expect(requested, [
        Uri.parse('https://example.com/c/old/7.json'),
        Uri.parse('https://example.com/c/current/7.json'),
      ]);
    });

    for (final location in [null, '']) {
      test('rejects a redirect with location $location', () async {
        var calls = 0;
        final transport = DiscourseTransport.create(
          client: MockClient((_) async {
            calls++;
            return http.Response('', 301, headers: {'location': ?location});
          }),
        );
        addTearDown(transport.close);

        await expectLater(
          transport.get(
            Uri.parse('https://example.com/latest.json'),
            siteUrl: 'https://example.com',
          ),
          throwsA(
            isA<SiteLookupException>().having(
              (error) => error.statusCode,
              'statusCode',
              301,
            ),
          ),
        );
        expect(calls, 1);
      });
    }

    test('stops after five redirects', () async {
      var calls = 0;
      final transport = DiscourseTransport.create(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            '',
            301,
            headers: {'location': '/redirect-$calls.json'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.get(
          Uri.parse('https://example.com/latest.json'),
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        ),
        throwsA(
          isA<SiteLookupException>().having(
            (error) => error.statusCode,
            'statusCode',
            301,
          ),
        ),
      );
      expect(calls, 6);
    });

    test('coalesces redirected reads with one request slot', () async {
      final gate = Completer<void>();
      final requested = <Uri>[];
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((request) async {
            requested.add(request.url);
            if (request.url.path == '/old.json') {
              return http.Response(
                '',
                301,
                headers: {'location': '/current.json'},
              );
            }
            await gate.future;
            return http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
        maxConcurrentPerOrigin: 1,
      );
      addTearDown(transport.close);

      Future<http.Response> read() => transport.get(
        Uri.parse('https://example.com/old.json'),
        siteUrl: 'https://example.com',
        apiKey: 'secret',
      );

      final first = read();
      final second = read();
      await pumpEventQueue();
      expect(requested, [
        Uri.parse('https://example.com/old.json'),
        Uri.parse('https://example.com/current.json'),
      ]);

      gate.complete();
      final responses = await Future.wait([first, second]);
      expect(responses.first.statusCode, 200);
      expect(responses.first, same(responses.last));
    });

    test('a redirected 429 pauses later requests', () async {
      final scheduler = ManualScheduler();
      final requested = <String>[];
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((request) async {
            requested.add(request.url.path);
            return switch (request.url.path) {
              '/old.json' => http.Response(
                '',
                301,
                headers: {'location': '/current.json'},
              ),
              '/current.json' => http.Response('{}', 429),
              _ => http.Response('{}', 200),
            };
          }),
        ),
        const Duration(seconds: 1),
        1024,
        coordinator: DiscourseRequestCoordinator(
          defaultRateLimitCooldown: const Duration(minutes: 1),
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        ),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.get(
          Uri.parse('https://example.com/old.json'),
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        ),
        throwsA(
          isA<SiteLookupException>().having(
            (error) => error.statusCode,
            'statusCode',
            429,
          ),
        ),
      );

      final later = transport.get(
        Uri.parse('https://example.com/later.json'),
        siteUrl: 'https://example.com',
      );
      await pumpEventQueue();
      expect(requested, ['/old.json', '/current.json']);
      scheduler.advance(const Duration(minutes: 1));
      expect((await later).statusCode, 200);
      expect(requested, ['/old.json', '/current.json', '/later.json']);
    });
  });
}
