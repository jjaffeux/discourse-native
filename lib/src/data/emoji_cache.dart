import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

/// Deduplicates and caches emoji fetches without throttling CDN traffic.
///
/// A sibling of `AvatarLoader` rather than a use of it because emoji still need
/// URL de-duplication, failure caching, response bounds, and persistent bytes.
/// Unlike API calls and forum-origin avatars, the many small immutable picker
/// assets are normally served by a CDN, so the default leaves concurrency to
/// the HTTP stack instead of feeding the picker through an application queue.
///
/// It also makes the cache worth more. The same handful of URLs repeat across
/// every post on a site, so after the first screen almost every emoji is
/// already in hand and paints without going async at all.
///
/// Nothing here sniffs the format. An emoji set is PNG and a custom emoji is an
/// upload, PNG or GIF; both go through Flutter's raster decoder and neither is
/// SVG.
class EmojiCache extends ByteCache<Uint8List> {
  EmojiCache({super.client, super.retryAfter, super.store});

  /// Swappable so tests do not reach the network.
  static EmojiCache instance = EmojiCache();

  @override
  Uint8List? decode(http.Response response) =>
      response.bodyBytes.isEmpty ? null : response.bodyBytes;
}
