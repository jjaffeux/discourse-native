import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../data/composer_media_preparation.dart';
import '../../data/site_video_thumbnail_repository.dart';
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
  VideoThumbnailRequest? _thumbnail;
  bool get isVideo => original.isVideo;

  static ComposerUploadPreview? forFile(ComposerUploadFile file) =>
      file.isVideo || SiteConfig.isImageFilename(file.name)
      ? ComposerUploadPreview._(file)
      : null;

  Future<void> _stage() async {
    try {
      final length = await Future.any<int?>([
        original.length(),
        _aborted.future.then((_) => null),
      ]).timeout(const Duration(seconds: 30));
      final limit = isVideo ? 2 * 1024 * 1024 * 1024 : 32 * 1024 * 1024;
      if (_references == 0 || length == null || length <= 0 || length > limit)
        return;
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
      notifyListeners();
      if (isVideo &&
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        final request = generateNativeVideoThumbnail(staged.uri);
        _thumbnail = request;
        try {
          final bytes = await request.result;
          if (_references > 0 && identical(_thumbnail, request)) {
            poster = bytes;
            notifyListeners();
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
    super.dispose();
  }

  Future<void> _removeFile() async {
    final directory = _directory;
    _directory = null;
    file = null;
    poster = null;
    if (directory == null) return;
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary storage can be reclaimed by the operating system.
    }
  }
}
