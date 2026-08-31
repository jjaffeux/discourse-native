import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/foundation/diagnostic_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiagnosticsRedactor', () {
    test('retains URI shape but never URI secrets', () {
      final safe = DiagnosticsRedactor.uri(
        'https://name:password@example.com/t/42.json?api_key=SECRET&'
        'page=4&page=5#private-fragment',
      );

      expect(safe, 'https://example.com/t/42.json?api_key&page&page');
      expect(safe, isNot(contains('password')));
      expect(safe, isNot(contains('SECRET')));
      expect(safe, isNot(contains('private-fragment')));
      expect(safe, isNot(contains('=4')));
    });

    test('malformed query encoding is redacted without throwing', () {
      expect(
        DiagnosticsRedactor.uri('https://example.com/t/1?%ZZ=SECRET#private'),
        'https://example.com/t/1?invalid-query-name',
      );
    });

    test('drops a query value whose separator is percent-encoded', () {
      const secret = 'ENCODED_SEPARATOR_SECRET_SENTINEL';
      final safe = DiagnosticsRedactor.uri(
        'https://x.com/cb?code%3D$secret&state=STATE_VALUE_SENTINEL',
      );

      expect(safe, 'https://x.com/cb?code&state');
      expect(safe, isNot(contains(secret)));
      expect(safe, isNot(contains(Uri.encodeQueryComponent(secret))));
      expect(safe, isNot(contains('STATE_VALUE_SENTINEL')));
    });

    test(
      'redacts credentials before truncating or recovering malformed URIs',
      () {
        const oversizedSecret = 'OVERSIZED_PASSWORD_SENTINEL';
        const malformedSecret = 'SLASH_BEFORE_AT_PASSWORD_SENTINEL';
        final oversizedPassword =
            '$oversizedSecret${'x'.padRight(DiagnosticsRedactor.maximumStringLength, 'x')}';

        final oversized = DiagnosticsRedactor.uri(
          'https://reader:$oversizedPassword@example.com/t/42?token=private',
        );
        final malformed = DiagnosticsRedactor.uri(
          'https://reader:$malformedSecret/broken@authority.example/t/42'
          '?token=private',
        );

        expect(oversized, 'https://example.com/t/42?token');
        expect(malformed, contains('<redacted-malformed-uri>'));
        expect(oversized, isNot(contains(oversizedSecret)));
        expect(malformed, isNot(contains(malformedSecret)));
        expect(malformed, isNot(contains('private')));
      },
    );

    test('allows only safe response metadata', () {
      final safe = DiagnosticsRedactor.responseHeaders({
        'Content-Type': ['application/json'],
        'X-Request-ID': ['request-123'],
        'Set-Cookie': ['session=SECRET'],
        'Authorization': ['Bearer SECRET'],
      });

      expect(safe, {
        'content-type': ['application/json'],
        'x-request-id': ['request-123'],
      });
      expect(
        () => safe['content-type']!.add('text/plain'),
        throwsUnsupportedError,
      );
    });

    test('scrubs URLs, authorization values, and home paths from errors', () {
      const secret = 'highly-secret-token';
      const home = '/Users/private-person';
      final safe = DiagnosticsRedactor.scrub(
        'GET https://user:pass@example.com/path?token=$secret#fragment\n'
        'Authorization: Bearer $secret\n'
        'Cookie: session=$secret\n'
        '$home/project/file.dart:12',
        homeDirectory: home,
      );

      expect(safe, contains('https://example.com/path?token'));
      expect(safe, contains('Authorization=<redacted>'));
      expect(safe, contains('Cookie=<redacted>'));
      expect(safe, contains('<home>/project/file.dart'));
      expect(safe, isNot(contains(secret)));
      expect(safe, isNot(contains('user:pass')));
      expect(safe, isNot(contains('fragment')));
    });

    test('scrubs secrets assigned through quoted JSON keys', () {
      const secret = 'QUOTED_JSON_SECRET_SENTINEL';
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.'
          'abcdefghijklmnop';
      final safe = DiagnosticsRedactor.scrub(
        '{"api_key":"$secret","credential":"$secret",'
        '"token":"$secret","sdp":"a=ice-pwd:$secret",'
        '"ice_ufrag":"$secret","client_id":"$secret",'
        '"vendor":"$jwt"}',
      );

      expect(safe, isNot(contains(secret)));
      expect(safe, isNot(contains(jwt)));
      expect(safe, contains('api_key=<redacted>'));
      expect(safe, contains('credential=<redacted>'));
      expect(safe, contains('token=<redacted>'));
      expect(safe, contains('ice-pwd=<redacted>'));
      expect(safe, contains('ice_ufrag=<redacted>'));
      expect(safe, contains('client_id=<redacted>'));
      expect(safe, contains('<redacted-jwt>'));
    });

    test('scrubs quoted secrets containing escaped quote characters', () {
      const secret = 'ESCAPED_QUOTE_SECRET_SENTINEL';
      final safe = DiagnosticsRedactor.scrub(
        r'''{"credential":"prefix\"ESCAPED_QUOTE_SECRET_SENTINEL",'''
        r'''"api_key":'prefix\'ESCAPED_QUOTE_SECRET_SENTINEL'}''',
      );

      expect(safe, isNot(contains(secret)));
      expect(safe, contains('credential=<redacted>'));
      expect(safe, contains('api_key=<redacted>'));
    });

    test('scrubs credentials from absolute URIs under every scheme', () {
      const credential = 'FTP_PASSWORD_SENTINEL';
      const queryValue = 'FTP_QUERY_SENTINEL';
      final safe = DiagnosticsRedactor.scrub(
        'redirect ftp://alice:$credential@example.test/archive'
        '?token=$queryValue#private',
      );

      expect(safe, contains('ftp://example.test/archive?token'));
      expect(safe, isNot(contains(credential)));
      expect(safe, isNot(contains(queryValue)));
      expect(safe, isNot(contains('alice')));
    });

    test('scrubs credentials from scheme-relative URLs', () {
      const secret = 'SCHEME_RELATIVE_SECRET_SENTINEL';
      final safe = DiagnosticsRedactor.scrub(
        'socket error //user:$secret@x.com/a?token=QUERY_VALUE_SENTINEL',
      );

      expect(safe, contains('socket error //x.com/a?token'));
      expect(safe, isNot(contains(secret)));
      expect(safe, isNot(contains('user:')));
      expect(safe, isNot(contains('QUERY_VALUE_SENTINEL')));
    });

    test('redacts malformed scheme-relative authorities as a unit', () {
      const secret = 'SCHEME_RELATIVE_MALFORMED_SENTINEL';
      final safe = DiagnosticsRedactor.scrub(
        'redirect //user:$secret/broken@authority.example/a'
        '?token=QUERY_VALUE_SENTINEL',
      );

      expect(safe, contains('//<redacted-malformed-uri>'));
      expect(safe, isNot(contains(secret)));
      expect(safe, isNot(contains('QUERY_VALUE_SENTINEL')));
    });

    test('keeps non-URL double-slash text legible', () {
      final safe = DiagnosticsRedactor.scrub(
        '#0 main (file:///app/main.dart:1:1)\n'
        'note: retry disabled // scheduler paused\n'
        'ratio 50 m//s stays',
      );

      expect(safe, contains('(file:///app/main.dart:1:1)'));
      expect(safe, contains('retry disabled // scheduler paused'));
      expect(safe, contains('ratio 50 m//s stays'));
    });
  });

  group('DiagnosticLogEvent', () {
    test('recursively sanitizes and freezes structured attributes', () {
      const secret = 'STRUCTURED_LOG_SECRET_SENTINEL';
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      final timestamp = DateTime.utc(2026, 8, 8, 9);
      final event = DiagnosticLogEvent(
        id: 'log-1',
        sessionId: 'session-1',
        sequence: 1,
        timestampUtc: timestamp,
        updatedAtUtc: timestamp,
        severity: DiagnosticSeverity.info,
        source: 'resenha',
        name: 'peer.connected',
        component: 'mesh',
        message:
            'connected to https://user:pass@example.test/room?token=$secret',
        attributes: {
          'participant': {
            'id': 42,
            'username': 'reader',
            'authorization': 'Bearer $secret',
          },
          'candidate': ['udp', 'https://example.test/ice?credential=$secret'],
          'clientId': secret,
          'cyclic': cyclic,
          'elapsed': const Duration(milliseconds: 12),
        },
      );

      final participant =
          event.attributes['participant']! as Map<String, Object?>;
      final candidate = event.attributes['candidate']! as List<Object?>;
      final serialized = jsonEncode(event.toJson());

      expect(event.kind, DiagnosticEventKind.log);
      expect(event.isError, isFalse);
      expect(participant['id'], 42);
      expect(participant['username'], 'reader');
      expect(participant['authorization'], '<redacted>');
      expect(event.attributes['clientId'], '<redacted>');
      expect(candidate[1], 'https://example.test/ice?credential');
      expect(
        (event.attributes['cyclic']! as Map<String, Object?>)['self'],
        '<cyclic value>',
      );
      expect(event.attributes['elapsed'], 12000);
      expect(event.message, 'connected to https://example.test/room?token');
      expect(serialized, isNot(contains(secret)));
      expect(serialized, isNot(contains('user:pass')));
      expect(() => event.attributes['later'] = true, throwsUnsupportedError);
      expect(() => participant['later'] = true, throwsUnsupportedError);
      expect(() => candidate.add('later'), throwsUnsupportedError);
    });

    test('round-trips logs and accepts absent optional log fields', () {
      final timestamp = DateTime.utc(2026, 8, 8, 9);
      final event = DiagnosticLogEvent(
        id: 'log-2',
        sessionId: 'session-1',
        sequence: 2,
        timestampUtc: timestamp,
        updatedAtUtc: timestamp,
        severity: DiagnosticSeverity.warning,
        source: 'resenha',
        name: 'reconnect.scheduled',
        attributes: const {
          'attempt': 2,
          'delays': [0, 1000, 2000],
        },
      );

      final decoded = DiagnosticEvent.fromJson(event.toJson());
      expect(decoded, isA<DiagnosticLogEvent>());
      expect((decoded! as DiagnosticLogEvent).toJson(), event.toJson());

      final minimal = Map<String, Object?>.of(event.toJson())
        ..remove('attributes');
      final minimalDecoded =
          DiagnosticEvent.fromJson(minimal)! as DiagnosticLogEvent;
      expect(minimalDecoded.attributes, isEmpty);
      expect(minimalDecoded.component, isNull);
      expect(minimalDecoded.message, isNull);

      expect(
        DiagnosticEvent.fromJson({...event.toJson(), 'kind': 'future-kind'}),
        isNull,
      );
    });
  });

  group('DiagnosticsController', () {
    late DateTime now;
    late MemoryDiagnosticsPersistence persistence;
    late DiagnosticsController controller;

    setUp(() async {
      now = DateTime.utc(2026, 8, 8, 9);
      persistence = MemoryDiagnosticsPersistence();
      controller = await DiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        sessionId: 'current-session',
      );
    });

    tearDown(() async {
      await controller.close();
    });

    test(
      'keeps events, panel state, and unseen errors independently listenable',
      () {
        var eventNotifications = 0;
        var panelNotifications = 0;
        var unseenNotifications = 0;
        controller.eventsListenable.addListener(() => eventNotifications += 1);
        controller.panelStateListenable.addListener(
          () => panelNotifications += 1,
        );
        controller.unseenErrorCountListenable.addListener(
          () => unseenNotifications += 1,
        );

        controller.reportError(
          StateError('topic did not load'),
          StackTrace.current,
          operation: 'topic.load',
          source: 'topic',
        );

        expect(eventNotifications, 1);
        expect(panelNotifications, 0);
        expect(unseenNotifications, 1);
        expect(controller.unseenErrorCountListenable.value, 1);

        controller.openPanel();

        expect(panelNotifications, 1);
        expect(controller.unseenErrorCountListenable.value, 0);
      },
    );

    test('captures the intermediate HTTP phase only for a live panel', () {
      expect(controller.recordsHttpResponseHeaderPhase, isFalse);

      controller.openPanel();
      expect(controller.recordsHttpResponseHeaderPhase, isTrue);

      controller.closePanel();
      expect(controller.recordsHttpResponseHeaderPhase, isFalse);
    });

    test(
      'inherits operation and correlation through asynchronous zones',
      () async {
        await DiagnosticsSink.runOperation('topic.load', () async {
          await Future<void>.delayed(Duration.zero);
          controller.reportError(StateError('timeout'), StackTrace.current);
        }, correlationId: 'topic-42');

        final event = controller.events
            .whereType<ErrorDiagnosticEvent>()
            .single;
        expect(event.operation, 'topic.load');
        expect(event.correlationId, 'topic-42');
      },
    );

    test('records, filters, persists, and exports structured logs', () async {
      const secret = 'CONTROLLER_LOG_SECRET_SENTINEL';
      final binding = DiagnosticsSink.install(controller);
      try {
        await DiagnosticsSink.runOperation('resenha.join', () async {
          await Future<void>.delayed(Duration.zero);
          DiagnosticsSink.current.recordLog(
            name: 'peer.connected',
            source: 'resenha',
            component: 'mesh',
            message: 'connected',
            attributes: {
              'participantId': 42,
              'endpoint': 'https://reader:pass@turn.example.test?token=$secret',
              'accessToken': secret,
            },
          );
        }, correlationId: 'resenha-call-42');
      } finally {
        binding.close();
      }

      final log = controller.events.whereType<DiagnosticLogEvent>().single;
      expect(log.operation, 'resenha.join');
      expect(log.correlationId, 'resenha-call-42');
      expect(log.component, 'mesh');
      expect(log.attributes['accessToken'], '<redacted>');

      controller.setQuery('turn.example.test');
      expect(controller.visibleEvents, [log]);
      controller.setKindFilter(DiagnosticsKindFilter.requests);
      expect(controller.visibleEvents, isEmpty);
      controller.setKindFilter(DiagnosticsKindFilter.errors);
      expect(controller.visibleEvents, isEmpty);
      controller
        ..setKindFilter(DiagnosticsKindFilter.all)
        ..setQuery('');

      controller.recordLog(
        name: 'peer.failed',
        source: 'resenha',
        component: 'mesh',
        severity: DiagnosticSeverity.error,
        degraded: true,
      );
      controller.setKindFilter(DiagnosticsKindFilter.errors);
      expect(controller.visibleEvents, hasLength(1));
      expect(controller.visibleEvents.single, isA<DiagnosticLogEvent>());

      final report = controller.buildJsonReport(controller.events);
      expect(report, contains('reported structured application logs'));
      expect(report, contains('peer.connected'));
      expect(report, contains('resenha-call-42'));
      expect(report, isNot(contains(secret)));
      expect(report, isNot(contains('reader:pass')));

      await controller.flush();
      final stored = await persistence.load(nowUtc: now);
      expect(stored.events.whereType<DiagnosticLogEvent>(), hasLength(2));
    });

    test(
      'the process-wide sink has a no-op fallback and restorable binding',
      () {
        expect(
          () => DiagnosticsSink.current.reportError(
            StateError('ignored'),
            StackTrace.current,
          ),
          returnsNormally,
        );
        final before = DiagnosticsSink.current;
        final binding = DiagnosticsSink.install(controller);
        expect(DiagnosticsSink.current, same(controller));

        DiagnosticsSink.current.reportError(
          StateError('recorded'),
          StackTrace.current,
        );
        binding.close();

        expect(DiagnosticsSink.current, same(before));
        expect(
          controller.events.whereType<ErrorDiagnosticEvent>(),
          hasLength(1),
        );
      },
    );

    test(
      'a fixed plugin reporter keeps its sink and operation correlation',
      () async {
        final ambient = await DiagnosticsController.create(
          persistence: MemoryDiagnosticsPersistence(),
          sessionId: 'ambient-plugin-reporter',
        );
        final binding = DiagnosticsSink.install(ambient);
        addTearDown(() async {
          binding.close();
          await ambient.close();
        });
        final reporter = PluginDiagnosticsReporter.fixed(controller);

        await reporter.runOperation('plugin.refresh', () async {
          await Future<void>.delayed(Duration.zero);
          expect(reporter.currentOperation, 'plugin.refresh');
          expect(reporter.currentCorrelationId, 'plugin-correlation');
          reporter.recordLog(name: 'plugin.refreshed', source: 'test-plugin');
        }, correlationId: 'plugin-correlation');

        final event = controller.events.whereType<DiagnosticLogEvent>().single;
        expect(event.operation, 'plugin.refresh');
        expect(event.correlationId, 'plugin-correlation');
        expect(ambient.events.whereType<DiagnosticLogEvent>(), isEmpty);
      },
    );

    test(
      'a fixed plugin reporter preserves clear generation isolation',
      () async {
        final reporter = PluginDiagnosticsReporter.fixed(controller);
        final started = Completer<void>();
        final release = Completer<void>();
        final oldOperation = reporter.runOperation('plugin.old-work', () async {
          started.complete();
          await release.future;
          reporter.reportError(StateError('stale failure'), StackTrace.current);
        });
        await started.future;

        await controller.clear();
        release.complete();
        await oldOperation;

        expect(controller.events, isEmpty);
      },
    );

    test('folds HTTP updates by ID and classifies HTTP failures as errors', () {
      controller.recordHttp(_httpRecord(now, HttpDiagnosticPhase.started));
      now = now.add(const Duration(milliseconds: 125));
      controller.recordHttp(
        _httpRecord(
          now,
          HttpDiagnosticPhase.completed,
          statusCode: 503,
          receivedBytes: 512,
        ),
      );

      final requests = controller.events.whereType<HttpDiagnosticEvent>();
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.state, DiagnosticHttpState.completed);
      expect(request.statusCode, 503);
      expect(request.totalDuration, const Duration(milliseconds: 125));
      expect(request.receivedBytes, 512);
      expect(request.isError, isTrue);
      expect(controller.unseenErrorCountListenable.value, 1);
    });

    test('terminal HTTP folds do not re-badge a seen error', () {
      controller.recordHttp(_httpRecord(now, HttpDiagnosticPhase.started));
      final initialSequence = controller.events
          .whereType<HttpDiagnosticEvent>()
          .single
          .sequence;

      now = now.add(const Duration(milliseconds: 50));
      controller.recordHttp(
        _httpRecord(now, HttpDiagnosticPhase.responseHeaders, statusCode: 503),
      );
      final errorSequence = controller.events
          .whereType<HttpDiagnosticEvent>()
          .single
          .sequence;
      expect(errorSequence, greaterThan(initialSequence));
      expect(controller.unseenErrorCountListenable.value, 1);
      controller.openPanel();
      controller.closePanel();
      expect(controller.unseenErrorCountListenable.value, 0);

      now = now.add(const Duration(milliseconds: 75));
      controller.recordHttp(
        _httpRecord(now, HttpDiagnosticPhase.completed, statusCode: 503),
      );

      final completed = controller.events
          .whereType<HttpDiagnosticEvent>()
          .single;
      expect(completed.sequence, errorSequence);
      expect(completed.state, DiagnosticHttpState.completed);
      expect(controller.unseenErrorCountListenable.value, 0);
    });

    test('a later body transport failure becomes newly unseen', () {
      controller.recordHttp(
        _httpRecord(now, HttpDiagnosticPhase.started, eventId: 'body-failure'),
      );
      now = now.add(const Duration(milliseconds: 50));
      controller.recordHttp(
        _httpRecord(
          now,
          HttpDiagnosticPhase.responseHeaders,
          eventId: 'body-failure',
          statusCode: 200,
        ),
      );
      final successfulHeaderSequence = controller.events
          .whereType<HttpDiagnosticEvent>()
          .single
          .sequence;

      controller.reportError(
        StateError('unrelated and already seen'),
        StackTrace.current,
      );
      final previouslySeenSequence = controller.events
          .whereType<ErrorDiagnosticEvent>()
          .single
          .sequence;
      expect(previouslySeenSequence, greaterThan(successfulHeaderSequence));
      controller.openPanel();
      controller.closePanel();

      now = now.add(const Duration(milliseconds: 75));
      controller.recordHttp(
        _httpRecord(
          now,
          HttpDiagnosticPhase.failed,
          eventId: 'body-failure',
          statusCode: 200,
          errorType: 'SocketException',
        ),
      );

      final failed = controller.events.whereType<HttpDiagnosticEvent>().single;
      expect(failed.sequence, greaterThan(previouslySeenSequence));
      expect(failed.state, DiagnosticHttpState.failed);
      expect(controller.unseenErrorCountListenable.value, 1);
    });

    test('freeze and filters retain a stable visible snapshot', () {
      controller.reportError(
        StateError('first'),
        StackTrace.current,
        source: 'topic',
        severity: DiagnosticSeverity.warning,
      );
      controller.setKindFilter(DiagnosticsKindFilter.errors);
      controller.setSources({'topic'});
      controller.setQuery('first');
      controller.setFrozen(true);
      expect(controller.visibleEvents, hasLength(1));

      controller.reportError(
        StateError('second'),
        StackTrace.current,
        source: 'topic',
        severity: DiagnosticSeverity.warning,
      );
      expect(controller.visibleEvents, hasLength(1));

      controller.setFrozen(false);
      controller.setQuery('');
      expect(controller.visibleEvents, hasLength(2));
    });

    test('errors hidden by a frozen panel remain unseen until it resumes', () {
      controller.openPanel();
      controller.setFrozen(true);

      controller.reportError(
        StateError('arrived while frozen'),
        StackTrace.current,
      );

      expect(
        controller.visibleEvents.whereType<ErrorDiagnosticEvent>(),
        isEmpty,
      );
      expect(controller.unseenErrorCountListenable.value, 1);

      controller
        ..closePanel()
        ..openPanel();
      expect(controller.unseenErrorCountListenable.value, 1);

      controller.setFrozen(false);
      expect(
        controller.visibleEvents.whereType<ErrorDiagnosticEvent>(),
        hasLength(1),
      );
      expect(controller.unseenErrorCountListenable.value, 0);
    });

    test(
      'clear prevents old in-flight HTTP updates from reappearing',
      () async {
        controller.recordHttp(_httpRecord(now, HttpDiagnosticPhase.started));
        await controller.clear();

        now = now.add(const Duration(seconds: 1));
        controller.recordHttp(
          _httpRecord(now, HttpDiagnosticPhase.completed, statusCode: 200),
        );
        await controller.flush();

        expect(controller.events, isEmpty);
        expect((await persistence.load(nowUtc: now)).events, isEmpty);
      },
    );

    test('clear prevents an old operation error from reappearing', () async {
      final binding = DiagnosticsSink.install(controller);
      addTearDown(binding.close);
      final started = Completer<void>();
      final release = Completer<void>();
      final oldOperation = DiagnosticsSink.runOperation('topic.load', () async {
        started.complete();
        await release.future;
        controller.reportError(
          TimeoutException('old topic timeout'),
          StackTrace.current,
        );
      });
      await started.future;

      await controller.clear();
      release.complete();
      await oldOperation;

      expect(controller.events.whereType<ErrorDiagnosticEvent>(), isEmpty);
    });

    test('reports safely even when an error cannot be stringified', () {
      expect(
        () => controller.reportError(_HostileError(), StackTrace.current),
        returnsNormally,
      );
      final event = controller.events.whereType<ErrorDiagnosticEvent>().single;
      expect(event.message, contains('<unprintable'));
    });

    test('never retains a FormatException source', () {
      const secret = 'SECRET_RESPONSE_BODY_SENTINEL';
      controller.reportError(
        const FormatException('invalid response JSON', secret, 17),
        StackTrace.current,
      );

      final event = controller.events.whereType<ErrorDiagnosticEvent>().single;
      final serialized = jsonEncode(event.toJson());
      expect(event.message, 'invalid response JSON (offset 17)');
      expect(event.toString(), isNot(contains(secret)));
      expect(serialized, isNot(contains(secret)));
      expect(controller.buildJsonReport(), isNot(contains(secret)));
    });

    test('never retains a bare credentialed site lookup term', () {
      const secret = 'bare-site-password-sentinel';
      controller.reportError(
        const SiteLookupException(
          SiteLookupFailure.unreachable,
          'reader:$secret@forum.example',
          statusCode: 503,
        ),
        StackTrace.current,
        operation: 'site.add',
      );

      final event = controller.events.whereType<ErrorDiagnosticEvent>().single;
      expect(
        event.message,
        'SiteLookupException(SiteLookupFailure.unreachable, statusCode: 503)',
      );
      expect(event.toString(), isNot(contains(secret)));
      expect(controller.buildJsonReport(), isNot(contains(secret)));
    });

    test('never retains write validation response text', () {
      const secret = 'write-response-body-sentinel';
      controller.reportError(
        const WriteException(
          WriteFailure.validation,
          errors: [secret],
          statusCode: 422,
        ),
        StackTrace.current,
        operation: 'composer.submit',
      );

      final event = controller.events.whereType<ErrorDiagnosticEvent>().single;
      expect(event.message, contains('WriteFailure.validation'));
      expect(event.toString(), isNot(contains(secret)));
      expect(controller.buildJsonReport(), isNot(contains(secret)));
    });

    test('never retains auth or updater implementation details', () {
      const authSecret = 'auth-plugin-detail-sentinel';
      const updaterSecret = 'update-manifest-detail-sentinel';
      controller.reportError(
        const UserApiAuthException(UserApiAuthFailure.launchFailed, authSecret),
        StackTrace.current,
        operation: 'authentication.connect',
      );
      controller.reportError(
        const UpdateException(UpdateFailure.malformed, updaterSecret),
        StackTrace.current,
        operation: 'updater.check',
      );

      final report = controller.buildJsonReport();
      expect(report, contains('UserApiAuthFailure.launchFailed'));
      expect(report, contains('UpdateFailure.malformed'));
      expect(report, isNot(contains(authSecret)));
      expect(report, isNot(contains(updaterSecret)));
    });

    test('never retains oversized or malformed authority credentials', () {
      const oversizedSecret = 'EVENT_OVERSIZED_PASSWORD_SENTINEL';
      const malformedSecret = 'EVENT_SLASH_PASSWORD_SENTINEL';
      final oversizedPassword =
          '$oversizedSecret${'x'.padRight(DiagnosticsRedactor.maximumStringLength, 'x')}';
      controller.reportError(
        StateError(
          'GET https://reader:$oversizedPassword@example.com/t/42?token=private',
        ),
        StackTrace.current,
      );
      controller.reportError(
        StateError(
          'GET https://reader:$malformedSecret/broken@authority.example/t/42'
          '?token=private',
        ),
        StackTrace.current,
      );

      final events = controller.events.whereType<ErrorDiagnosticEvent>();
      final serialized = jsonEncode([
        for (final event in events) event.toJson(),
      ]);
      final rendered = events.map((event) => event.toString()).join('\n');
      final report = controller.buildJsonReport();
      for (final secret in [oversizedSecret, malformedSecret]) {
        expect(serialized, isNot(contains(secret)));
        expect(rendered, isNot(contains(secret)));
        expect(report, isNot(contains(secret)));
      }
    });

    test('never retains a credentialed non-HTTP redirect URI', () {
      const credential = 'EVENT_FTP_PASSWORD_SENTINEL';
      const queryValue = 'EVENT_FTP_QUERY_SENTINEL';
      controller.reportError(
        StateError(
          'redirect ftp://alice:$credential@example.test/archive'
          '?token=$queryValue#private',
        ),
        StackTrace.current,
      );

      final event = controller.events.whereType<ErrorDiagnosticEvent>().single;
      final serialized = jsonEncode(event.toJson());
      final report = controller.buildJsonReport();
      for (final secret in [credential, queryValue]) {
        expect(event.toString(), isNot(contains(secret)));
        expect(serialized, isNot(contains(secret)));
        expect(report, isNot(contains(secret)));
      }
    });

    test('deduplicates the same error crossing adjacent terminal handlers', () {
      final error = StateError('reported by framework and zone');
      controller.reportError(error, StackTrace.current, source: 'framework');
      controller.reportError(error, StackTrace.current, source: 'zone');
      controller.reportError(
        StateError('a distinct failure'),
        StackTrace.current,
        source: 'zone',
      );

      expect(controller.events.whereType<ErrorDiagnosticEvent>(), hasLength(2));
    });

    test('the same exception can be reported by a later operation', () async {
      final error = StateError('reusable failure object');
      controller.reportError(error, StackTrace.current, operation: 'first');
      await Future<void>.delayed(Duration.zero);
      controller.reportError(error, StackTrace.current, operation: 'second');

      expect(controller.events.whereType<ErrorDiagnosticEvent>(), hasLength(2));
    });

    test('an image fallback reports its cached exception only once', () {
      final binding = DiagnosticsSink.install(controller);
      addTearDown(binding.close);
      final error = StateError('cached image decode failed');

      reportImageError(error, StackTrace.current);
      reportImageError(error, StackTrace.current);

      expect(controller.events.whereType<ErrorDiagnosticEvent>(), hasLength(1));
    });

    test('exported reports contain only the sanitized representation', () {
      const secret = 'secret-query-value';
      controller.recordHttp(
        HttpDiagnosticRecord(
          eventId: 'private-request',
          phase: HttpDiagnosticPhase.started,
          timestamp: now,
          method: 'GET',
          uri: Uri.parse('https://user:pass@example.com/t/1?token=$secret'),
          sentBytes: 0,
          receivedBytes: 0,
        ),
      );
      controller.setQuery('a pasted $secret');

      final report = controller.buildJsonReport(controller.events);
      final decoded = jsonDecode(report) as Map<String, Object?>;
      expect(decoded['version'], 1);
      expect(decoded['scope'], isA<Map<String, Object?>>());
      expect(report, contains('https://example.com/t/1?token'));
      expect(report, contains('"hasQuery": true'));
      expect(report, isNot(contains(secret)));
      expect(report, isNot(contains('a pasted')));
      expect(report, isNot(contains('user:pass')));
    });
  });

  test(
    'concurrent close callers share failure and still release notifiers',
    () async {
      final persistence = _GatedClosePersistence();
      final controller = await DiagnosticsController.create(
        persistence: persistence,
        sessionId: 'failing-close',
      );

      final first = controller.close();
      final second = controller.close();
      expect(second, same(first));
      await persistence.started.future;

      var completed = false;
      second.whenComplete(() => completed = true).ignore();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      final firstFailure = expectLater(first, throwsA(isA<StateError>()));
      final secondFailure = expectLater(second, throwsA(isA<StateError>()));
      persistence.release.complete();
      await Future.wait([firstFailure, secondFailure]);

      expect(persistence.closeCalls, 1);
      await expectLater(controller.close(), completes);
      expect(persistence.closeCalls, 1);
      expect(
        () => controller.eventsListenable.addListener(() {}),
        throwsFlutterError,
      );
    },
  );

  test(
    'prior-session pending requests reload as interrupted, not errors',
    () async {
      final now = DateTime.utc(2026, 8, 8, 9);
      final persistence = MemoryDiagnosticsPersistence();
      final first = await DiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        sessionId: 'first-session',
      );
      first.recordHttp(_httpRecord(now, HttpDiagnosticPhase.started));
      await first.flush();

      final later = now.add(const Duration(minutes: 2));
      final second = await DiagnosticsController.create(
        persistence: persistence,
        clock: () => later,
        sessionId: 'second-session',
      );
      final request = second.events.whereType<HttpDiagnosticEvent>().single;

      expect(request.state, DiagnosticHttpState.interrupted);
      expect(request.severity, DiagnosticSeverity.warning);
      expect(request.isError, isFalse);
      expect(request.totalDuration, const Duration(minutes: 2));
      await second.close();
    },
  );

  test('a prior-session error is unseen once, then stays seen', () async {
    final now = DateTime.utc(2026, 8, 8, 9);
    final persistence = MemoryDiagnosticsPersistence();
    final first = await DiagnosticsController.create(
      persistence: persistence,
      clock: () => now,
      sessionId: 'error-producing-session',
    );
    first.reportError(StateError('previous launch failed'), StackTrace.current);
    await first.close();

    final second = await DiagnosticsController.create(
      persistence: persistence,
      clock: () => now.add(const Duration(minutes: 1)),
      sessionId: 'first-reload',
    );
    expect(second.unseenErrorCountListenable.value, 1);
    second.openPanel();
    await second.close();

    final third = await DiagnosticsController.create(
      persistence: persistence,
      clock: () => now.add(const Duration(minutes: 2)),
      sessionId: 'second-reload',
    );
    expect(third.unseenErrorCountListenable.value, 0);
    await third.close();
  });

  test(
    'persistence failure degrades once and never escapes reporting',
    () async {
      final controller = await DiagnosticsController.create(
        persistence: _FailingPersistence(),
        sessionId: 'memory-only',
      );

      controller.reportError(StateError('one'), StackTrace.current);
      controller.reportError(StateError('two'), StackTrace.current);
      await controller.flush();

      final warnings = controller.events
          .whereType<ErrorDiagnosticEvent>()
          .where((event) => event.source == 'diagnostics');
      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('memory-only'));
      await controller.close();
    },
  );

  test(
    'a persistence warning is seen when the panel is already open',
    () async {
      final persistence = _TrackingPersistence();
      final controller = await DiagnosticsController.create(
        persistence: persistence,
        sessionId: 'open-panel-persistence-failure',
      );
      addTearDown(controller.close);
      controller.openPanel();
      persistence.failNextAppend = true;

      controller.reportError(
        StateError('foreground failure'),
        StackTrace.current,
      );
      await controller.flush();

      expect(
        controller.events.whereType<ErrorDiagnosticEvent>().where(
          (event) => event.source == 'diagnostics',
        ),
        hasLength(1),
      );
      expect(controller.unseenErrorCountListenable.value, 0);
    },
  );

  test(
    'clear re-arms a persistence warning when disk deletion fails',
    () async {
      final persistence = _FailingPersistence();
      final controller = await DiagnosticsController.create(
        persistence: persistence,
        sessionId: 'clear-failure',
      );
      expect(controller.events.whereType<ErrorDiagnosticEvent>(), isNotEmpty);

      await controller.clear();

      final afterClear = controller.events.whereType<ErrorDiagnosticEvent>();
      expect(persistence.clearCalls, 1);
      expect(afterClear, hasLength(1));
      expect(afterClear.single.message, contains('clear unavailable'));
      await controller.close();
    },
  );

  test('clear can delete a backing store that failed to load', () async {
    final persistence = _LoadFailingPersistence();
    final controller = await DiagnosticsController.create(
      persistence: persistence,
      sessionId: 'load-failure',
    );
    expect(persistence.diskHistoryPresent, isTrue);

    await controller.clear();

    expect(persistence.clearCalls, 1);
    expect(persistence.diskHistoryPresent, isFalse);
    controller.reportError(
      StateError('post-clear persisted error'),
      StackTrace.current,
    );
    await controller.close();

    final reloaded = await DiagnosticsController.create(
      persistence: persistence,
      sessionId: 'after-load-failure-clear',
    );
    expect(
      reloaded.events.whereType<ErrorDiagnosticEvent>().any(
        (event) => event.message.contains('post-clear persisted error'),
      ),
      isTrue,
    );
    await reloaded.close();
  });

  test('clear keeps the memory-only persistence warning visible', () async {
    final controller = await DiagnosticsController.create(
      persistenceFactory: () async =>
          throw const FileSystemException('support directory unavailable'),
      sessionId: 'memory-only',
    );
    addTearDown(controller.close);
    expect(controller.events.whereType<ErrorDiagnosticEvent>(), hasLength(1));

    await controller.clear();

    final warnings = controller.events.whereType<ErrorDiagnosticEvent>();
    expect(warnings, hasLength(1));
    expect(warnings.single.message, contains('remains unavailable'));
  });

  test(
    'an old persistence failure cannot repopulate cleared history',
    () async {
      final persistence = _GatedFailurePersistence();
      final controller = await DiagnosticsController.create(
        persistence: persistence,
        sessionId: 'clear-persistence-race',
      );
      addTearDown(controller.close);
      persistence.failNextAppend = true;
      controller.reportError(StateError('soon cleared'), StackTrace.current);
      await persistence.started.future;

      final clearing = controller.clear();
      persistence.release.complete();
      await clearing;

      expect(controller.events, isEmpty);
    },
  );

  test(
    'the expiry timer prunes live and frozen history from memory and disk',
    () async {
      var now = DateTime.utc(2026, 8, 8, 9);
      final persistence = MemoryDiagnosticsPersistence();
      late _ManualTimer expiry;
      final controller = await DiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        timerFactory: (duration, callback) {
          expiry = _ManualTimer(callback);
          return expiry;
        },
        sessionId: 'expiring-session',
      );
      addTearDown(controller.close);
      controller.reportError(
        StateError('expires while frozen'),
        StackTrace.current,
      );
      final selected = controller.events
          .whereType<ErrorDiagnosticEvent>()
          .single;
      controller
        ..setFrozen(true)
        ..selectEvent(selected.id);

      now = now.add(diagnosticsRetentionAge);
      expiry.fire();
      await controller.flush();

      expect(controller.events, isEmpty);
      expect(controller.visibleEvents, isEmpty);
      expect(controller.panelState.selectedEventId, isNull);
      expect((await persistence.load(nowUtc: now)).events, isEmpty);
    },
  );

  test(
    'expiry rebases the unseen count and the next expiry on what it kept',
    () async {
      var now = DateTime.utc(2026, 8, 8, 9);
      final delays = <Duration>[];
      late _ManualTimer expiry;
      final controller = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        clock: () => now,
        timerFactory: (duration, callback) {
          delays.add(duration);
          expiry = _ManualTimer(callback);
          return expiry;
        },
        sessionId: 'expiry-rebase',
      );
      addTearDown(controller.close);

      controller.reportError(StateError('aged out'), StackTrace.current);
      now = now.add(const Duration(hours: 20));
      controller.reportError(StateError('still here'), StackTrace.current);
      expect(controller.unseenErrorCountListenable.value, 2);

      now = now.add(const Duration(hours: 5));
      expiry.fire();
      await controller.flush();

      expect(controller.events.whereType<ErrorDiagnosticEvent>(), hasLength(1));
      expect(controller.unseenErrorCountListenable.value, 1);

      // And the next expiry is measured from the oldest event still held. Timing
      // it off the evicted one would ask for a timer that has already elapsed,
      // and the history would re-expire itself every turn from then on.
      expect(delays.last, diagnosticsRetentionAge - const Duration(hours: 5));
    },
  );

  test('one request that fails counts as one unseen error', () async {
    final now = DateTime.utc(2026, 8, 8, 9);
    final controller = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      clock: () => now,
      sessionId: 'failing-request',
    );
    addTearDown(controller.close);

    controller.recordHttp(
      _httpRecord(now, HttpDiagnosticPhase.started, eventId: 'request-1'),
    );
    expect(controller.unseenErrorCountListenable.value, 0);

    controller.recordHttp(
      _httpRecord(
        now,
        HttpDiagnosticPhase.responseHeaders,
        eventId: 'request-1',
        statusCode: 500,
      ),
    );
    controller.recordHttp(
      _httpRecord(
        now,
        HttpDiagnosticPhase.completed,
        eventId: 'request-1',
        statusCode: 500,
      ),
    );

    expect(controller.events.whereType<HttpDiagnosticEvent>(), hasLength(1));
    expect(controller.unseenErrorCountListenable.value, 1);
  });

  test('an HTTP request cannot reappear after retention evicts it', () async {
    var now = DateTime.utc(2026, 8, 8, 9);
    late _ManualTimer expiry;
    final controller = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      clock: () => now,
      timerFactory: (duration, callback) {
        expiry = _ManualTimer(callback);
        return expiry;
      },
      sessionId: 'http-retention-generation',
    );
    addTearDown(controller.close);
    controller.recordHttp(
      _httpRecord(now, HttpDiagnosticPhase.started, eventId: 'aged-request'),
    );

    now = now.add(diagnosticsRetentionAge);
    expiry.fire();
    expect(controller.events.whereType<HttpDiagnosticEvent>(), isEmpty);

    controller.recordHttp(
      _httpRecord(
        now,
        HttpDiagnosticPhase.completed,
        eventId: 'aged-request',
        statusCode: 200,
      ),
    );
    expect(controller.events.whereType<HttpDiagnosticEvent>(), isEmpty);
  });

  test(
    'coalesces request phases that complete inside one persistence window',
    () async {
      final now = DateTime.utc(2026, 8, 8, 9);
      final persistence = _TrackingPersistence();
      final controller = await DiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        sessionId: 'coalesced-request',
      );
      addTearDown(controller.close);
      persistence.batches.clear();

      controller.recordHttp(
        _httpRecord(now, HttpDiagnosticPhase.started, eventId: 'request'),
      );
      controller.recordHttp(
        _httpRecord(
          now,
          HttpDiagnosticPhase.responseHeaders,
          eventId: 'request',
          statusCode: 200,
        ),
      );
      controller.recordHttp(
        _httpRecord(
          now,
          HttpDiagnosticPhase.completed,
          eventId: 'request',
          statusCode: 200,
        ),
      );
      await controller.flush();

      expect(persistence.batches, hasLength(1));
      final persisted = persistence.batches.single.single;
      expect(persisted, isA<HttpDiagnosticEvent>());
      expect(
        (persisted as HttpDiagnosticEvent).state,
        DiagnosticHttpState.completed,
      );
    },
  );

  test(
    'ordinary writes batch and an error flushes its batch immediately',
    () async {
      final now = DateTime.utc(2026, 8, 8, 9);
      final persistence = _TrackingPersistence();
      final controller = await DiagnosticsController.create(
        persistence: persistence,
        clock: () => now,
        sessionId: 'batch-session',
      );
      addTearDown(controller.close);
      persistence.batches.clear();

      _ManualTimer? ordinaryWrite;
      runZoned(
        () {
          controller.recordHttp(
            _httpRecord(
              now,
              HttpDiagnosticPhase.started,
              eventId: 'ordinary-1',
            ),
          );
          controller.recordHttp(
            _httpRecord(
              now,
              HttpDiagnosticPhase.started,
              eventId: 'ordinary-2',
            ),
          );
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration != DiagnosticsController.ordinaryWriteDelay) {
              return parent.createTimer(zone, duration, callback);
            }
            final timer = _ManualTimer(zone.bindCallback(callback));
            ordinaryWrite = timer;
            return timer;
          },
        ),
      );
      expect(persistence.batches, isEmpty);

      expect(
        ordinaryWrite,
        isNotNull,
        reason: 'ordinary diagnostics writes must schedule a bounded batch',
      );
      ordinaryWrite!.fire();
      await Future<void>.delayed(Duration.zero);
      expect(persistence.batches, hasLength(1));
      expect(persistence.batches.single.map((event) => event.id), [
        'ordinary-1',
        'ordinary-2',
      ]);

      persistence.batches.clear();
      controller.recordHttp(
        _httpRecord(now, HttpDiagnosticPhase.started, eventId: 'ordinary-3'),
      );
      controller.reportError(StateError('flush now'), StackTrace.current);

      await Future<void>.delayed(Duration.zero);
      expect(persistence.batches, hasLength(1));
      expect(persistence.batches.single, hasLength(2));
      expect(persistence.batches.single.first.id, 'ordinary-3');
      expect(persistence.batches.single.last, isA<ErrorDiagnosticEvent>());
    },
  );
}

