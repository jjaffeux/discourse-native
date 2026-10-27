import 'dart:typed_data';

enum AvifKind { still, animated }

/// Identifies AVIF by the major and compatible brands in its file-type box.
AvifKind? avifKind(Uint8List bytes) {
  if (bytes.length < 16 || !_brand(bytes, 4, 'ftyp')) return null;
  final data = ByteData.sublistView(bytes);
  var size = data.getUint32(0);
  var major = 8;
  if (size == 1) {
    if (bytes.length < 24) return null;
    size = data.getUint64(8);
    major = 16;
  }
  if (size < major + 8 || size > bytes.length || size % 4 != 0) {
    return null;
  }
  AvifKind? kind;
  for (var offset = major; offset + 4 <= size; offset += 4) {
    if (offset == major + 4) continue; // Minor version, not a brand.
    if (_brand(bytes, offset, 'avis')) return AvifKind.animated;
    if (_brand(bytes, offset, 'avif')) kind = AvifKind.still;
  }
  return kind;
}

bool _brand(Uint8List bytes, int offset, String brand) =>
    bytes[offset] == brand.codeUnitAt(0) &&
    bytes[offset + 1] == brand.codeUnitAt(1) &&
    bytes[offset + 2] == brand.codeUnitAt(2) &&
    bytes[offset + 3] == brand.codeUnitAt(3);
