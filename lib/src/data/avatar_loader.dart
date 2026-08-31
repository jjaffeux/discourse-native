import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'byte_cache.dart';

class AvatarBytes {
  const AvatarBytes(this.bytes, {required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;
}

class AvatarLoader extends ByteCache<AvatarBytes> {
  AvatarLoader({super.client, super.retryAfter, super.store});

  static AvatarLoader instance = AvatarLoader();

  @override
  AvatarBytes decode(http.Response response) => AvatarBytes(
    response.bodyBytes,
    isSvg: looksLikeSvg(
      response.bodyBytes,
      contentType: response.headers['content-type'],
    ),
  );

  static bool looksLikeSvg(Uint8List bytes, {String? contentType}) {
    if (contentType != null && contentType.contains('image/svg')) return true;
    if (contentType != null && contentType.startsWith('image/')) {
      return false;
    }

    final head = String.fromCharCodes(bytes.take(256)).trimLeft().toLowerCase();
    return head.startsWith('<svg') ||
        (head.startsWith('<?xml') && head.contains('<svg'));
  }
}
