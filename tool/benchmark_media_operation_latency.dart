import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/composer_video_optimizer.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/foundation/media_download_environment.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/image_download.dart';
import 'package:discourse_native/src/shell/media_download_result.dart';
import 'package:discourse_native/src/shell/video_download.dart';
import 'package:discourse_video_optimizer/encoder.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _site = 'https://forum.example';
const _network = Duration(milliseconds: 35);
const _platform = Duration(milliseconds: 12);
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
);
final _video = Uint8List(2 * 1024 * 1024);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp('media-operation-');
  try {
    stdout.writeln(
      jsonEncode({
        'share_downloaded_image': await _measure(() => _shareImage(directory)),
        'save_protected_video': await _measure(() => _saveVideo(directory)),
        'prepare_composer_video': await _measure(
          () => _prepareVideo(directory),
        ),
      }),
    );
  } finally {
    await directory.delete(recursive: true);
  }
  exit(0);
}

Future<int> _measure(Future<int> Function() action) async {
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final value = await action();
    if (i >= 2) times.add(value);
  }
  times.sort();
  return times[2];
}

Future<int> _shareImage(Directory directory) async {
  final environment = _Environment(directory);
  var requests = 0;
  final client = MockClient((_) async {
    requests++;
    await Future<void>.delayed(_network);
    return http.Response.bytes(
      _png,
      200,
      headers: {'content-type': 'image/png'},
    );
  });
  final repository = SiteImageRepository(
    credentials: const _Credentials(),
    lifecycle: SiteLifecycle(),
    client: client,
  );
  try {
    final watch = Stopwatch()..start();
    final result =
        await NativeLightboxImageDownloader(
          platform: TargetPlatform.iOS,
          environment: environment,
        ).download(
          url: '/image.png',
          title: 'Image',
          siteUrl: _site,
          repository: repository,
        );
    watch.stop();
    if (result is! MediaDownloadShared ||
        requests != 1 ||
        base64Encode(environment.shared!) != base64Encode(_png)) {
      throw StateError('Image bytes did not reach the share adapter');
    }
    return watch.elapsedMicroseconds;
  } finally {
    repository.dispose();
    client.close();
  }
}

Future<int> _saveVideo(Directory directory) async {
  final environment = _Environment(directory);
  var requests = 0;
  final client = MockClient((request) async {
    requests++;
    if (request.headers['User-Api-Key'] != 'fixture-key') {
      throw StateError('Missing forum credential');
    }
    await Future<void>.delayed(_network);
    return http.Response.bytes(
      _video,
      200,
      headers: {'content-type': 'video/mp4'},
    );
  });
  try {
    final watch = Stopwatch()..start();
    final result =
        await NativeVideoDownloader(
          platform: TargetPlatform.macOS,
          environment: environment,
          client: client,
        ).download(
          url: Uri.parse('$_site/secure-uploads/example.mp4'),
          title: 'Video',
          siteUrl: _site,
          credentials: const _Credentials(),
          lifecycle: SiteLifecycle(),
        );
    watch.stop();
    if (result is! MediaDownloadSaved ||
        requests != 1 ||
        environment.saved != _video.length) {
      throw StateError('Video was not saved completely');
    }
    return watch.elapsedMicroseconds;
  } finally {
    client.close();
  }
}

Future<int> _prepareVideo(Directory directory) async {
  final encoder = _Encoder();
  final optimizer = ComposerVideoOptimizer(
    temporaryDirectory: () async {
      await Future<void>.delayed(_platform);
      return directory;
    },
    native: encoder,
  );
  final aborted = Completer<void>();
  final watch = Stopwatch()..start();
  final result = await optimizer.prepare(
    ComposerUploadFile(
      name: 'example.mov',
      length: () async => _video.length,
      openRead: () => Stream.value(_video),
    ),
    canUpload: (_) => true,
    abortTrigger: aborted.future,
  );
  watch.stop();
  try {
    if (result.file.name != 'example.mp4' ||
        encoder.calls != 1 ||
        await result.file.length() != 128 * 1024) {
      throw StateError('The optimized attachment is incomplete');
    }
    return watch.elapsedMicroseconds;
  } finally {
    await result.dispose();
    aborted.complete();
  }
}

final class _Credentials implements ApiCredentialReader {
  const _Credentials();
  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    await Future<void>.delayed(_platform);
    return 'fixture-key';
  }

  @override
  Future<String> clientId() async => '';
}

final class _Environment implements MediaDownloadEnvironment {
  _Environment(this.directory);
  final Directory directory;
  Uint8List? shared;
  int? saved;

  @override
  Future<String?> chooseSavePath({
    required String suggestedName,
    ({String label, String extension})? fileType,
  }) async => '${directory.path}/saved.mp4';

  @override
  Future<void> saveBytes(
    Uint8List bytes, {
    required String path,
    required String filename,
    required String mimeType,
  }) async => throw StateError('Unexpected image save');

  @override
  Future<void> saveFile(File file, String path) async =>
      saved = await file.length();

  @override
  Future<Directory> temporaryDirectory() async {
    await Future<void>.delayed(_platform);
    return directory;
  }

  @override
  Future<MediaShareOutcome> shareFile(
    File file, {
    String? filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    shared = await file.readAsBytes();
    return MediaShareOutcome.shared;
  }
}

final class _Encoder implements VideoEncoder {
  var calls = 0;
  @override
  Future<bool> isAvailable() async {
    await Future<void>.delayed(_platform);
    return true;
  }

  @override
  Future<bool> optimize({
    required int id,
    required String inputPath,
    required String outputPath,
  }) async {
    calls++;
    if (await File(inputPath).length() != _video.length) {
      throw StateError('The source was not staged completely');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await File(outputPath).writeAsBytes(Uint8List(128 * 1024));
    return true;
  }

  @override
  Future<void> cancel(int id) async {}
}
