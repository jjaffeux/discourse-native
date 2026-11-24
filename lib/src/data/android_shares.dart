import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/composer_upload.dart';

final class AndroidShare {
  const AndroidShare(this.text, this.mediaUris, this.mimeType);

  final String? text;
  final List<String> mediaUris;
  final String? mimeType;
}

/// Android makes the selected files available in the app's cache so composer
/// uploads can reopen them for retries and media optimization.
final class ImportedAndroidShareMedia {
  const ImportedAndroidShareMedia(this.files, this._directory);

  final List<ComposerUploadFile> files;
  final Directory? _directory;

  Future<void> dispose() async {
    try {
      await _directory?.delete(recursive: true);
    } on FileSystemException {
      // The OS may already have evicted the cache entry.
    }
  }
}

final class PlatformAndroidShares {
  static const _channel = MethodChannel('org.discourse.native/android_shares');

  late final StreamController<AndroidShare> _shares =
      StreamController<AndroidShare>(
        onListen: () {
          _channel.setMethodCallHandler((call) async {
            if (call.method != 'receive' ||
                call.arguments is! Map<Object?, Object?>) {
              return;
            }
            final payload = call.arguments as Map<Object?, Object?>;
            final text = payload['text'] as String?;
            final uris = (payload['uris'] as List<Object?>).cast<String>();
            _shares.add(
              AndroidShare(text, uris, payload['mimeType'] as String?),
            );
          });
          unawaited(_listen());
        },
        onCancel: () => _channel.setMethodCallHandler(null),
      );

  Stream<AndroidShare> get shares => _shares.stream;

  void dispose() => unawaited(_shares.close());

  Future<void> _listen() async {
    try {
      await _channel.invokeMethod<void>('listen');
    } on MissingPluginException {
      // Widget tests and other hosts may run without the Android runner.
    } on PlatformException {
      return;
    }
  }

  Future<ImportedAndroidShareMedia> importMedia(AndroidShare share) async {
    final payload = await _channel.invokeMapMethod<String, Object?>(
      'importMedia',
      {'uris': share.mediaUris, 'mimeType': share.mimeType},
    );
    final directory = payload?['directory'] as String?;
    final files = (payload?['files'] as List<Object?>?) ?? const [];
    return ImportedAndroidShareMedia([
      for (final entry in files.cast<Map<Object?, Object?>>())
        _upload(File(entry['path'] as String), entry['name'] as String),
    ], directory == null ? null : Directory(directory));
  }

  ComposerUploadFile _upload(File file, String name) => ComposerUploadFile(
    name: name,
    length: file.length,
    openRead: file.openRead,
  );
}
