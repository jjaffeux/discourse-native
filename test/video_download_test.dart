import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/video_download.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/manual_scheduler.dart';

void main() {
  const siteUrl = 'https://forum.example';
  final url = Uri.parse('$siteUrl/secure-uploads/demo.mp4');
  late Directory directory;
  late _Environment environment;
  late SiteLifecycle lifecycle;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('video-download-test-');
    environment = _Environment(directory);
    lifecycle = SiteLifecycle();
  });
  tearDown(() => directory.delete(recursive: true));

  Future<VideoDownloadOutcome> download(
    http.Client client, {
    TargetPlatform platform = TargetPlatform.macOS,
    Duration timeout = const Duration(seconds: 30),
    Uri? source,
  }) =>
      NativeVideoDownloader(
        platform: platform,
        environment: environment,
        client: client,
        requestTimeout: timeout,
      ).download(
        url: source ?? url,
        title: 'Demo clip',
        siteUrl: siteUrl,
        credentials: const _Credentials(),
        lifecycle: lifecycle,
        sharePositionOrigin: const Rect.fromLTWH(10, 20, 40, 40),
      );

  test('cancelling the save dialog does not fetch or stage a video', () async {
    var requests = 0;
    final result = await download(
      MockClient((_) async {
        requests++;
        return http.Response.bytes([1], 200);
      }),
    );

    expect(result, VideoDownloadOutcome.cancelled);
    expect(environment.suggestedName, 'Demo clip.mp4');
    expect(requests, 0);
    expect(directory.listSync(), isEmpty);
  });

  test('saves protected bytes and keeps credentials on the forum', () async {
    environment.savePath = '${directory.path}/saved.mp4';
    final requests = <http.Request>[];
    final result = await download(
      MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'forum.example') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://cdn.example/signed/demo.mp4'},
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    expect(result, VideoDownloadOutcome.saved);
    expect(requests.first.url, url);
    expect(requests.first.method, 'GET');
    expect(requests.first.headers['User-Api-Key'], 'secret');
    expect(requests.first.headers['User-Api-Client-Id'], 'client');
    expect(requests.last.headers, isNot(contains('User-Api-Key')));
    expect(requests.last.headers, isNot(contains('User-Api-Client-Id')));
    expect(requests.every((request) => !request.followRedirects), isTrue);
    expect(await File(environment.savePath!).readAsBytes(), [1, 2, 3]);
    expect(directory.listSync().whereType<Directory>(), isEmpty);
    expect(environment.sharedBytes, isNull);
  });

  test(
    'mobile shares a real file and cleans up after the sheet closes',
    () async {
      final result = await download(
        MockClient((request) async {
          expect(request.headers, isNot(contains('User-Api-Key')));
          return http.Response.bytes([4, 5], 200);
        }),
        platform: TargetPlatform.iOS,
        source: Uri.parse('https://cdn.example/demo.mov'),
      );

      expect(result, VideoDownloadOutcome.shared);
      expect(environment.suggestedName, isNull);
      expect(environment.sharedBytes, [4, 5]);
      expect(environment.sharedName, 'Demo clip.mov');
      expect(environment.mimeType, 'video/quicktime');
      expect(environment.shareOrigin, const Rect.fromLTWH(10, 20, 40, 40));
      expect(directory.listSync(), isEmpty);
    },
  );

  test('streams videos larger than the image cache limit', () async {
    environment.savePath = '${directory.path}/large.mp4';
    final chunk = Uint8List(1024 * 1024)..[0] = 7;
    final result = await download(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable(Iterable.generate(33, (_) => chunk)),
          200,
        ),
      ),
    );

    expect(result, VideoDownloadOutcome.saved);
    expect(await File(environment.savePath!).length(), 33 * 1024 * 1024);
    expect(directory.listSync().whereType<Directory>(), isEmpty);
  });

  test('a failed transfer preserves an existing destination', () async {
    environment.savePath = '${directory.path}/existing.mp4';
    final destination = File(environment.savePath!);
    await destination.writeAsBytes([9]);
    Stream<List<int>> body() async* {
      yield [1, 2];
      throw const HttpException('Transfer failed');
    }

    await expectLater(
      download(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(body(), 200),
        ),
      ),
      throwsA(isA<HttpException>()),
    );

    expect(await destination.readAsBytes(), [9]);
    expect(directory.listSync().whereType<Directory>(), isEmpty);
  });

  test('an expired account session cannot save a pending download', () async {
    environment.savePath = '${directory.path}/expired.mp4';
    Stream<List<int>> body() async* {
      yield [1];
      lifecycle.invalidate(siteUrl);
      yield [2];
    }

    await expectLater(
      download(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(body(), 200),
        ),
      ),
      throwsA(isA<VideoDownloadException>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test(
    'an account change while choosing a save path cancels the fetch',
    () async {
      environment.savePath = '${directory.path}/expired.mp4';
      environment.onChoose = () => lifecycle.invalidate(siteUrl);
      var requests = 0;
      await expectLater(
        download(
          MockClient((_) async {
            requests++;
            return http.Response.bytes([1], 200);
          }),
        ),
        throwsA(isA<VideoDownloadException>()),
      );
      expect(requests, 0);
      expect(directory.listSync(), isEmpty);
    },
  );

  test('rejects unsafe redirect targets before requesting them', () async {
    environment.savePath = '${directory.path}/unsafe.mp4';
    var requests = 0;
    await expectLater(
      download(
        MockClient((_) async {
          requests++;
          return http.Response(
            '',
            302,
            headers: {'location': 'http://cdn.example/demo.mp4'},
          );
        }),
      ),
      throwsA(isA<UnsafeHttpTransportException>()),
    );
    expect(requests, 1);
    expect(directory.listSync(), isEmpty);
  });

  test('bounds redirect loops', () async {
    environment.savePath = '${directory.path}/loop.mp4';
    var requests = 0;
    await expectLater(
      download(
        MockClient((_) async {
          requests++;
          return http.Response('', 302, headers: {'location': url.toString()});
        }),
      ),
      throwsA(isA<VideoDownloadException>()),
    );
    expect(requests, 6);
    expect(directory.listSync(), isEmpty);
  });

  test('cancels download headers that arrive after the deadline', () async {
    environment.savePath = '${directory.path}/late.mp4';
    final started = Completer<void>();
    final headers = Completer<http.StreamedResponse>();
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    addTearDown(() async {
      if (!cancelled) await body.stream.listen(null).cancel();
      await body.close();
    });
    final scheduler = ManualScheduler();
    final pending = runZoned(
      () => download(
        MockClient.streaming((request, _) {
          started.complete();
          return headers.future;
        }),
        timeout: const Duration(minutes: 1),
      ),
      zoneSpecification: ZoneSpecification(
        createTimer: (_, _, zone, duration, callback) =>
            scheduler.createTimer(duration, zone.bindCallback(callback)),
      ),
    );
    await started.future;
    final timedOut = expectLater(pending, throwsA(isA<TimeoutException>()));
    scheduler.advance(const Duration(minutes: 1));
    await timedOut;
    expect(directory.listSync(), isEmpty);

    headers.complete(http.StreamedResponse(body.stream, 200));
    // Drain the late-response continuation queued by completing headers.
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isTrue);
  });

  test('a stalled body times out and removes its partial file', () async {
    environment.savePath = '${directory.path}/stalled.mp4';
    final body = StreamController<List<int>>();
    final cancelled = Completer<void>();
    body.onCancel = cancelled.complete;
    await expectLater(
      download(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(body.stream, 200),
        ),
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled.isCompleted, isTrue);
    await body.close();
    expect(directory.listSync(), isEmpty);
  });

  test('rejects errors, empty bodies, and HTML login pages', () async {
    environment.savePath = '${directory.path}/invalid.mp4';
    for (final response in [
      http.Response('missing', 404),
      http.Response('', 200),
      http.Response(
        '<html>Log in</html>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
    ]) {
      await expectLater(
        download(MockClient((_) async => response)),
        throwsA(isA<VideoDownloadException>()),
      );
      expect(directory.listSync(), isEmpty);
    }
  });

  test('video filenames sanitize titles and preserve source extensions', () {
    expect(
      videoDownloadFilename(title: 'A demo: 100%', url: url),
      'A demo_ 100%.mp4',
    );
    expect(videoDownloadFilename(title: 'CON', url: url), '_CON.mp4');
    expect(
      videoDownloadFilename(
        title: '',
        url: Uri.parse('$siteUrl/a%20clip.webm?dl=1'),
      ),
      'a clip.webm',
    );
    expect(videoDownloadFilename(title: '..', url: url), 'video.mp4');
  });
}

class _Environment implements VideoDownloadEnvironment {
  _Environment(this.directory);

  final Directory directory;
  String? savePath;
  String? suggestedName;
  VoidCallback? onChoose;
  List<int>? sharedBytes;
  String? sharedName;
  String? mimeType;
  Rect? shareOrigin;

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    this.suggestedName = suggestedName;
    onChoose?.call();
    return savePath;
  }

  @override
  Future<Directory> temporaryDirectory() async => directory;

  @override
  Future<VideoDownloadOutcome> shareVideo(
    File file, {
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    sharedBytes = await file.readAsBytes();
    sharedName = filename;
    this.mimeType = mimeType;
    shareOrigin = sharePositionOrigin;
    return VideoDownloadOutcome.shared;
  }
}

class _Credentials implements ApiCredentialReader {
  const _Credentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'secret';

  @override
  Future<String> clientId() async => 'client';
}
