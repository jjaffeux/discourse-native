import 'package:file_selector/file_selector.dart' as selector;

import '../models/composer_upload.dart';
import '../models/site_config.dart';

typedef ComposerImagePicker = Future<List<ComposerUploadFile>> Function();

/// Opens the platform's multiple-file picker for images the native composer
/// knows how to render, then adapts its files to the app-owned upload boundary.
Future<List<ComposerUploadFile>> pickComposerImages() async {
  final files = await selector.openFiles(
    acceptedTypeGroups: [_composerImageTypes],
    confirmButtonText: 'Upload',
  );
  return composerUploadFilesFromSelection(files);
}

/// Preserves the platform file's lazy length and byte-stream operations so an
/// upload can start immediately and retry without buffering the whole image.
List<ComposerUploadFile> composerUploadFilesFromSelection(
  Iterable<selector.XFile> files,
) {
  return List.unmodifiable([
    for (final file in files)
      ComposerUploadFile(
        name: file.name,
        length: file.length,
        openRead: file.openRead,
      ),
  ]);
}

final _composerImageTypes = selector.XTypeGroup(
  label: 'Images',
  extensions: SiteConfig.imageExtensions.toList(growable: false),
  // iOS requires a UTI while Android and Linux use MIME types/extensions.
  // Supplying each platform's native vocabulary keeps one picker definition
  // valid everywhere this app runs.
  mimeTypes: const ['image/*'],
  uniformTypeIdentifiers: const ['public.image'],
  webWildCards: const ['image/*'],
);
