import 'package:flutter/services.dart';

import 'encoder.dart';

/// File-to-file encoding. The caller owns staging, queuing and output lifetime.
class NativeVideoOptimizer implements VideoEncoder {
  const NativeVideoOptimizer();

  static const _channel = MethodChannel('org.discourse.native/video_optimizer');

  @override
  Future<bool> isAvailable() async =>
      await _channel.invokeMethod<bool>('isAvailable') ?? false;

  /// Returns true only after the encoder has closed a complete MP4 output.
  @override
  Future<bool> optimize({
    required int id,
    required String inputPath,
    required String outputPath,
  }) async =>
      await _channel.invokeMethod<bool>('optimize', {
        'id': id,
        'inputPath': inputPath,
        'outputPath': outputPath,
      }) ??
      false;

  /// Completes once native work has stopped and the files may be released.
  @override
  Future<void> cancel(int id) => _channel.invokeMethod('cancel', {'id': id});
}
