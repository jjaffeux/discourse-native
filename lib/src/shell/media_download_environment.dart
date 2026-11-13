import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart' as selector;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as sharing;

import 'media_download_result.dart';

abstract interface class MediaDownloadEnvironment {
  Future<String?> chooseSavePath({required String suggestedName});

  Future<void> saveBytes(
    Uint8List bytes, {
    required String path,
    required String filename,
    required String mimeType,
  });

  Future<void> saveFile(File file, String path);

  Future<Directory> temporaryDirectory();

  Future<MediaShareOutcome> shareFile(
    File file, {
    String? filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  });
}

final class NativeMediaDownloadEnvironment implements MediaDownloadEnvironment {
  const NativeMediaDownloadEnvironment();

  @override
  Future<String?> chooseSavePath({required String suggestedName}) async {
    final destination = await selector.getSaveLocation(
      suggestedName: suggestedName,
    );
    return destination?.path;
  }

  @override
  Future<void> saveBytes(
    Uint8List bytes, {
    required String path,
    required String filename,
    required String mimeType,
  }) => selector.XFile.fromData(
    bytes,
    name: filename,
    mimeType: mimeType,
  ).saveTo(path);

  @override
  Future<void> saveFile(File file, String path) =>
      selector.XFile(file.path).saveTo(path);

  @override
  Future<Directory> temporaryDirectory() => getTemporaryDirectory();

  @override
  Future<MediaShareOutcome> shareFile(
    File file, {
    String? filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    final result = await sharing.SharePlus.instance.share(
      sharing.ShareParams(
        files: [sharing.XFile(file.path, mimeType: mimeType)],
        fileNameOverrides: filename == null ? null : [filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return result.status == sharing.ShareResultStatus.dismissed
        ? MediaShareOutcome.cancelled
        : MediaShareOutcome.shared;
  }
}
