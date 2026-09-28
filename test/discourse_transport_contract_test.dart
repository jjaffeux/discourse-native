import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/manual_scheduler.dart';

void main() {
  group('Discourse API transport contract', () {
    test('DiscourseApi delegates requests to an injected transport', () async {
      late http.Request sent;
      final transport = DiscourseTransport.create(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );
      final api = DiscourseApi(transport: transport);
      addTearDown(api.close);

      await api.notificationTotals(
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
      );

      expect(
        sent.url,
        Uri.parse('https://example.com/notifications/totals.json'),
      );
      expect(sent.headers, containsPair('User-Api-Key', 'secret'));
      expect(sent.headers, containsPair('User-Api-Client-Id', 'client'));
    });

    test('transport constructs authenticated JSON requests', () async {
      late http.Request sent;
      final transport = DiscourseTransport.create(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(transport.close);

      await transport.requestAuthenticated(
        'POST',
        Uri.parse('https://example.com/action.json'),
        siteUrl: 'https://example.com',
        apiKey: 'secret',
        clientId: 'client',
        jsonBody: const {'present': true, 'missing': null},
      );

      expect(sent.method, 'POST');
      expect(jsonDecode(sent.body), {'present': true, 'missing': null});
      expect(sent.headers, containsPair('User-Api-Key', 'secret'));
      expect(sent.headers, containsPair('User-Api-Client-Id', 'client'));
      expect(sent.headers, containsPair('User-Agent', DiscourseApi.userAgent));
      expect(sent.headers, containsPair('Content-Type', 'application/json'));
      expect(sent.headers, containsPair('Dont-Chunk', 'true'));
    });

    test('transport owns safe HEAD redirect execution', () async {
      final requested = <Uri>[];
      final transport = DiscourseTransport.create(
        client: MockClient((request) async {
          requested.add(request.url);
          if (requested.length == 1) {
            return http.Response(
              '',
              301,
              headers: {'location': 'https://meta.example.com/probe'},
            );
          }
          return http.Response('', 200, headers: {'auth-api-version': '4'});
        }),
      );
      addTearDown(transport.close);

      final response = await transport.head(
        Uri.parse('https://example.com/probe'),
      );

      expect(response.url, Uri.parse('https://meta.example.com/probe'));
      expect(response.statusCode, 200);
      expect(response.headers['auth-api-version'], '4');
      expect(requested, [
        Uri.parse('https://example.com/probe'),
        Uri.parse('https://meta.example.com/probe'),
      ]);
    });

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

    test('identical appearance reads share site metadata in flight', () async {
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
      final appearance = transport.siteAppearance(
        siteUrl: 'https://example.com',
      );
      final repeated = transport.siteAppearance(siteUrl: 'https://example.com');
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      gate.complete();
      expect(await appearance, isNull);
      expect(await repeated, isNull);
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

    test('a batch of uploads leaves the forum free to read', () async {
      final sent = <String>[];
      final uploads = <Completer<void>>[];
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((request) async {
            sent.add('${request.method} ${request.url.path}');
            if (request.url.path == '/uploads.json') {
              final uplink = Completer<void>();
              uploads.add(uplink);
              await uplink.future;
            }
            return http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
      );
      addTearDown(transport.close);

      final batch = [
        for (var index = 0; index < 4; index++)
          transport.upload(
            url: Uri.parse('https://example.com/uploads.json'),
            siteUrl: 'https://example.com',
            apiKey: 'secret',
            uploadType: 'composer',
            filename: 'photo-$index.png',
            fileLength: 3,
            fileBytes: Stream.value([1, 2, 3]),
            onProgress: (_) {},
            abortTrigger: Completer<void>().future,
          ),
      ];
      await pumpEventQueue();
      expect(sent, ['POST /uploads.json', 'POST /uploads.json']);

      final topic = transport.get(
        Uri.parse('https://example.com/t/42.json'),
        siteUrl: 'https://example.com',
        apiKey: 'secret',
      );
      await pumpEventQueue();
      expect(sent.last, 'GET /t/42.json');
      expect((await topic).statusCode, 200);

      uploads.first.complete();
      await pumpEventQueue();
      expect(
        sent.where((route) => route == 'POST /uploads.json'),
        hasLength(3),
      );
      for (final uplink in uploads.skip(1)) {
        uplink.complete();
      }
      await pumpEventQueue();
      expect(uploads, hasLength(4));
      uploads.last.complete();
      await Future.wait(batch);
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
      final scheduler = ManualScheduler();
      var calls = 0;
      final coordinator = DiscourseRequestCoordinator(
        defaultRateLimitCooldown: const Duration(minutes: 1),
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
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
        coordinator: coordinator,
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

      final later = transport.get(
        Uri.parse('https://example.com/later.json'),
        siteUrl: 'https://example.com',
      );
      expect(calls, 1);
      scheduler.advance(const Duration(seconds: 59));
      expect(calls, 1);
      scheduler.advance(const Duration(seconds: 1));
      await later;
      expect(calls, 2);
    });

    test(
      'a refused action keeps its delay without pausing the origin',
      () async {
        final scheduler = ManualScheduler();
        final sent = <String>[];
        final transport = DiscourseTransport(
          SafeHttpClient.owned(
            MockClient((request) async {
              sent.add('${request.method} ${request.url.path}');
              if (request.method == 'POST') {
                return http.Response(
                  jsonEncode({
                    'errors': ["You've reached the maximum number of likes."],
                    'error_type': 'rate_limit',
                    'extras': {'wait_seconds': 68400, 'time_left': '19 hours'},
                  }),
                  429,
                  headers: {'retry-after': '68400'},
                );
              }
              return http.Response('{}', 200);
            }),
          ),
          const Duration(seconds: 1),
          1024,
          coordinator: DiscourseRequestCoordinator(
            cooldownFactory: () => OriginCooldown(
              clock: scheduler.now,
              timerFactory: scheduler.createTimer,
            ),
          ),
        );
        addTearDown(transport.close);

        await expectLater(
          transport.write(
            Uri.parse('https://example.com/post_actions'),
            siteUrl: 'https://example.com',
            method: 'POST',
            apiKey: 'secret',
            body: const {'id': 1, 'post_action_type_id': 2},
          ),
          throwsA(
            isA<WriteException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  WriteFailure.rateLimited,
                )
                .having(
                  (error) => error.retryAfter,
                  'retryAfter',
                  DiscourseRequestCoordinator.maximumRetryAfter,
                )
                .having((error) => error.errors, 'errors', [
                  "You've reached the maximum number of likes.",
                ]),
          ),
        );

        final later = transport.get(
          Uri.parse('https://example.com/latest.json'),
          siteUrl: 'https://example.com',
          apiKey: 'secret',
        );
        await pumpEventQueue();
        expect(sent, ['POST /post_actions', 'GET /latest.json']);
        expect((await later).statusCode, 200);
        expect(scheduler.activeTimerCount, 0);
      },
    );

    test('closing the coordinator makes an in-flight 429 inert', () async {
      final scheduler = ManualScheduler();
      final coordinator = DiscourseRequestCoordinator(
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      final response = Completer<http.Response>();
      final limited = coordinator.run(
        Uri.parse('https://example.com/limited.json'),
        () => response.future,
      );

      coordinator.close();
      response.complete(
        http.Response('{}', 429, headers: {'retry-after': '3600'}),
      );

      // The caller keeps the response it already earned, but no wake timer
      // survives after close has discarded its origin queue.
      expect((await limited).statusCode, 429);
      expect(scheduler.activeTimerCount, 0);
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

    test('anonymous reads identify the app', () async {
      final sent = <http.Request>[];
      final transport = DiscourseTransport.create(
        client: MockClient((request) async {
          sent.add(request);
          return switch (request.url.path) {
            '/c/old.json' => http.Response(
              '',
              301,
              headers: {'location': '/c/new.json'},
            ),
            '/user-api-key/new' => http.Response(
              '',
              200,
              headers: {'auth-api-version': '4'},
            ),
            '/site/basic-info.json' => http.Response(
              jsonEncode({'title': 'Example'}),
              200,
            ),
            _ => http.Response('{}', 200),
          };
        }),
      );
      final api = DiscourseApi(transport: transport);
      addTearDown(api.close);

      await transport.get(
        Uri.parse('https://example.com/c/old.json'),
        siteUrl: 'https://example.com',
      );
      await transport.head(Uri.parse('https://example.com/probe'));
      await api.lookup('example.com');

      expect(
        [for (final request in sent) (request.method, request.url.path)],
        [
          ('GET', '/c/old.json'),
          ('GET', '/c/new.json'),
          ('HEAD', '/probe'),
          ('HEAD', '/user-api-key/new'),
          ('GET', '/site/basic-info.json'),
        ],
      );
      for (final request in sent) {
        expect(
          request.headers,
          containsPair('User-Agent', DiscourseApi.userAgent),
          reason: '${request.method} ${request.url}',
        );
        expect(
          request.headers,
          isNot(contains('User-Api-Key')),
          reason: '${request.method} ${request.url}',
        );
      }
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
        ChatApiClient(api).sendChatMessage(
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

    test('chat replies serialize the original message ID', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'message_id': 42}), 200);
        }),
      );

      expect(
        await ChatApiClient(api).sendChatMessage(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
          channelId: 9,
          message: 'A reply',
          inReplyToId: 7,
        ),
        42,
      );
      expect(sent.method, 'POST');
      expect(sent.url.path, '/chat/9.json');
      expect(jsonDecode(sent.body), {
        'message': 'A reply',
        'in_reply_to_id': 7,
      });
    });

    test(
      'chat sends serialize optimistic metadata and return the message ID',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(jsonEncode({'message_id': 42}), 200);
          }),
        );
        final clientCreatedAt = DateTime.parse('2026-08-11T16:15:16.123+02:00');

        final messageId = await ChatApiClient(api).sendChatMessage(
          siteUrl: 'https://example.com',
          apiKey: 'secret',
          clientId: 'client',
          channelId: 9,
          message: '',
          uploadIds: const [5, 9],
          threadId: 17,
          stagedId: 'staged-123',
          clientCreatedAt: clientCreatedAt,
          contextTopicId: 31,
          contextPostIds: const [101, 102, 103],
        );

        expect(messageId, 42);
        expect(sent.method, 'POST');
        expect(sent.url.path, '/chat/9.json');
        expect(jsonDecode(sent.body), {
          'message': '',
          'upload_ids': [5, 9],
          'thread_id': 17,
          'staged_id': 'staged-123',
          'client_created_at': '2026-08-11T14:15:16.123Z',
          'context_topic_id': 31,
          'context_post_ids': [101, 102, 103],
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

    test('writes preserve how many users a refused change reaches', () async {
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'user_count': 3,
                'errors': ['This change affects 3 existing group members.'],
              }),
              422,
            ),
          ),
        ),
        const Duration(seconds: 1),
        1024,
      );

      await expectLater(
        transport.write(
          Uri.parse('https://example.com/groups/7.json'),
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
              .having((error) => error.statusCode, 'statusCode', 422)
              .having(
                (error) => error.affectedUserCount,
                'affectedUserCount',
                3,
              ),
        ),
      );
    });
  });

  group('whether a failed write reached the site', () {
    final onDarwin = Platform.isMacOS || Platform.isIOS;
    OSError os(String message, {required int darwin, required int linux}) =>
        OSError(message, onDarwin ? darwin : linux);

    Future<WriteException> failedWrite(
      DiscourseTransport transport,
      Uri url,
    ) async {
      try {
        await transport.write(
          url,
          siteUrl: url.origin,
          method: 'POST',
          apiKey: 'secret',
          body: const {'message': 'hi'},
        );
      } on WriteException catch (error) {
        return error;
      }
      fail('The write succeeded.');
    }

    for (final (label, error, notSent) in <(String, Object, bool)>[
      (
        'a failed host lookup',
        const SocketException(
          "Failed host lookup: 'forum.invalid'",
          osError: OSError('nodename nor servname provided, or not known', 8),
        ),
        true,
      ),
      (
        'a refused connection',
        SocketException(
          'Connection refused',
          osError: os('Connection refused', darwin: 61, linux: 111),
        ),
        true,
      ),
      (
        'an unreachable network',
        SocketException(
          'Connection failed',
          osError: os('Network is unreachable', darwin: 51, linux: 101),
        ),
        true,
      ),
      (
        'an unreachable host',
        SocketException(
          'Connection failed',
          osError: os('No route to host', darwin: 65, linux: 113),
        ),
        true,
      ),
      (
        'a network that is down',
        SocketException(
          'Connection failed',
          osError: os('Network is down', darwin: 50, linux: 100),
        ),
        true,
      ),
      (
        'a failed TLS handshake',
        const HandshakeException('Handshake error in client'),
        true,
      ),
      (
        'a connection reset',
        SocketException(
          'Read failed',
          osError: os('Connection reset by peer', darwin: 54, linux: 104),
        ),
        false,
      ),
      (
        'a broken pipe',
        const SocketException(
          'Write failed',
          osError: OSError('Broken pipe', 32),
        ),
        false,
      ),
      (
        "another kernel's number for a refused connection",
        SocketException(
          'Connection failed',
          osError: os('Unrelated error', darwin: 111, linux: 61),
        ),
        false,
      ),
      (
        'a socket error without a code',
        const SocketException('offline'),
        false,
      ),
      (
        'a connection closed early',
        http.ClientException(
          'Connection closed before full header was received',
        ),
        false,
      ),
      ('a timeout', TimeoutException('Future not completed'), false),
    ]) {
      test(
        '${notSent ? 'is known unsent' : 'stays uncertain'} after $label',
        () async {
          final transport = DiscourseTransport(
            SafeHttpClient.owned(MockClient((_) async => throw error)),
            const Duration(seconds: 1),
            1024,
          );
          addTearDown(transport.close);

          final failure = await failedWrite(
            transport,
            Uri.parse('https://example.com/chat/9.json'),
          );

          expect(failure.failure, WriteFailure.unreachable);
          expect(failure.notSent, notSent);
          expect(failure.diagnosticCause, same(error));
        },
      );
    }

    test('is known unsent when the origin backlog refuses it', () async {
      final gate = Completer<void>();
      final started = <String>[];
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((request) async {
            started.add(request.url.path);
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
      final active = transport.get(
        Uri.parse('https://example.com/active.json'),
        siteUrl: 'https://example.com',
      );
      final queued = transport.get(
        Uri.parse('https://example.com/queued.json'),
        siteUrl: 'https://example.com',
      );
      await Future<void>.delayed(Duration.zero);

      final failure = await failedWrite(
        transport,
        Uri.parse('https://example.com/overflow.json'),
      );

      expect(failure.notSent, isTrue);
      expect(failure.diagnosticCause, isA<DiscourseRequestOverloadException>());
      gate.complete();
      await Future.wait([active, queued]);
      expect(started, ['/active.json', '/queued.json']);
    });

    test('is classified from what the real socket stack raises', () async {
      final transport = DiscourseTransport.create();
      addTearDown(transport.close);

      final vacated = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = vacated.port;
      await vacated.close();
      final refused = await failedWrite(
        transport,
        Uri.parse('http://127.0.0.1:$closedPort/chat/9.json'),
      );
      expect(refused.diagnosticCause, isA<SocketException>());
      expect(refused.notSent, isTrue);

      // The site read the whole request before the connection dropped: it
      // may have been applied, so nothing may say it was not.
      final reader = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(reader.close);
      final received = Completer<void>();
      reader.listen((socket) {
        final request = <int>[];
        socket.listen((bytes) {
          request.addAll(bytes);
          if (utf8.decode(request, allowMalformed: true).endsWith('"hi"}')) {
            if (!received.isCompleted) received.complete();
            socket.destroy();
          }
        });
      });
      final dropped = await failedWrite(
        transport,
        Uri.parse('http://127.0.0.1:${reader.port}/chat/9.json'),
      );
      expect(received.isCompleted, isTrue);
      expect(dropped.failure, WriteFailure.unreachable);
      expect(dropped.notSent, isFalse);
    });
  });
}
