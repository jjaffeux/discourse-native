import 'dart:io' show zlib;
import 'dart:typed_data';

/// A valid PNG of [width] × [height] black one-bit pixels.
///
/// All-zero rows compress about a thousandfold, so a test can declare far
/// more pixels than it could afford to decode.
Uint8List blankPng({required int width, required int height}) {
  // Each row is a filter-type byte followed by its packed pixels.
  final pixels = Uint8List((1 + (width + 7) ~/ 8) * height);
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 1)
    ..setUint8(9, 0);
  return Uint8List.fromList([
    ...const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    ..._chunk('IHDR', header.buffer.asUint8List()),
    ..._chunk('IDAT', zlib.encode(pixels)),
    ..._chunk('IEND', const []),
  ]);
}

List<int> _chunk(String type, List<int> data) {
  final typed = [...type.codeUnits, ...data];
  return [..._uint32(data.length), ...typed, ..._uint32(_crc32(typed))];
}

List<int> _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
