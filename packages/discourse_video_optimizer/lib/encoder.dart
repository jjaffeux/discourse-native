/// File-to-file video encoding. The caller owns staging and file lifetime.
abstract interface class VideoEncoder {
  Future<bool> isAvailable();

  /// Returns true after the encoder closes a complete MP4 output.
  Future<bool> optimize({
    required int id,
    required String inputPath,
    required String outputPath,
  });

  /// Completes when encoding has stopped and the files may be released.
  Future<void> cancel(int id);
}
