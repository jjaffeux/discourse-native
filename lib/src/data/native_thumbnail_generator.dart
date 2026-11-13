import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'thumbnail_request.dart';

bool get nativeThumbnailsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS);

final generateNativePdfThumbnail = _NativeThumbnailGenerator(
  'pdf_thumbnails',
).generate;
final generateNativeVideoThumbnail = _NativeThumbnailGenerator(
  'video_thumbnails',
).generate;

final class _NativeThumbnailGenerator {
  _NativeThumbnailGenerator(String channel)
    : _channel = MethodChannel('org.discourse.native/$channel');

  final MethodChannel _channel;
  int _nextRequestId = 0;

  ThumbnailRequest generate(Uri source) {
    final id = _nextRequestId++;
    return ThumbnailRequest(
      _channel.invokeMethod<Uint8List>('generate', {
        'id': id,
        'url': source.toString(),
      }),
      () => _channel.invokeMethod<void>('cancel', {'id': id}).ignore(),
    );
  }
}
