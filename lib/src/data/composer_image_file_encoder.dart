import 'dart:io';

import 'composer_image_codec.dart';

String? encodeComposerImage({
  required String inputPath,
  required String outputPath,
  required int resizeThreshold,
  required int resizeTarget,
  required int quality,
  required bool allowJpeg,
  required bool allowWebp,
}) {
  final input = File(inputPath);
  if (input.lengthSync() > composerImageMaxInputBytes) return null;
  final result = encodeComposerImageBytes(
    input.readAsBytesSync(),
    resizeThreshold: resizeThreshold,
    resizeTarget: resizeTarget,
    quality: quality,
    allowJpeg: allowJpeg,
    allowWebp: allowWebp,
  );
  if (result == null) return null;
  File(outputPath).writeAsBytesSync(result.bytes);
  return result.extension;
}
