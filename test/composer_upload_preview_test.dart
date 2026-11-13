import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/shell/composer/upload_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'release from the staged-file notification skips native generation',
    () async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('org.discourse.native/video_thumbnails');
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previous;
        messenger.setMockMethodCallHandler(channel, null);
      });

      final preview = ComposerUploadPreview.forFile(
        ComposerUploadFile(
          name: 'video.mp4',
          length: () async => 4,
          openRead: () => Stream.value([1, 2, 3, 4]),
        ),
      )!;
      late File staged;
      preview.addListener(() {
        staged = preview.file!;
        preview.release();
      });
      await preview.ready;
      await _waitUntilRemoved(staged);
      expect(calls, isEmpty);
    },
  );

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    test(
      'staged video requests native artwork on supported platforms ($platform)',
      () async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('org.discourse.native/video_thumbnails');
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'generate' ? Uint8List.fromList([42]) : null;
        });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = previous;
          messenger.setMockMethodCallHandler(channel, null);
        });

        final preview = ComposerUploadPreview.forFile(
          ComposerUploadFile(
            name: 'video.mp4',
            length: () async => 4,
            openRead: () => Stream.value([1, 2, 3, 4]),
          ),
        )!;
        await preview.ready;
        final staged = preview.file!;
        try {
          if (platform == TargetPlatform.macOS) {
            expect(calls.map((call) => call.method), ['generate', 'cancel']);
            expect(preview.poster, [42]);
          } else {
            expect(calls, isEmpty);
            expect(preview.poster, isNull);
          }
        } finally {
          preview.release();
          await _waitUntilRemoved(staged);
        }
      },
    );
  }

  test(
    'a viewer retains its staged original after the upload is removed',
    () async {
      final preview = ComposerUploadPreview.forFile(
        ComposerUploadFile(
          name: 'photo.png',
          length: () async => 4,
          openRead: () => Stream.value([1, 2, 3, 4]),
        ),
      )!;
      await preview.ready;
      final file = preview.file!;
      if (Platform.isMacOS || Platform.isLinux) {
        expect((await file.stat()).mode & 0x1ff, 0x180);
        expect((await file.parent.stat()).mode & 0x1ff, 0x1c0);
      }
      final releaseViewer = preview.retain();
      preview.release();
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      releaseViewer();
      releaseViewer();
      await _waitUntilRemoved(file);
    },
  );

  test('cancelled staging cannot publish a late file', () async {
    final bytes = StreamController<List<int>>();
    final preview = ComposerUploadPreview.forFile(
      ComposerUploadFile(
        name: 'video.mp4',
        length: () async => 4,
        openRead: () => bytes.stream,
      ),
    )!;
    final loading = preview.ready;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    preview.release();
    await loading;
    expect(preview.file, isNull);
    await bytes.close();
  });

  test(
    'cancellation does not wait for file metadata that never returns',
    () async {
      final length = Completer<int>();
      final preview = ComposerUploadPreview.forFile(
        ComposerUploadFile(
          name: 'photo.png',
          length: () => length.future,
          openRead: () =>
              throw StateError('Cancelled metadata must not read bytes'),
        ),
      )!;
      final loading = preview.ready;
      preview.release();
      await loading.timeout(const Duration(seconds: 1));
      expect(preview.file, isNull);
      length.complete(10);
      await Future<void>.delayed(Duration.zero);
      expect(preview.file, isNull);
    },
  );

  test('oversized files and non-media do not create previews', () async {
    var opened = false;
    ComposerUploadFile file(String name, int size) => ComposerUploadFile(
      name: name,
      length: () async => size,
      openRead: () {
        opened = true;
        return Stream.value([1]);
      },
    );
    expect(ComposerUploadPreview.forFile(file('data.zip', 1)), isNull);
    final preview = ComposerUploadPreview.forFile(
      file('huge.png', 33 * 1024 * 1024),
    )!;
    await preview.ready;
    expect(preview.file, isNull);
    expect(opened, isFalse);
    preview.release();
  });

  test('a false declared length does not expose a partial preview', () async {
    final preview = ComposerUploadPreview.forFile(
      ComposerUploadFile(
        name: 'photo.png',
        length: () async => 2,
        openRead: () => Stream.value([1, 2, 3]),
      ),
    )!;
    await preview.ready;
    expect(preview.file, isNull);
    preview.release();
  });
}

Future<void> _waitUntilRemoved(File file) async {
  for (var attempt = 0; attempt < 100 && await file.exists(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(await file.exists(), isFalse);
}
