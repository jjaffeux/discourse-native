import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

import '../models/composer_upload.dart';

typedef ComposerClipboardImageReader =
    Future<List<ComposerUploadFile>> Function();

/// Reads a native clipboard image into the composer's retryable upload shape.
Future<List<ComposerUploadFile>> readComposerClipboardImages() async {
  final image = await Pasteboard.image;
  if (image == null || image.isEmpty) return const [];

  // Native clipboard representations vary (TIFF is common on macOS), but the
  // plugin normalizes the bytes to PNG before they cross this boundary.
  final bytes = Uint8List.fromList(image);
  return List.unmodifiable([
    ComposerUploadFile(
      name: 'pasted-image.png',
      length: () async => bytes.length,
      openRead: () => Stream<List<int>>.value(bytes),
    ),
  ]);
}
