import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

/// What came back for an avatar URL.
class AvatarBytes {
  const AvatarBytes(this.bytes, {required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;
}

/// Fetches avatars once each, and not all at once.
///
/// The caching and the concurrency cap are [ByteCache]'s, and the reasons for
/// them are written down there. What is left here is the one thing particular
/// to avatars: Discourse serves some of them as SVG even though the URL ends in
/// `.png`, so the format cannot be known from the URL — only from the bytes.
class AvatarLoader extends ByteCache<AvatarBytes> {
  AvatarLoader({super.client, super.maxConcurrent, super.retryAfter});

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
