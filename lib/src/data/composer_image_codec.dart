import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The codec runs in a disposable isolate. Limits are checked before pixels
/// are decoded; larger inputs keep their original upload stream.
const composerImageMaxInputBytes = 32 * 1024 * 1024;
const composerImageMaxPixels = 16 * 1000 * 1000;

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
  final bytes = input.readAsBytesSync();
  final dimensions = composerImageDimensions(bytes);
  if (dimensions == null ||
      dimensions.width <= 0 ||
      dimensions.height <= 0 ||
      dimensions.width * dimensions.height > composerImageMaxPixels) {
    return null;
  }
  img.Image? image;
  if (bytes[0] == 0xff) {
    // startDecode would allocate coefficient buffers once just to report
    // dimensions, then decodeFrame would allocate them a second time.
    image = img.decodeJpg(bytes);
  } else {
    final decoder = img.PngDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null || info.numFrames > 1) return null;
    image = decoder.decodeFrame(0);
  }
  if (image == null) return null;
  if (image.exif.imageIfd.hasOrientation &&
      image.exif.imageIfd.orientation != 1) {
    image = img.bakeOrientation(image);
  }
  final transparent = image.any((pixel) => pixel.a < pixel.maxChannelValue);
  if (transparent ? !allowWebp : !allowJpeg) return null;

  // Colour profiles describe the pixels, unlike camera/GPS metadata. Keep
  // them so wide-gamut photos do not change colour on re-encoding.
  image.exif = img.ExifData();
  image.textData?.clear();
  if (image.hasPalette) image = image.convert(numChannels: transparent ? 4 : 3);
  if (image.width > resizeThreshold && image.width > resizeTarget) {
    image = img.copyResize(
      image,
      width: resizeTarget,
      height: (image.height * resizeTarget / image.width).round().clamp(
        1,
        image.height,
      ),
      interpolation: img.Interpolation.average,
    );
  }
  final encoded = transparent
      ? img.encodeWebP(image, lossless: false, quality: quality)
      : img.encodeJpg(image, quality: quality);
  if (encoded.isEmpty || encoded.length >= bytes.length) return null;

  final checked = transparent
      ? img.decodeWebP(encoded)
      : img.decodeJpg(encoded);
  if (checked == null ||
      checked.width != image.width ||
      checked.height != image.height) {
    return null;
  }
  File(outputPath).writeAsBytesSync(encoded);
  return transparent ? 'webp' : 'jpg';
}

/// Reads dimensions without starting a decoder. JPEG startDecode allocates
/// coefficient buffers for the entire image, even before decodeFrame runs.
({int width, int height})? composerImageDimensions(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  if (img.PngDecoder().isValidFile(bytes)) {
    if (bytes.length < 24) return null;
    return (width: view.getUint32(16), height: view.getUint32(20));
  }
  if (bytes.length < 2 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  var offset = 2;
  while (offset + 1 < bytes.length) {
    if (bytes[offset++] != 0xff) return null;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset++];
    if (marker == 0xda || marker == 0xd9) return null;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > bytes.length) return null;
    final length = view.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) return null;
    final startOfFrame =
        marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc;
    if (startOfFrame) {
      if (length < 8) return null;
      return (
        width: view.getUint16(offset + 5),
        height: view.getUint16(offset + 3),
      );
    }
    offset += length;
  }
  return null;
}
