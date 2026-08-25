import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/aggregate_preferences_store.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/topic.dart';

@immutable
final class AggregateTopicRef {
  const AggregateTopicRef({required this.siteUrl, required this.topicId});

  final String siteUrl;
  final int topicId;

  @override
  bool operator ==(Object other) =>
      other is AggregateTopicRef &&
      other.siteUrl == siteUrl &&
      other.topicId == topicId;

  @override
  int get hashCode => Object.hash(siteUrl, topicId);
}

@immutable
final class AggregateFeedState {
  const AggregateFeedState({
    this.topics = const [],
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.loaded = false,
    this.includedForums = 0,
    this.loadedForums = 0,
    this.failures = const {},
    this.hasMore = false,
    this.updatedAt,
  });

  final List<AggregateTopicRef> topics;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final bool loaded;
  final int includedForums;
  final int loadedForums;
  final Map<String, String> failures;
  final bool hasMore;
  final DateTime? updatedAt;

  bool get isEmpty => loaded && topics.isEmpty;

  AggregateFeedState copyWith({
    List<AggregateTopicRef>? topics,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    bool? loaded,
    int? includedForums,
    int? loadedForums,
    Map<String, String>? failures,
    bool? hasMore,
    DateTime? updatedAt,
  }) => AggregateFeedState(
    topics: topics ?? this.topics,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    loaded: loaded ?? this.loaded,
    includedForums: includedForums ?? this.includedForums,
    loadedForums: loadedForums ?? this.loadedForums,
    failures: failures ?? this.failures,
    hasMore: hasMore ?? this.hasMore,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

typedef AggregateCategoriesReader =
    List<TopicCategory> Function(String siteUrl);
typedef AggregateCategoriesWriter =
    void Function(String siteUrl, Iterable<TopicCategory> categories);
typedef AggregateUserWriter =
    void Function(DiscourseInstance instance, DiscourseUser user);
typedef AggregatePersonalizationVersionReader = int Function(String siteUrl);
typedef AggregateTopicPreparer =
    Topic Function(String siteUrl, Topic topic, int versionAtDispatch);

/// Owns the global, account-specific feed without widening shell rebuilds.
///
/// Each origin remains governed by [DiscourseRequestCoordinator]. The small
/// app-wide semaphore here addresses the distinct Aggregate problem: opening
/// one screen can otherwise start work against every saved origin at once.
final class AggregateFeedController extends FrameSafeNotifier {
  AggregateFeedController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.store,
    required this.preferences,
    required this.readCategories,
    required this.writeCategories,
    required this.writeUser,
    required this.readPersonalizationVersion,
    required this.prepareTopic,
    this.freshness = const Duration(minutes: 1),
    this.batchSize = 30,
    this.maximumConcurrentRequests = 4,
  }) : assert(freshness >= Duration.zero),
       assert(batchSize > 0),
       assert(maximumConcurrentRequests > 0),
       _requests = _AggregateRequestPool(maximumConcurrentRequests);

  final DiscourseApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final AggregatePreferencesStore preferences;
  final AggregateCategoriesReader readCategories;
  final AggregateCategoriesWriter writeCategories;
  final AggregateUserWriter writeUser;
  final AggregatePersonalizationVersionReader readPersonalizationVersion;
  final AggregateTopicPreparer prepareTopic;
  final Duration freshness;
  final int batchSize;
  final int maximumConcurrentRequests;
  final _AggregateRequestPool _requests;

  AggregateFeedState _state = const AggregateFeedState();
  AggregateFeedState get state => _state;

  Set<String> _excludedForums = const {};
  Set<String> get excludedForums => Set.unmodifiable(_excludedForums);

  final Map<String, _AggregateSource> _sources = {};
  final Set<AggregateTopicRef> _emitted = {};
  Object? _revision;
  Future<void>? _refreshRequest;
  Future<void>? _pageRequest;

  Future<void> loadPreferences(Iterable<DiscourseInstance> instances) async {
    final loaded = await preferences.load();
    if (isDisposed) return;
    final valid = {for (final instance in instances) instance.url};
    _excludedForums = Set.unmodifiable(loaded.intersection(valid));
  }

  bool includes(DiscourseInstance instance) =>
      instance.isConnected && !_excludedForums.contains(instance.url);

  Future<void> setIncludedForums({
    required Iterable<DiscourseInstance> allForums,
    required Set<String> includedConnectedForums,
  }) async {
    final valid = {for (final instance in allForums) instance.url};
    final next = _excludedForums.intersection(valid);
    for (final instance in allForums) {
      if (!instance.isConnected) continue;
      if (includedConnectedForums.contains(instance.url)) {
        next.remove(instance.url);
      } else {
        next.add(instance.url);
      }
    }
    if (setEquals(next, _excludedForums)) return;
    _excludedForums = Set.unmodifiable(next);
    notifySafely();
    await preferences.save(_excludedForums);
  }

