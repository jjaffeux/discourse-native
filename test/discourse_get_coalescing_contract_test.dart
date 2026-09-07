import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/site_appearance_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/manual_scheduler.dart';

void main() {
  group('GET representation sharing', () {
    for (final accept in [null, 'application/json']) {
      for (final htmlFirst in [true, false]) {
        test(
          'isolates Accept=$accept from HTML, HTML first=$htmlFirst',
          () async {
            final release = Completer<void>();
            addTearDown(() {
              if (!release.isCompleted) release.complete();
            });
            final requested = <String?>[];
            final transport = DiscourseTransport.create(
              client: MockClient((request) async {
                final representation = request.headers['accept'];
                requested.add(representation);
                await release.future;
                return http.Response(representation ?? 'default', 200);
              }),
            );
            addTearDown(transport.close);

            Future<http.Response> read(String? representation) => transport.get(
              Uri.https('forum.example', '/'),
              siteUrl: 'https://forum.example',
              apiKey: 'secret',
              clientId: 'client',
              accept: representation,
            );

            final representations = htmlFirst
                ? ['text/html', accept]
                : [accept, 'text/html'];
            final results = [for (final value in representations) read(value)];
            await Future<void>.delayed(Duration.zero);
            release.complete();

            expect(
              (await Future.wait(results)).map((response) => response.body),
              representations.map((value) => value ?? 'default'),
            );
            expect(requested, representations);
          },
        );
      }
    }

    test('isolates API keys, client IDs, and anonymous reads', () async {
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final requested = <(String?, String?)>[];
      final transport = DiscourseTransport.create(
        client: MockClient((request) async {
          final credentials = (
            request.headers['user-api-key'],
            request.headers['user-api-client-id'],
          );
          requested.add(credentials);
          await release.future;
          return http.Response('${credentials.$1}/${credentials.$2}', 200);
        }),
      );
      addTearDown(transport.close);
      const credentials = [
        (null, null),
        ('first-key', 'first-client'),
        ('second-key', 'first-client'),
        ('first-key', 'second-client'),
      ];

      final results = [
        for (final (key, client) in credentials)
          transport.get(
            Uri.https('forum.example', '/site.json'),
            siteUrl: 'https://forum.example',
            apiKey: key,
            clientId: client,
            accept: 'application/json',
          ),
      ];
      await Future<void>.delayed(Duration.zero);
      release.complete();

      expect(
        (await Future.wait(results)).map((response) => response.body),
        credentials.map((value) => '${value.$1}/${value.$2}'),
      );
      expect(requested, credentials);
    });
  });

  for (final appearance in [false, true]) {
    group('${appearance ? 'appearance' : 'transport'} GET policy sharing', () {
      for (final strictFirst in [true, false]) {
        test('enforces each byte limit, strict first=$strictFirst', () async {
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          final body = '${' ' * 64}{}';
          var requests = 0;
          final client = MockClient((request) async {
            requests++;
            await release.future;
            return http.Response(body, 200);
          });
          addTearDown(client.close);
          final coordinator = DiscourseRequestCoordinator();
          addTearDown(coordinator.close);

          Future<Object?> read(int maxBytes) => _capture(
            _readMetadata(
              client,
              coordinator,
              appearance: appearance,
              maxBytes: maxBytes,
            ),
          );

          final limits = strictFirst ? [8, 1024] : [1024, 8];
          final results = [for (final limit in limits) read(limit)];
          await Future<void>.delayed(Duration.zero);
          release.complete();
          final outcomes = await Future.wait(results);

          expect(
            outcomes[limits.indexOf(8)],
            appearance
                ? _appearanceFailure(SiteAppearanceLoadFailure.responseTooLarge)
                : isA<SiteLookupException>().having(
                    (error) => error.diagnosticCause,
                    'diagnosticCause',
                    isA<HttpResponseTooLargeException>().having(
                      (error) => error.maxBytes,
                      'maxBytes',
                      8,
                    ),
                  ),
          );
          expect(
            outcomes[limits.indexOf(1024)],
            appearance
                ? isNull
                : isA<http.Response>().having(
                    (value) => value.body,
                    'body',
                    body,
                  ),
          );
          expect(requests, 2);
        });

        test('enforces each deadline, strict first=$strictFirst', () async {
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          var requests = 0;
          final client = MockClient((request) async {
            requests++;
            await release.future;
            return http.Response('{}', 200);
          });
          addTearDown(client.close);
          final coordinator = DiscourseRequestCoordinator();
          addTearDown(coordinator.close);
          final scheduler = ManualScheduler();
          var relaxedCompleted = false;

          Future<Object?> read(int minutes) => runZoned(
            () =>
                _capture(
                  _readMetadata(
                    client,
                    coordinator,
                    appearance: appearance,
                    timeout: Duration(minutes: minutes),
                  ),
                ).then((value) {
                  if (minutes == 2) relaxedCompleted = true;
                  return value;
                }),
            zoneSpecification: ZoneSpecification(
              createTimer: (self, parent, zone, duration, callback) =>
                  scheduler.createTimer(duration, zone.bindCallback(callback)),
            ),
          );

          final deadlines = strictFirst ? [1, 2] : [2, 1];
          final results = [for (final minutes in deadlines) read(minutes)];
          await Future<void>.delayed(Duration.zero);
          scheduler.advance(const Duration(minutes: 1));
          await Future<void>.delayed(Duration.zero);
          final completedAtDeadline = relaxedCompleted;
          release.complete();
          final outcomes = await Future.wait(results);

          expect(
            outcomes[deadlines.indexOf(1)],
            appearance
                ? _appearanceFailure(SiteAppearanceLoadFailure.timedOut)
                : isA<SiteLookupException>().having(
                    (error) => error.diagnosticCause,
                    'diagnosticCause',
                    isA<TimeoutException>(),
                  ),
          );
          expect(completedAtDeadline, isFalse);
          expect(
            outcomes[deadlines.indexOf(2)],
            appearance
                ? isNull
                : isA<http.Response>().having(
                    (value) => value.body,
                    'body',
                    '{}',
                  ),
          );
          expect(requests, 2);
        });
      }
    });
  }
}

Future<Object?> _readMetadata(
  http.Client client,
  DiscourseRequestCoordinator coordinator, {
  required bool appearance,
  int maxBytes = 1024,
  Duration timeout = const Duration(minutes: 1),
}) {
  if (appearance) {
    return SiteAppearanceLoader(
      client: client,
      coordinator: coordinator,
      maxResponseBytes: maxBytes,
      timeout: timeout,
    ).load(siteUrl: 'https://forum.example');
  }
  return DiscourseTransport(
    SafeHttpClient.borrowed(client),
    timeout,
    maxBytes,
    coordinator: coordinator,
  ).get(
    Uri.https('forum.example', '/site.json'),
    siteUrl: 'https://forum.example',
    accept: 'application/json',
  );
}

Future<Object?> _capture(Future<Object?> result) =>
    result.then((value) => value, onError: (Object error) => error);

Matcher _appearanceFailure(SiteAppearanceLoadFailure failure) =>
    isA<SiteAppearanceLoadException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );
