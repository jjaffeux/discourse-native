import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/composer_image_optimizer.dart';
import 'package:discourse_native/src/data/composer_video_optimizer.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_video_optimizer/discourse_video_optimizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late _Encoder encoder;
  late ComposerVideoOptimizer optimizer;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    temporary = await Directory.systemTemp.createTemp('video-optimizer-test-');
    encoder = _Encoder();
    optimizer = ComposerVideoOptimizer(
      native: encoder,
      temporaryDirectory: () async => temporary,
      minimumBytes: 1,
      maximumBytes: 100,
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await temporary.delete(recursive: true);
  });

  Future<PreparedComposerUpload> prepare({
    ComposerUploadFile? file,
    Future<void>? abort,
    bool Function(String)? canUpload,
  }) => optimizer.prepare(
    file ?? _file(),
    canUpload: canUpload ?? (_) => true,
    abortTrigger: abort ?? Completer<void>().future,
  );

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    test('smaller MP4 owns reusable output on ${platform.name}', () async {
      debugDefaultTargetPlatformOverride = platform;
      final result = await prepare();
      expect(result.file.name, 'movie.mp4');
      expect(await result.file.length(), 2);
      expect(await result.file.openRead().expand((chunk) => chunk).toList(), [
        1,
        2,
      ]);
      expect(await result.file.openRead().expand((chunk) => chunk).toList(), [
        1,
        2,
      ]);
      expect(
        await temporary
            .list(recursive: true)
            .where((entry) => entry is File)
            .length,
        1,
      );
      await result.dispose();
      await result.dispose();
      expect(await temporary.list().length, 0);
      expect(encoder.starts, 1);
    });
  }

  for (final (size, shouldOptimize) in [
    (1024 * 1024 - 1, false),
    (1024 * 1024, true),
    (2 * 1024 * 1024, true),
  ]) {
    test('default video threshold at $size bytes', () async {
      optimizer = ComposerVideoOptimizer(
        native: encoder,
        temporaryDirectory: () async => temporary,
      );
      final source = _file(size: size);

      final result = await prepare(file: source);

      expect(encoder.starts, shouldOptimize ? 1 : 0);
      if (shouldOptimize) {
        expect(result.file.name, 'movie.mp4');
        expect(await result.file.length(), 2);
      } else {
        expect(result.file, same(source));
        expect(encoder.availabilityChecks, 0);
      }
      await result.dispose();
      expect(await temporary.list().length, 0);
    });
  }

  test(
    'Linux passes through without invoking the platform or reading data',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final source = _file();
      expect((await prepare(file: source)).file, same(source));
      expect(encoder.availabilityChecks, 0);
      expect(encoder.starts, 0);
    },
  );

  test(
    'small, oversized, non-video and unauthorized MP4 bypass encoding',
    () async {
      for (final source in [
        _file(size: 0),
        _file(size: 101),
        _file(name: 'photo.jpg'),
      ]) {
        expect((await prepare(file: source)).file, same(source));
      }
      final source = _file();
      expect(
        (await prepare(
          file: source,
          canUpload: (name) => name.endsWith('.MOV'),
        )).file,
        same(source),
      );
      expect(encoder.availabilityChecks, 0);
      expect(await temporary.list().length, 0);
    },
  );

  test('missing plugin uploads the original without staging it', () async {
    optimizer = ComposerVideoOptimizer(
      minimumBytes: 1,
      temporaryDirectory: () async => temporary,
    );
    final source = _file();
    expect((await prepare(file: source)).file, same(source));
    expect(await temporary.list().length, 0);
  });

  for (final failure in [
    'unavailable',
    'exception',
    'false',
    'larger',
    'empty',
    'missing',
  ]) {
    test('$failure falls back and removes temporary data', () async {
      encoder.available = failure != 'unavailable';
      encoder.encode = (input, output) async {
        if (failure == 'exception') {
          throw PlatformException(code: 'unsupported_codec');
        }
        if (failure == 'missing') return true;
        await File(
          output,
        ).writeAsBytes(failure == 'larger' ? List.filled(20, 0) : []);
        return failure != 'false';
      };
      final source = _file();
      expect((await prepare(file: source)).file, same(source));
      expect(await temporary.list().length, 0);
    });
  }

  test('cancellation stops the encoder before releasing its files', () async {
    final abort = Completer<void>();
    final result = Completer<bool>();
    final started = Completer<void>();
    final stopped = Completer<void>();
    encoder.encode = (input, output) {
      started.complete();
      encoder.onCancel = () async {
        expect(await File(input).exists(), isTrue);
        await stopped.future;
        result.complete(false);
      };
      return result.future;
    };
    final pending = prepare(abort: abort.future);
    await started.future;
    abort.complete();
    await Future<void>.delayed(Duration.zero);
    expect(await temporary.list().length, 1);
    stopped.complete();
    await pending;
    expect(encoder.cancels, 1);
    expect(await temporary.list().length, 0);
  });

  test(
    'cancelled queued selection cannot let the next encoder overlap',
    () async {
      final firstStarted = Completer<void>();
      final firstGate = Completer<void>();
      encoder.encode = (input, output) async {
        if (encoder.starts == 1) {
          firstStarted.complete();
          await firstGate.future;
        }
        await File(output).writeAsBytes([1]);
        return true;
      };
      final first = prepare();
      await firstStarted.future;
      final abort = Completer<void>();
      final cancelled = prepare(abort: abort.future);
      final third = prepare();
      await Future<void>.delayed(Duration.zero);
      abort.complete();
      await cancelled;
      expect(encoder.starts, 1);
      firstGate.complete();
      await (await first).dispose();
      await (await third).dispose();
      expect(encoder.starts, 2);
      expect(await temporary.list().length, 0);
    },
  );

  test(
    'cancellation while staging stops reading and never starts native work',
    () async {
      final stream = StreamController<List<int>>();
      final abort = Completer<void>();
      final listening = Completer<void>();
      stream.onListen = listening.complete;
      stream.onCancel = () {};
      final source = ComposerUploadFile(
        name: 'movie.mov',
        length: () async => 10,
        openRead: () => stream.stream,
      );
      final pending = prepare(file: source, abort: abort.future);
      await listening.future;
      abort.complete();
      expect((await pending).file, same(source));
      await stream.close();
      expect(encoder.starts, 0);
      expect(await temporary.list().length, 0);
    },
  );

  test('truncated streams never reach the encoder', () async {
    final source = ComposerUploadFile(
      name: 'movie.mov',
      length: () async => 10,
      openRead: () => Stream.value([1]),
    );
    expect((await prepare(file: source)).file, same(source));
    expect(encoder.starts, 0);
    expect(await temporary.list().length, 0);
  });

  test('active image staging does not block the video lane', () async {
    final listening = Completer<void>();
    final stream = StreamController<List<int>>(onListen: listening.complete);
    final image = ComposerImageOptimizer(
      temporaryDirectory: () async => temporary,
    );
    final pendingImage = image.prepare(
      ComposerUploadFile(
        name: 'photo.jpg',
        length: () async => 3,
        openRead: () => stream.stream,
      ),
      settings: const ComposerImageOptimization(bytesThreshold: 1),
      canUpload: (_) => true,
      abortTrigger: Completer<void>().future,
    );
    await listening.future;
    final video = await prepare();
    expect(encoder.starts, 1);
    await video.dispose();
    stream.add([1, 2, 3]);
    await stream.close();
    await (await pendingImage).dispose();
    expect(await temporary.list().length, 0);
  });

  for (final failure in ['surplus', 'read-error', 'stalled']) {
    test(
      '$failure staging falls back before native encoding and cleans files',
      () async {
        optimizer = ComposerVideoOptimizer(
          native: encoder,
          temporaryDirectory: () async => temporary,
          minimumBytes: 1,
          maximumBytes: 100,
          ioTimeout: const Duration(milliseconds: 20),
        );
        final stream = StreamController<List<int>>();
        final source = ComposerUploadFile(
          name: 'movie.mov',
          length: () async => 10,
          openRead: () => switch (failure) {
            'surplus' => Stream.value(List.filled(11, 1)),
            'read-error' => Stream.error(StateError('unreadable')),
            _ => stream.stream,
          },
        );
        expect((await prepare(file: source)).file, same(source));
        if (failure == 'stalled') await stream.close();
        expect(encoder.starts, 0);
        expect(await temporary.list().length, 0);
      },
    );
  }

  test('stalled export is cancelled and falls back', () async {
    optimizer = ComposerVideoOptimizer(
      native: encoder,
      minimumBytes: 1,
      temporaryDirectory: () async => temporary,
      encodingTimeout: const Duration(milliseconds: 10),
    );
    final result = Completer<bool>();
    encoder.encode = (_, _) => result.future;
    encoder.onCancel = () async => result.complete(false);
    final source = _file();
    expect((await prepare(file: source)).file, same(source));
    expect(encoder.cancels, 1);
    expect(await temporary.list().length, 0);
  });
}

ComposerUploadFile _file({String name = 'movie.MOV', int size = 10}) =>
    ComposerUploadFile(
      name: name,
      length: () async => size,
      openRead: () => Stream.value(List.filled(size, 1)),
    );

class _Encoder extends NativeVideoOptimizer {
  bool available = true;
  int availabilityChecks = 0;
  int starts = 0;
  int cancels = 0;
  Future<void> Function()? onCancel;
  Future<bool> Function(String, String) encode = (input, output) async {
    await File(output).writeAsBytes([1, 2]);
    return true;
  };

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<bool> optimize({
    required int id,
    required String inputPath,
    required String outputPath,
  }) {
    starts++;
    return encode(inputPath, outputPath);
  }

  @override
  Future<void> cancel(int id) async {
    cancels++;
    await onCancel?.call();
  }
}
