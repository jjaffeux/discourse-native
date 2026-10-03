import '../models/composer_upload.dart';
import '../models/site_config.dart';
import 'composer_image_optimizer.dart';
import 'composer_video_optimizer.dart';

/// All composer surfaces prepare media here before applying upload size limits.
class ComposerMediaOptimizer {
  Future<PreparedComposerUpload> prepare(
    ComposerUploadFile file, {
    required ComposerImageOptimization imageSettings,
    required bool Function(String filename) canUpload,
    required Future<void> abortTrigger,
  }) => file.isVideo
      ? ComposerVideoOptimizer().prepare(
          file,
          canUpload: canUpload,
          abortTrigger: abortTrigger,
        )
      : ComposerImageOptimizer().prepare(
          file,
          settings: imageSettings,
          canUpload: canUpload,
          abortTrigger: abortTrigger,
        );
}
