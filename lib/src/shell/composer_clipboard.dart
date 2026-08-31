import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:pasteboard/pasteboard.dart';

import '../models/composer_upload.dart';
import 'composer_upload_picker.dart';

typedef ComposerClipboardImageReader =
    Future<List<ComposerUploadFile>> Function();

/// Reads native clipboard images into the composer's retryable upload shape.
Future<List<ComposerUploadFile>> readComposerClipboardImages() async {
  // Finder publishes both a file URL and an NSImage representation when a user
  // copies an image file. AppKit may coerce that NSImage into the generic file
  // icon, so prefer the original file and its pixels whenever it is available.
  final files = await Pasteboard.files();
  if (files.isNotEmpty) {
    return composerUploadFilesFromSelection(files.map(selector.XFile.new));
  }

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
