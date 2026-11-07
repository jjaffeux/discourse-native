import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

/// Owned image data shared by public avatar and emoji consumers.
final class CachedImageBytes {
  factory CachedImageBytes.fromResponse(http.Response response) =>
      _responses[response] ??= CachedImageBytes._(
        Uint8List.fromList(response.bodyBytes).asUnmodifiableView(),
        looksLikeSvg(
          response.bodyBytes,
          contentType: response.headers['content-type'],
        ),
      );

  const CachedImageBytes._(this.bytes, this.isSvg);

  // Pooled caches decode one response; retain one owned buffer for all of them.
  static final Expando<CachedImageBytes> _responses = Expando();
  final Uint8List bytes;
  final bool isSvg;

  /// A declared image type wins; disk-cache responses are classified by bytes.
  static bool looksLikeSvg(Uint8List bytes, {String? contentType}) {
    final mediaType = contentType?.split(';').first.trim().toLowerCase();
    if (mediaType != null && mediaType.startsWith('image/svg')) return true;
    if (mediaType != null && mediaType.startsWith('image/')) return false;
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    final head = String.fromCharCodes(
      bytes.skip(start).take(2048),
    ).trimLeft().toLowerCase();
    return head.startsWith('<') && head.contains('<svg');
  }
}

abstract class CachedImageCache extends ByteCache<CachedImageBytes> {
  CachedImageCache({
    super.client,
    super.retryAfter,
    super.coordinator,
    super.requestPool,
    super.store,
    super.maxConcurrent,
    super.requestPriority,
  });

  @override
  CachedImageBytes? decode(http.Response response) => response.bodyBytes.isEmpty
      ? null
      : CachedImageBytes.fromResponse(response);

  /// One rejection per shared value; a late decoder cannot evict its successor.
  bool rejectAfterDecodeFailure(String url, CachedImageBytes image) {
    if (_decoderRejections[image] == true) return false;
    _decoderRejections[image] = true;
    discardCachedValue(url, image);
    return true;
  }

  final Expando<bool> _decoderRejections = Expando();
}
