import 'dart:async';
import 'dart:io';

import 'package:discourse_video_optimizer/discourse_video_optimizer.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/composer_upload.dart';

/// Optional, bounded video preparation shared by post and chat composers.
class ComposerVideoOptimizer {
  ComposerVideoOptimizer({
    Future<Directory> Function()? temporaryDirectory,
    this.native = const NativeVideoOptimizer(),
    this.minimumBytes = 1024 * 1024,
    this.maximumBytes = 2 * 1024 * 1024 * 1024,
    this.ioTimeout = const Duration(seconds: 30),
    this.encodingTimeout = const Duration(minutes: 11),
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectory;
  final NativeVideoOptimizer native;
  final int minimumBytes;
  final int maximumBytes;
  final Duration ioTimeout;
  final Duration encodingTimeout;
  static Future<void>? _queue;
  static int _nextId = 0;

  Future<PreparedComposerUpload> prepare(
    ComposerUploadFile file, {
    required bool Function(String filename) canUpload,
    required Future<void> abortTrigger,
  }) async {
    final original = PreparedComposerUpload(file);
    if (kIsWeb ||
        !{
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.android,
        }.contains(defaultTargetPlatform) ||
        !file.isVideo) {
      return original;
    }
    final outputName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '.mp4');
    if (!canUpload(outputName)) return original;

    var cancelled = false;
    final aborted = abortTrigger.then((_) => cancelled = true);
    Directory? directory;
    Completer<void>? slot;
    var retained = false;
    int? jobId;
    Future<bool>? encoding;
    try {
      final length = await Future.any<int?>([
        file.length().timeout(ioTimeout),
        aborted.then((_) => null),
      ]);
      if (length == null || length < minimumBytes || length > maximumBytes) {
        return original;
      }
      final available = await Future.any<bool>([
        native.isAvailable().timeout(ioTimeout),
        aborted.then((_) => false),
      ]);
      if (!available || cancelled) return original;

      // Even a cancelled waiter keeps its position until its predecessor ends.
      // Otherwise a third selection could overlap the active hardware encoder.
      final previous = _queue ?? Future<void>.value();
      final done = Completer<void>();
      slot = done;
      final tail = previous.then((_) => done.future);
      _queue = tail;
      unawaited(
        tail.then((_) {
          if (identical(_queue, tail)) _queue = null;
        }),
      );
      await Future.any<Object?>([previous, aborted]);
      if (cancelled) return original;

      final root = await _temporaryDirectory();
      if (cancelled) return original;
      directory = await root.createTemp('composer-video-');
      final input = File('${directory.path}/source');
      final output = File('${directory.path}/optimized.mp4');
      final iterator = StreamIterator(file.openRead());
      final sink = await input.open(mode: FileMode.write);
      try {
        var copied = 0;
        while (await Future.any<bool>([
          iterator.moveNext().timeout(ioTimeout),
          aborted.then((_) => false),
        ])) {
          if (cancelled) return original;
          copied += iterator.current.length;
          if (copied > length || copied > maximumBytes) return original;
          // Await writes: buffering a multi-gigabyte stream in an IOSink can
          // exhaust memory even though the source itself is streamed.
          await sink.writeFrom(iterator.current);
        }
        if (cancelled || copied != length) return original;
      } finally {
        await iterator.cancel();
        await sink.close();
      }
      if (cancelled) return original;

      jobId = ++_nextId;
      encoding = native.optimize(
        id: jobId,
        inputPath: input.path,
        outputPath: output.path,
      );
      final success = await Future.any<bool>([
        encoding.timeout(encodingTimeout),
        aborted.then((_) => false),
      ]);
      if (cancelled || !success) return original;
      // Native implementations validate tracks, duration and geometry. The
      // final size check also protects against inefficient/already-small input.
      final size = await output.length();
      if (size <= 0 || size >= length || cancelled) return original;
      await input.delete();
      if (cancelled) return original;
      retained = true;
      final ownedDirectory = directory;
      return PreparedComposerUpload(
        ComposerUploadFile(
          name: outputName,
          length: output.length,
          openRead: output.openRead,
        ),
        release: () => _removeDirectory(ownedDirectory),
      );
    } catch (_) {
      // A missing plugin, unsupported codec, low storage, or export failure
      // keeps the original. Cancellation is still enforced by the composer.
      return original;
    } finally {
      if (!retained && jobId != null) {
        try {
          await native.cancel(jobId).timeout(ioTimeout);
        } catch (_) {
          // Older/unavailable implementations may have no cancellation method.
        }
        // Consume late failures. Native cancellation closes the encoder before
        // acknowledging, so cleanup never races a healthy native writer.
        if (encoding != null) {
          unawaited(encoding.then<void>((_) {}, onError: (Object _) {}));
        }
      }
      if (!retained && directory != null) await _removeDirectory(directory);
      slot?.complete();
    }
  }
}

Future<void> _removeDirectory(Directory directory) async {
  try {
    await directory.delete(recursive: true);
  } on FileSystemException {
    // The system may already have reclaimed temporary storage.
  }
}
