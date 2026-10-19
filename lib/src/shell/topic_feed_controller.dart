import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
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

typedef TopicFeedPreparation =
    Future<void> Function(
      DiscourseInstance instance,
      String? apiKey,
      Iterable<TopicCategory> categories,
      Iterable<int> categoryIds,
    );

typedef TopicFeedIncomingFilter =
    IncomingTopicsFilter? Function(String path, TopicList list);

typedef _FeedKey = (String siteUrl, String destinationId);
typedef _FeedLoad = ({
  DiscourseInstance instance,
  String destinationId,
  String path,
  IncomingTopics? incoming,
});

typedef _RowRange = ({int first, int last});
typedef _CursorCheckpoint = ({
  int row,
  String path,
  String? resumePath,
  _PageShape? shape,
});

final class _PageShape {
  _PageShape(List<int> ids, Set<int> seen)
    : indices = [
        for (var index = 0; index < ids.length; index++)
          if (seen.add(ids[index])) index,
      ],
      signature = Object.hashAll(ids),
      count = ids.length;

  _PageShape._(this.indices, this.signature, this.count);

  final List<int> indices;
  final int signature;
  final int count;

  List<int> resolve(List<int> ids) {
    if (ids.length != count || Object.hashAll(ids) != signature) {
      throw StateError('The topic page changed. Refresh the list to continue.');
    }
    return [for (final index in indices) ids[index]];
  }

  _PageShape removingRows(int start, Set<int> removed) => _PageShape._(
    [
      for (var index = 0; index < indices.length; index++)
        if (!removed.contains(start + index)) indices[index],
    ],
    signature,
    count,
  );
}

final class _FeedWindow {
  _FeedWindow({this.readerTopics});

  final Set<int> Function()? readerTopics;
  String? rootPath;
  int pagesWithoutRows = 0;
  final Map<int, int> rows = {};
  final List<_CursorCheckpoint> checkpoints = [];
  final Map<Object, int> owners = {};
  final Map<Object, _RowRange> viewports = {};

  bool protects(int row, {Set<int> readers = const {}}) =>
      readers.contains(rows[row]) ||
      viewports.values.any((range) => row >= range.first && row <= range.last);

  void touch(int row) {
    if (rows.remove(row) case final id?) rows[row] = id;
  }

  void trim(int maximum, {_RowRange? preferredRange}) {
    final readers = readerTopics?.call() ?? const <int>{};
    while (rows.length > maximum) {
      final removable = rows.keys.where(
        (row) => !protects(row, readers: readers),
      );
      if (removable.isEmpty) return;
      final outside = preferredRange == null
          ? removable
          : removable.where(
              (row) => row < preferredRange.first || row > preferredRange.last,
            );
      rows.remove((outside.isEmpty ? removable : outside).first);
    }
  }

  void remember(
    int row,
    String path,
    int maximum, {
    String? resumePath,
    _PageShape? shape,
  }) {
    for (final previous in checkpoints) {
      if (previous.path == path) {
        resumePath ??= previous.resumePath;
        shape ??= previous.shape;
      }
    }
    checkpoints.removeWhere((checkpoint) => checkpoint.path == path);
    checkpoints.add((
      row: row,
      path: path,
      resumePath: resumePath,
      shape: shape,
    ));
    if (checkpoints.length > maximum) checkpoints.removeAt(0);
  }

  void put(
    int start,
    Iterable<int> ids,
    int maximum, {
    bool restoring = false,
    _RowRange? preferredRange,
  }) {
    if (restoring) {
      final readers = readerTopics?.call() ?? const <int>{};
      var row = start;
      for (final id in ids) {
        for (final entry in rows.entries) {
          if (protects(entry.key, readers: readers) &&
              ((entry.value == id && entry.key != row) ||
                  (entry.key == row && entry.value != id))) {
            throw StateError(
              'The topic page moved visible rows. Refresh the list.',
            );
          }
        }
        row++;
      }
    }
    var row = start;
    for (final id in ids) {
      rows.removeWhere((otherRow, otherId) => otherRow != row && otherId == id);
      rows.remove(row);
      rows[row++] = id;
    }
    trim(maximum, preferredRange: preferredRange);
  }

  void truncate(int count) {
    final readers = readerTopics?.call() ?? const <int>{};
    if (rows.keys.any(
      (row) => row >= count && protects(row, readers: readers),
    )) {
      throw StateError(
        'The topic list changed beyond a visible row. Refresh the list.',
      );
    }
    rows.removeWhere((row, _) => row >= count);
    checkpoints.removeWhere((checkpoint) => checkpoint.row >= count);
  }