  Future<void> pruneForums(Iterable<DiscourseInstance> instances) async {
    final valid = {for (final instance in instances) instance.url};
    final next = _excludedForums.intersection(valid);
    if (setEquals(next, _excludedForums)) return;
    _excludedForums = Set.unmodifiable(next);
    notifySafely();
    await preferences.save(next);
  }

  Future<void> open(Iterable<DiscourseInstance> instances) {
    _pruneInactiveTopics();
    final updated = _state.updatedAt;
    final stale =
        updated == null || DateTime.now().difference(updated) >= freshness;
    if (_state.loaded && !stale) return Future.value();
    return refresh(instances);
  }

  /// Removes a topic as soon as local reading state says it is caught up.
  ///
  /// The server is still authoritative on the next refresh, but returning to
  /// a fresh Aggregate snapshot should not resurrect a row just read here.
  void reconcileTopic(String siteUrl, int topicId) {
    final reference = AggregateTopicRef(siteUrl: siteUrl, topicId: topicId);
    if (!_state.topics.contains(reference)) return;
    final topic = store.read<Topic>(siteUrl, topicId);
    if (topic == null || topic.hasUnseenActivity) return;
    _state = _state.copyWith(
      topics: List.unmodifiable([
        for (final held in _state.topics)
          if (held != reference) held,
      ]),
    );
    notifySafely();
  }

  void _pruneInactiveTopics() {
    final topics = [
      for (final reference in _state.topics)
        if (store
                .read<Topic>(reference.siteUrl, reference.topicId)
                ?.hasUnseenActivity !=
            false)
          reference,
    ];
    if (topics.length == _state.topics.length) return;
    _state = _state.copyWith(topics: List.unmodifiable(topics));
    notifySafely();
  }

  Future<void> refresh(
    Iterable<DiscourseInstance> instances, {
    bool force = false,
  }) {
    final selected = [
      for (final instance in instances)
        if (includes(instance)) instance,
    ];
    final active = _refreshRequest;
    if (active != null && !force) return active;

    final revision = Object();
    _revision = revision;
    final held = _state;
    _state = held.copyWith(
      loading: held.topics.isEmpty,
      refreshing: held.topics.isNotEmpty,
      loadingMore: false,
      includedForums: selected.length,
      loadedForums: 0,
      failures: const {},
      hasMore: false,
    );
    notifySafely();

    late final Future<void> request;
    request = _performRefresh(selected, revision).whenComplete(() {
      if (identical(_refreshRequest, request)) _refreshRequest = null;
    });
    _refreshRequest = request;
    return request;
  }

  Future<void> _performRefresh(
    List<DiscourseInstance> instances,
    Object revision,
  ) async {
    final pageSize = (batchSize / (instances.isEmpty ? 1 : instances.length))
        .ceil()
        .clamp(10, 30);
    final sources = <String, _AggregateSource>{};
    final failures = <String, String>{};
    var loadedForums = 0;

    await Future.wait([
      for (var index = 0; index < instances.length; index++)
        _primeSource(instances[index], index, pageSize, revision)
            .then((source) {
              if (source != null) sources[source.instance.url] = source;
            })
            .catchError((Object error, StackTrace stackTrace) {
              final instance = instances[index];
              failures[instance.url] = "Couldn't refresh ${instance.host}.";
              _report(error, stackTrace, 'aggregate.loadForum');
            })
            .whenComplete(() {
              loadedForums++;
              if (_isCurrent(revision)) {
                _state = _state.copyWith(loadedForums: loadedForums);
                notifySafely();
              }
            }),
    ]);
    if (!_isCurrent(revision)) return;

    final emitted = <AggregateTopicRef>{};
    final topics = <AggregateTopicRef>[];
    await _appendBatch(
      sources: sources,
      topics: topics,
      emitted: emitted,
      failures: failures,
      revision: revision,
    );
    if (!_isCurrent(revision)) return;

    _sources
      ..clear()
      ..addAll(sources);
    _emitted
      ..clear()
      ..addAll(emitted);
    _state = AggregateFeedState(
      topics: List.unmodifiable(topics),
      loaded: true,
      includedForums: instances.length,
      loadedForums: loadedForums,
      failures: Map.unmodifiable(failures),
      hasMore: _sources.values.any((source) => source.hasMore),
      updatedAt: DateTime.now(),
    );
    notifySafely();
  }

