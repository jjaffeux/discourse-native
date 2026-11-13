import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_credentials.dart';
import 'http_url_safety.dart';
import 'site_lifecycle.dart';
import 'site_video_source.dart';
import 'thumbnail_request.dart';

/// Bounded, memory-only thumbnails scoped to the connected account session.
///
/// Uses the secure upload URL resolver so native requests never carry forum
/// credentials to a CDN. Generated artwork is shared across consumers and
/// released with the account.
class SiteThumbnailRepository {
  SiteThumbnailRepository({
    required this.credentials,
    required this.lifecycle,
    required this.generator,
    DateTime Function()? clock,
    this.maxConcurrent = 2,
    this.maxPending = 32,
    this.maxEntries = 64,
    this.maxCachedBytes = 8 * 1024 * 1024,
  }) : assert(maxConcurrent > 0),
       assert(maxPending > 0),
       assert(maxEntries > 0),
       assert(maxCachedBytes > 0),
       _clock = clock ?? DateTime.now;

  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final int maxConcurrent;
  final int maxPending;
  final int maxEntries;
  final int maxCachedBytes;
  final ThumbnailGenerator? generator;
  final DateTime Function() _clock;
  final _jobs = <(String, Uri), _ThumbnailJob>{};
  final _cache = <(String, Uri), _CachedThumbnail>{};
  int _active = 0;
  int _cachedBytes = 0;
  bool _disposed = false;

  ThumbnailRequest acquire({required String siteUrl, required Uri url}) {
    if (_disposed || generator == null) return _empty();
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
        return ThumbnailRequest(SynchronousFuture(cached.bytes), () {});
      }
      cached.detach();
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
      final owned = job;
      owned.removeRetirement = owned.lease.onRetire(() {
        _cancel(owned);
        _pump();
      });
    }
    final current = job;
    current.consumers++;
    _pump();
    return ThumbnailRequest(current.result.future, () {
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
      final extraction = generator!(source.url);
      job.extraction = extraction;
      bytes = await Future.any([extraction.result, job.result.future]);
      if (bytes != null) {
        bytes = bytes.isEmpty || bytes.length > 2 * 1024 * 1024
            ? null
            : Uint8List.fromList(bytes).asUnmodifiableView();
      }
    } on Object {
      // Unavailable uploads, failed rendering and missing platform bridges
      // retain the caller's fallback. Failed extraction is briefly cached.
    } finally {
      job.removeRetirement?.call();
      job.removeRetirement = null;
      if (_current(job)) {
        _remember(job, bytes);
      }
      if (identical(_jobs[job.key], job)) {
        _jobs.remove(job.key);
      }
      if (!job.result.isCompleted) {
        job.result.complete(job.lease.isCurrent && !_disposed ? bytes : null);
      }
      _releaseResources(job);
      _active--;
      _pump();
    }
  }

  void _remember(_ThumbnailJob job, Uint8List? bytes) {
    final cached = _CachedThumbnail(
      job.lease,
      bytes,
      _clock().add(const Duration(seconds: 30)),
    );
    _cache[job.key] = cached;
    _cachedBytes += bytes?.length ?? 0;
    final key = job.key;
    cached.removeRetirement = cached.lease.onRetire(() {
      if (identical(_cache[key], cached)) _removeCached(key);
    });
    while (_cache.length > maxEntries || _cachedBytes > maxCachedBytes) {
      _removeCached(_cache.keys.first);
    }
  }

  void _removeCached((String, Uri) key) {
    final cached = _cache.remove(key);
    if (cached == null) return;
    cached.detach();
    _cachedBytes -= cached.bytes?.length ?? 0;
  }

  void _cancel(_ThumbnailJob job) {
    job.removeRetirement?.call();
    job.removeRetirement = null;
    if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
    if (!job.result.isCompleted) job.result.complete(null);
    _releaseResources(job);
  }

  void _releaseResources(_ThumbnailJob job) {
    final resolver = job.resolver;
    final extraction = job.extraction;
    job.resolver = null;
    job.extraction = null;
    try {
      resolver?.close();
    } on Object {
      // Still release the extraction if its resolver failed to close.
    }
    try {
      extraction?.dispose();
    } on Object {
      // Optional bridge cleanup must not strand scheduler capacity.
    }
  }

  void forget(String siteUrl) {
    for (final key in _cache.keys.where((key) => key.$1 == siteUrl).toList()) {
      _removeCached(key);
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
    for (final key in _cache.keys.toList()) {
      _removeCached(key);
    }
  }

  static ThumbnailRequest _empty() =>
      ThumbnailRequest(SynchronousFuture(null), () {});
}

final class _ThumbnailJob {
  _ThumbnailJob(this.key, this.lease);

  final (String, Uri) key;
  final SiteLease lease;
  final result = Completer<Uint8List?>();
  int consumers = 0;
  bool active = false;
  VoidCallback? removeRetirement;
  SiteVideoSourceResolver? resolver;
  ThumbnailRequest? extraction;
}

final class _CachedThumbnail {
  _CachedThumbnail(this.lease, this.bytes, this.retryAt);

  final SiteLease lease;
  final Uint8List? bytes;
  final DateTime retryAt;
  VoidCallback? removeRetirement;

  void detach() {
    removeRetirement?.call();
    removeRetirement = null;
  }
}