  int removeSourceRows(Set<int> removed, int totalRows) {
    if (removed.any(rows.containsKey)) {
      throw StateError('The duplicate topic slot changed. Refresh the list.');
    }
    int shifted(int row) => row - removed.where((old) => old < row).length;
    final oldRows = rows.entries.toList();
    rows.clear();
    for (final entry in oldRows) {
      rows[shifted(entry.key)] = entry.value;
    }
    for (var index = 0; index < checkpoints.length; index++) {
      final checkpoint = checkpoints[index];
      checkpoints[index] = (
        row: shifted(checkpoint.row),
        path: checkpoint.path,
        resumePath: checkpoint.resumePath,
        shape: checkpoint.shape?.removingRows(checkpoint.row, removed),
      );
    }
    for (final entry in viewports.entries.toList()) {
      viewports[entry.key] = (
        first: shifted(entry.value.first),
        last:
            entry.value.last -
            removed.where((old) => old <= entry.value.last).length,
      );
    }
    return totalRows - removed.length;
  }

  int prepend(List<int> ids, int totalRows, int maximum) {
    final arrived = ids.toSet();
    final removed = [
      for (final entry in rows.entries)
        if (arrived.contains(entry.value)) entry.key,
    ];
    int shifted(int row) =>
        row + ids.length - removed.where((old) => old < row).length;
    final oldRows = rows.entries.toList();
    rows.clear();
    for (final entry in oldRows) {
      if (!arrived.contains(entry.value)) {
        rows[shifted(entry.key)] = entry.value;
      }
    }
    for (var i = 0; i < checkpoints.length; i++) {
      final checkpoint = checkpoints[i];
      checkpoints[i] = (
        row: shifted(checkpoint.row),
        path: checkpoint.path,
        resumePath: checkpoint.resumePath,
        shape: checkpoint.shape?.removingRows(checkpoint.row, removed.toSet()),
      );
    }
    for (final entry in viewports.entries.toList()) {
      viewports[entry.key] = (
        first: shifted(entry.value.first),
        last:
            entry.value.last +
            ids.length -
            removed.where((old) => old <= entry.value.last).length,
      );
    }
    put(0, ids, maximum);
    return totalRows + ids.length - removed.length;
  }

  TopicFeed publish(TopicFeed feed, {int? totalRows}) {
    final entries = rows.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return feed.copyWith(
      topicIds: [for (final entry in entries) entry.value],
      topicRows: [for (final entry in entries) entry.key],
      totalRows: totalRows ?? feed.totalRows ?? feed.rowCount,
    );
  }
}

final class _RangeRequest {
  final completion = Completer<void>();
  final List<_RowRange> pending = [];

  void add(int first, int last) {
    for (var i = 0; i < pending.length; i++) {
      final held = pending[i];
      if (first <= held.last + 1 && last >= held.first - 1) {
        pending[i] = (
          first: first < held.first ? first : held.first,
          last: last > held.last ? last : held.last,
        );
        return;
      }
    }
    pending.add((first: first, last: last));
  }
}

final class _TopicRequest {
  _TopicRequest(this.topicId);

  final int topicId;
  final completion = Completer<Topic?>();
}

