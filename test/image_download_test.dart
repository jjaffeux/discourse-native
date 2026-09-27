import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/image_download.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  const siteUrl = 'https://forum.example';
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('image-download-test-');
  });
  tearDown(() => temporary.delete(recursive: true));

  test('a cancelled desktop save does not fetch the image', () async {
    var requests = 0;
    final repository = _repository((request) async {
      requests++;
      return http.Response.bytes([1], 200);
    });
    addTearDown(repository.dispose);
    final environment = _FakeImageDownloadEnvironment(temporary);
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
      temporary,
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

  test(
    'an account change during the save dialog cancels the image fetch',
    () async {
      var requests = 0;
      final repository = _repository((_) async {
        requests++;
        return http.Response.bytes([1], 200);
      });
      addTearDown(repository.dispose);
      final choice = Completer<String?>();
      final environment = _FakeImageDownloadEnvironment(
        temporary,
        saveChoice: choice.future,
      );
      final downloader = NativeLightboxImageDownloader(
        platform: TargetPlatform.macOS,
        environment: environment,
      );

      final download = downloader.download(
        url: '/uploads/image.png',
        title: 'image.png',
        siteUrl: siteUrl,
        repository: repository,
      );
      final failure = expectLater(
        download,
        throwsA(isA<ImageDownloadException>()),
      );
      repository.lifecycle.invalidate(siteUrl);
      choice.complete('/chosen/image.png');
      await failure;

      expect(requests, 0);
      expect(environment.savedPath, isNull);
      expect(environment.shareCalls, 0);
    },
  );

  group('mobile file-sharing sheet', () {
    late SiteImageRepository repository;

    setUp(() {
      repository = _repository((_) async => http.Response.bytes([4, 5], 200));
      addTearDown(repository.dispose);
    });

    Future<ImageDownloadOutcome> share(
      _FakeImageDownloadEnvironment environment, {
      String? title,
      Rect? origin,
    }) =>
        NativeLightboxImageDownloader(
          platform: TargetPlatform.iOS,
          environment: environment,
        ).download(
          url: '$siteUrl/secure-uploads/photo.webp?dl=1',
          title: title,
          siteUrl: siteUrl,
          repository: repository,
          sharePositionOrigin: origin,
        );

    test('receives a private copy named after the image', () async {
      const origin = Rect.fromLTWH(10, 20, 30, 40);
      final environment = _FakeImageDownloadEnvironment(
        temporary,
        shareOutcome: ImageDownloadOutcome.shared,
      );

      final outcome = await share(
        environment,
        title: 'Private scan.webp',
        origin: origin,
      );

      expect(outcome, ImageDownloadOutcome.shared);
      expect(environment.suggestedName, isNull);
      final staging = File(environment.sharedPath!).parent;
      expect(staging.parent.path, temporary.path);
      expect(staging.path, startsWith('${temporary.path}/image-share-'));
      expect(environment.filename, 'Private scan.webp');
      if (!Platform.isWindows) {
        expect(environment.sharedMode, 0x180); // 0600
      }
      expect(environment.mimeType, 'image/webp');
      expect(environment.bytes, orderedEquals([4, 5]));
      expect(environment.shareOrigin, origin);
      expect(environment.shareCalls, 1);
      expect(temporary.listSync(), isEmpty);
    });

    test('names an untitled copy after the URL', () async {
      final environment = _FakeImageDownloadEnvironment(temporary);

      await share(environment);

      expect(environment.filename, 'photo.webp');
    });

    test('a dismissed sheet leaves no copy behind', () async {
      final environment = _FakeImageDownloadEnvironment(temporary);

      expect(await share(environment), ImageDownloadOutcome.cancelled);
      expect(environment.shareCalls, 1);
      expect(temporary.listSync(), isEmpty);
    });

    test('a failed share leaves no copy behind', () async {
      final environment = _FakeImageDownloadEnvironment(
        temporary,
        shareError: PlatformException(code: 'error'),
      );

      await expectLater(share(environment), throwsA(isA<PlatformException>()));
      expect(environment.shareCalls, 1);
      expect(temporary.listSync(), isEmpty);
    });

    test('an account change while staging never reaches the sheet', () async {
      final environment = _FakeImageDownloadEnvironment(
        temporary,
        onTemporaryDirectory: () => repository.lifecycle.invalidate(siteUrl),
      );

      await expectLater(
        share(environment),
        throwsA(isA<ImageDownloadException>()),
      );
      expect(environment.shareCalls, 0);
      expect(temporary.listSync(), isEmpty);
    });
  });

  test(
    'fails instead of opening a browser when no repository is available',
    () {
      final downloader = NativeLightboxImageDownloader(
        platform: TargetPlatform.android,
        environment: _FakeImageDownloadEnvironment(temporary),
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
  _FakeImageDownloadEnvironment(
    this.temporary, {
    this.savePath,
    this.saveChoice,
    this.shareOutcome = ImageDownloadOutcome.cancelled,
    this.shareError,
    this.onTemporaryDirectory,
  });

  final Directory temporary;
  final String? savePath;
  final Future<String?>? saveChoice;
  final ImageDownloadOutcome shareOutcome;
  final Object? shareError;
  final VoidCallback? onTemporaryDirectory;

  String? suggestedName;
  String? savedPath;
  String? sharedPath;
  int? sharedMode;
  String? filename;
  String? mimeType;
  Uint8List? bytes;
  Rect? shareOrigin;
  int shareCalls = 0;

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    this.suggestedName = suggestedName;
    return saveChoice == null ? savePath : await saveChoice;
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
  Future<Directory> temporaryDirectory() async {
    onTemporaryDirectory?.call();
    return temporary;
  }

  @override
  Future<ImageDownloadOutcome> shareImage(
    File file, {
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    shareCalls++;
    sharedPath = file.path;
    sharedMode = (await file.stat()).mode & 0x1ff;
    bytes = await file.readAsBytes();
    filename = file.uri.pathSegments.last;
    this.mimeType = mimeType;
    shareOrigin = sharePositionOrigin;
    if (shareError case final error?) throw error;
    return shareOutcome;
  }
}
