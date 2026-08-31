import 'package:http/http.dart' as http;

import 'avatar_loader.dart';
import 'byte_cache.dart';
import 'byte_cache_store.dart';
import 'emoji_cache.dart';
import 'http_transport.dart';
import 'media_request_coordinator.dart';
import 'origin_cooldown.dart';

/// Owns the application's public-media caches and their shared admission.
///
/// Replacement is atomic from a caller's perspective: new lookups see the new
/// pipeline before the old pipeline is closed, while old work is invalidated
/// and aborted so it cannot publish into either cache generation.
final class MediaPipeline {
  factory MediaPipeline({
    http.Client? client,
    ByteCacheStore? store,
    int maxConcurrent = 8,
    int maxConcurrentPerOrigin = 4,
    int maxQueuedPerOrigin = 64,
    Duration rateLimitCooldown = const Duration(minutes: 2),
    DateTime Function()? clock,
    OriginCooldown Function()? cooldownFactory,
  }) {
    final ownedClient = client == null;
    final sharedClient = client ?? SafeHttpClient.create();
    final coordinator = MediaRequestCoordinator(
      maxConcurrent: maxConcurrent,
      maxConcurrentPerOrigin: maxConcurrentPerOrigin,
      maxQueuedPerOrigin: maxQueuedPerOrigin,
      defaultRateLimitCooldown: rateLimitCooldown,
      clock: clock,
      cooldownFactory: cooldownFactory,
    );
    final requestPool = ByteCacheRequestPool();
    return MediaPipeline._(
      client: sharedClient,
      ownsClient: ownedClient,
      coordinator: coordinator,
      requestPool: requestPool,
      store: store,
      retryAfter: rateLimitCooldown,
    );
  }

  MediaPipeline._({
    required http.Client client,
    required this._ownsClient,
    required MediaRequestCoordinator coordinator,
    required ByteCacheRequestPool requestPool,
    required ByteCacheStore? store,
    required Duration retryAfter,
  }) : _client = client,
       _coordinator = coordinator,
       _requestPool = requestPool,
       avatars = AvatarLoader(
         client: client,
         coordinator: coordinator,
         requestPool: requestPool,
         retryAfter: retryAfter,
         store: store,
       ),
       emoji = EmojiCache(
         client: client,
         coordinator: coordinator,
         requestPool: requestPool,
         retryAfter: retryAfter,
         store: store,
       );

  static MediaPipeline _instance = MediaPipeline();

  static MediaPipeline get instance => _instance;

  static void replace(MediaPipeline replacement) {
    if (identical(_instance, replacement)) return;
    final previous = _instance;
    _instance = replacement;
    previous.close();
  }

  final http.Client _client;
  final bool _ownsClient;
  final MediaRequestCoordinator _coordinator;
  final ByteCacheRequestPool _requestPool;
  final AvatarLoader avatars;
  final EmojiCache emoji;
  bool _closed = false;

  bool get isClosed => _closed;

  void close() {
    if (_closed) return;
    _closed = true;
    avatars.close();
    emoji.close();
    _coordinator.close();
    _requestPool.close();
    if (_ownsClient) _client.close();
  }
}
