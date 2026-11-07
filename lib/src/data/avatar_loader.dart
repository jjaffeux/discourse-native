import 'cached_image_bytes.dart';

class AvatarLoader extends CachedImageCache {
  AvatarLoader({
    super.client,
    super.retryAfter,
    super.coordinator,
    super.requestPool,
    super.store,
  });
}
