import 'package:file_selector/file_selector.dart' as selector;
import 'package:image_picker/image_picker.dart' as image_picker;

import '../models/composer_upload.dart';

typedef ComposerFilePicker = Future<List<ComposerUploadFile>> Function();
typedef ComposerImagePicker = ComposerFilePicker;

Future<List<ComposerUploadFile>> pickComposerFiles() async {
  // Let the site/user validator decide which files are allowed. Native type
  // filters cannot describe every extension an instance may authorize.
  final files = await selector.openFiles(confirmButtonText: 'Upload');
  return composerUploadFilesFromSelection(files);
}

Future<List<ComposerUploadFile>> pickComposerImages() async {
  final files = await image_picker.ImagePicker().pickMultiImage(
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
