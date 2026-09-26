import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final scenario in [
    (
      name: 'header takes precedence',
      headers: {'retry-after': '3'},
      body: '{"extras":{"wait_seconds":7}}',
      seconds: 3,
    ),
    (
      name: 'HTTP date uses server clock',
      headers: {
        'retry-after': 'Mon, 21 Sep 2026 12:00:05 GMT',
        'date': 'Mon, 21 Sep 2026 12:00:00 GMT',
      },
      body: '{}',
      seconds: 5,
    ),
    (
      name: 'body delay',
      headers: <String, String>{},
      body: '{"extras":{"wait_seconds":4}}',
      seconds: 4,
    ),
    (
      name: 'missing delay uses fallback',
      headers: <String, String>{},
      body: '{}',
      seconds: 15,
    ),
    (
      name: 'invalid delay uses fallback',
      headers: {'retry-after': 'invalid'},
      body: '{"extras":{"wait_seconds":-1}}',
      seconds: 15,
    ),
    (
      name: 'maximum automatic wait',
      headers: {'retry-after': '60'},
      body: '{}',
      seconds: 60,
    ),
  ]) {
    testWidgets('retries once after ${scenario.name} with fresh file bytes', (
      tester,
    ) async {
      final requests = <http.Request>[];
      var opens = 0;
      final api = _api(tester, (request) async {
        requests.add(request);
        return requests.length == 1
            ? http.Response(scenario.body, 429, headers: scenario.headers)
            : _success();
      });
      addTearDown(api.close);
      final file = ComposerUploadFile(
        name: 'photo.png',
        length: () async => 3,
        openRead: () {
          opens++;
          return Stream.value([1, 2, 3]);
        },
      );
      ComposerUploadResult? result;
      final operation = _upload(
        api,
        file: file,
      ).then((value) => result = value);
      await tester.pump();
      expect(requests, hasLength(1));
      expect(opens, 1);
      await tester.pump(Duration(seconds: scenario.seconds - 1));
      expect(requests, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await operation;
      expect(result!.id, 73);
      expect(opens, 2);
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'POST /uploads.json',
        'POST /uploads.json',
      ]);
      for (final request in requests) {
        expect(request.bodyBytes, containsAllInOrder([1, 2, 3]));
        expect(request.headers['user-api-key'], 'key');
      }
    });
  }

  testWidgets('network errors fail without retrying the upload', (
    tester,
  ) async {
    var sends = 0;
    final api = _api(tester, (_) async {
      sends++;
      throw http.ClientException('connection lost');
    });
    addTearDown(api.close);
    final failure = expectLater(
      _upload(api),
      throwsA(
        isA<ComposerUploadException>().having(
          (e) => e.retryAfter,
          'wait',
          isNull,
        ),
      ),
    );
    await tester.pump();
    await failure;
    await tester.pump(const Duration(seconds: 60));
    expect(sends, 1);
  });

  testWidgets(
    'a second 429 fails with its delay and manual retry respects cooldown',
    (tester) async {
      var sends = 0;
      final api = _api(tester, (_) async {
        sends++;
        return sends <= 2
            ? http.Response('{}', 429, headers: {'retry-after': '2'})
            : _success();
      });
      addTearDown(api.close);
      final failure = expectLater(
        _upload(api),
        throwsA(
          isA<ComposerUploadException>()
              .having((e) => e.statusCode, 'status', 429)
              .having((e) => e.retryAfter, 'wait', const Duration(seconds: 2)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await failure;
      expect(sends, 2);
      final manual = _upload(api);
      await tester.pump();
      expect(sends, 2);
      await tester.pump(const Duration(seconds: 2));
      expect((await manual).id, 73);
      expect(sends, 3);
    },
  );

  for (final status in [429, 422, 500]) {
    testWidgets('does not automatically retry $status with a long delay', (
      tester,
    ) async {
      var sends = 0;
      final api = _api(tester, (_) async {
        sends++;
        return http.Response(
          '{"errors":["Rejected"]}',
          status,
          headers: {'retry-after': '120'},
        );
      });
      addTearDown(api.close);
      final failure = expectLater(
        _upload(api),
        throwsA(
          isA<ComposerUploadException>()
              .having((e) => e.statusCode, 'status', status)
              .having(
                (e) => e.retryAfter,
                'wait',
                status == 429 ? const Duration(seconds: 120) : null,
              ),
        ),
      );
      await tester.pump();
      await failure;
      await tester.pump(const Duration(seconds: 120));
      expect(sends, 1);
    });
  }

  testWidgets('cancellation resolves immediately during the retry wait', (
    tester,
  ) async {
    final abort = Completer<void>();
    var sends = 0;
    final api = _api(tester, (_) async {
      sends++;
      return http.Response('{}', 429, headers: {'retry-after': '60'});
    });
    addTearDown(api.close);
    final failure = expectLater(
      api.uploadComposerImage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        file: _file,
        onProgress: (_) {},
        abortTrigger: abort.future,
      ),
      throwsA(
        isA<ComposerUploadException>().having(
          (e) => e.message,
          'message',
          'Upload cancelled.',
        ),
      ),
    );
    await tester.pump();
    abort.complete();
    await tester.pump();
    await failure;
    expect(sends, 1);
    api.close();
  });

  testWidgets(
    'long body waits surface recovery without retaining an active upload',
    (tester) async {
      var sends = 0;
      final api = _api(tester, (_) async {
        sends++;
        return http.Response('{"extras":{"wait_seconds":121}}', 429);
      });
      addTearDown(api.close);
      final composer = _composer(api);
      addTearDown(composer.dispose);
      composer.addImages([_file], 0);
      await tester.pump();
      expect(composer.hasActiveUploads, isFalse);
      expect(
        composer.uploads.single.error,
        'Too many uploads. Try again in 121 seconds.',
      );
      expect(sends, 1);
      api.close();
    },
  );

  for (final dispose in [false, true]) {
    testWidgets(
      '${dispose ? 'disposing' : 'cancelling'} the composer during the wait prevents retry',
      (tester) async {
        var sends = 0;
        final api = _api(tester, (_) async {
          sends++;
          return http.Response('{}', 429, headers: {'retry-after': '5'});
        });
        addTearDown(api.close);
        final composer = _composer(api);
        if (!dispose) addTearDown(composer.dispose);
        composer.addImages([_file], 0);
        await tester.pump();
        expect(sends, 1);
        if (dispose) {
          composer.dispose();
        } else {
          composer.cancelUpload(composer.uploads.single.id);
        }
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        expect(sends, 1);
        if (!dispose) expect(composer.uploads, isEmpty);
      },
    );
  }

  testWidgets(
    'an upload that outlives its deadline fails as a timeout, not a cancellation',
    (tester) async {
      final client = _InFlightClient();
      final api = DiscourseApi(transport: _transport(tester, client));
      addTearDown(api.close);
      Object? failure;
      unawaited(
        _upload(
          api,
        ).then<void>((_) {}, onError: (Object error) => failure = error),
      );
      await tester.pump();
      expect(client.sent, ['POST /uploads.json']);

      await tester.pump(const Duration(minutes: 5));

      expect(failure, _uploadError("Couldn't upload photo.png."));
      // The deadline closes the connection rather than leaving the file
      // streaming behind a failed row.
      expect(client.aborted, ['POST /uploads.json']);
    },
  );

  testWidgets(
    'cancelling an upload queued behind a busy origin settles it unsent',
    (tester) async {
      final client = _InFlightClient();
      final transport = _transport(tester, client, maxConcurrentPerOrigin: 1);
      final api = DiscourseApi(transport: transport);
      addTearDown(api.close);
      final read = _holdSlot(transport);
      final abort = Completer<void>();
      Object? failure;
      unawaited(
        _upload(
          api,
          abortTrigger: abort.future,
        ).then<void>((_) {}, onError: (Object error) => failure = error),
      );
      await tester.pump();
      expect(client.sent, ['GET /latest.json']);

      abort.complete();
      await tester.pump();
      expect(failure, _uploadError('Upload cancelled.'));

      client.release.complete(_emptyObject());
      await tester.pump();
      expect((await read).statusCode, 200);
      expect(client.sent, ['GET /latest.json']);
    },
  );

  testWidgets("an upload's deadline starts when its origin admits it", (
    tester,
  ) async {
    final client = _InFlightClient();
    final transport = _transport(tester, client, maxConcurrentPerOrigin: 1);
    final api = DiscourseApi(transport: transport);
    addTearDown(api.close);
    final read = _holdSlot(transport);
    Object? failure;
    unawaited(
      _upload(
        api,
      ).then<void>((_) {}, onError: (Object error) => failure = error),
    );
    await tester.pump();
    await tester.pump(const Duration(minutes: 4));
    expect(client.sent, ['GET /latest.json']);

    client.release.complete(_emptyObject());
    await tester.pump();
    expect((await read).statusCode, 200);
    expect(client.sent, ['GET /latest.json', 'POST /uploads.json']);

    await tester.pump(const Duration(minutes: 5) - const Duration(seconds: 1));
    expect(failure, isNull);
    expect(client.aborted, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(failure, _uploadError("Couldn't upload photo.png."));
    expect(client.aborted, ['POST /uploads.json']);
  });

  testWidgets(
    'rate-limited first upload retains the completed sibling and batch order',
    (tester) async {
      final first = Completer<http.Response>();
      var sends = 0;
      final api = _api(tester, (_) async {
        sends++;
        if (sends == 1) return first.future;
        return _success(name: sends == 2 ? 'two' : 'one');
      });
      addTearDown(api.close);
      final composer = _composer(api);
      addTearDown(composer.dispose);
      composer.addImages([_file, _file], 0);
      await tester.pump();
      first.complete(http.Response('{}', 429, headers: {'retry-after': '2'}));
      await tester.pump();
      expect(sends, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(sends, 3);
      expect(composer.raw, '![one](upload://one)\n![two](upload://two)');
      expect(composer.uploads, isEmpty);
    },
  );
}

DiscourseApi _api(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) send,
) => DiscourseApi(transport: _transport(tester, MockClient(send)));

DiscourseTransport _transport(
  WidgetTester tester,
  http.Client client, {
  int maxConcurrentPerOrigin = 4,
}) {
  final start = tester.binding.clock.now();
  return DiscourseTransport(
    SafeHttpClient.owned(client),
    const Duration(seconds: 10),
    1024 * 1024,
    coordinator: DiscourseRequestCoordinator(
      maxConcurrentPerOrigin: maxConcurrentPerOrigin,
      clock: tester.binding.clock.now,
      cooldownFactory: () => OriginCooldown(
        clock: () => tester.binding.clock.now().difference(start),
      ),
    ),
  );
}

Future<ComposerUploadResult> _upload(
  DiscourseApi api, {
  ComposerUploadFile? file,
  Future<void>? abortTrigger,
}) => api.uploadComposerImage(
  siteUrl: 'https://example.com',
  apiKey: 'key',
  file: file ?? _file,
  onProgress: (_) {},
  abortTrigger: abortTrigger ?? Completer<void>().future,
);

/// A read that holds the origin's only slot until [_InFlightClient.release].
Future<http.Response> _holdSlot(DiscourseTransport transport) => transport.get(
  Uri.parse('https://example.com/latest.json'),
  siteUrl: 'https://example.com',
  requestTimeout: const Duration(hours: 1),
);

Matcher _uploadError(String message) => isA<ComposerUploadException>().having(
  (error) => error.message,
  'message',
  message,
);

/// Records each request as the network would see it. A GET waits for
/// [release]; an upload stays in flight until its abort trigger fires and then
/// fails the way IOClient reports an aborted request.
final class _InFlightClient extends http.BaseClient {
  final sent = <String>[];
  final aborted = <String>[];
  final release = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final route = '${request.method} ${request.url.path}';
    sent.add(route);
    if (request.method == 'GET') return release.future;
    await switch (request) {
      http.Abortable(:final abortTrigger?) => abortTrigger,
      _ => Completer<void>().future,
    };
    aborted.add(route);
    throw http.RequestAbortedException(request.url);
  }
}

http.StreamedResponse _emptyObject() =>
    http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);

ComposerController _composer(DiscourseApi api) => ComposerController(
  const ComposerTarget(
    siteUrl: 'https://example.com',
    topicId: 1,
    slug: 'topic',
    topicTitle: 'Topic',
  ),
  imageUploader: (file, {required onProgress, required abortTrigger}) =>
      api.uploadComposerImage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        file: file,
        onProgress: onProgress,
        abortTrigger: abortTrigger,
      ),
);

final _file = ComposerUploadFile(
  name: 'photo.png',
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);
http.Response _success({String name = 'photo'}) => http.Response(
  jsonEncode({
    'id': 73,
    'original_filename': '$name.png',
    'url': '/uploads/$name.png',
    'short_url': 'upload://$name',
  }),
  200,
);
