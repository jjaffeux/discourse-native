import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../data/composer_media_preparation.dart';
import '../../data/native_thumbnail_generator.dart';
import '../../data/thumbnail_request.dart';
import '../../foundation/private_file_staging.dart';
import '../../models/composer_upload.dart';
import '../../models/site_config.dart';

/// A staged original survives removal while a media viewer still holds it.
final class ComposerUploadPreview extends ChangeNotifier {
  ComposerUploadPreview._(this.original);

  final ComposerUploadFile original;
  Future<void>? _ready;
  Future<void> get ready => _ready ??= _stage();
  void start() => unawaited(ready);
  File? file;
  Uint8List? poster;
  int? width;
  int? height;
  Directory? _directory;
  final _aborted = Completer<void>();
  int _references = 1;
  bool _notifying = false;
  ThumbnailRequest? _thumbnail;
  bool get isVideo => original.isVideo;

  static ComposerUploadPreview? forFile(ComposerUploadFile file) =>
      file.isVideo || SiteConfig.isImageFilename(file.name)
      ? ComposerUploadPreview._(file)
      : null;

  Future<void> _stage() async {
    if (_references == 0) return;
    try {
      final length = await Future.any<int?>([
        original.length(),
        _aborted.future.then((_) => null),
      ]).timeout(const Duration(seconds: 30));
      final limit = isVideo ? 2 * 1024 * 1024 * 1024 : 32 * 1024 * 1024;
      if (_references == 0 || length == null || length <= 0 || length > limit) {
        return;
      }
      final directory = await Directory.systemTemp.createTemp(
        'composer-preview-',
      );
      _directory = directory;
      final extension = RegExp(
        r'\.([a-zA-Z0-9]+)$',
      ).firstMatch(original.name)?.group(1)?.toLowerCase();
      if (extension == null) return;
      final staged = File('${directory.path}/preview.$extension');
      if (!await stageComposerMedia(
            source: original.openRead(),
            input: staged,
            length: length,
            maximumBytes: limit,
            aborted: _aborted.future,
            timeout: const Duration(seconds: 30),
          ) ||
          _references == 0) {
        return;
      }
      file = staged;
      if (!isVideo) {
        try {
          final buffer = await ui.ImmutableBuffer.fromFilePath(staged.path);
          try {
            final descriptor = await ui.ImageDescriptor.encoded(buffer);
            width = descriptor.width;
            height = descriptor.height;
            descriptor.dispose();
          } finally {
            buffer.dispose();
          }
        } catch (_) {
          // The image widget presents the same unavailable-media fallback.
        }
      }
      if (_references == 0) return;
      _publish();
      if (_references > 0 && isVideo && nativeThumbnailsSupported) {
        final request = generateNativeVideoThumbnail(staged.uri);
        _thumbnail = request;
        try {
          final bytes = await Future.any<Uint8List?>([
            request.result,
            _aborted.future.then((_) => null),
          ]);
          if (_references > 0 && identical(_thumbnail, request)) {
            poster = bytes;
            _publish();
          }
        } finally {
          request.dispose();
          if (identical(_thumbnail, request)) _thumbnail = null;
        }
      }
    } catch (_) {
      // Unreadable media remains an ordinary cancellable attachment.
    } finally {
      if (_references == 0 || file == null) await _removeFile();
    }
  }

  VoidCallback retain() {
    if (_references == 0) throw StateError('Preview already released');
    _references++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      release();
    };
  }

  void release() {
    if (_references == 0) return;
    if (--_references != 0) return;
    _aborted.complete();
    _thumbnail?.dispose();
    _thumbnail = null;
    final staging = _ready;
    if (staging != null) unawaited(staging.then((_) => _removeFile()));
    if (!_notifying) super.dispose();
  }

  void _publish() {
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
      if (_references == 0) super.dispose();
    }
  }

  Future<void> _removeFile() async {
    final directory = _directory;
    _directory = null;
    file = null;
    poster = null;
    if (directory == null) return;
    await removeStagingDirectory(directory);
  }
}
