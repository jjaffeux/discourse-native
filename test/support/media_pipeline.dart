import 'package:discourse_native/src/data/byte_cache_store.dart';
import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

MediaPipeline installTestMediaPipeline({
  http.Client? client,
  ByteCacheStore? store,
  int maxConcurrent = 8,
  int maxConcurrentPerOrigin = 4,
  int maxQueuedPerOrigin = 64,
  Duration rateLimitCooldown = const Duration(minutes: 2),
}) {
  final pipeline = MediaPipeline(
    client: client,
    store: store,
    maxConcurrent: maxConcurrent,
    maxConcurrentPerOrigin: maxConcurrentPerOrigin,
    maxQueuedPerOrigin: maxQueuedPerOrigin,
    rateLimitCooldown: rateLimitCooldown,
  );
  MediaPipeline.replace(pipeline);
  addTearDown(() {
    if (identical(MediaPipeline.instance, pipeline)) {
      MediaPipeline.replace(MediaPipeline());
    } else {
      pipeline.close();
    }
  });
  return pipeline;
}
