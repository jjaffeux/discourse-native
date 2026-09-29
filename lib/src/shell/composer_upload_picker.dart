import 'package:discourse_native/l10n/strings.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as image_picker;

import '../models/composer_upload.dart';
import '../models/site_config.dart';

typedef ComposerFilePicker = Future<List<ComposerUploadFile>> Function();
typedef ComposerImagePicker = ComposerFilePicker;

Future<List<ComposerUploadFile>> pickComposerFiles() async {
  // Let the site/user validator decide which files are allowed. Native type
  // filters cannot describe every extension an instance may authorize.
  final files = await selector.openFiles(confirmButtonText: appL10n.upload);
  return composerUploadFilesFromSelection(files);
}

/// [optimization] is the site's; mobile pickers apply it during photo export.
/// [limit] keeps a selection
/// within the batch the composer accepts, which would otherwise refuse all
/// of it.
Future<List<ComposerUploadFile>> pickComposerImages({
  ComposerImageOptimization optimization = const ComposerImageOptimization(),
  int? limit,
}) async {
  final files = await image_picker.ImagePicker().pickMultiImage(
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