  Future<_AggregateSource?> _primeSource(
    DiscourseInstance instance,
    int order,
    int pageSize,
    Object revision,
  ) async {
    final lease = lifecycle.capture(instance.url);
    final apiKey = await credentials.apiKeyFor(instance.url);
    if (!_isCurrent(revision) || !lease.isCurrent) {
      return null;
    }
    if (apiKey == null) {
      throw StateError('Connected Aggregate forum has no credential.');
    }

    final user = await _requests.run(
      () => api.currentUser(siteUrl: instance.url, apiKey: apiKey),
    );
    if (!_isCurrent(revision) || !lease.isCurrent) return null;
    writeUser(instance, user);

    final followed = user.followedCategoryIds ?? const <int>{};
    final source = _AggregateSource(
      instance: instance.copyWith(user: user),
      order: order,
      apiKey: apiKey,
      followedCategoryIds: followed,
      categories: {
        for (final category in readCategories(instance.url))
          category.id: category,
      },
      pageSize: pageSize,
    );
    if (followed.isEmpty) {
      source.complete = true;
      return source;
    }

    await _loadPage(source, source.firstPagePath, revision);
    return source;
  }

  Future<void> loadMore() {
    if (_state.loadingMore || !_state.hasMore || _refreshRequest != null) {
      return Future.value();
    }
    final active = _pageRequest;
    if (active != null) return active;
    final revision = _revision;
    if (revision == null) return Future.value();

    _state = _state.copyWith(loadingMore: true);
    notifySafely();
    late final Future<void> request;
    request = _performLoadMore(revision).whenComplete(() {
      if (identical(_pageRequest, request)) _pageRequest = null;
    });
    _pageRequest = request;
    return request;
  }

  Future<void> _performLoadMore(Object revision) async {
    final topics = [..._state.topics];
    final failures = {..._state.failures};
    await _appendBatch(
      sources: _sources,
      topics: topics,
      emitted: _emitted,
      failures: failures,
      revision: revision,
    );
    if (!_isCurrent(revision)) return;
    _state = _state.copyWith(
      topics: List.unmodifiable(topics),
      loadingMore: false,
      failures: Map.unmodifiable(failures),
      hasMore: _sources.values.any((source) => source.hasMore),
    );
    notifySafely();
  }

  Future<void> _appendBatch({
    required Map<String, _AggregateSource> sources,
    required List<AggregateTopicRef> topics,
    required Set<AggregateTopicRef> emitted,
    required Map<String, String> failures,
    required Object revision,
  }) async {
    var added = 0;
    while (added < batchSize && _isCurrent(revision)) {
      final empty = [
        for (final source in sources.values)
          if (source.buffer.isEmpty && source.hasMore) source,
      ];
      if (empty.isNotEmpty) {
        await Future.wait([
          for (final source in empty)
            _ensureHead(source, revision).catchError((
              Object error,
              StackTrace stackTrace,
            ) {
              source.complete = true;
              source.nextPagePath = null;
              failures[source.instance.url] =
                  "Couldn't load more from ${source.instance.host}.";
              _report(error, stackTrace, 'aggregate.loadPage');
            }),
        ]);
        if (!_isCurrent(revision)) return;
      }

      _AggregateSource? best;
      for (final source in sources.values) {
        if (source.buffer.isEmpty) continue;
        if (best == null || _comesBefore(source, best)) best = source;
      }
      if (best == null) return;

      final topic = best.buffer.removeFirst();
      final ref = AggregateTopicRef(
        siteUrl: best.instance.url,
        topicId: topic.id,
      );
      if (!emitted.add(ref)) continue;
      topics.add(ref);
      added++;
    }
  }

  Future<void> _ensureHead(_AggregateSource source, Object revision) async {
    while (source.buffer.isEmpty && source.hasMore && _isCurrent(revision)) {
      final path = source.nextPagePath;
      if (path == null) return;
      await _loadPage(source, path, revision);
    }
  }

