import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/incoming_topics.dart';
import '../models/topic_feed.dart';

typedef TopicFeedLoaded =
    void Function(DiscourseInstance instance, String? apiKey);

typedef _FeedKey = (String siteUrl, String destinationId);

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
  });

  final TopicFeedsApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final TopicFeedLoaded? onFeedLoaded;

  final Map<_FeedKey, TopicFeed> _feeds = {};
  final Map<String, String> _filterQueries = {};
  final Map<_FeedKey, Object> _revisions = {};
  final Map<_FeedKey, Object> _pageRequests = {};
  final Map<_FeedKey, int> _rows = {};

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
  }) async {
    if (isDisposed) return;
    final key = (instance.url, destinationId);
    final existing = _feeds[key];
    if (existing != null && !force && (existing.loading || existing.loaded)) {
      return;
    }

    final lease = lifecycle.capture(instance.url);
    final revision = Object();
    _revisions[key] = revision;
    _pageRequests.remove(key);
    _rows.remove(key);

    final announced = incoming?.topicIds(destinationId) ?? const <int>[];
    incoming?.reset(destinationId);
    _feeds[key] = TopicFeed(
      loading: true,
      filterOptions: existing?.filterOptions ?? const [],
    );
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
        store.putAll(instance.url, list.topics);
        _feeds[key] = TopicFeed.of(list);
        notifySafely();
        onFeedLoaded?.call(instance, apiKey);
      });
    } on SiteLookupException catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _report(error, stackTrace, 'topics.loadFeed');
      _commit(lease, () {
        if (!identical(_revisions[key], revision)) return;
        incoming?.restore(destinationId, announced);
        _feeds[key] = TopicFeed(
          error: error.failure == SiteLookupFailure.notDiscourse
              ? 'Not allowed — try reconnecting to ${instance.host}.'
              : "Couldn't reach ${instance.host}.",
          loaded: true,
          filterOptions: existing?.filterOptions ?? const [],
        );
        notifySafely();
      });
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _report(error, stackTrace, 'topics.loadFeed');
      _commit(lease, () {
        if (!identical(_revisions[key], revision)) return;
        incoming?.restore(destinationId, announced);
        _feeds[key] = TopicFeed(
          error: "Couldn't load ${instance.host}.",
          loaded: true,
          filterOptions: existing?.filterOptions ?? const [],
        );
        notifySafely();
      });
    }
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

    final ids = incoming.topicIds(destinationId);
    if (ids.isEmpty) return;
    final lease = lifecycle.capture(instance.url);
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
        store.putAll(instance.url, list.topics);
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
    if (feed == null || feed.loadingMore || !feed.hasMore) return;
    if (_pageRequests.containsKey(key)) return;

    final lease = lifecycle.capture(instance.url);
    final feedRevision = _revisions[key];
    final pageRequest = Object();
    _pageRequests[key] = pageRequest;

    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_revisions[key], feedRevision) &&
        identical(_pageRequests[key], pageRequest);

    _feeds[key] = feed.copyWith(loadingMore: true);
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
        store.putAll(instance.url, next.topics);
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
          clearNextPage: next.nextPagePath == null || fresh.isEmpty,
        );
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
        if (held != null) _feeds[key] = held.copyWith(loadingMore: false);
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
    if (_feeds.length != before) notifySafely();
  }

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
    _revisions.clear();
    _pageRequests.clear();
    super.dispose();
  }
}
