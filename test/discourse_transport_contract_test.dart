import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/site_appearance_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Discourse API transport contract', () {
    test('identical reads share one in-flight request', () async {
      final gate = Completer<void>();
      var calls = 0;
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((_) async {
            calls++;
            await gate.future;
            return http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
      );
      addTearDown(transport.close);

      final first = transport.get(
        Uri.parse('https://example.com/site.json'),
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );
      final second = transport.get(
        Uri.parse('https://example.com/site.json'),
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      gate.complete();
      await Future.wait([first, second]);
      expect(calls, 1);
    });

    test('appearance and API reads share site metadata in flight', () async {
      final gate = Completer<void>();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        await gate.future;
        return http.Response('{}', 200);
      });
      final transport = DiscourseTransport(
        SafeHttpClient.borrowed(client),
        const Duration(seconds: 1),
        1024,
      );
      addTearDown(transport.close);
      final appearance = SiteAppearanceLoader(
        client: client,
        coordinator: transport.coordinator,
      ).load(siteUrl: 'https://example.com');
      final metadata = transport.get(
        Uri.parse('https://example.com/site.json'),
        siteUrl: 'https://example.com',
      );
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      gate.complete();
      expect(await appearance, isNull);
      await metadata;
      expect(calls, 1);
    });

    test('bounds concurrent requests to one origin', () async {
      final gates = <Completer<void>>[];
      var active = 0;
      var maximumActive = 0;
      var calls = 0;
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((_) async {
            calls++;
            active++;
            maximumActive = active > maximumActive ? active : maximumActive;
            final gate = Completer<void>();
            gates.add(gate);
            await gate.future;
            active--;
            return http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
        maxConcurrentPerOrigin: 2,
      );
      addTearDown(transport.close);

      final reads = [
        for (var index = 0; index < 5; index++)
          transport.get(
            Uri.parse('https://example.com/read-$index.json'),
            siteUrl: 'https://example.com',
          ),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);

      gates[0].complete();
      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 4);

      gates[2].complete();
      gates[3].complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 5);
      gates[4].complete();
      await Future.wait(reads);
      expect(maximumActive, 2);
    });

    test(
      'bounds queued work per origin and reuses capacity in FIFO order',
      () async {
        final gates = <Completer<void>>[];
        final started = <String>[];
        final transport = DiscourseTransport(
          SafeHttpClient.owned(
            MockClient((request) async {
              started.add(request.url.path);
              final gate = Completer<void>();
              gates.add(gate);
              await gate.future;
              return http.Response('{}', 200);
            }),
          ),
          const Duration(seconds: 1),
          1024,
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 2,
        );
        addTearDown(transport.close);

        Future<http.Response> read(String path) => transport.get(
          Uri.parse('https://example.com/$path.json'),
          siteUrl: 'https://example.com',
        );

        final first = read('first');
        final second = read('second');
        final third = read('third');
        await Future<void>.delayed(Duration.zero);
        expect(started, ['/first.json']);

        await expectLater(
          read('overflow'),
          throwsA(
            isA<SiteLookupException>().having(
              (error) => error.diagnosticCause,
              'diagnosticCause',
              isA<DiscourseRequestOverloadException>()
                  .having(
                    (error) => error.origin,
                    'origin',
                    'https://example.com',
                  )
                  .having((error) => error.maxQueued, 'maxQueued', 2),
            ),
          ),
        );
        expect(started, ['/first.json']);

        gates[0].complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(started, ['/first.json', '/second.json']);
        gates[1].complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(started, ['/first.json', '/second.json', '/third.json']);
        gates[2].complete();
        await Future.wait([first, second, third]);

        final afterDrain = read('after-drain');
        await Future<void>.delayed(Duration.zero);
        expect(started.last, '/after-drain.json');
        gates[3].complete();
        await afterDrain;
      },
    );

    test(
      'coalesces an accepted GET even when its origin queue is full',
      () async {
        final gates = <Completer<void>>[];
        final started = <String>[];
        final transport = DiscourseTransport(
          SafeHttpClient.owned(
            MockClient((request) async {
              started.add(request.url.path);
              final gate = Completer<void>();
              gates.add(gate);
              await gate.future;
              return http.Response('{}', 200);
            }),
          ),
          const Duration(seconds: 1),
          1024,
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 1,
        );
        addTearDown(transport.close);

        Future<http.Response> read(String path) => transport.get(
          Uri.parse('https://example.com/$path.json'),
          siteUrl: 'https://example.com',
        );

        final active = read('active');
        final shared = read('shared');
        final sharedAgain = read('shared');
        await Future<void>.delayed(Duration.zero);
        expect(started, ['/active.json']);
        await expectLater(
          transport.write(
            Uri.parse('https://example.com/overflow.json'),
            siteUrl: 'https://example.com',
            method: 'POST',
            apiKey: 'secret',
            body: const {},
          ),
          throwsA(
            isA<WriteException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  WriteFailure.unreachable,
                )
                .having(
                  (error) => error.diagnosticCause,
                  'diagnosticCause',
                  isA<DiscourseRequestOverloadException>(),
                ),
          ),
        );

        gates[0].complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(started, ['/active.json', '/shared.json']);
        gates[1].complete();
        await Future.wait([active, shared, sharedAgain]);
        expect(started.where((path) => path == '/shared.json'), hasLength(1));
      },
    );

    test('a 429 pauses later work for the same origin', () async {
      var calls = 0;
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((_) async {
            calls++;
            return calls == 1
                ? http.Response('{}', 429)
                : http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
        defaultRateLimitCooldown: const Duration(milliseconds: 60),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.get(
          Uri.parse('https://example.com/limited.json'),
          siteUrl: 'https://example.com',
        ),
        throwsA(
          isA<SiteLookupException>().having(
            (error) => error.statusCode,
            'statusCode',
            429,
          ),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final later = transport.get(
        Uri.parse('https://example.com/later.json'),
        siteUrl: 'https://example.com',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, 1);
      await later;
      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 35)),
      );
      expect(calls, 2);
    });

    testWidgets('closing the coordinator makes an in-flight 429 inert', (
      tester,
    ) async {
      final coordinator = DiscourseRequestCoordinator();
      final response = Completer<http.Response>();
      final limited = coordinator.run(
        Uri.parse('https://example.com/limited.json'),
        () => response.future,
      );

      coordinator.close();
      response.complete(
        http.Response('{}', 429, headers: {'retry-after': '3600'}),
      );
      await tester.pump();

      // The caller keeps the response it already earned; what must not
      // survive is the hour-long origin wake timer, which close() has no
      // queue left to cancel. testWidgets fails on any timer still pending.
      expect((await limited).statusCode, 429);
      await expectLater(
        coordinator.run(
          Uri.parse('https://example.com/later.json'),
          () async => http.Response('{}', 200),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cross-origin credentials are rejected before delegation', () async {
      var delegated = 0;
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((_) async {
            delegated += 1;
            return http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
      );

      await expectLater(
        transport.get(
          Uri.parse('https://attacker.example/read.json'),
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        ),
        throwsA(isA<SiteLookupException>()),
      );
      await expectLater(
        transport.write(
          Uri.parse('https://attacker.example/write.json'),
          siteUrl: 'https://example.com',
          method: 'POST',
          apiKey: 'secret',
          body: const {},
        ),
        throwsA(isA<WriteException>()),
      );
      await expectLater(
        transport.get(
          Uri.parse('https://example.com/read.json'),
          siteUrl: 'https://reader:password@example.com',
          apiKey: 'secret',
        ),
        throwsA(isA<SiteLookupException>()),
      );

      expect(delegated, 0);
    });

    test('ordinary reads use one authenticated header envelope', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );

      await api.notificationTotals(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );

      expect(sent.method, 'GET');
      expect(sent.headers, containsPair('User-Api-Key', 'secret'));
      expect(sent.headers, containsPair('User-Api-Client-Id', 'client'));
      expect(sent.headers, containsPair('User-Agent', DiscourseApi.userAgent));
      expect(sent.headers, containsPair('Content-Type', 'application/json'));
      expect(sent.headers, containsPair('Dont-Chunk', 'true'));
    });

    test('malformed object reads preserve a diagnostic cause', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('[]', 200)),
      );

      await expectLater(
        api.notificationTotals(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        ),
        throwsA(
          isA<SiteLookupException>()
              .having(
                (error) => error.failure,
                'failure',
                SiteLookupFailure.unreachable,
              )
              .having((error) => error.term, 'term', 'https://example.com')
              .having(
                (error) => error.diagnosticCause,
                'diagnosticCause',
                isA<FormatException>(),
              )
              .having(
                (error) => error.diagnosticCauseStackTrace,
                'diagnosticCauseStackTrace',
                isNotNull,
              ),
        ),
      );
    });

    test('writes omit nulls and apply the shared refusal policy', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'errors': ['  Message is too short.  ', ''],
            }),
            422,
          );
        }),
      );

      await expectLater(
        api.sendChatMessage(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
          clientId: 'client',
          channelId: 9,
          message: 'hi',
        ),
        throwsA(
          isA<WriteException>()
              .having(
                (error) => error.failure,
                'failure',
                WriteFailure.validation,
              )
              .having((error) => error.errors, 'errors', [
                'Message is too short.',
              ])
              .having((error) => error.statusCode, 'statusCode', 422),
        ),
      );

      expect(sent.method, 'POST');
      expect(sent.headers, containsPair('User-Api-Key', 'secret'));
      expect(sent.headers, containsPair('User-Api-Client-Id', 'client'));
      expect(jsonDecode(sent.body), {'message': 'hi'});
    });

    test(
      'chat sends serialize optimistic metadata and return the message id',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(jsonEncode({'message_id': 42}), 200);
          }),
        );
        final clientCreatedAt = DateTime.parse('2026-08-11T16:15:16.123+02:00');

        final messageId = await api.sendChatMessage(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
          clientId: 'client',
          channelId: 9,
          message: 'hello',
          threadId: 17,
          stagedId: 'staged-123',
          clientCreatedAt: clientCreatedAt,
        );

        expect(messageId, 42);
        expect(sent.method, 'POST');
        expect(sent.url.path, '/chat/9.json');
        expect(jsonDecode(sent.body), {
          'message': 'hello',
          'thread_id': 17,
          'staged_id': 'staged-123',
          'client_created_at': '2026-08-11T14:15:16.123Z',
        });
      },
    );

    test('writes preserve a plugin singular error response', () async {
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'error': 'You have reached the assignment limit.'}),
              400,
            ),
          ),
        ),
        const Duration(seconds: 1),
        1024,
      );

      await expectLater(
        transport.write(
          Uri.parse('https://example.com/assign/assign.json'),
          siteUrl: 'https://example.com',
          method: 'PUT',
          apiKey: 'secret',
          body: const {},
        ),
        throwsA(
          isA<WriteException>()
              .having(
                (error) => error.failure,
                'failure',
                WriteFailure.validation,
              )
              .having((error) => error.errors, 'errors', [
                'You have reached the assignment limit.',
              ])
              .having((error) => error.statusCode, 'statusCode', 400),
        ),
      );
    });
  });
}