  Future<void> _loadPage(
    _AggregateSource source,
    String path,
    Object revision,
  ) async {
    final lease = lifecycle.capture(source.instance.url);
    final personalizationVersion = readPersonalizationVersion(
      source.instance.url,
    );
    final list = await _requests.run(
      () => api.topicList(
        siteUrl: source.instance.url,
        path: path,
        apiKey: source.apiKey,
      ),
    );
    if (!_isCurrent(revision) || !lease.isCurrent) return;

    await _resolveCategories(source, list.topics, revision);
    if (!_isCurrent(revision) || !lease.isCurrent) return;

    final accepted = <Topic>[];
    for (final incoming in list.topics) {
      if (!incoming.hasUnseenActivity ||
          !_belongsToFollowedCategory(source, incoming.categoryId)) {
        continue;
      }
      final topic = prepareTopic(
        source.instance.url,
        incoming,
        personalizationVersion,
      );
      accepted.add(store.put(source.instance.url, topic));
    }
    accepted.sort(_compareTopics);
    source.buffer.addAll(accepted);
    source.nextPagePath = list.nextPagePath;
    source.complete = list.nextPagePath == null;
  }

  Future<void> _resolveCategories(
    _AggregateSource source,
    List<Topic> topics,
    Object revision,
  ) async {
    bool unresolved() {
      for (final topic in topics) {
        final categoryId = topic.categoryId;
        if (categoryId == null) continue;
        if (_categoryMatch(source, categoryId) == _CategoryMatch.unknown) {
          return true;
        }
      }
      return false;
    }

    while (unresolved() && !source.categoriesComplete && _isCurrent(revision)) {
      final result = await _requests.run(
        () => api.loadCategories(
          siteUrl: source.instance.url,
          apiKey: source.apiKey,
          page: source.nextCategoryPage,
        ),
      );
      if (!_isCurrent(revision)) return;
      source.nextCategoryPage++;
      for (final category in result.categories) {
        source.categories[category.id] = category;
      }
      writeCategories(source.instance.url, result.categories);
      if (result.rootCategoryIds.isEmpty) source.categoriesComplete = true;
    }
  }

  bool _belongsToFollowedCategory(_AggregateSource source, int? categoryId) =>
      categoryId != null &&
      _categoryMatch(source, categoryId) == _CategoryMatch.yes;

  _CategoryMatch _categoryMatch(_AggregateSource source, int categoryId) {
    var current = categoryId;
    final visited = <int>{};
    while (visited.add(current)) {
      if (source.followedCategoryIds.contains(current)) {
        return _CategoryMatch.yes;
      }
      final category = source.categories[current];
      if (category == null) return _CategoryMatch.unknown;
      final parent = category.parentCategoryId;
      if (parent == null) return _CategoryMatch.no;
      current = parent;
    }
    return _CategoryMatch.no;
  }

  bool _comesBefore(_AggregateSource left, _AggregateSource right) {
    final compared = _compareTopics(left.buffer.first, right.buffer.first);
    if (compared != 0) return compared < 0;
    return left.order < right.order;
  }

  static int _compareTopics(Topic left, Topic right) {
    final leftTime = left.bumpedAt;
    final rightTime = right.bumpedAt;
    if (leftTime != null && rightTime != null) {
      final time = rightTime.compareTo(leftTime);
      if (time != 0) return time;
    } else if (leftTime != null) {
      return -1;
    } else if (rightTime != null) {
      return 1;
    }
    return right.id.compareTo(left.id);
  }

  bool _isCurrent(Object revision) =>
      !isDisposed && identical(_revision, revision);

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'aggregate',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  @override
  void dispose() {
    _revision = null;
    _sources.clear();
    _emitted.clear();
    _requests.close();
    super.dispose();
  }
}

enum _CategoryMatch { yes, no, unknown }

final class _AggregateSource {
  _AggregateSource({
    required this.instance,
    required this.order,
    required this.apiKey,
    required this.followedCategoryIds,
    required this.categories,
    required this.pageSize,
  });

  final DiscourseInstance instance;
  final int order;
  final String apiKey;
  final Set<int> followedCategoryIds;
  final Map<int, TopicCategory> categories;
  final int pageSize;
  final Queue<Topic> buffer = Queue();
  String? nextPagePath;
  bool complete = false;
  int nextCategoryPage = 1;
  bool categoriesComplete = false;

  String get firstPagePath =>
      '/unseen.json?f=tracked&no_definitions=true&per_page=$pageSize';

  bool get hasMore => buffer.isNotEmpty || (!complete && nextPagePath != null);
}

final class _AggregateRequestPool {
  _AggregateRequestPool(this.maximumConcurrent);

  final int maximumConcurrent;
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;
  bool _closed = false;

  Future<T> run<T>(Future<T> Function() operation) async {
    await _acquire();
    try {
      return await operation();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_closed) {
      return Future.error(StateError('Aggregate request pool closed'));
    }
    if (_active < maximumConcurrent) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_closed) return;
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
      return;
    }
    _active--;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final error = StateError('Aggregate request pool closed');
    final stackTrace = StackTrace.current;
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().completeError(error, stackTrace);
    }
  }
}
