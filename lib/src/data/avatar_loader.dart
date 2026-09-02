import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

class AvatarBytes {
  const AvatarBytes(this.bytes, {required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;
}

class AvatarLoader extends ByteCache<AvatarBytes> {
  AvatarLoader({
    super.client,
    super.retryAfter,
    super.coordinator,
    super.requestPool,
    super.store,
  });

  @override
  AvatarBytes decode(http.Response response) => AvatarBytes(
    response.bodyBytes,
    isSvg: looksLikeSvg(
      response.bodyBytes,
      contentType: response.headers['content-type'],
    ),
  );

  /// Whether [bytes] are an SVG document.
  ///
  /// A served content type decides. Without one — the disk cache keeps only
  /// the bytes, so every avatar read back after a relaunch arrives without
  /// its type — the bytes are sniffed. An SVG opens with markup, after an
  /// optional byte-order mark, and its root can sit past a prolog, a doctype
  /// and an editor's comment; a raster image opens with a binary signature.
  static bool looksLikeSvg(Uint8List bytes, {String? contentType}) {
    if (contentType != null && contentType.contains('image/svg')) return true;
    if (contentType != null && contentType.startsWith('image/')) {
      return false;
    }

    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final head = String.fromCharCodes(
      bytes.skip(start).take(_svgSniffLength),
    ).trimLeft().toLowerCase();
    return head.startsWith('<') && head.contains('<svg');
  }

  static const _svgSniffLength = 2048;
}
