import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';

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
      bool Function() isCurrent,
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
    final incoming = ids.toList();
    final destinations = <int, int>{};
    final duplicateIds = <int>{};
    var row = start;
    for (final id in incoming) {
      if (restoring && destinations.containsKey(id)) duplicateIds.add(id);
      destinations[id] = row++;
    }
    if (restoring && incoming.isNotEmpty) {
      final readers = readerTopics?.call() ?? const <int>{};
      for (final entry in rows.entries) {
        if (!protects(entry.key, readers: readers)) continue;
        final destination = destinations[entry.value];
        final incomingOffset = entry.key - start;
        if ((destination != null &&
                (destination != entry.key ||
                    duplicateIds.contains(entry.value))) ||
            (incomingOffset >= 0 &&
                incomingOffset < incoming.length &&
                incoming[incomingOffset] != entry.value)) {
          throw StateError(
            'The topic page moved visible rows. Refresh the list.',
          );
        }
      }
    }
    if (incoming.isNotEmpty) {
      rows.removeWhere((_, id) => destinations.containsKey(id));
      row = start;
      for (final id in incoming) {
        rows.remove(row);
        if (destinations[id] == row) rows[row] = id;
        row++;
      }
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

final class _FeedReplay {
  _FeedReplay(this.load);

  _FeedLoad load;
  final completion = Completer<void>();
}

final class _FeedSession {
  _FeedSession(this.key, this.window);

  final _FeedKey key;
  final _FeedWindow window;
  TopicFeed? feed;
  Object? revision;
  int? scrollRow;
  ({IncomingTopicsFilter filter, int order})? incomingFilter;
  Future<void>? loadRequest;
  _FeedReplay? replay;
  Completer<void>? pageRequest;
  _RangeRequest? rangeRequest;
  _TopicRequest? topicRequest;
  final Set<Object> incomingRequests = {};
  bool retired = false;

  bool get hasRequests =>
      loadRequest != null ||
      replay != null ||
      pageRequest != null ||
      rangeRequest != null ||
      topicRequest != null ||
      incomingRequests.isNotEmpty;

  Future<void> queueReplay(_FeedLoad load) {
    final pending = replay ??= _FeedReplay(load);
    pending.load = load;
    return pending.completion.future;
  }

  void cancelPage() {
    final request = pageRequest;
    pageRequest = null;
    if (request != null && !request.isCompleted) request.complete();
  }

  void cancelRange() {
    final request = rangeRequest;
    rangeRequest = null;
    if (request != null && !request.completion.isCompleted) {
      request.completion.complete();
    }
  }

  void cancelTopic() {
    final request = topicRequest;
    topicRequest = null;
    if (request != null && !request.completion.isCompleted) {
      request.completion.complete();
    }
  }

  void cancelPaging() {
    cancelPage();
    cancelRange();
    cancelTopic();
  }

  void retire() {
    if (retired) return;
    retired = true;
    revision = null;
    loadRequest = null;
    final pending = replay;
    replay = null;
    if (pending != null && !pending.completion.isCompleted) {
      pending.completion.complete();
    }
    cancelPaging();
    incomingRequests.clear();
    feed = null;
    scrollRow = null;
    incomingFilter = null;
    window.owners.clear();
    window.viewports.clear();
    window.rows.clear();
    window.checkpoints.clear();
    window.rootPath = null;
  }
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

  final Map<_FeedKey, _FeedSession> _sessions = {};
  final Map<String, String> _filterQueries = {};
  int _incomingFilterOrder = 0;

  TopicFeed? feedFor(String siteUrl, String destinationId) {
    final session = _sessions[(siteUrl, destinationId)];
    if (session != null) _touchSession(session);
    return session?.feed;
  }

  VoidCallback retainFeed(
    String siteUrl,
    String destinationId, {
    Object? owner,
  }) {
    if (isDisposed) return () {};
    final session = _session((siteUrl, destinationId));
    final token = owner ?? Object();
    final window = session.window;
    window.owners.update(token, (count) => count + 1, ifAbsent: () => 1);
    _pruneDestinations();
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (!identical(_sessions[session.key], session)) return;
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
      final feed = session.feed;
      if (feed != null && window.rows.length != before) {
        session.feed = window.publish(feed);
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
    final session = _sessions[(siteUrl, destinationId)];
    if (session == null || !session.window.owners.containsKey(owner)) return;
    final window = session.window;
    window.viewports[owner] = (first: firstRow, last: lastRow);
    for (final row in window.rows.keys.toList()) {
      if (row >= firstRow && row <= lastRow) window.touch(row);
    }
    final before = window.rows.length;
    window.trim(maximumRetainedTopics);
    final feed = session.feed;
    _touchSession(session);
    if (feed != null && window.rows.length != before) {
      session.feed = window.publish(feed);
      notifySafely();
    }
  }

  _FeedSession _session(_FeedKey key) {
    final session =
        _sessions.remove(key) ??
        _FeedSession(
          key,
          _FeedWindow(
            readerTopics: () => readerTopics?.call(key.$1, key.$2) ?? {},
          ),
        );
    _sessions[key] = session;
    return session;
  }

  bool _sessionIsCurrent(_FeedSession session, Object? revision) =>
      !isDisposed &&
      identical(_sessions[session.key], session) &&
      identical(session.revision, revision);

  void _touchSession(_FeedSession session) {
    if (!identical(_sessions[session.key], session)) return;
    _sessions.remove(session.key);
    _sessions[session.key] = session;
  }

  void _retireSession(_FeedSession session) {
    if (identical(_sessions[session.key], session)) {
      _sessions.remove(session.key);
    }
    session.retire();
  }

  void _pruneDestinations() {
    while (_sessions.length > maximumDestinations) {
      final candidates = _sessions.values.where(
        (session) =>
            session.window.owners.isEmpty &&
            (session.window.readerTopics?.call().isEmpty ?? true) &&
            !session.hasRequests,
      );
      if (candidates.isEmpty) return;
      _retireSession(candidates.first);
    }
  }

  /// The filter of every list loaded on [siteUrl] that announces arrivals,
  /// by destination, oldest load first.
  Map<String, IncomingTopicsFilter> incomingFiltersFor(String siteUrl) {
    final sessions =
        _sessions.values
            .where(
              (session) =>
                  session.key.$1 == siteUrl && session.incomingFilter != null,
            )
            .toList()
          ..sort(
            (a, b) =>
                a.incomingFilter!.order.compareTo(b.incomingFilter!.order),
          );
    return {
      for (final session in sessions)
        session.key.$2: session.incomingFilter!.filter,
    };
  }

  String filterQueryFor(String siteUrl) => _filterQueries[siteUrl] ?? '';

  void setFilterQuery(String siteUrl, String query) {
    _filterQueries[siteUrl] = query;
    _sessions[(siteUrl, 'filter')]?.scrollRow = null;
  }

  int scrollRowFor(String siteUrl, String destinationId) =>
      _sessions[(siteUrl, destinationId)]?.scrollRow ?? 0;

  void saveScrollRow(String siteUrl, String destinationId, int row) {
    if (isDisposed) return;
    final key = (siteUrl, destinationId);
    _session(key).scrollRow = row;
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
    final session = _session(key);
    final load = (
      instance: instance,
      destinationId: destinationId,
      path: path,
      incoming: incoming,
    );
    final active = session.loadRequest;
    if (active != null) {
      if (!force) return active;
      // A refresh means "give me data newer than the request already in
      // flight", not "send another request alongside it". Keep only the
      // newest path and let every repeated refresh await the same replay.
      return session.queueReplay(load);
    }

    final existing = session.feed;
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

    return _startLoad(session, load);
  }

  Future<void> _startLoad(_FeedSession session, _FeedLoad load) {
    final completion = Completer<void>();
    final request = completion.future;
    // Loading notifications can synchronously retry or forget this feed.
    // Publish ownership before the worker exposes its loading state.
    session.loadRequest = request;
    _pruneDestinations();
    completion.complete(
      _performLoad(
        session,
        load,
      ).whenComplete(() => _finishLoad(session, request)),
    );
    return request;
  }

  Future<void> _performLoad(_FeedSession session, _FeedLoad load) async {
    final (:instance, :destinationId, :path, :incoming) = load;
    final existing = session.feed;

    final lease = lifecycle.capture(instance.url);
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    final revision = Object();
    session.revision = revision;
    session.cancelPaging();

    final announced = incoming?.topicIds(destinationId) ?? const <int>[];
    incoming?.reset(destinationId);
    session.feed = (existing ?? const TopicFeed()).refreshing();
    notifySafely();

    bool requestIsCurrent() =>
        lease.isCurrent && _sessionIsCurrent(session, revision);

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
        requestIsCurrent,
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
        _touchSession(session);
        final window = session.window;
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
        session.feed = window.publish(
          TopicFeed.of(list),
          totalRows: ids.length,
        );
        // Core's `trackIncoming` starts counting once the list is found, so
        // an arrival the answer already lists is not announced over it. One
        // that arrived while the request was out and that the answer missed
        // stays announced rather than being dropped.
        incoming?.clear(destinationId, [
          for (final topic in list.topics) topic.id,
        ]);
        session.scrollRow = null;
        session.incomingFilter = null;
        if (incomingFilterFor?.call(path, list) case final filter?) {
          session.incomingFilter = (
            filter: filter,
            order: _incomingFilterOrder++,
          );
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
    } on SiteLookupException catch (error) {
      if (!requestIsCurrent()) return;

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        incoming?.restore(destinationId, announced);
        final held = session.feed ?? existing ?? const TopicFeed();
        session.feed = held.withError(
          error.failure == SiteLookupFailure.notDiscourse
              ? appL10n.notAllowedTryReconnectingTo((instance.host).toString())
              : appL10n.couldnTReach((instance.host).toString()),
        );
        notifySafely();
      });
    } catch (error) {
      if (!requestIsCurrent()) return;

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        incoming?.restore(destinationId, announced);
        final held = session.feed ?? existing ?? const TopicFeed();
        session.feed = held.withError(
          appL10n.couldnTLoadTopicfeedcontroller((instance.host).toString()),
        );
        notifySafely();
      });
    }
  }

  void _finishLoad(_FeedSession session, Future<void> request) {
    if (!identical(_sessions[session.key], session) ||
        !identical(session.loadRequest, request)) {
      return;
    }
    session.loadRequest = null;

    final pending = session.replay;
    session.replay = null;
    if (pending == null || isDisposed) {
      if (pending != null && !pending.completion.isCompleted) {
        pending.completion.complete();
      }
      _pruneDestinations();
      return;
    }

    final replay = _startLoad(session, pending.load);
    unawaited(
      replay.then<void>(
        (_) {
          if (!pending.completion.isCompleted) pending.completion.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!pending.completion.isCompleted) {
            pending.completion.completeError(error, stackTrace);
          }
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
    final session = _sessions[key];
    if (session == null) return;
    final feed = session.feed;
    if (feed == null || feed.loadingIncoming) return;

    final ids = incoming.topicIds(destinationId, limit: incomingPageSize);
    if (ids.isEmpty) return;
    final lease = lifecycle.capture(instance.url);
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    final feedRevision = session.revision;
    final incomingRequest = Object();
    session.incomingRequests.add(incomingRequest);
    _touchSession(session);

    bool requestIsCurrent() =>
        lease.isCurrent && _sessionIsCurrent(session, feedRevision);

    session.feed = feed.copyWith(loadingIncoming: true);
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
        requestIsCurrent,
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
        final held = session.feed ?? feed;
        final arrived = list.topics.map((topic) => topic.id).toSet().toList();
        _touchSession(session);
        final window = session.window;
        final previousRoot = window.checkpoints.where(
          (checkpoint) => checkpoint.row == 0,
        );
        final resumePath = previousRoot.isEmpty
            ? window.rootPath
            : previousRoot.last.path;
        session.cancelRange();
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
        session.feed = window.publish(
          held.copyWith(loadingIncoming: false),
          totalRows: totalRows,
        );
        incoming.clear(destinationId, ids);
        session.scrollRow = 0;
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
    } catch (error) {
      if (!requestIsCurrent()) return;

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        session.feed = (session.feed ?? feed).copyWith(loadingIncoming: false);
        notifySafely();
      });
    } finally {
      session.incomingRequests.remove(incomingRequest);
      _pruneDestinations();
    }
  }

  Future<void> loadMore({
    required DiscourseInstance instance,
    required String destinationId,
  }) async {
    if (isDisposed) return;
    final key = (instance.url, destinationId);
    final session = _sessions[key];
    if (session == null) return;
    if (session.pageRequest case final pending?) {
      await pending.future;
      return;
    }
    if (session.rangeRequest case final range?) {
      final lease = lifecycle.capture(instance.url);
      final revision = session.revision;
      await range.completion.future;
      if (!lease.isCurrent || !_sessionIsCurrent(session, revision)) {
        return;
      }
      return loadMore(instance: instance, destinationId: destinationId);
    }
    final feed = session.feed;
    if (feed == null || feed.loading || feed.loadingMore || !feed.hasMore) {
      return;
    }
    if (feed.error != null && !feed.pageError) return;

    final lease = lifecycle.capture(instance.url);
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    final feedRevision = session.revision;
    final pageRequest = Completer<void>();
    session.pageRequest = pageRequest;
    _touchSession(session);

    bool feedIsCurrent() =>
        lease.isCurrent && _sessionIsCurrent(session, feedRevision);
    bool requestIsCurrent() =>
        feedIsCurrent() && identical(session.pageRequest, pageRequest);

    session.feed = feed.loadingNextPage();
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
        feedIsCurrent,
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
        final held = session.feed;
        if (held == null) return;
        _touchSession(session);
        final window = session.window;
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
        session.feed = window.publish(
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
    } catch (error) {
      if (!requestIsCurrent()) return;

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        final held = session.feed;
        if (held != null) {
          session.feed = held.withError(
            appL10n.couldnTLoadMoreTopicsFrom((instance.host).toString()),
            page: true,
          );
        }
      });
    } finally {
      if (identical(session.pageRequest, pageRequest)) {
        session.pageRequest = null;
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
    final session = _sessions[key];
    if (session == null) return Future.value();
    final feed = session.feed;
    final window = session.window;
    if (feed == null || window.rootPath == null || feed.loading) {
      return Future.value();
    }
    final first = firstRow < 0 ? 0 : firstRow;
    final last = lastRow >= feed.rowCount ? feed.rowCount - 1 : lastRow;
    if (first > last) return Future.value();
    _touchSession(session);
    for (final row in window.rows.keys.toList()) {
      if (row >= first && row <= last) window.touch(row);
    }
    if (session.rangeRequest case final request?) {
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
    session.rangeRequest = request;
    unawaited(_performRanges(session, instance, request));
    return request.completion.future;
  }

  Future<Topic?> restoreTopic({
    required DiscourseInstance instance,
    required String destinationId,
    required int topicId,
  }) {
    if (isDisposed) return Future.value();
    final key = (instance.url, destinationId);
    final session = _sessions[key];
    if (session == null) return Future.value();
    final path = session.window.rootPath;
    if (path == null) return Future.value();
    final active = session.topicRequest;
    if (active?.topicId == topicId) return active!.completion.future;
    session.cancelTopic();
    final request = _TopicRequest(topicId);
    session.topicRequest = request;
    _touchSession(session);
    unawaited(_performTopicRestore(session, instance, request));
    return request.completion.future;
  }

  Future<void> _performTopicRestore(
    _FeedSession session,
    DiscourseInstance instance,
    _TopicRequest request,
  ) async {
    final lease = lifecycle.capture(instance.url);
    final revision = session.revision;
    final version = readPersonalizationVersion?.call(instance.url);
    bool feedIsCurrent() =>
        lease.isCurrent && _sessionIsCurrent(session, revision);
    bool requestIsCurrent() =>
        feedIsCurrent() && identical(session.topicRequest, request);
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
        feedIsCurrent,
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
    } catch (_) {
    } finally {
      if (identical(session.topicRequest, request)) {
        session.topicRequest = null;
      }
      if (!request.completion.isCompleted) request.completion.complete();
      _pruneDestinations();
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
    _FeedSession session,
    DiscourseInstance instance,
    _RangeRequest request,
  ) async {
    final window = session.window;
    final lease = lifecycle.capture(instance.url);
    final revision = session.revision;
    final personalizationVersion = readPersonalizationVersion?.call(
      instance.url,
    );
    bool feedIsCurrent() =>
        lease.isCurrent && _sessionIsCurrent(session, revision);
    bool requestIsCurrent() =>
        feedIsCurrent() && identical(session.rangeRequest, request);

    try {
      if (session.pageRequest case final page?) {
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
            feedIsCurrent,
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
              feedIsCurrent,
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
              final held = session.feed;
              if (held == null) return;
              final count = window.removeSourceRows(
                duplicateRows,
                held.rowCount,
              );
              shape = shape.removingRows(start, duplicateRows);
              ids = shape.resolve(rawIds);
              session.feed = window.publish(held, totalRows: count);
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
              final held = session.feed;
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
                session.feed = window.publish(
                  held.copyWith(clearNextPage: true),
                  totalRows: end,
                );
              } else {
                session.feed = window.publish(held);
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
        final last = (session.feed?.rowCount ?? 0) - 1;
        if (!_rangeIsBacked(
          instance.url,
          window,
          range.first,
          range.last < last ? range.last : last,
        )) {
          throw StateError('The requested topic range could not be restored.');
        }
        final held = session.feed;
        if (held != null) {
          session.feed = window.publish(held.copyWith(clearError: true));
        }
      }
    } catch (error) {
      if (!requestIsCurrent()) return;

      _commit(lease, () {
        if (!requestIsCurrent()) return;
        final held = session.feed;
        if (held == null) return;
        session.feed = held.withError(
          appL10n.couldnTLoadMoreTopicsFrom((instance.host).toString()),
          page: true,
        );
      });
    } finally {
      if (identical(session.rangeRequest, request)) {
        session.rangeRequest = null;
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

  void forget(String siteUrl) {
    final sessions = _sessions.values
        .where((session) => session.key.$1 == siteUrl)
        .toList();
    final hadFeeds = sessions.any((session) => session.feed != null);
    _filterQueries.remove(siteUrl);
    for (final session in sessions) {
      _retireSession(session);
    }
    if (hadFeeds) notifySafely();
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

  @override
  void dispose() {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      session.retire();
    }
    _filterQueries.clear();
    super.dispose();
  }
}
