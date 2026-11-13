import 'site_thumbnail_repository.dart';

final class SitePdfThumbnailRepository extends SiteThumbnailRepository {
  SitePdfThumbnailRepository({
    required super.credentials,
    required super.lifecycle,
    super.generator,
    super.clock,
    super.maxConcurrent,
    super.maxPending,
    super.maxEntries,
    super.maxCachedBytes,
  });
}

bool isPdfAttachment(String filename, String url) =>
    Uri.tryParse(url)?.path.toLowerCase().endsWith('.pdf') == true ||
    // Discourse's upload short URL carries no filename or extension.
    (url.startsWith('upload://') &&
        filename.split('|').first.trim().toLowerCase().endsWith('.pdf'));
