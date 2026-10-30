import 'dart:io';

import 'package:libavif/libavif.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/decode.dart <image.avif>');
    exitCode = 64;
    return;
  }

  await Avif.warmUp();
  final bytes = await File(arguments.single).readAsBytes();
  final decoder = await AvifSequenceDecoder.open(
    bytes,
    prefetchFirstFrame: true,
  );
  try {
    stdout.writeln(
      '${decoder.info.width}x${decoder.info.height}, '
      '${decoder.info.frameCount} frame(s), '
      '${decoder.info.sourceBitDepth}-bit source',
    );

    AvifSequenceFrame? frame;
    while ((frame = await decoder.nextFrame()) != null) {
      stdout.writeln(
        'frame ${frame!.index}: ${frame.duration.inMicroseconds} us, '
        '${frame.image.pixels.length} RGBA bytes',
      );
    }
  } finally {
    decoder.dispose();
  }
}
