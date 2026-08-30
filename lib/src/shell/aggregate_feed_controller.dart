import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/aggregate_preferences_store.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';

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

/// A saved work context in the app-wide Aggregate surface.
@immutable
final class AggregateFeedTab {
  const AggregateFeedTab({required this.id, this.name});

  final String id;
  final String? name;
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
    required this.readPersonalizationVersion,
    required this.prepareTopic,
    this.freshness = const Duration(minutes: 1),
    this.batchSize = 30,
    this.maximumConcurrentRequests = 4,
  }) : assert(freshness >= Duration.zero),
       assert(batchSize > 0),
       assert(maximumConcurrentRequests > 0),
       _requests = _AggregateRequestPool(maximumConcurrentRequests) {
    final tab = _AggregateTabSession(
      id: AggregatePreferencesStore.defaultTabId,
    );
    _tabs[tab.id] = tab;
    _activeTabId = tab.id;
  }

  final TopicFeedsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final AggregatePreferencesStore preferences;
  final AggregatePersonalizationVersionReader readPersonalizationVersion;
  final AggregateTopicPreparer prepareTopic;
  final Duration freshness;
  final int batchSize;
  final int maximumConcurrentRequests;
  final _AggregateRequestPool _requests;

  final Map<String, _AggregateTabSession> _tabs = {};
  late String _activeTabId;
  int _tabSequence = 0;

  _AggregateTabSession get _activeTab => _tabs[_activeTabId]!;

  AggregateFeedState get state => _activeTab.state;
  String get activeTabId => _activeTabId;
  List<AggregateFeedTab> get tabs => List.unmodifiable([
    for (final tab in _tabs.values)
      AggregateFeedTab(id: tab.id, name: tab.name),
  ]);
  bool get canCreateTab => _tabs.length < AggregatePreferencesStore.maximumTabs;

  Set<String> get excludedForums => Set.unmodifiable(_activeTab.excludedForums);

  String queryFor(String siteUrl) => _activeTab.queries[siteUrl] ?? '';

  List<TopicFilterOption> filterOptionsFor(String siteUrl) =>
      _activeTab.sources[siteUrl]?.filterOptions ?? const [];

  Future<void> loadPreferences(Iterable<DiscourseInstance> instances) async {
    final loaded = await preferences.load();
    if (isDisposed) return;
    final valid = {for (final instance in instances) instance.url};
    _tabs.clear();
    for (final saved in loaded.tabs.take(
      AggregatePreferencesStore.maximumTabs,
    )) {
      final tab = _AggregateTabSession(
        id: saved.id,
        name: saved.name,
        excludedForums: saved.excludedForums.intersection(valid),
        queries: {
          for (final MapEntry(:key, :value) in saved.queries.entries)
            if (valid.contains(key)) key: value,
        },
      );
      _tabs[tab.id] = tab;
    }
    if (_tabs.isEmpty) {
      final tab = _AggregateTabSession(
        id: AggregatePreferencesStore.defaultTabId,
      );
      _tabs[tab.id] = tab;
    }
    _activeTabId = _tabs.containsKey(loaded.activeTabId)
        ? loaded.activeTabId
        : _tabs.keys.first;
  }

  bool includes(DiscourseInstance instance) =>
      instance.isConnected && !_activeTab.excludedForums.contains(instance.url);

  Future<void> setForumFilters({
    required Iterable<DiscourseInstance> allForums,
    required Set<String> includedConnectedForums,
    required Map<String, String> queries,
  }) async {
    final tab = _activeTab;
    final valid = {for (final instance in allForums) instance.url};
    final nextExcluded = tab.excludedForums.intersection(valid);
    for (final instance in allForums) {
      if (!instance.isConnected) continue;
      if (includedConnectedForums.contains(instance.url)) {
        nextExcluded.remove(instance.url);
      } else {
        nextExcluded.add(instance.url);
      }
    }
    final nextQueries = {
      for (final MapEntry(:key, :value) in queries.entries)
        if (valid.contains(key) && value.trim().isNotEmpty)
          key: _boundedQuery(value),
    };
    if (setEquals(nextExcluded, tab.excludedForums) &&
        mapEquals(nextQueries, tab.queries)) {
      return;
    }
    tab.excludedForums = Set.unmodifiable(nextExcluded);
    tab.queries = Map.unmodifiable(nextQueries);
    notifySafely();
    await _persistTabs();
  }

  Future<void> pruneForums(Iterable<DiscourseInstance> instances) async {
    final valid = {for (final instance in instances) instance.url};
    var changed = false;
    for (final tab in _tabs.values) {
      final nextExcluded = tab.excludedForums.intersection(valid);
      final nextQueries = {
        for (final MapEntry(:key, :value) in tab.queries.entries)
          if (valid.contains(key)) key: value,
      };
      if (setEquals(nextExcluded, tab.excludedForums) &&
          mapEquals(nextQueries, tab.queries)) {
        continue;
      }
      tab.excludedForums = Set.unmodifiable(nextExcluded);
      tab.queries = Map.unmodifiable(nextQueries);
      changed = true;
    }
    if (!changed) return;
    notifySafely();
    await _persistTabs();
  }

  String? createTab() {
    if (!canCreateTab) return null;
    final tab = _AggregateTabSession(id: _nextTabId());
    _tabs[tab.id] = tab;
    _activeTabId = tab.id;
    unawaited(_persistTabs());
    notifySafely();
    return tab.id;
  }

  bool selectTab(String id) {
    if (!_tabs.containsKey(id)) return false;
    if (_activeTabId != id) {
      _activeTabId = id;
      unawaited(_persistTabs());
      notifySafely();
    }
    return true;
  }

  bool moveTab(String id, int newIndex) {
    if (_tabs.length < 2) return false;
    final entries = _tabs.entries.toList();
    final oldIndex = entries.indexWhere((entry) => entry.key == id);
    if (oldIndex < 0) return false;
    final destination = newIndex.clamp(0, entries.length - 1);
    if (oldIndex == destination) return true;

    final moved = entries.removeAt(oldIndex);
    entries.insert(destination, moved);
    _tabs
      ..clear()
      ..addEntries(entries);
    unawaited(_persistTabs());
    notifySafely();
    return true;
  }

  bool renameTab(String id, String name) {
    final tab = _tabs[id];
    final normalized = AggregatePreferencesStore.normalizeTabName(name);
    if (tab == null || normalized == null) return false;
    if (tab.name == normalized) return true;
    tab.name = normalized;
    unawaited(_persistTabs());
    notifySafely();
    return true;
  }

  bool closeTab(String id) {
    final closing = _tabs[id];
    if (closing == null) return false;
    final ids = _tabs.keys.toList();
    final index = ids.indexOf(id);
    final closedActive = id == _activeTabId;
    closing.invalidate();
    _tabs.remove(id);

    if (_tabs.isEmpty) {
      final replacement = _AggregateTabSession(id: _nextTabId());
      _tabs[replacement.id] = replacement;
      _activeTabId = replacement.id;
    } else if (closedActive) {
      final remaining = _tabs.keys.toList();
      _activeTabId =
          remaining[index < remaining.length ? index : remaining.length - 1];
    }
    unawaited(_persistTabs());
    notifySafely();
    return closedActive;
  }

  bool closeOtherTabs(String id) {
    final kept = _tabs[id];
    if (kept == null || _tabs.length == 1) return false;
    for (final tab in _tabs.values) {
      if (!identical(tab, kept)) tab.invalidate();
    }
    _tabs
      ..clear()
      ..[id] = kept;
    _activeTabId = id;
    unawaited(_persistTabs());
    notifySafely();
    return true;
  }

  String _nextTabId() {
    late String id;
    do {
      _tabSequence++;
      id =
          'aggregate-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
          '${_tabSequence.toRadixString(36)}';
    } while (_tabs.containsKey(id));
    return id;
  }

  Future<void> _persistTabs() => preferences.save(
    tabs: [for (final tab in _tabs.values) tab.preferences],
    activeTabId: _activeTabId,
  );

  Future<void> open(Iterable<DiscourseInstance> instances) {
    final updated = state.updatedAt;
    final stale =
        updated == null || DateTime.now().difference(updated) >= freshness;
    if (state.loaded && !stale) return Future.value();
    return refresh(instances);
  }

  Future<void> refresh(
    Iterable<DiscourseInstance> instances, {
    bool force = false,
  }) {
    final tab = _activeTab;
    final selected = [
      for (final instance in instances)
        if (instance.isConnected && !tab.excludedForums.contains(instance.url))
          _ConfiguredAggregateForum(instance, tab.queries[instance.url] ?? ''),
    ];
    final active = tab.refreshRequest;
    if (active != null && !force) return active;

    final revision = Object();
    tab.revision = revision;
    final held = tab.state;
    tab.state = held.copyWith(
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
    request = _performRefresh(tab, selected, revision).whenComplete(() {
      if (identical(tab.refreshRequest, request)) tab.refreshRequest = null;
    });
    tab.refreshRequest = request;
    return request;
  }

  Future<void> _performRefresh(
    _AggregateTabSession tab,
    List<_ConfiguredAggregateForum> forums,
    Object revision,
  ) async {
    final pageSize = (batchSize / (forums.isEmpty ? 1 : forums.length))
        .ceil()
        .clamp(10, 30);
    final sources = <String, _AggregateSource>{};
    final failures = <String, String>{};
    var loadedForums = 0;

    await Future.wait([
      for (var index = 0; index < forums.length; index++)
        _primeSource(tab, forums[index], index, pageSize, revision)
            .then((source) {
              if (source != null) sources[source.instance.url] = source;
            })
            .catchError((Object error, StackTrace stackTrace) {
              final instance = forums[index].instance;
              failures[instance.url] = "Couldn't refresh ${instance.host}.";
              _report(error, stackTrace, 'aggregate.loadForum');
            })
            .whenComplete(() {
              loadedForums++;
              if (_isCurrent(tab, revision)) {
                tab.state = tab.state.copyWith(loadedForums: loadedForums);
                if (identical(tab, _activeTab)) notifySafely();
              }
            }),
    ]);
    if (!_isCurrent(tab, revision)) return;

    final emitted = <AggregateTopicRef>{};
    final topics = <AggregateTopicRef>[];
    await _appendBatch(
      tab: tab,
      sources: sources,
      topics: topics,
      emitted: emitted,
      failures: failures,
      revision: revision,
    );
    if (!_isCurrent(tab, revision)) return;

    tab.sources
      ..clear()
      ..addAll(sources);
    tab.emitted
      ..clear()
      ..addAll(emitted);
    tab.state = AggregateFeedState(
      topics: List.unmodifiable(topics),
      loaded: true,
      includedForums: forums.length,
      loadedForums: loadedForums,
      failures: Map.unmodifiable(failures),
      hasMore: tab.sources.values.any((source) => source.hasMore),
      updatedAt: DateTime.now(),
    );
    if (identical(tab, _activeTab)) notifySafely();
  }

  Future<_AggregateSource?> _primeSource(
    _AggregateTabSession tab,
    _ConfiguredAggregateForum configured,
    int order,
    int pageSize,
    Object revision,
  ) async {
    final instance = configured.instance;
    final lease = lifecycle.capture(instance.url);
    final apiKey = await credentials.apiKeyFor(instance.url);
    if (!_isCurrent(tab, revision) || !lease.isCurrent) {
      return null;
    }
    if (apiKey == null) {
      throw StateError('Connected Aggregate forum has no credential.');
    }

    final source = _AggregateSource(
      instance: instance,
      order: order,
      apiKey: apiKey,
      query: configured.query,
      pageSize: pageSize,
    );
    await _loadPage(tab, source, source.firstPagePath, revision);
    return source;
  }

  Future<void> loadMore() {
    final tab = _activeTab;
    if (tab.state.loadingMore ||
        !tab.state.hasMore ||
        tab.refreshRequest != null) {
      return Future.value();
    }
    final active = tab.pageRequest;
    if (active != null) return active;
    final revision = tab.revision;
    if (revision == null) return Future.value();

    tab.state = tab.state.copyWith(loadingMore: true);
    notifySafely();
    late final Future<void> request;
    request = _performLoadMore(tab, revision).whenComplete(() {
      if (identical(tab.pageRequest, request)) tab.pageRequest = null;
    });
    tab.pageRequest = request;
    return request;
  }

  Future<void> _performLoadMore(
    _AggregateTabSession tab,
    Object revision,
  ) async {
    final topics = [...tab.state.topics];
    final failures = {...tab.state.failures};
    await _appendBatch(
      tab: tab,
      sources: tab.sources,
      topics: topics,
      emitted: tab.emitted,
      failures: failures,
      revision: revision,
    );
    if (!_isCurrent(tab, revision)) return;
    tab.state = tab.state.copyWith(
      topics: List.unmodifiable(topics),
      loadingMore: false,
      failures: Map.unmodifiable(failures),
      hasMore: tab.sources.values.any((source) => source.hasMore),
    );
    if (identical(tab, _activeTab)) notifySafely();
  }

  Future<void> _appendBatch({
    required _AggregateTabSession tab,
    required Map<String, _AggregateSource> sources,
    required List<AggregateTopicRef> topics,
    required Set<AggregateTopicRef> emitted,
    required Map<String, String> failures,
    required Object revision,
  }) async {
    var added = 0;
    while (added < batchSize && _isCurrent(tab, revision)) {
      final empty = [
        for (final source in sources.values)
          if (source.buffer.isEmpty && source.hasMore) source,
      ];
      if (empty.isNotEmpty) {
        await Future.wait([
          for (final source in empty)
            _ensureHead(tab, source, revision).catchError((
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
        if (!_isCurrent(tab, revision)) return;
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

  Future<void> _ensureHead(
    _AggregateTabSession tab,
    _AggregateSource source,
    Object revision,
  ) async {
    while (source.buffer.isEmpty &&
        source.hasMore &&
        _isCurrent(tab, revision)) {
      final path = source.nextPagePath;
      if (path == null) return;
      await _loadPage(tab, source, path, revision);
    }
  }

  Future<void> _loadPage(
    _AggregateTabSession tab,
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
    if (!_isCurrent(tab, revision) || !lease.isCurrent) return;

    final accepted = <Topic>[];
    for (final incoming in list.topics) {
      final topic = prepareTopic(
        source.instance.url,
        incoming,
        personalizationVersion,
      );
      accepted.add(store.put(source.instance.url, topic));
    }
    accepted.sort(_compareTopics);
    source.buffer.addAll(accepted);
    if (list.filterOptions.isNotEmpty) {
      source.filterOptions = list.filterOptions;
    }
    source.nextPagePath = list.nextPagePath;
    source.complete = list.nextPagePath == null;
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

  bool _isCurrent(_AggregateTabSession tab, Object revision) =>
      !isDisposed &&
      identical(_tabs[tab.id], tab) &&
      identical(tab.revision, revision);

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
    for (final tab in _tabs.values) {
      tab.invalidate();
    }
    _tabs.clear();
    _requests.close();
    super.dispose();
  }

  static String _boundedQuery(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= AggregatePreferencesStore.maximumQueryLength) {
      return trimmed;
    }
    return trimmed.substring(0, AggregatePreferencesStore.maximumQueryLength);
  }
}

final class _AggregateTabSession {
  _AggregateTabSession({
    required this.id,
    this.name,
    Set<String> excludedForums = const {},
    Map<String, String> queries = const {},
  }) : excludedForums = Set.unmodifiable(excludedForums),
       queries = Map.unmodifiable(queries);

  final String id;
  String? name;
  Set<String> excludedForums;
  Map<String, String> queries;
  AggregateFeedState state = const AggregateFeedState();
  final Map<String, _AggregateSource> sources = {};
  final Set<AggregateTopicRef> emitted = {};
  Object? revision;
  Future<void>? refreshRequest;
  Future<void>? pageRequest;

  AggregateTabPreferences get preferences => AggregateTabPreferences(
    id: id,
    name: name,
    excludedForums: excludedForums,
    queries: queries,
  );

  void invalidate() {
    revision = null;
    sources.clear();
    emitted.clear();
  }
}

final class _ConfiguredAggregateForum {
  const _ConfiguredAggregateForum(this.instance, this.query);

  final DiscourseInstance instance;
  final String query;
}

final class _AggregateSource {
  _AggregateSource({
    required this.instance,
    required this.order,
    required this.apiKey,
    required this.query,
    required this.pageSize,
  });

  final DiscourseInstance instance;
  final int order;
  final String apiKey;
  final String query;
  final int pageSize;
  final Queue<Topic> buffer = Queue();
  List<TopicFilterOption> filterOptions = const [];
  String? nextPagePath;
  bool complete = false;

  String get firstPagePath => Uri(
    path: '/filter.json',
    queryParameters: {
      'per_page': '$pageSize',
      if (query.isNotEmpty) 'q': query,
    },
  ).toString();

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
