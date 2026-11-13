import 'site_thumbnail_repository.dart';

export 'site_thumbnail_repository.dart' show ThumbnailRequest;

typedef VideoThumbnailRequest = ThumbnailRequest;
typedef VideoThumbnailGenerator = ThumbnailGenerator;

final class SiteVideoThumbnailRepository extends SiteThumbnailRepository {
  SiteVideoThumbnailRepository({
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
