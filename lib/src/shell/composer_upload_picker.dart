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
  final files = await selector.openFiles(confirmButtonText: 'Upload');
  return composerUploadFilesFromSelection(files);
}

/// [optimization] is the site's, so that a photo leaves at the size the web
/// composer would upload; only iOS applies it. [limit] keeps a selection
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
  return composerUploadFilesFromSelection(files);
}

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
