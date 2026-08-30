import 'dart:async';

import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/incoming_topics.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';

typedef TopicFeedLoaded =
    void Function(
      DiscourseInstance instance,
      String? apiKey,
      Iterable<TopicCategory> categories,
      Iterable<int> categoryIds,
    );

typedef _FeedKey = (String siteUrl, String destinationId);
typedef _FeedLoad = ({
  DiscourseInstance instance,
  String destinationId,
  String path,
  IncomingTopics? incoming,
});

/// Owns topic-list state independently from shell navigation.
///
/// Whole-list refreshes, incoming-topic merges, and pagination all replace the
/// same snapshot. Keeping their revision tokens beside that snapshot makes the
/// ordering contract explicit and gives site disconnect one exact-key cleanup
/// boundary instead of several string-prefix sweeps in [ShellController].
final class TopicFeedController extends FrameSafeNotifier {
  TopicFeedController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.store,
    this.onFeedLoaded,
    this.readPersonalizationVersion,
    this.prepareTopicForStore,
  });

  /// Core's default topic-list page size. A `topic_ids` filter narrows that
  /// page; it does not raise the server limit, so overflow must remain queued
  /// for another incoming-topic request.
  static const int incomingPageSize = 30;

  final TopicFeedsApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final TopicFeedLoaded? onFeedLoaded;
  final int Function(String siteUrl)? readPersonalizationVersion;
  final Topic Function(String siteUrl, Topic incoming, int? versionAtDispatch)?
  prepareTopicForStore;

  final Map<_FeedKey, TopicFeed> _feeds = {};
  final Map<String, String> _filterQueries = {};
  final Map<_FeedKey, Object> _revisions = {};
  final Map<_FeedKey, Object> _pageRequests = {};
  final Map<_FeedKey, int> _rows = {};
  final Map<_FeedKey, Future<void>> _loadRequests = {};
  final Map<_FeedKey, _FeedLoad> _pendingLoads = {};
  final Map<_FeedKey, Completer<void>> _pendingLoadWaiters = {};

  TopicFeed? feedFor(String siteUrl, String destinationId) =>
      _feeds[(siteUrl, destinationId)];

  String filterQueryFor(String siteUrl) => _filterQueries[siteUrl] ?? '';

  void setFilterQuery(String siteUrl, String query) {
    _filterQueries[siteUrl] = query;
    _rows.remove((siteUrl, 'filter'));
  }

  int scrollRowFor(String siteUrl, String destinationId) =>
      _rows[(siteUrl, destinationId)] ?? 0;

  void saveScrollRow(String siteUrl, String destinationId, int row) {
    _rows[(siteUrl, destinationId)] = row;
  }

  Future<void> load({
    required DiscourseInstance instance,
    required String destinationId,
    required String path,
    required IncomingTopics? incoming,
    bool force = false,
  }) {
    if (isDisposed) return Future.value();
    final key = (instance.url, destinationId);
    final load = (
      instance: instance,
      destinationId: destinationId,
      path: path,
      incoming: incoming,
    );
    final active = _loadRequests[key];
    if (active != null) {
      if (!force) return active;
      // A refresh means "give me data newer than the request already in
      // flight", not "send another request alongside it". Keep only the
      // newest path and let every repeated refresh await the same replay.
      _pendingLoads[key] = load;
      return _pendingLoadWaiters.putIfAbsent(key, Completer<void>.new).future;
    }

    final existing = _feeds[key];
    if (existing != null &&
        !force &&
        (existing.loading || (existing.loaded && existing.error == null))) {
      return Future.value();
    }

    return _startLoad(key, load);
  }

  Future<void> _startLoad(_FeedKey key, _FeedLoad load) {
    late final Future<void> request;
    request = _performLoad(key, load).whenComplete(() {
      _finishLoad(key, request);
    });
    _loadRequests[key] = request;
    return request;
  }

  Future<void> _performLoad(_FeedKey key, _FeedLoad load) async {
    final (:instance, :destinationId, :path, :incoming) = load;
    final existing = _feeds[key];

    final lease = lifecycle.capture(instance.url);
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    final revision = Object();
    _revisions[key] = revision;
    _pageRequests.remove(key);

    final announced = incoming?.topicIds(destinationId) ?? const <int>[];
    incoming?.reset(destinationId);
    _feeds[key] = (existing ?? const TopicFeed()).refreshing();
    notifySafely();

    bool requestIsCurrent() =>
        !isDisposed && lease.isCurrent && identical(_revisions[key], revision);

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (!requestIsCurrent()) return;
      final list = await api.topicList(
        siteUrl: instance.url,
        path: path,
        apiKey: apiKey,
      );
      _commit(lease, () {
        if (!identical(_revisions[key], revision)) return;
        _putTopics(instance.url, list.topics, personalizationVersion);
        _feeds[key] = TopicFeed.of(list);
        _rows.remove(key);
        notifySafely();
        // Publishing can synchronously dispose this owner through a listener.
        // Do not let its post-load hook start category work for a replacement
        // shell after that ownership boundary.
        if (!isDisposed) {
          onFeedLoaded?.call(
            instance,
            apiKey,
            list.categories,
            _categoryIds(list.topics),
          );
        }
      });
    } on SiteLookupException catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _report(error, stackTrace, 'topics.loadFeed');
      _commit(lease, () {
        if (!identical(_revisions[key], revision)) return;
        incoming?.restore(destinationId, announced);
        final held = _feeds[key] ?? existing ?? const TopicFeed();
        _feeds[key] = held.withError(
          error.failure == SiteLookupFailure.notDiscourse
              ? 'Not allowed — try reconnecting to ${instance.host}.'
              : "Couldn't reach ${instance.host}.",
        );
        notifySafely();
      });
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _report(error, stackTrace, 'topics.loadFeed');
      _commit(lease, () {
        if (!identical(_revisions[key], revision)) return;
        incoming?.restore(destinationId, announced);
        final held = _feeds[key] ?? existing ?? const TopicFeed();
        _feeds[key] = held.withError("Couldn't load ${instance.host}.");
        notifySafely();
      });
    }
  }

  void _finishLoad(_FeedKey key, Future<void> request) {
    if (!identical(_loadRequests[key], request)) return;
    final removed = _loadRequests.remove(key);
    assert(identical(removed, request));

    final pending = _pendingLoads.remove(key);
    final waiter = _pendingLoadWaiters.remove(key);
    if (pending == null || waiter == null || isDisposed) {
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      return;
    }

    final replay = _startLoad(key, pending);
    unawaited(
      replay.then<void>(
        (_) {
          if (!waiter.isCompleted) waiter.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
        },
      ),
    );
  }

  Future<void> showIncoming({
    required DiscourseInstance instance,
    required String destinationId,
    required String path,
    required IncomingTopics incoming,
  }) async {
    if (isDisposed) return;
    final key = (instance.url, destinationId);
    final feed = _feeds[key];
    if (feed == null || feed.loadingIncoming) return;

    final ids = incoming.topicIds(destinationId, limit: incomingPageSize);
    if (ids.isEmpty) return;
    final lease = lifecycle.capture(instance.url);
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    final feedRevision = _revisions[key];

    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_revisions[key], feedRevision);

    _feeds[key] = feed.copyWith(loadingIncoming: true);
    notifySafely();

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (!requestIsCurrent()) return;
      final list = await api.topicList(
        siteUrl: instance.url,
        path: '$path?topic_ids=${ids.join(',')}',
        apiKey: apiKey,
      );

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        _putTopics(instance.url, list.topics, personalizationVersion);
        final held = _feeds[key] ?? feed;
        final arrived = [for (final topic in list.topics) topic.id];
        final prepended = arrived.toSet();
        _feeds[key] = held.copyWith(
          topicIds: [
            ...arrived,
            ...held.topicIds.where((id) => !prepended.contains(id)),
          ],
          loadingIncoming: false,
        );
        incoming.clear(destinationId, ids);
        _rows[key] = 0;
        notifySafely();
        if (!isDisposed) {
          onFeedLoaded?.call(
            instance,
            apiKey,
            list.categories,
            _categoryIds(list.topics),
          );
        }
      });
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _report(
        error,
        stackTrace,
        'topics.loadIncoming',
        severity: DiagnosticSeverity.warning,
      );
      _commit(lease, () {
        if (!requestIsCurrent()) return;
        _feeds[key] = (_feeds[key] ?? feed).copyWith(loadingIncoming: false);
        notifySafely();
      });
    }
  }

  Future<void> loadMore({
    required DiscourseInstance instance,
    required String destinationId,
  }) async {
    if (isDisposed) return;
    final key = (instance.url, destinationId);
    final feed = _feeds[key];
    if (feed == null || feed.loading || feed.loadingMore || !feed.hasMore) {
      return;
    }
    if (feed.error != null && !feed.pageError) return;
    if (_pageRequests.containsKey(key)) return;

    final lease = lifecycle.capture(instance.url);
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    final feedRevision = _revisions[key];
    final pageRequest = Object();
    _pageRequests[key] = pageRequest;

    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_revisions[key], feedRevision) &&
        identical(_pageRequests[key], pageRequest);

    _feeds[key] = feed.loadingNextPage();
    notifySafely();

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (!requestIsCurrent()) return;
      final next = await api.topicList(
        siteUrl: instance.url,
        path: feed.nextPagePath!,
        apiKey: apiKey,
      );

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        _putTopics(instance.url, next.topics, personalizationVersion);
        final held = _feeds[key];
        if (held == null) return;
        final seen = held.topicIds.toSet();
        final fresh = [
          for (final topic in next.topics)
            if (!seen.contains(topic.id)) topic.id,
        ];
        _feeds[key] = held.copyWith(
          topicIds: [...held.topicIds, ...fresh],
          loadingMore: false,
          nextPagePath: next.nextPagePath,
          // A page whose topics were all already on the list — routine after
          // the incoming banner prepends them — still advances the cursor.
          // Pagination ends only when the server stops supplying one or
          // repeats the cursor just requested, which would loop forever.
          clearNextPage:
              next.nextPagePath == null ||
              next.nextPagePath == feed.nextPagePath,
          clearError: true,
        );
        if (!isDisposed) {
          onFeedLoaded?.call(
            instance,
            apiKey,
            next.categories,
            _categoryIds(next.topics),
          );
        }
      });
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _report(
        error,
        stackTrace,
        'topics.loadMore',
        severity: DiagnosticSeverity.warning,
      );
      _commit(lease, () {
        if (!requestIsCurrent()) return;
        final held = _feeds[key];
        if (held != null) {
          _feeds[key] = held.withError(
            "Couldn't load more topics from ${instance.host}.",
            page: true,
          );
        }
      });
    } finally {
      _commit(lease, () {
        if (!identical(_pageRequests[key], pageRequest)) return;
        _pageRequests.remove(key);
        notifySafely();
      });
    }
  }

  void forget(String siteUrl) {
    final before = _feeds.length;
    _feeds.removeWhere((key, _) => key.$1 == siteUrl);
    _filterQueries.remove(siteUrl);
    _revisions.removeWhere((key, _) => key.$1 == siteUrl);
    _pageRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _rows.removeWhere((key, _) => key.$1 == siteUrl);
    _loadRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _pendingLoads.removeWhere((key, _) => key.$1 == siteUrl);
    for (final entry in _pendingLoadWaiters.entries.toList()) {
      if (entry.key.$1 != siteUrl) continue;
      _pendingLoadWaiters.remove(entry.key);
      if (!entry.value.isCompleted) entry.value.complete();
    }
    if (_feeds.length != before) notifySafely();
  }

  void _putTopics(
    String siteUrl,
    Iterable<Topic> topics,
    int? versionAtDispatch,
  ) {
    final prepare = prepareTopicForStore;
    store.putAll(
      siteUrl,
      prepare == null
          ? topics
          : [
              for (final topic in topics)
                prepare(siteUrl, topic, versionAtDispatch),
            ],
    );
  }

  Iterable<int> _categoryIds(Iterable<Topic> topics) => <int>{
    for (final topic in topics) ?topic.categoryId,
  };

  void _commit(SiteLease lease, void Function() mutation) {
    if (isDisposed || !lease.isCurrent) return;
    lease.commit(mutation);
  }

  void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    DiagnosticSeverity severity = DiagnosticSeverity.error,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'topics',
      severity: severity,
      handled: true,
      degraded: true,
    );
  }

  @override
  void dispose() {
    for (final waiter in _pendingLoadWaiters.values) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _pendingLoadWaiters.clear();
    _pendingLoads.clear();
    _loadRequests.clear();
    _revisions.clear();
    _pageRequests.clear();
    super.dispose();
  }
}
