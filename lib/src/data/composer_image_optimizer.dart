import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/composer_upload.dart';
import '../models/site_config.dart';
import 'composer_image_codec.dart';

/// Serializes image work across composers; the network uploads can still run
/// concurrently. Callers own the returned preparation through retries.
class ComposerImageOptimizer {
  ComposerImageOptimizer({
    Future<Directory> Function()? temporaryDirectory,
    this.workerTimeout = const Duration(seconds: 30),
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectory;
  final Duration workerTimeout;
  static Future<void>? _queue;

  Future<PreparedComposerUpload> prepare(
    ComposerUploadFile file, {
    required ComposerImageOptimization settings,
    required bool Function(String filename) canUpload,
    required Future<void> abortTrigger,
  }) async {
    final original = PreparedComposerUpload(file);
    if (!settings.enabled ||
        (defaultTargetPlatform == TargetPlatform.iOS && !settings.iosEnabled) ||
        file.imageOptimizationApplied ||
        !RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(file.name)) {
      return original;
    }
    final baseName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final allowJpeg = canUpload('$baseName.jpg');
    final allowWebp = canUpload('$baseName.webp');
    if (!allowJpeg && !allowWebp) return original;

    var cancelled = false;
    final aborted = abortTrigger.then((_) => cancelled = true);
    Completer<void>? slot;
    Directory? directory;
    var retained = false;
    try {
      // The size limits are decided before queueing: a file that will never
      // be encoded must not wait behind another composer's image.
      final length = await Future.any<int?>([
        file.length(),
        aborted.then((_) => null),
      ]);
      if (length == null ||
          length < settings.bytesThreshold ||
          length > composerImageMaxInputBytes) {
        return original;
      }
      // A cancelled queued job must not release the next job ahead of the
      // image that currently owns the worker slot.
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
      directory = await root.createTemp('composer-image-');
      final input = File('${directory.path}/source');
      final output = File('${directory.path}/optimized');
      final iterator = StreamIterator(file.openRead());
      final sink = input.openWrite();
      try {
        var copied = 0;
        while (await Future.any<bool>([
          iterator.moveNext(),
          aborted.then((_) => false),
        ]).timeout(workerTimeout)) {
          if (cancelled) return original;
          copied += iterator.current.length;
          if (copied > composerImageMaxInputBytes) return original;
          sink.add(iterator.current);
        }
      } finally {
        await iterator.cancel();
        await sink.close();
      }
      if (cancelled) return original;
      final port = ReceivePort();
      Isolate? worker;
      Object? extension;
      try {
        final reply = port.first;
        worker = await Isolate.spawn(
          _encode,
          (
            port: port.sendPort,
            inputPath: input.path,
            outputPath: output.path,
            resizeThreshold: settings.resizeDimensionsThreshold,
            resizeTarget: settings.resizeWidthTarget,
            quality: settings.quality,
            allowJpeg: allowJpeg,
            allowWebp: allowWebp,
          ),
          onError: port.sendPort,
          onExit: port.sendPort,
        );
        extension = await Future.any<Object?>([
          reply,
          aborted.then((_) => null),
        ]).timeout(workerTimeout);
      } finally {
        worker?.kill(priority: Isolate.immediate);
        port.close();
      }
      if (cancelled || extension is! String) return original;
      await input.delete();
      final ownedDirectory = directory;
      retained = true;
      return PreparedComposerUpload(
        ComposerUploadFile(
          name: '$baseName.$extension',
          length: output.length,
          openRead: output.openRead,
          imageOptimizationApplied: true,
        ),
        release: () => _removeDirectory(ownedDirectory),
      );
    } catch (_) {
      // Optimization is optional; read/codec/cache failures must not prevent
      // the normal upload path from trying the original file.
      return original;
    } finally {
      if (!retained && directory != null) await _removeDirectory(directory);
      slot?.complete();
    }
  }
}

Future<void> _removeDirectory(Directory directory) async {
  try {
    await directory.delete(recursive: true);
  } on FileSystemException {
    // The OS may have already reclaimed temporary storage.
  }
}

typedef _ImageJob = ({
  SendPort port,
  String inputPath,
  String outputPath,
  int resizeThreshold,
  int resizeTarget,
  int quality,
  bool allowJpeg,
  bool allowWebp,
});

void _encode(_ImageJob job) {
  job.port.send(
    encodeComposerImage(
      inputPath: job.inputPath,
      outputPath: job.outputPath,
      resizeThreshold: job.resizeThreshold,
      resizeTarget: job.resizeTarget,
      quality: job.quality,
      allowJpeg: job.allowJpeg,
      allowWebp: job.allowWebp,
    ),
  );
}
