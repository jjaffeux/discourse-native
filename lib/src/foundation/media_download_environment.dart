import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

enum MediaShareOutcome { shared, cancelled }

abstract interface class MediaDownloadEnvironment {
  Future<String?> chooseSavePath({
    required String suggestedName,
    ({String label, String extension})? fileType,
  });

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
