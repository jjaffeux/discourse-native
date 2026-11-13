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
