import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

/// What came back for an avatar URL.
class AvatarBytes {
  const AvatarBytes(this.bytes, {required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;
}

/// Deduplicates and caches avatar fetches without throttling static media.
///
/// [ByteCache] retains URL de-duplication, failure caching, response bounds,
/// and persistent bytes while leaving request concurrency to the HTTP stack.
/// What is particular to avatars is that Discourse serves some as SVG even
/// though the URL ends in `.png`, so only the response reveals the format.
class AvatarLoader extends ByteCache<AvatarBytes> {
  AvatarLoader({super.client, super.retryAfter, super.store});

  /// Swappable so tests do not reach the network.
  static AvatarLoader instance = AvatarLoader();

  @override
  AvatarBytes decode(http.Response response) => AvatarBytes(
    response.bodyBytes,
    isSvg: looksLikeSvg(
      response.bodyBytes,
      contentType: response.headers['content-type'],
    ),
  );

  /// Content type first; some CDNs mislabel, so fall back to sniffing the
  /// leading bytes for an SVG or XML prolog.
  static bool looksLikeSvg(Uint8List bytes, {String? contentType}) {
    if (contentType != null && contentType.contains('image/svg')) return true;
    if (contentType != null && contentType.startsWith('image/')) {
      // A declared raster type is trustworthy; do not sniff further.
      return false;
    }

    final head = String.fromCharCodes(bytes.take(256)).trimLeft().toLowerCase();
    return head.startsWith('<svg') ||
        (head.startsWith('<?xml') && head.contains('<svg'));
  }
}
