import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

/// Deduplicates emoji fetches and keeps their concurrency bounded.
///
/// A sibling of `AvatarLoader` rather than a use of it, and for the same reason
/// that exists at all — see [ByteCache]. Emoji make the case harder, not
/// easier: a paragraph can carry thirty of them, and a screen can carry six
/// paragraphs, so the unbounded request per glyph a `NetworkImage` would make
/// is the rate limit rather than a risk of one.
///
/// It also makes the cache worth more. The same handful of URLs repeat across
/// every post on a site, so after the first screen almost every emoji is
/// already in hand and paints without going async at all.
///
/// Nothing here sniffs the format. An emoji set is PNG and a custom emoji is an
/// upload, PNG or GIF; both go through Flutter's raster decoder and neither is
/// SVG.
class EmojiCache extends ByteCache<Uint8List> {
  EmojiCache({super.client, super.maxConcurrent, super.retryAfter});

  /// Swappable so tests do not reach the network.
  static EmojiCache instance = EmojiCache();

  @override
  Uint8List? decode(http.Response response) =>
      response.bodyBytes.isEmpty ? null : response.bodyBytes;
}