HttpDiagnosticRecord _httpRecord(
  DateTime at,
  HttpDiagnosticPhase phase, {
  String eventId = 'request-1',
  int? statusCode,
  int receivedBytes = 0,
  String? errorType,
}) => HttpDiagnosticRecord(
  eventId: eventId,
  phase: phase,
  timestamp: at,
  method: 'GET',
  uri: Uri.parse('https://example.com/t/42.json?page'),
  statusCode: statusCode,
  errorType: errorType,
  totalDuration: phase == HttpDiagnosticPhase.started
      ? null
      : const Duration(milliseconds: 125),
  sentBytes: 0,
  receivedBytes: receivedBytes,
);

final class _HostileError {
  @override
  String toString() => throw StateError('toString failed');
}

final class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

final class _TrackingPersistence implements DiagnosticsPersistence {
  final MemoryDiagnosticsPersistence _delegate = MemoryDiagnosticsPersistence();
  final List<List<DiagnosticEvent>> batches = [];
  bool failNextAppend = false;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _delegate.load(nowUtc: nowUtc);

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) async {
    if (failNextAppend) {
      failNextAppend = false;
      throw StateError('append unavailable');
    }
    batches.add(List.unmodifiable(events));
    await _delegate.appendEvents(events, nowUtc: nowUtc);
  }

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> compact({required DateTime nowUtc}) =>
      _delegate.compact(nowUtc: nowUtc);

  @override
  Future<void> writeLastSeenSequence(int sequence) =>
      _delegate.writeLastSeenSequence(sequence);
}

