import 'package:discourse_native/l10n/strings.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import '../../models/composer_upload.dart';
import '../../models/site_config.dart';

typedef ComposerFilePicker = Future<List<ComposerUploadFile>> Function();
typedef ComposerImagePicker = ComposerFilePicker;

Future<List<ComposerUploadFile>> pickComposerFiles() async {
  // Let the site/user validator decide which files are allowed. Native type
  // filters cannot describe every extension an instance may authorize.
  final files = await selector.openFiles(confirmButtonText: appL10n.upload);
  return composerUploadFilesFromSelection(files);
}

/// Picks only photos for image galleries.
Future<List<ComposerUploadFile>> pickComposerImages({
  ComposerImageOptimization optimization = const ComposerImageOptimization(),
  int? limit,
}) => _pickComposerLibrary(
  optimization: optimization,
  limit: limit,
  imagesOnly: true,
);

/// Picks photos and videos for composer attachments.
///
/// [optimization] is the site's; mobile pickers apply it during photo export.
/// [limit] keeps a selection within the batch the composer accepts.
Future<List<ComposerUploadFile>> pickComposerMedia({
  ComposerImageOptimization optimization = const ComposerImageOptimization(),
  int? limit,
}) => _pickComposerLibrary(
  optimization: optimization,
  limit: limit,
  imagesOnly: false,
);

Future<List<ComposerUploadFile>> _pickComposerLibrary({
  required ComposerImageOptimization optimization,
  required int? limit,
  required bool imagesOnly,
}) async {
  final picker = image_picker.ImagePicker();
  final pick = imagesOnly ? picker.pickMultiImage : picker.pickMultipleMedia;
  final files = await pick(
    maxWidth: optimization
        .resizeWidth(ios: defaultTargetPlatform == TargetPlatform.iOS)
        ?.toDouble(),
    imageQuality: optimization.quality,
    limit: limit != null && limit > 0 ? limit : null,
    requestFullMetadata: false,
  );
  return composerUploadFilesFromSelection(
    files,
    photosAlreadyEncoded:
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android,
  );
}

List<ComposerUploadFile> composerUploadFilesFromSelection(
  Iterable<selector.XFile> files, {
  bool photosAlreadyEncoded = false,
}) {
  return List.unmodifiable([
    for (final file in files)
      ComposerUploadFile(
        name: file.name,
        length: file.length,
        openRead: file.openRead,
        // The mobile picker already resized and encoded JPEG photos. PNGs
        // still need the shared transparency/format decision before upload.
        imageOptimizationApplied:
            photosAlreadyEncoded &&
            RegExp(r'\.(jpe?g)$', caseSensitive: false).hasMatch(file.name),
      ),
  ]);
}
