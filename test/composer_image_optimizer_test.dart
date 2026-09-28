import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/composer_image_codec.dart';
import 'package:discourse_native/src/data/composer_image_optimizer.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory temporary;
  late ComposerImageOptimizer optimizer;
  const settings = ComposerImageOptimization(
    bytesThreshold: 1,
    resizeDimensionsThreshold: 100,
    resizeWidthTarget: 60,
    encodeQuality: 75,
  );

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('optimizer-test-');
    optimizer = ComposerImageOptimizer(
      temporaryDirectory: () async => temporary,
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await temporary.delete(recursive: true);
  });

  Future<PreparedComposerUpload> prepare(
    ComposerUploadFile file, {
    ComposerImageOptimization options = settings,
    bool Function(String)? allowed,
    Future<void>? abort,
  }) => optimizer.prepare(
    file,
    settings: options,
    canUpload: allowed ?? (_) => true,
    abortTrigger: abort ?? Completer<void>().future,
  );

  test(
    'opaque PNG becomes a smaller JPEG with proportional dimensions',
    () async {
      final source = _file('photo.PNG', img.encodePng(_image(), level: 0));
      final result = await prepare(source);
      expect(result.file.name, 'photo.jpg');
      expect(result.file.imageOptimizationApplied, isTrue);
      expect(await result.file.length(), lessThan(await source.length()));
      final bytes = await _read(result.file);
      final decoded = img.decodeJpg(bytes)!;
      expect((decoded.width, decoded.height), (60, 40));
      expect(
        bytes.length,
        lessThan(20000),
        reason: 'small valid results are useful',
      );
      expect(
        await _read(result.file),
        bytes,
        reason: 'retry streams are repeatable',
      );
      expect(await temporary.list().length, 1);
      await result.dispose();
      await result.dispose();
      expect(await temporary.list().length, 0);
    },
  );

  test('transparent PNG becomes WebP without flattening alpha', () async {
    final source = _file(
      'alpha.png',
      img.encodePng(_image(alpha: true), level: 0),
    );
    final result = await prepare(source);
    expect(result.file.name, 'alpha.webp');
    final decoded = img.decodeWebP(await _read(result.file))!;
    expect((decoded.width, decoded.height), (60, 40));
    expect(decoded.getPixel(5, 5).a, 128);
    expect(decoded.getPixel(50, 5).a, 255);
    await result.dispose();
  });

  test(
    'JPEG orientation is baked before resizing and EXIF is removed',
    () async {
      final image = _image();
      image.exif.imageIfd.orientation = 6;
      image.exif.imageIfd.make = 'Camera metadata';
      final source = _file('rotated.jpg', img.encodeJpg(image, quality: 100));
      final result = await prepare(source);
      expect(result.file, isNot(same(source)));
      final decoded = img.decodeJpg(await _read(result.file))!;
      expect((decoded.width, decoded.height), (80, 120));
      expect(decoded.exif.isEmpty, isTrue);
      await result.dispose();
    },
  );

  test('width threshold is independent of target and height', () async {
    final source = _file('wide.png', img.encodePng(_image(), level: 0));
    final result = await prepare(
      source,
      options: const ComposerImageOptimization(
        bytesThreshold: 1,
        resizeDimensionsThreshold: 120,
        resizeWidthTarget: 60,
      ),
    );
    final decoded = img.decodeJpg(await _read(result.file))!;
    expect((decoded.width, decoded.height), (120, 80));
    await result.dispose();
  });

  test('a custom target never upscales an image', () async {
    final source = _file('wide.png', img.encodePng(_image(), level: 0));
    final result = await prepare(
      source,
      options: const ComposerImageOptimization(
        bytesThreshold: 1,
        resizeDimensionsThreshold: 10,
        resizeWidthTarget: 1920,
      ),
    );
    final decoded = img.decodeJpg(await _read(result.file))!;
    expect((decoded.width, decoded.height), (120, 80));
    await result.dispose();
  });

  test('unauthorized output formats preserve the original', () async {
    for (final alpha in [false, true]) {
      final source = _file(
        'photo.png',
        img.encodePng(_image(alpha: alpha), level: 0),
      );
      final result = await prepare(
        source,
        allowed: (name) => !name.endsWith(alpha ? '.webp' : '.jpg'),
      );
      expect(result.file, same(source));
      expect(await temporary.list().length, 0);
    }
  });

  test('a larger JPEG result preserves the original PNG', () async {
    final small = img.Image(width: 1, height: 1);
    final source = _file('tiny.png', img.encodePng(small));
    final result = await prepare(source);
    expect(result.file, same(source));
    expect(await temporary.list().length, 0);
  });

  test('APNG, GIF and unsupported image data are preserved', () async {
    final animation = _image()..addFrame(_image(alpha: true));
    for (final source in [
      _file('animated.png', img.encodePng(animation)),
      _file('animated.gif', img.encodeGif(animation)),
      _file('disguised.jpg', img.encodeGif(animation)),
      _file(
        'broken.png',
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
    ]) {
      final result = await prepare(source);
      expect(result.file, same(source), reason: source.name);
      expect(await temporary.list().length, 0);
    }
  });

  test('oversized dimensions are rejected before pixel decoding', () async {
    final bytes = img.encodePng(_image());
    ByteData.sublistView(bytes).setUint32(16, composerImageMaxPixels + 1);
    final source = _file('giant.png', bytes);
    expect((await prepare(source)).file, same(source));
    expect(await temporary.list().length, 0);
  });

  test(
    'JPEG frame dimensions are inspected without allocating decoder buffers',
    () async {
      final header = Uint8List.fromList([
        0xff,
        0xd8,
        0xff,
        0xe0,
        0,
        4,
        0,
        0,
        0xff,
        0xff,
        0xc2,
        0,
        17,
        8,
        0x7f,
        0xff,
        0x7f,
        0xff,
        3,
        1,
        0x11,
        0,
        2,
        0x11,
        0,
        3,
        0x11,
        0,
        0xff,
        0xd9,
      ]);
      expect(composerImageDimensions(header), (width: 32767, height: 32767));
      final source = _file('giant.jpg', header);
      expect((await prepare(source)).file, same(source));
      expect(await temporary.list().length, 0);
    },
  );

  test(
    'an expensive worker times out and releases its files and queue slot',
    () async {
      optimizer = ComposerImageOptimizer(
        temporaryDirectory: () async => temporary,
        workerTimeout: const Duration(milliseconds: 10),
      );
      final large = img.copyResize(_image(alpha: true), width: 2400);
      final source = _file('slow.png', img.encodePng(large, level: 0));
      expect((await prepare(source)).file, same(source));
      expect(await temporary.list().length, 0);
      optimizer = ComposerImageOptimizer(
        temporaryDirectory: () async => temporary,
      );
      final result = await prepare(
        _file('next.png', img.encodePng(_image(), level: 0)),
      );
      expect(result.file.name, 'next.jpg');
      await result.dispose();
    },
  );

  test(
    'small, disabled, oversized and already encoded files are not read',
    () async {
      var reads = 0;
      ComposerUploadFile source({
        int length = 500,
        bool encoded = false,
        String name = 'photo.jpg',
      }) => ComposerUploadFile(
        name: name,
        length: () async => length,
        imageOptimizationApplied: encoded,
        openRead: () {
          reads++;
          throw StateError('Should not be read');
        },
      );
      for (final entry in [
        (source(), const ComposerImageOptimization()),
        (source(), const ComposerImageOptimization(enabled: false)),
        (source(length: composerImageMaxInputBytes + 1), settings),
        (source(encoded: true), settings),
        (source(name: 'notes.pdf'), settings),
        (source(name: 'photo.heic'), settings),
        (source(name: 'photo.jxl'), settings),
        (source(name: 'photo.webp'), settings),
      ]) {
        expect(
          (await prepare(entry.$1, options: entry.$2)).file,
          same(entry.$1),
        );
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final ios = source();
      expect(
        (await prepare(
          ios,
          options: const ComposerImageOptimization(
            iosEnabled: false,
            bytesThreshold: 1,
          ),
        )).file,
        same(ios),
      );
      expect(reads, 0);
      expect(await temporary.list().length, 0);
    },
  );

  test('cancelling queued work never overlaps the active image', () async {
    final firstStarted = Completer<void>();
    final firstStream = StreamController<List<int>>();
    final first = prepare(
      ComposerUploadFile(
        name: 'one.jpg',
        length: () async => 3,
        openRead: () {
          firstStarted.complete();
          return firstStream.stream;
        },
      ),
    );
    await firstStarted.future;
    var secondRead = false;
    var thirdRead = false;
    final abort = Completer<void>();
    final second = prepare(
      ComposerUploadFile(
        name: 'two.jpg',
        length: () async => 3,
        openRead: () {
          secondRead = true;
          return Stream.value([1, 2, 3]);
        },
      ),
      abort: abort.future,
    );
    final third = prepare(
      ComposerUploadFile(
        name: 'three.jpg',
        length: () async => 3,
        openRead: () {
          thirdRead = true;
          return Stream.value([1, 2, 3]);
        },
      ),
    );
    abort.complete();
    await second;
    expect(secondRead, isFalse);
    expect(thirdRead, isFalse);
    firstStream.add([1, 2, 3]);
    await firstStream.close();
    await first;
    await third;
    expect(thirdRead, isTrue);
    expect(await temporary.list().length, 0);
  });

  test(
    'files outside the byte limits never wait for the active image',
    () async {
      final firstStarted = Completer<void>();
      final firstStream = StreamController<List<int>>();
      final first = prepare(
        ComposerUploadFile(
          name: 'one.jpg',
          length: () async => 3,
          openRead: () {
            firstStarted.complete();
            return firstStream.stream;
          },
        ),
      );
      await firstStarted.future;
      var reads = 0;
      ComposerUploadFile source(int length) => ComposerUploadFile(
        name: 'photo.png',
        length: () async => length,
        openRead: () {
          reads++;
          throw StateError('Should not be read');
        },
      );
      for (final entry in [
        (source(10), const ComposerImageOptimization(bytesThreshold: 1 << 20)),
        (source(composerImageMaxInputBytes + 1), settings),
      ]) {
        PreparedComposerUpload? result;
        unawaited(
          prepare(entry.$1, options: entry.$2).then((value) => result = value),
        );
        await pumpEventQueue();
        expect(result?.file, same(entry.$1));
      }
      expect(reads, 0);
      firstStream.add([1, 2, 3]);
      await firstStream.close();
      await first;
      expect(await temporary.list().length, 0);
    },
  );

  test(
    'cancelling a stalled source releases the queue and temporary files',
    () async {
      final started = Completer<void>();
      final stream = StreamController<List<int>>();
      final abort = Completer<void>();
      final source = ComposerUploadFile(
        name: 'photo.jpg',
        length: () async => 10,
        openRead: () {
          started.complete();
          return stream.stream;
        },
      );
      final job = prepare(source, abort: abort.future);
      await started.future;
      abort.complete();
      expect((await job).file, same(source));
      await stream.close();
      expect(await temporary.list().length, 0);
      final next = _file('next.png', img.encodePng(_image(), level: 0));
      final result = await prepare(next);
      expect(result.file.name, 'next.jpg');
      await result.dispose();
    },
  );

  test('source errors fall back and clean temporary storage', () async {
    final source = ComposerUploadFile(
      name: 'photo.jpg',
      length: () async => 100,
      openRead: () => Stream.error(const FileSystemException('unreadable')),
    );
    expect((await prepare(source)).file, same(source));
    expect(await temporary.list().length, 0);
  });
}

img.Image _image({bool alpha = false}) {
  final image = img.Image(width: 120, height: 80, numChannels: alpha ? 4 : 3);
  for (final pixel in image) {
    pixel.setRgba(
      pixel.x * 2,
      pixel.y * 3,
      (pixel.x + pixel.y) % 256,
      alpha && pixel.x < 60 ? 128 : 255,
    );
  }
  return image;
}

ComposerUploadFile _file(String name, Uint8List bytes) => ComposerUploadFile(
  name: name,
  length: () async => bytes.length,
  openRead: () => Stream.value(bytes),
);

Future<Uint8List> _read(ComposerUploadFile file) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
