import 'dart:typed_data';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/image_download.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  const siteUrl = 'https://forum.example';

  test('a cancelled desktop save does not fetch the image', () async {
    var requests = 0;
    final repository = _repository((request) async {
      requests++;
      return http.Response.bytes([1], 200);
    });
    addTearDown(repository.dispose);
    final environment = _FakeImageDownloadEnvironment();
    final downloader = NativeLightboxImageDownloader(
      platform: TargetPlatform.macOS,
      environment: environment,
    );

    final outcome = await downloader.download(
      url: '/uploads/short-url/image.png?dl=1',
      title: 'screenshot 100%.png',
      siteUrl: siteUrl,
      repository: repository,
    );

    expect(outcome, ImageDownloadOutcome.cancelled);
    expect(environment.suggestedName, 'screenshot 100%.png');
    expect(requests, 0);
  });

  test('desktop downloads authenticated bytes to the selected file', () async {
    late http.Request sent;
    final repository = _repository((request) async {
      sent = request;
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    addTearDown(repository.dispose);
    final environment = _FakeImageDownloadEnvironment(
      savePath: '/chosen/screenshot.png',
    );
    final downloader = NativeLightboxImageDownloader(
      platform: TargetPlatform.linux,
      environment: environment,
    );

    final outcome = await downloader.download(
      url: '/uploads/short-url/image.png?dl=1',
      title: 'screenshot.png',
      siteUrl: siteUrl,
      repository: repository,
    );

    expect(outcome, ImageDownloadOutcome.saved);
    expect(sent.url, Uri.parse('$siteUrl/uploads/short-url/image.png?dl=1'));
    expect(sent.headers['User-Api-Key'], 'account-key');
    expect(environment.savedPath, '/chosen/screenshot.png');
    expect(environment.filename, 'screenshot.png');
    expect(environment.mimeType, 'image/png');
    expect(environment.bytes, orderedEquals([1, 2, 3]));
    expect(environment.shareCalls, 0);
  });

  test('mobile downloads bytes into the native file-sharing sheet', () async {
    final repository = _repository(
      (_) async => http.Response.bytes([4, 5], 200),
    );
    addTearDown(repository.dispose);
    const origin = Rect.fromLTWH(10, 20, 30, 40);
    final environment = _FakeImageDownloadEnvironment(
      shareOutcome: ImageDownloadOutcome.shared,
    );
    final downloader = NativeLightboxImageDownloader(
      platform: TargetPlatform.iOS,
      environment: environment,
    );

    final outcome = await downloader.download(
      url: '$siteUrl/uploads/photo.webp?dl=1',
      title: null,
      siteUrl: siteUrl,
      repository: repository,
      sharePositionOrigin: origin,
    );

    expect(outcome, ImageDownloadOutcome.shared);
    expect(environment.suggestedName, isNull);
    expect(environment.filename, 'photo.webp');
    expect(environment.mimeType, 'image/webp');
    expect(environment.bytes, orderedEquals([4, 5]));
    expect(environment.shareOrigin, origin);
    expect(environment.shareCalls, 1);
  });

  test(
    'fails instead of opening a browser when no repository is available',
    () {
      final downloader = NativeLightboxImageDownloader(
        platform: TargetPlatform.android,
        environment: _FakeImageDownloadEnvironment(),
      );

      expect(
        downloader.download(
          url: '$siteUrl/image.png',
          title: null,
          siteUrl: siteUrl,
          repository: null,
        ),
        throwsA(isA<ImageDownloadException>()),
      );
    },
  );

  group('imageDownloadFilename', () {
    test('prefers and sanitizes the upload title', () {
      expect(
        imageDownloadFilename(
          title: r'capture: before/after?.png',
          url: '$siteUrl/fallback.jpg?dl=1',
        ),
        'capture_ before_after_.png',
      );
    });

    test('decodes a URL filename and ignores its query', () {
      expect(
        imageDownloadFilename(
          title: null,
          url: '$siteUrl/a/my%20photo.jpeg?dl=1',
        ),
        'my photo.jpeg',
      );
    });

    test('preserves a literal percent sign in the upload title', () {
      expect(
        imageDownloadFilename(
          title: '100% complete.png',
          url: '$siteUrl/a/fallback.png?dl=1',
        ),
        '100% complete.png',
      );
    });

    test('decodes an escaped percent in the URL filename exactly once', () {
      expect(
        imageDownloadFilename(
          title: null,
          url: '$siteUrl/a/100%2520-complete.png?dl=1',
        ),
        '100%20-complete.png',
      );
    });

    test('adds the URL extension when a descriptive title lacks one', () {
      expect(
        imageDownloadFilename(
          title: 'A useful diagram',
          url: '$siteUrl/a/diagram.svg?dl=1',
        ),
        'A useful diagram.svg',
      );
    });
  });
}

SiteImageRepository _repository(
  Future<http.Response> Function(http.Request request) handler,
) => SiteImageRepository(
  credentials: FakeApiCredentialReader()
    ..keys['https://forum.example'] = 'account-key',
  lifecycle: SiteLifecycle(),
  client: MockClient(handler),
);

final class _FakeImageDownloadEnvironment implements ImageDownloadEnvironment {
  _FakeImageDownloadEnvironment({
    this.savePath,
    this.shareOutcome = ImageDownloadOutcome.cancelled,
  });

  final String? savePath;
  final ImageDownloadOutcome shareOutcome;

  String? suggestedName;
  String? savedPath;
  String? filename;
  String? mimeType;
  Uint8List? bytes;
  Rect? shareOrigin;
  int shareCalls = 0;

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    this.suggestedName = suggestedName;
    return savePath;
  }

  @override
  Future<void> saveImage(
    Uint8List bytes, {
    required String path,
    required String filename,
    required String mimeType,
  }) async {
    this.bytes = bytes;
    savedPath = path;
    this.filename = filename;
    this.mimeType = mimeType;
  }

  @override
  Future<ImageDownloadOutcome> shareImage(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    shareCalls++;
    this.bytes = bytes;
    this.filename = filename;
    this.mimeType = mimeType;
    shareOrigin = sharePositionOrigin;
    return shareOutcome;
  }
}
