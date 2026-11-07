import 'cached_image_bytes.dart';
import 'media_request_coordinator.dart';

class EmojiCache extends CachedImageCache {
  EmojiCache({
    super.client,
    super.retryAfter,
    super.coordinator,
    super.maxConcurrent,
    super.requestPriority = MediaRequestPriority.interactive,
    super.requestPool,
    super.store,
  });
}
