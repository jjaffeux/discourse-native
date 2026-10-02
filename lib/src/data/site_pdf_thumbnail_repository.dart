import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'site_thumbnail_repository.dart';

const _channel = MethodChannel('org.discourse.native/pdf_thumbnails');
int _nextRequestId = 0;

ThumbnailRequest generateNativePdfThumbnail(Uri source) {
  final id = _nextRequestId++;
  return ThumbnailRequest(
    _channel.invokeMethod<Uint8List>('generate', {
      'id': id,
      'url': source.toString(),
    }),
    () => _channel.invokeMethod<void>('cancel', {'id': id}).ignore(),
  );
}

final class SitePdfThumbnailRepository extends SiteThumbnailRepository {
  SitePdfThumbnailRepository({
    required super.credentials,
    required super.lifecycle,
    ThumbnailGenerator? generator,
    super.clock,
    super.maxConcurrent,
    super.maxPending,
    super.maxEntries,
    super.maxCachedBytes,
  }) : super(
         generator:
             generator ??
             (!kIsWeb &&
                     (defaultTargetPlatform == TargetPlatform.macOS ||
                         defaultTargetPlatform == TargetPlatform.iOS)
                 ? generateNativePdfThumbnail
                 : null),
       );
}

bool isPdfAttachment(String filename, String url) =>
    Uri.tryParse(url)?.path.toLowerCase().endsWith('.pdf') == true ||
    // Discourse's upload short URL carries no filename or extension.
    (url.startsWith('upload://') &&
        filename.split('|').first.trim().toLowerCase().endsWith('.pdf'));
