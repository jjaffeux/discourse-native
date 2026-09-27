import 'dart:io';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../models/composer_upload.dart';
import 'composer_upload_picker.dart';

typedef ComposerClipboardFileReader =
    Future<List<ComposerUploadFile>> Function();

const _macOSPasteboard = MethodChannel('org.discourse.native/pasteboard');

/// Reads native clipboard files or pixels into retryable uploads.
Future<List<ComposerUploadFile>> readComposerClipboardFiles() async {
  // Finder publishes both a file URL and an NSImage representation when a user
  // copies an image file. AppKit may coerce that NSImage into the generic file
  // icon, so prefer the original file and its pixels whenever it is available.
  final paths = await _copiedFilePaths();
  if (paths.isNotEmpty) {
    // Paste starts uploading at once, so each path must still name a regular
    // file. When none does (a copied folder, a file moved since), paste falls
    // through to text rather than to the pixels, which are only Finder's icon.
    final files = [
      for (final path in paths)
        if (await FileSystemEntity.isFile(path)) selector.XFile(path),
    ];
    return composerUploadFilesFromSelection(files);
  }

  // Excel, Numbers and Word publish PDF or TIFF renderings beside the copied
  // text, and the plugin accepts any flavour NSImage can read as the image.
  // As on Discourse web, any plain text wins over clipboard pixels, so only a
  // clipboard without text (a screenshot) uploads them; a browser's Copy Image
  // that also publishes its address as text pastes that address instead.
  if (await Clipboard.hasStrings()) return const [];

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

Future<List<String>> _copiedFilePaths() async {
  // On macOS the plugin reduces every URL to its path, so a copied web link
  // `https://host/Users/me/secret` would name a local file. The runner reads
  // file URLs only (darwin/PasteboardFilePaths.swift). On Linux the plugin
  // resolves only file:// URIs, and on iOS it reads no files.
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return await _macOSPasteboard.invokeListMethod<String>('fileURLPaths') ??
        const [];
  }
  return Pasteboard.files();
}
