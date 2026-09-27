import 'dart:io';

import 'package:discourse_native/src/data/composer_image_codec.dart';

// Run an AOT build against local photos/screenshots to measure the codec,
// including output validation, independently of file picking and networking:
// dart compile exe tool/benchmark_composer_image_optimization.dart -o /tmp/image-bench
// /tmp/image-bench photo.jpg screenshot.png
void main(List<String> paths) {
  if (paths.isEmpty) {
    stderr.writeln(
      'Pass JPEG/PNG paths. The benchmark bypasses the byte threshold.',
    );
    exitCode = 64;
    return;
  }
  final temporary = Directory.systemTemp.createTempSync('image-benchmark-');
  try {
    for (final path in paths) {
      final input = File(path);
      final bytes = input.readAsBytesSync();
      final info = composerImageDimensions(bytes);
      final output = File('${temporary.path}/output');
      final watch = Stopwatch()..start();
      final extension = encodeComposerImage(
        inputPath: path,
        outputPath: output.path,
        resizeThreshold: 1920,
        resizeTarget: 1920,
        quality: 90,
        allowJpeg: true,
        allowWebp: true,
      );
      watch.stop();
      stdout.writeln(
        '${input.uri.pathSegments.last}: '
        '${info?.width}x${info?.height}, ${bytes.length} bytes -> '
        '${extension == null ? 'original' : '${output.lengthSync()} bytes $extension'}, '
        '${watch.elapsedMilliseconds} ms',
      );
    }
    stdout.writeln(
      'Process peak RSS: ${(ProcessInfo.maxRss / 1048576).toStringAsFixed(1)} MiB',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