final class _GatedFailurePersistence implements DiagnosticsPersistence {
  final MemoryDiagnosticsPersistence _delegate = MemoryDiagnosticsPersistence();
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  bool failNextAppend = false;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _delegate.load(nowUtc: nowUtc);

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) async {
    if (failNextAppend) {
      failNextAppend = false;
      started.complete();
      await release.future;
      throw StateError('old generation append failed');
    }
    await _delegate.appendEvents(events, nowUtc: nowUtc);
  }

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> compact({required DateTime nowUtc}) =>
      _delegate.compact(nowUtc: nowUtc);

  @override
  Future<void> writeLastSeenSequence(int sequence) =>
      _delegate.writeLastSeenSequence(sequence);
}

final class _GatedClosePersistence implements DiagnosticsPersistence {
  final MemoryDiagnosticsPersistence _delegate = MemoryDiagnosticsPersistence();
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  int closeCalls = 0;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _delegate.load(nowUtc: nowUtc);

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) => _delegate.appendEvents(events, nowUtc: nowUtc);

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<void> close() async {
    closeCalls++;
    started.complete();
    await release.future;
    throw StateError('close unavailable');
  }

  @override
  Future<void> compact({required DateTime nowUtc}) =>
      _delegate.compact(nowUtc: nowUtc);

  @override
  Future<void> writeLastSeenSequence(int sequence) =>
      _delegate.writeLastSeenSequence(sequence);
}

