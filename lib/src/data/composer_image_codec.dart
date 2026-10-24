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
  final jpeg = bytes[0] == 0xff;
  img.Image? image;
  if (jpeg) {
    // startDecode would allocate coefficient buffers once just to report
    // dimensions, then decodeFrame would allocate them a second time.
    final icc = _jpegSourceIccProfile(bytes);
    if (icc == null) return null;
    image = img.decodeJpg(bytes);
    // A later scan can introduce ICC data the header collector did not see.
    final decodedIcc = image?.iccProfile?.decompressed();
    final lastPart = icc.lastPart;
    if (decodedIcc != null) {
      if (lastPart == null || decodedIcc.length != lastPart.length) return null;
      for (var i = 0; i < decodedIcc.length; i++) {
        if (decodedIcc[i] != lastPart[i]) return null;
      }
    } else if (lastPart != null) {
      return null;
    }
    image?.iccProfile = icc.profile;
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
  // The JPEG encoder reads one-channel gray as red alone, and 16-bit
  // gray+alpha as red with alpha for green, so gray is copied into every
  // colour channel first. A gray PNG may only carry a gray profile, which
  // cannot describe the RGB result.
  final gray = !image.hasPalette && image.numChannels < 3;
  if (image.hasPalette || gray) {
    image = image.convert(numChannels: transparent ? 4 : 3);
  }
  if (gray) image.iccProfile = null;
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
  if (!transparent && !jpeg && image.iccProfile != null) {
    final profile = _pngToJpegIccProfile(image.iccProfile!);
    if (profile == null) return null;
    image.iccProfile = profile;
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

/// A JPEG APP2 segment holds `ICC_PROFILE\0`, a one-based sequence number,
/// the segment count, then that part of the profile; its 16-bit length counts
/// itself and the signature.
const _jpegIccSegmentData = 0xffff - 2 - 12;

final _jpegIccSignature = 'ICC_PROFILE\x00'.codeUnits;

/// package:image keeps only the last source ICC part and writes one output
/// part verbatim. Read the complete source sequence before decoding pixels.
({img.IccProfile? profile, Uint8List? lastPart})? _jpegSourceIccProfile(
  Uint8List bytes,
) {
  final view = ByteData.sublistView(bytes);
  final parts = <int, Uint8List>{};
  int? count;
  Uint8List? lastPart;
  var total = 0;
  var offset = 2;
  while (true) {
    if (offset + 1 >= bytes.length || bytes[offset++] != 0xff) return null;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) return null;
    final marker = bytes[offset++];
    if (marker == 0xda || marker == 0xd9) break;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > bytes.length) return null;
    final length = view.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) return null;
    final body = offset + 2;
    var icc = marker == 0xe2 && length >= 2 + _jpegIccSignature.length;
    for (var i = 0; icc && i < _jpegIccSignature.length; i++) {
      icc = bytes[body + i] == _jpegIccSignature[i];
    }
    if (icc) {
      final prefix = body + _jpegIccSignature.length;
      if (prefix + 2 >= offset + length) return null;
      final sequence = bytes[prefix];
      final segmentCount = bytes[prefix + 1];
      if (sequence == 0 ||
          segmentCount == 0 ||
          sequence > segmentCount ||
          (count != null && count != segmentCount) ||
          parts.containsKey(sequence)) {
        return null;
      }
      count = segmentCount;
      final part = Uint8List.sublistView(bytes, prefix + 2, offset + length);
      total += part.length;
      if (total > _jpegIccSegmentData - 2) return null;
      parts[sequence] = part;
      lastPart = Uint8List.sublistView(bytes, prefix, offset + length);
    }
    offset += length;
  }
  if (count == null) return (profile: null, lastPart: null);
  if (parts.length != count) return null;
  final data = Uint8List(total + 2)..setAll(0, [1, 1]);
  var position = 2;
  for (var sequence = 1; sequence <= count; sequence++) {
    final part = parts[sequence]!;
    data.setAll(position, part);
    position += part.length;
  }
  return (
    profile: img.IccProfile('', img.IccProfileCompression.none, data),
    lastPart: lastPart,
  );
}

img.IccProfile? _pngToJpegIccProfile(img.IccProfile profile) {
  final data = profile.decompressed();
  if (data.isEmpty || data.length > _jpegIccSegmentData - 2) return null;
  return img.IccProfile(
    profile.name,
    img.IccProfileCompression.none,
    Uint8List.fromList([1, 1, ...data]),
  );
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
