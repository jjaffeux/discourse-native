import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_credentials.dart';
import 'http_transport.dart';
import 'site_lifecycle.dart';
import 'site_video_source.dart';

typedef VideoThumbnailGenerator = VideoThumbnailRequest Function(Uri source);

/// One consumer's interest in a thumbnail. Release it when the preview leaves
/// the tree; shared work is cancelled only after the last consumer leaves.
final class VideoThumbnailRequest {
  VideoThumbnailRequest(this.result, this._release);

  final Future<Uint8List?> result;
  final VoidCallback _release;
  bool _released = false;

  void dispose() {
    if (_released) return;
    _released = true;
    _release();
  }
}

const _channel = MethodChannel('org.discourse.native/video_thumbnails');
int _nextRequestId = 0;

VideoThumbnailRequest generateNativeVideoThumbnail(Uri source) {
  final id = _nextRequestId++;
  return VideoThumbnailRequest(
    _channel.invokeMethod<Uint8List>('generate', {
      'id': id,
      'url': source.toString(),
    }),
    () => _channel.invokeMethod<void>('cancel', {'id': id}).ignore(),
  );
}

/// Bounded, memory-only thumbnails scoped to the connected account session.
///
/// Uses the playback URL resolver so native range requests never carry forum
/// credentials to a CDN. No player is constructed to extract a frame.
final class SiteVideoThumbnailRepository {
  SiteVideoThumbnailRepository({
    required this.credentials,
    required this.lifecycle,
    VideoThumbnailGenerator? generator,
    DateTime Function()? clock,
    this.maxConcurrent = 2,
    this.maxPending = 32,
    this.maxEntries = 64,
    this.maxCachedBytes = 8 * 1024 * 1024,
  }) : assert(maxConcurrent > 0),
       assert(maxPending > 0),
       assert(maxEntries > 0),
       assert(maxCachedBytes > 0),
       _clock = clock ?? DateTime.now,
       _generator =
           generator ??
           (!kIsWeb &&
                   (defaultTargetPlatform == TargetPlatform.macOS ||
                       defaultTargetPlatform == TargetPlatform.iOS)
               ? generateNativeVideoThumbnail
               : null);

  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final int maxConcurrent;
  final int maxPending;
  final int maxEntries;
  final int maxCachedBytes;
  final VideoThumbnailGenerator? _generator;
  final DateTime Function() _clock;
  final _jobs = <(String, Uri), _ThumbnailJob>{};
  final _cache = <(String, Uri), _CachedThumbnail>{};
  int _active = 0;
  int _cachedBytes = 0;
  bool _disposed = false;

  VideoThumbnailRequest acquire({required String siteUrl, required Uri url}) {
    if (_disposed || _generator == null) return _empty();
    try {
      requireSafeHttpUrl(url);
      requireSafeHttpUrl(Uri.parse(siteUrl));
    } on Object {
      return _empty();
    }

    final key = (siteUrl, url);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cachedBytes -= cached.bytes?.length ?? 0;
      if (cached.lease.isCurrent &&
          (cached.bytes != null || _clock().isBefore(cached.retryAt))) {
        _cache[key] = cached;
        _cachedBytes += cached.bytes?.length ?? 0;
        return VideoThumbnailRequest(SynchronousFuture(cached.bytes), () {});
      }
    }

    var job = _jobs[key];
    if (job != null && !job.lease.isCurrent) {
      _cancel(job);
      job = null;
    }
    if (job == null) {
      if (_jobs.length >= maxPending) return _empty();
      job = _ThumbnailJob(key, lifecycle.capture(siteUrl));
      _jobs[key] = job;
    }
    final current = job;
    current.consumers++;
    _pump();
    return VideoThumbnailRequest(current.result.future, () {
      if (--current.consumers == 0 && !current.result.isCompleted) {
        _cancel(current);
        _pump();
      }
    });
  }

  void _pump() {
    if (_disposed) return;
    for (final job in _jobs.values.toList(growable: false)) {
      if (_active >= maxConcurrent) break;
      if (!job.active) unawaited(_run(job));
    }
  }

  bool _current(_ThumbnailJob job) =>
      !_disposed &&
      job.lease.isCurrent &&
      identical(_jobs[job.key], job) &&
      !job.result.isCompleted;

  Future<void> _run(_ThumbnailJob job) async {
    job.active = true;
    _active++;
    Uint8List? bytes;
    try {
      if (!_current(job)) return;
      final resolver = SiteVideoSourceResolver(
        credentials: credentials,
        lifecycle: lifecycle,
      );
      job.resolver = resolver;
      final source = await resolver.resolve(
        siteUrl: job.key.$1,
        url: job.key.$2,
      );
      if (!_current(job)) return;
      final extraction = _generator!(source.url);
      job.extraction = extraction;
      bytes = await Future.any([extraction.result, job.result.future]);
      if (bytes != null && (bytes.isEmpty || bytes.length > 2 * 1024 * 1024)) {
        bytes = null;
      }
    } on Object {
      // Unsupported codecs, unavailable uploads and missing platform bridges
      // retain the normal play action. Failed extraction is briefly cached.
    } finally {
      if (_current(job)) {
        _remember(job, bytes);
      }
      if (identical(_jobs[job.key], job)) {
        _jobs.remove(job.key);
      }
      if (!job.result.isCompleted) {
        job.result.complete(job.lease.isCurrent && !_disposed ? bytes : null);
      }
      job.resolver?.close();
      job.extraction?.dispose();
      _active--;
      _pump();
    }
  }

  void _remember(_ThumbnailJob job, Uint8List? bytes) {
    _cache[job.key] = _CachedThumbnail(
      job.lease,
      bytes,
      _clock().add(const Duration(seconds: 30)),
    );
    _cachedBytes += bytes?.length ?? 0;
    while (_cache.length > maxEntries || _cachedBytes > maxCachedBytes) {
      _cachedBytes -= _cache.remove(_cache.keys.first)!.bytes?.length ?? 0;
    }
  }

  void _cancel(_ThumbnailJob job) {
    if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
    if (!job.result.isCompleted) job.result.complete(null);
    job.resolver?.close();
    job.extraction?.dispose();
  }

  void forget(String siteUrl) {
    for (final key in _cache.keys.where((key) => key.$1 == siteUrl).toList()) {
      _cachedBytes -= _cache.remove(key)!.bytes?.length ?? 0;
    }
    for (final job in _jobs.values.toList(growable: false)) {
      if (job.key.$1 == siteUrl) _cancel(job);
    }
    _pump();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _jobs.values.toList(growable: false)) {
      _cancel(job);
    }
    _cache.clear();
    _cachedBytes = 0;
  }

  static VideoThumbnailRequest _empty() =>
      VideoThumbnailRequest(SynchronousFuture(null), () {});
}

final class _ThumbnailJob {
  _ThumbnailJob(this.key, this.lease);

  final (String, Uri) key;
  final SiteLease lease;
  final result = Completer<Uint8List?>();
  int consumers = 0;
  bool active = false;
  SiteVideoSourceResolver? resolver;
  VideoThumbnailRequest? extraction;
}

final class _CachedThumbnail {
  const _CachedThumbnail(this.lease, this.bytes, this.retryAt);

  final SiteLease lease;
  final Uint8List? bytes;
  final DateTime retryAt;
}
