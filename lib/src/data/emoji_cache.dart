import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'avatar_loader.dart';
import 'byte_cache.dart';
import 'media_request_coordinator.dart';

final class EmojiBytes {
  const EmojiBytes(this.bytes, {required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;
}

class EmojiCache extends ByteCache<EmojiBytes> {
  EmojiCache({
    super.client,
    super.retryAfter,
    super.coordinator,
    super.requestPriority = MediaRequestPriority.interactive,
    super.requestPool,
    super.store,
  });

  @override
  EmojiBytes? decode(http.Response response) {
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) return null;
    return EmojiBytes(
      bytes,
      isSvg: AvatarLoader.looksLikeSvg(
        bytes,
        contentType: response.headers['content-type'],
      ),
    );
  }

  /// Rejects bytes which a platform decoder could not read.
  ///
  /// Every widget sharing this cache receives the same [EmojiBytes] object.
  /// Remembering the object prevents a row of identical broken emoji from
  /// producing one warning per widget, while discarding it prevents another
  /// rebuild (or app relaunch through the disk cache) from trying it again.
  bool rejectAfterDecodeFailure(String url, EmojiBytes image) {
    if (_decoderRejections[image] == true) return false;
    _decoderRejections[image] = true;
    discardCachedValue(url, image);
    return true;
  }

  final Expando<bool> _decoderRejections = Expando<bool>();
}