final class TopicFeedController extends FrameSafeNotifier {
  TopicFeedController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.store,
    this.onFeedLoaded,
    this.prepareFeed,
    this.readPersonalizationVersion,
    this.prepareTopicForStore,
    this.incomingFilterFor,
    this.readerTopics,
    this.maximumRetainedTopics = 300,
    this.maximumCursorCheckpoints = 32,
    this.maximumDestinations = 32,
  }) : assert(maximumRetainedTopics > 0),
       assert(maximumCursorCheckpoints > 0),
       assert(maximumDestinations > 0);

  static const int incomingPageSize = 30;

  final TopicFeedsApi api;
  final int maximumRetainedTopics;
  final int maximumCursorCheckpoints;
  final int maximumDestinations;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final Store store;
  final TopicFeedLoaded? onFeedLoaded;
  final TopicFeedPreparation? prepareFeed;
  final int Function(String siteUrl)? readPersonalizationVersion;
  final Topic Function(String siteUrl, Topic incoming, int? versionAtDispatch)?
  prepareTopicForStore;

  /// Which arrivals a list announces, read from its path and the response
  /// that loaded it, as core's `trackIncoming` runs once a list is found.
  final TopicFeedIncomingFilter? incomingFilterFor;
  final Set<int> Function(String siteUrl, String destinationId)? readerTopics;

  final Map<_FeedKey, TopicFeed> _feeds = {};
  final Map<String, String> _filterQueries = {};
  final Map<_FeedKey, Object> _revisions = {};
  final Map<_FeedKey, Completer<void>> _pageRequests = {};
  final Map<_FeedKey, int> _rows = {};
  final Map<_FeedKey, Future<void>> _loadRequests = {};
  final Map<_FeedKey, _FeedLoad> _pendingLoads = {};
  final Map<_FeedKey, Completer<void>> _pendingLoadWaiters = {};
  final Map<_FeedKey, IncomingTopicsFilter> _incomingFilters = {};
  final Map<_FeedKey, _FeedWindow> _windows = {};
  final Map<_FeedKey, _RangeRequest> _rangeRequests = {};
  final Map<_FeedKey, _TopicRequest> _topicRequests = {};
  final Map<_FeedKey, Set<Object>> _incomingRequests = {};

  TopicFeed? feedFor(String siteUrl, String destinationId) {
    final key = (siteUrl, destinationId);
    if (_windows.containsKey(key)) _window(key);
    return _feeds[key];
  }

  VoidCallback retainFeed(
    String siteUrl,
    String destinationId, {
    Object? owner,
  }) {
    if (isDisposed) return () {};
    final key = (siteUrl, destinationId);
    final token = owner ?? Object();
    final window = _window(key);
    window.owners.update(token, (count) => count + 1, ifAbsent: () => 1);
    _pruneDestinations();
    var released = false;
    return () {
      if (released) return;
      released = true;
      final count = window.owners[token];
      if (count == null) return;
      if (count > 1) {
        window.owners[token] = count - 1;
      } else {
        window.owners.remove(token);
        window.viewports.remove(token);
      }
      final before = window.rows.length;
      window.trim(maximumRetainedTopics);
      final feed = _feeds[key];
      if (identical(_windows[key], window) &&
          feed != null &&
          window.rows.length != before) {
        _feeds[key] = window.publish(feed);
        if (!isDisposed) notifySafely();
      }
      _pruneDestinations();
    };
  }

  void updateViewport(
    String siteUrl,
    String destinationId, {
    required Object owner,
    required int firstRow,
    required int lastRow,
  }) {
    if (isDisposed) return;
    final key = (siteUrl, destinationId);
    final window = _windows[key];
    if (window == null || !window.owners.containsKey(owner)) return;
    window.viewports[owner] = (first: firstRow, last: lastRow);
    for (final row in window.rows.keys.toList()) {
      if (row >= firstRow && row <= lastRow) window.touch(row);
    }
    final before = window.rows.length;
    window.trim(maximumRetainedTopics);
    final feed = _feeds[key];
    _window(key);
    if (feed != null && window.rows.length != before) {
      _feeds[key] = window.publish(feed);
      notifySafely();
    }
  }

  _FeedWindow _window(_FeedKey key) {
    final window =
        _windows.remove(key) ??
        _FeedWindow(
          readerTopics: () => readerTopics?.call(key.$1, key.$2) ?? {},
        );
    _windows[key] = window;
    return window;
  }

  void _pruneDestinations() {
    while (_windows.length > maximumDestinations) {
      final candidates = _windows.entries.where(
        (entry) =>
            entry.value.owners.isEmpty &&
            (entry.value.readerTopics?.call().isEmpty ?? true) &&
            !_loadRequests.containsKey(entry.key) &&
            !_pageRequests.containsKey(entry.key) &&
            !_rangeRequests.containsKey(entry.key) &&
            !_topicRequests.containsKey(entry.key) &&
            !_incomingRequests.containsKey(entry.key),
      );
      if (candidates.isEmpty) return;
      final key = candidates.first.key;
      _windows.remove(key);
      _feeds.remove(key);
      _revisions.remove(key);
      _rows.remove(key);
      _incomingFilters.remove(key);
      _pendingLoads.remove(key);
      final waiter = _pendingLoadWaiters.remove(key);
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
  }

  /// The filter of every list loaded on [siteUrl] that announces arrivals,
  /// by destination, oldest load first.
  Map<String, IncomingTopicsFilter> incomingFiltersFor(String siteUrl) => {
    for (final MapEntry(key: (site, destinationId), :value)
        in _incomingFilters.entries)
      if (site == siteUrl) destinationId: value,
  };

  String filterQueryFor(String siteUrl) => _filterQueries[siteUrl] ?? '';

  void setFilterQuery(String siteUrl, String query) {
    _filterQueries[siteUrl] = query;
    _rows.remove((siteUrl, 'filter'));
  }

  int scrollRowFor(String siteUrl, String destinationId) =>
      _rows[(siteUrl, destinationId)] ?? 0;

  void saveScrollRow(String siteUrl, String destinationId, int row) {
    if (isDisposed) return;
    final key = (siteUrl, destinationId);
    _rows[key] = row;
    _window(key);
    _pruneDestinations();
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
    _window(key);
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
        (existing.loading ||
            (existing.loaded &&
                existing.error == null &&
                existing.topicIds.every(
                  (id) => store.containsRecord<Topic>(instance.url, id),
                )))) {
      return Future.value();
    }

    return _startLoad(key, load);
  }

  Future<void> _startLoad(_FeedKey key, _FeedLoad load) {
    final completion = Completer<void>();
    final request = completion.future;
    // Loading notifications can synchronously retry or forget this feed.
    // Publish ownership before the worker exposes its loading state.
    _loadRequests[key] = request;
    _pruneDestinations();
    completion.complete(
      _performLoad(key, load).whenComplete(() => _finishLoad(key, request)),
    );
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
    _cancelPageRequest(key);
    _cancelRangeRequest(key);
    _cancelTopicRequest(key);

    final announced = incoming?.topicIds(destinationId) ?? const <int>[];
    incoming?.reset(destinationId);
    _feeds[key] = (existing ?? const TopicFeed()).refreshing();
    notifySafely();

    bool requestIsCurrent() =>
        !isDisposed && lease.isCurrent && identical(_revisions[key], revision);

    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!requestIsCurrent()) return;
      final list = await auth.run(
        () => api.topicList(siteUrl: instance.url, path: path, apiKey: apiKey),
      );
      if (!requestIsCurrent()) return;
      await prepareFeed?.call(
        instance,
        apiKey,
        list.categories,
        _categoryIds(list.topics),
      );
      _commit(lease, () {
        if (!identical(_revisions[key], revision)) return;
        if (!_putTopics(
          instance.url,
          list.topics,
          personalizationVersion,
          requestIsCurrent,
        )) {
          return;
        }
        final window = _window(key);
        window.rootPath = path;
        window.pagesWithoutRows = 0;
        window.rows.clear();
        window.checkpoints.clear();
        final rawIds = list.topics.map((topic) => topic.id).toList();
        final shape = _PageShape(rawIds, {});
        final ids = shape.resolve(rawIds);
        window.put(0, ids, maximumRetainedTopics);
        window.remember(0, path, maximumCursorCheckpoints, shape: shape);
        if (list.nextPagePath case final nextPath?) {
          window.remember(ids.length, nextPath, maximumCursorCheckpoints);
        }
        _feeds[key] = window.publish(TopicFeed.of(list), totalRows: ids.length);
        // Core's `trackIncoming` starts counting once the list is found, so
        // an arrival the answer already lists is not announced over it. One
        // that arrived while the request was out and that the answer missed
        // stays announced rather than being dropped.
        incoming?.clear(destinationId, [
          for (final topic in list.topics) topic.id,
        ]);
        _rows.remove(key);
        _incomingFilters.remove(key);
        if (incomingFilterFor?.call(path, list) case final filter?) {
          _incomingFilters[key] = filter;
        }
        notifySafely();
        // Publishing can synchronously replace the account or forget the feed.
        // Its completion hook must retain the same owner as the response.
        if (requestIsCurrent()) {
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
              ? appL10n.notAllowedTryReconnectingTo((instance.host).toString())
              : appL10n.couldnTReach((instance.host).toString()),
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
        _feeds[key] = held.withError(
          appL10n.couldnTLoadTopicfeedcontroller((instance.host).toString()),
        );
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
      _pruneDestinations();
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
    final incomingRequest = Object();
    (_incomingRequests[key] ??= {}).add(incomingRequest);
    _window(key);

    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_revisions[key], feedRevision);

    _feeds[key] = feed.copyWith(loadingIncoming: true);
    notifySafely();

    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!requestIsCurrent()) return;
      // The list's own query — its category, tags, subset or order — still
      // applies, as core's `loadBefore` sends the list's params along.
      final list = await auth.run(
        () => api.topicList(
          siteUrl: instance.url,
          path: _topicIdsPath(path, ids),
          apiKey: apiKey,
        ),
      );
      if (!requestIsCurrent()) return;
      await prepareFeed?.call(
        instance,
        apiKey,
        list.categories,
        _categoryIds(list.topics),
      );

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        if (!_putTopics(
          instance.url,
          list.topics,
          personalizationVersion,
          requestIsCurrent,
        )) {
          return;
        }
        final held = _feeds[key] ?? feed;
        final arrived = list.topics.map((topic) => topic.id).toSet().toList();
        final window = _window(key);
        final previousRoot = window.checkpoints.where(
          (checkpoint) => checkpoint.row == 0,
        );
        final resumePath = previousRoot.isEmpty
            ? window.rootPath
            : previousRoot.last.path;
        _cancelRangeRequest(key);
        final totalRows = window.prepend(
          arrived,
          held.rowCount,
          maximumRetainedTopics,
        );
        if (arrived.isNotEmpty) {
          window.remember(
            0,
            _topicIdsPath(path, ids),
            maximumCursorCheckpoints,
            resumePath: resumePath,
            shape: _PageShape(
              list.topics.map((topic) => topic.id).toList(),
              {},
            ),
          );
        }
        _feeds[key] = window.publish(
          held.copyWith(loadingIncoming: false),
          totalRows: totalRows,
        );
        incoming.clear(destinationId, ids);
        _rows[key] = 0;
        notifySafely();
        if (requestIsCurrent()) {
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
    } finally {
      final requests = _incomingRequests[key];
      requests?.remove(incomingRequest);
      if (requests?.isEmpty == true) _incomingRequests.remove(key);
      _pruneDestinations();
    }
  }

  Future<void> loadMore({
    required DiscourseInstance instance,
    required String destinationId,
  }) async {
    if (isDisposed) return;
    final key = (instance.url, destinationId);
    if (_pageRequests[key] case final pending?) {
      await pending.future;
      return;
    }
    if (_rangeRequests[key] case final range?) {
      final lease = lifecycle.capture(instance.url);
      final revision = _revisions[key];
      await range.completion.future;
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_revisions[key], revision)) {
        return;
      }
      return loadMore(instance: instance, destinationId: destinationId);
    }
    final feed = _feeds[key];
    if (feed == null || feed.loading || feed.loadingMore || !feed.hasMore) {
      return;
    }
    if (feed.error != null && !feed.pageError) return;

    final lease = lifecycle.capture(instance.url);
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    final feedRevision = _revisions[key];
    final pageRequest = Completer<void>();
    _pageRequests[key] = pageRequest;
    _window(key);

    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_revisions[key], feedRevision) &&
        identical(_pageRequests[key], pageRequest);

    _feeds[key] = feed.loadingNextPage();
    notifySafely();

    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!requestIsCurrent()) return;
      final next = await auth.run(
        () => api.topicList(
          siteUrl: instance.url,
          path: feed.nextPagePath!,
          apiKey: apiKey,
        ),
      );
      if (!requestIsCurrent()) return;
      await prepareFeed?.call(
        instance,
        apiKey,
        next.categories,
        _categoryIds(next.topics),
      );

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        if (!_putTopics(
          instance.url,
          next.topics,
          personalizationVersion,
          requestIsCurrent,
        )) {
          return;
        }
        final held = _feeds[key];
        if (held == null) return;
        final window = _window(key);
        final rawIds = next.topics.map((topic) => topic.id).toList();
        final shape = _PageShape(rawIds, held.topicIds.toSet());
        final fresh = shape.resolve(rawIds);
        final start = held.rowCount;
        final repeatsCursor = window.checkpoints.any(
          (checkpoint) => checkpoint.path == next.nextPagePath,
        );
        window.pagesWithoutRows = fresh.isEmpty
            ? window.pagesWithoutRows + 1
            : 0;
        window.remember(
          start,
          feed.nextPagePath!,
          maximumCursorCheckpoints,
          shape: shape,
        );
        window.put(start, fresh, maximumRetainedTopics);
        final nextPath = next.nextPagePath;
        if (!repeatsCursor && nextPath != null) {
          window.remember(
            start + fresh.length,
            nextPath,
            maximumCursorCheckpoints,
          );
        }
        _feeds[key] = window.publish(
          held.copyWith(
            loadingMore: false,
            nextPagePath: next.nextPagePath,
            clearNextPage:
                next.nextPagePath == null ||
                repeatsCursor ||
                window.pagesWithoutRows >= maximumCursorCheckpoints,
            clearError: true,
          ),
          totalRows: start + fresh.length,
        );
        if (requestIsCurrent()) {
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
            appL10n.couldnTLoadMoreTopicsFrom((instance.host).toString()),
            page: true,
          );
        }
      });
    } finally {
      if (identical(_pageRequests[key], pageRequest)) {
        _pageRequests.remove(key);
        if (!isDisposed && lease.isCurrent) notifySafely();
      }
      if (!pageRequest.isCompleted) pageRequest.complete();
      _pruneDestinations();
    }
  }

  Future<void> ensureRange({
    required DiscourseInstance instance,
    required String destinationId,
    required int firstRow,
    required int lastRow,
  }) {
    if (isDisposed) return Future.value();
    final key = (instance.url, destinationId);
    final feed = _feeds[key];
    final window = _windows[key];
    if (feed == null || window?.rootPath == null || feed.loading) {
      return Future.value();
    }
    final first = firstRow < 0 ? 0 : firstRow;
    final last = lastRow >= feed.rowCount ? feed.rowCount - 1 : lastRow;
    if (first > last) return Future.value();
    _window(key);
    for (final row in window!.rows.keys.toList()) {
      if (row >= first && row <= last) window.touch(row);
    }
    if (_rangeRequests[key] case final request?) {
      if (request.pending.length >= maximumCursorCheckpoints) {
        request.pending.removeAt(0);
      }
      request.add(first, last);
      return request.completion.future;
    }
    if (_rangeIsBacked(instance.url, window, first, last)) {
      return Future.value();
    }
    final request = _RangeRequest()..add(first, last);
    _rangeRequests[key] = request;
    unawaited(_performRanges(key, instance, window, request));
    return request.completion.future;
  }

  Future<Topic?> restoreTopic({
    required DiscourseInstance instance,
    required String destinationId,
    required int topicId,
  }) {
    if (isDisposed) return Future.value();
    final key = (instance.url, destinationId);
    final path = _windows[key]?.rootPath;
    if (path == null) return Future.value();
    final active = _topicRequests[key];
    if (active?.topicId == topicId) return active!.completion.future;
    _cancelTopicRequest(key);
    final request = _TopicRequest(topicId);
    _topicRequests[key] = request;
    _window(key);
    unawaited(_performTopicRestore(key, instance, request));
    return request.completion.future;
  }

  Future<void> _performTopicRestore(
    _FeedKey key,
    DiscourseInstance instance,
    _TopicRequest request,
  ) async {
    final lease = lifecycle.capture(instance.url);
    final revision = _revisions[key];
    final version = readPersonalizationVersion?.call(instance.url);
    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_revisions[key], revision) &&
        identical(_topicRequests[key], request);
    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!requestIsCurrent()) return;
      final topic = await auth.run(
        () => api.topicSummary(
          siteUrl: instance.url,
          id: request.topicId,
          apiKey: apiKey,
        ),
      );
      if (!requestIsCurrent()) return;
      await prepareFeed?.call(
        instance,
        apiKey,
        const [],
        _categoryIds([topic]),
      );
      if (!requestIsCurrent()) return;
      _commit(lease, () {
        if (!requestIsCurrent()) return;
        if (!_putTopics(instance.url, [topic], version, requestIsCurrent)) {
          return;
        }
        if (!request.completion.isCompleted) {
          request.completion.complete(
            store.read<Topic>(instance.url, request.topicId),
          );
        }
      });
    } catch (error, stackTrace) {
      if (requestIsCurrent()) {
        _report(
          error,
          stackTrace,
          'topics.restoreSelection',
          severity: DiagnosticSeverity.warning,
        );
      }
    } finally {
      if (identical(_topicRequests[key], request)) {
        _topicRequests.remove(key);
      }
      if (!request.completion.isCompleted) request.completion.complete();
      _pruneDestinations();
    }
  }

  void _cancelTopicRequest(_FeedKey key) {
    final request = _topicRequests.remove(key);
    if (request != null && !request.completion.isCompleted) {
      request.completion.complete();
    }
  }

  bool _rangeIsBacked(String siteUrl, _FeedWindow window, int first, int last) {
    for (var row = first; row <= last; row++) {
      final id = window.rows[row];
      if (id == null || !store.containsRecord<Topic>(siteUrl, id)) return false;
    }
    return true;
  }

  Future<void> _performRanges(
    _FeedKey key,
    DiscourseInstance instance,
    _FeedWindow window,
    _RangeRequest request,
  ) async {
    final lease = lifecycle.capture(instance.url);
    final revision = _revisions[key];
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    bool requestIsCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_revisions[key], revision) &&
        identical(_rangeRequests[key], request);

    try {
      if (_pageRequests[key] case final page?) {
        await page.future;
      }
      if (!requestIsCurrent()) return;
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).keyCredentials(credentials);
      final apiKey = auth.apiKey;
      if (!requestIsCurrent()) return;
      while (request.pending.isNotEmpty) {
        final range = request.pending.removeAt(0);
        if (_rangeIsBacked(instance.url, window, range.first, range.last)) {
          continue;
        }
        final missingIds = [
          for (final entry in window.rows.entries)
            if (entry.key >= range.first &&
                entry.key <= range.last &&
                !store.containsRecord<Topic>(instance.url, entry.value))
              entry.value,
        ];
        if (missingIds.isNotEmpty) {
          final topics = <Topic>[];
          for (final id in missingIds) {
            final topic = await auth.run(
              () => api.topicSummary(
                siteUrl: instance.url,
                id: id,
                apiKey: apiKey,
              ),
            );
            if (!requestIsCurrent()) return;
            topics.add(topic);
          }
          await prepareFeed?.call(
            instance,
            apiKey,
            const [],
            _categoryIds(topics),
          );
          if (!requestIsCurrent()) return;
          _commit(lease, () {
            if (!requestIsCurrent()) return;
            _putTopics(
              instance.url,
              topics,
              personalizationVersion,
              requestIsCurrent,
            );
          });
          if (!requestIsCurrent()) return;
          if (missingIds.any(
            (id) => !store.containsRecord<Topic>(instance.url, id),
          )) {
            throw StateError('The requested topics are no longer available.');
          }
        }

        int? firstMissing;
        for (var row = range.first; row <= range.last; row++) {
          if (!window.rows.containsKey(row)) {
            firstMissing = row;
            break;
          }
        }
        if (firstMissing != null) {
          _CursorCheckpoint checkpoint = (
            row: 0,
            path: window.rootPath!,
            resumePath: null,
            shape: null,
          );
          for (final candidate in window.checkpoints) {
            if (candidate.row <= firstMissing &&
                candidate.row >= checkpoint.row) {
              checkpoint = candidate;
            }
          }
          var start = checkpoint.row;
          String? path = checkpoint.path;
          var resumePath = checkpoint.resumePath;
          var pageShape = checkpoint.shape;
          final Set<String> visited = {};
          var pagesWithoutRows = 0;
          while (start <= range.last) {
            if (path == null || !visited.add(path)) {
              throw StateError(
                'The requested topic range is no longer available.',
              );
            }
            if (visited.length > maximumCursorCheckpoints) {
              visited.remove(visited.first);
            }
            final requestPath = path;
            final list = await auth.run(
              () => api.topicList(
                siteUrl: instance.url,
                path: requestPath,
                apiKey: apiKey,
              ),
            );
            if (!requestIsCurrent()) return;
            await prepareFeed?.call(
              instance,
              apiKey,
              list.categories,
              _categoryIds(list.topics),
            );
            if (!requestIsCurrent()) return;
            final earlier = {
              for (final entry in window.rows.entries)
                if (entry.key < start) entry.value,
            };
            final rawIds = list.topics.map((topic) => topic.id).toList();
            var shape = pageShape ?? _PageShape(rawIds, {...earlier});
            var ids = shape.resolve(rawIds);
            final duplicateRows = <int>{
              for (var index = 0; index < ids.length; index++)
                if (earlier.contains(ids[index])) start + index,
            };
            if (duplicateRows.isNotEmpty) {
              final held = _feeds[key];
              if (held == null) return;
              final count = window.removeSourceRows(
                duplicateRows,
                held.rowCount,
              );
              shape = shape.removingRows(start, duplicateRows);
              ids = shape.resolve(rawIds);
              _feeds[key] = window.publish(held, totalRows: count);
            }
            final nextPath = resumePath ?? list.nextPagePath;
            _commit(lease, () {
              if (!requestIsCurrent()) return;
              if (!_putTopics(
                instance.url,
                list.topics,
                personalizationVersion,
                requestIsCurrent,
              )) {
                return;
              }
              final held = _feeds[key];
              if (held == null) return;
              window.remember(
                start,
                path!,
                maximumCursorCheckpoints,
                resumePath: resumePath,
                shape: shape,
              );
              window.put(
                start,
                ids.take(held.rowCount - start),
                maximumRetainedTopics,
                restoring: true,
                preferredRange: range,
              );
              if (nextPath case final next?) {
                window.remember(
                  start + ids.length,
                  next,
                  maximumCursorCheckpoints,
                );
              }
              final end = start + ids.length;
              if (nextPath == null && end <= held.rowCount) {
                window.truncate(end);
                _feeds[key] = window.publish(
                  held.copyWith(clearNextPage: true),
                  totalRows: end,
                );
              } else {
                _feeds[key] = window.publish(held);
              }
              notifySafely();
              if (requestIsCurrent()) {
                onFeedLoaded?.call(
                  instance,
                  apiKey,
                  list.categories,
                  _categoryIds(list.topics),
                );
              }
            });
            if (!requestIsCurrent()) return;
            if (ids.isEmpty) {
              if (++pagesWithoutRows >= maximumCursorCheckpoints) {
                throw StateError('Pagination did not advance the topic range.');
              }
            } else {
              pagesWithoutRows = 0;
            }
            start += ids.length;
            path = nextPath;
            resumePath = null;
            pageShape = null;
            for (final candidate in window.checkpoints) {
              if (candidate.path == path) {
                resumePath = candidate.resumePath;
                pageShape = candidate.shape;
              }
            }
            if (path == null) break;
          }
        }
        if (!requestIsCurrent()) return;
        final last = (_feeds[key]?.rowCount ?? 0) - 1;
        if (!_rangeIsBacked(
          instance.url,
          window,
          range.first,
          range.last < last ? range.last : last,
        )) {
          throw StateError('The requested topic range could not be restored.');
        }
        final held = _feeds[key];
        if (held != null) {
          _feeds[key] = window.publish(held.copyWith(clearError: true));
        }
      }
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _report(
        error,
        stackTrace,
        'topics.restoreRange',
        severity: DiagnosticSeverity.warning,
      );
      _commit(lease, () {
        if (!requestIsCurrent()) return;
        final held = _feeds[key];
        if (held == null) return;
        _feeds[key] = held.withError(
          appL10n.couldnTLoadMoreTopicsFrom((instance.host).toString()),
          page: true,
        );
      });
    } finally {
      if (identical(_rangeRequests[key], request)) {
        _rangeRequests.remove(key);
        if (!isDisposed && lease.isCurrent) notifySafely();
      }
      if (!request.completion.isCompleted) request.completion.complete();
      _pruneDestinations();
    }
  }

  String _topicIdsPath(String path, Iterable<int> ids) {
    final separator = path.contains('?') ? '&' : '?';
    return '$path${separator}topic_ids=${ids.join(',')}';
  }

  void _cancelRangeRequest(_FeedKey key) {
    final request = _rangeRequests.remove(key);
    if (request != null && !request.completion.isCompleted) {
      request.completion.complete();
    }
  }

  void _cancelPageRequest(_FeedKey key) {
    final pending = _pageRequests.remove(key);
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void forget(String siteUrl) {
    final before = _feeds.length;
    _feeds.removeWhere((key, _) => key.$1 == siteUrl);
    _filterQueries.remove(siteUrl);
    _revisions.removeWhere((key, _) => key.$1 == siteUrl);
    for (final key in _pageRequests.keys.toList()) {
      if (key.$1 == siteUrl) _cancelPageRequest(key);
    }
    for (final key in _rangeRequests.keys.toList()) {
      if (key.$1 == siteUrl) _cancelRangeRequest(key);
    }
    for (final key in _topicRequests.keys.toList()) {
      if (key.$1 == siteUrl) _cancelTopicRequest(key);
    }
    _windows.removeWhere((key, _) => key.$1 == siteUrl);
    _incomingRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _rows.removeWhere((key, _) => key.$1 == siteUrl);
    _incomingFilters.removeWhere((key, _) => key.$1 == siteUrl);
    _loadRequests.removeWhere((key, _) => key.$1 == siteUrl);
    _pendingLoads.removeWhere((key, _) => key.$1 == siteUrl);
    for (final entry in _pendingLoadWaiters.entries.toList()) {
      if (entry.key.$1 != siteUrl) continue;
      _pendingLoadWaiters.remove(entry.key);
      if (!entry.value.isCompleted) entry.value.complete();
    }
    if (_feeds.length != before) notifySafely();
  }

  bool _putTopics(
    String siteUrl,
    Iterable<Topic> topics,
    int? versionAtDispatch,
    bool Function() requestIsCurrent,
  ) {
    final prepare = prepareTopicForStore;
    for (final topic in topics) {
      if (!requestIsCurrent()) return false;
      final incoming =
          prepare?.call(siteUrl, topic, versionAtDispatch) ?? topic;
      if (!requestIsCurrent()) return false;
      // Record refs notify independently of the feed. An observer may forget
      // the site, in which case the remaining rows must not repopulate it.
      store.put(siteUrl, incoming);
    }
    return requestIsCurrent();
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
    for (final key in _pageRequests.keys.toList()) {
      _cancelPageRequest(key);
    }
    for (final key in _rangeRequests.keys.toList()) {
      _cancelRangeRequest(key);
    }
    for (final key in _topicRequests.keys.toList()) {
      _cancelTopicRequest(key);
    }
    _feeds.clear();
    _windows.clear();
    _rows.clear();
    _incomingFilters.clear();
    _incomingRequests.clear();
    _filterQueries.clear();
    super.dispose();
  }
}
