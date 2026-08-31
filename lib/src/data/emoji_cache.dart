import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

class EmojiCache extends ByteCache<Uint8List> {
  EmojiCache({super.client, super.retryAfter, super.store});

  static EmojiCache instance = EmojiCache();

  @override
  Uint8List? decode(http.Response response) =>
      response.bodyBytes.isEmpty ? null : response.bodyBytes;
}
