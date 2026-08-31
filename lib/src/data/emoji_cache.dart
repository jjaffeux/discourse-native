import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';
import 'media_request_coordinator.dart';

class EmojiCache extends ByteCache<Uint8List> {
  EmojiCache({
    super.client,
    super.retryAfter,
    super.coordinator,
    super.requestPriority = MediaRequestPriority.interactive,
    super.requestPool,
    super.store,
  });

  @override
  Uint8List? decode(http.Response response) =>
      response.bodyBytes.isEmpty ? null : response.bodyBytes;
}