final class _FailingPersistence implements DiagnosticsPersistence {
  int clearCalls = 0;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) async =>
      const DiagnosticsPersistenceState();

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) async => throw StateError('unavailable');

  @override
  Future<void> clear() async {
    clearCalls += 1;
    throw StateError('clear unavailable');
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> compact({required DateTime nowUtc}) async =>
      throw StateError('unavailable');

  @override
  Future<void> writeLastSeenSequence(int sequence) async =>
      throw StateError('unavailable');
}

final class _LoadFailingPersistence implements DiagnosticsPersistence {
  final MemoryDiagnosticsPersistence _recovered =
      MemoryDiagnosticsPersistence();
  bool diskHistoryPresent = true;
  int clearCalls = 0;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) async =>
      diskHistoryPresent
      ? throw const FileSystemException('history cannot be read')
      : _recovered.load(nowUtc: nowUtc);

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) => _recovered.appendEvents(events, nowUtc: nowUtc);

  @override
  Future<void> writeLastSeenSequence(int sequence) =>
      _recovered.writeLastSeenSequence(sequence);

  @override
  Future<void> compact({required DateTime nowUtc}) =>
      _recovered.compact(nowUtc: nowUtc);

  @override
  Future<void> clear() async {
    clearCalls += 1;
    diskHistoryPresent = false;
    await _recovered.clear();
  }

  @override
  Future<void> close() => _recovered.close();
}
