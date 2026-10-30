import 'dart:typed_data';

/// A decoded, premultiplied RGBA8 image owned by Dart.
final class AvifFrame {
  const AvifFrame({
    required this.pixels,
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.sourceBitDepth,
    required this.hasAlpha,
  });

  /// Premultiplied RGBA8 pixels.
  final Uint8List pixels;

  final int width;
  final int height;
  final int rowBytes;

  /// Bit depth of the encoded AVIF image.
  final int sourceBitDepth;

  final bool hasAlpha;
}
