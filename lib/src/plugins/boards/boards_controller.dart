import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import 'boards_api.dart';
import 'boards_data.dart';

const boardsControllerKey = PluginServiceKey<BoardsController>(
  owner: boardsPluginId,
  name: 'controller',
);
typedef BoardMoveReviewer =
    Future<BoardRepair?> Function(
      BoardSnapshot board,
      BoardColumn target,
      BoardConstraintCheck check,
    );

final class BoardsController extends FrameSafeNotifier
    implements
        PluginCurrentUserObserver,
        PluginTrackerAttachment,
        PluginRouteHydrator,
        PluginSiteActivator {
  BoardsController({
    required this.api,
    required this.requests,
    required this.siteState,
    required this.trackers,
    required this.topics,
    this.composer,
  });
  final BoardsApi api;
  final PluginRequestHost requests;
  final PluginSiteStateHost siteState;
  final PluginTrackerReader trackers;
  final PluginTopicRefreshHost topics;
  final PluginComposerHost? composer;
  final _settingsListeners = <String, (Listenable, VoidCallback)>{};
  final _composing = <(String, int, int)>{};
  final _createdTopics = <(String, int, int), int>{};
  final _entries = <(String, int), BoardHandle>{};
  final _directory = <String, List<BoardSnapshot>>{};
  final _directoryReads = <String, Future<List<BoardSnapshot>>>{};
  final _revisions = <String, int>{};
  final _trackers = <String, PluginLiveChannelHandle>{};
  bool _foreground = true;
  void changed() => notifySafely();
  int accountRevision(String site) => _revisions[site] ?? 0;
  bool sourceCurrent(String site, PluginSiteLease lease, int revision) =>
      enabled(site) && lease.isCurrent && accountRevision(site) == revision;

  bool enabled(String site) =>
      !isDisposed &&
      (siteState.siteConfigFor(site).plugins.get(boardsSettingsKey)?.enabled ??
          false);
  List<BoardSnapshot> directory(String site) =>
      enabled(site) ? _directory[site] ?? const [] : const [];

  Future<List<BoardSnapshot>> loadDirectory(String site, {int? topicId}) async {
    _observeSettings(site);
    if (!enabled(site)) return const [];
    if (topicId == null) {
      final held = _directoryReads[site];
      if (held != null) return held;
    }
    final lease = requests.capture(site);
    final revision = _revisions[site] ?? 0;
    bool current() =>
        lease.isCurrent && enabled(site) && revision == (_revisions[site] ?? 0);
    final future = () async {
      final credentials = await requests.credentialsFor(site);
      if (!current()) return <BoardSnapshot>[];
      final boards = await credentials.run(
        () => api.list(site, credentials, topicId: topicId),
      );
      if (!current()) return <BoardSnapshot>[];
      if (topicId == null) {
        lease.commit(() {
          _directory[site] = boards;
          notifySafely();
        });
      }
      return boards;
    }();
    if (topicId == null) {
      _directoryReads[site] = future;
    }
    try {
      return await future;
    } finally {
      if (identical(_directoryReads[site], future)) {
        final _ = _directoryReads.remove(site);
      }
    }
  }

  BoardHandle acquire(String site, int id) {
    _observeSettings(site);
    final handle = _entries.putIfAbsent((
      site,
      id,
    ), () => BoardHandle._(this, site, id));
    handle._references++;
    handle._subscribe();
    if (handle.snapshot == null) unawaited(handle.refresh());
    return handle;
  }

  void _release(BoardHandle entry) {
    if (entry._references <= 0) return;
    if (--entry._references > 0) return;
    if (identical(_entries[(entry.site, entry.id)], entry)) {
      _entries.remove((entry.site, entry.id));
    }
    entry._retire();
  }

  void forget(String site) {
    _revisions[site] = (_revisions[site] ?? 0) + 1;
    _directory.remove(site);
    final _ = _directoryReads.remove(site);
    _trackers.remove(site);
    _createdTopics.removeWhere((key, _) => key.$1 == site);
    _composing.removeWhere((key) => key.$1 == site);
    for (final entry
        in _entries.values.where((entry) => entry.site == site).toList()) {
      entry._reset();
    }
    notifySafely();
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) => forget(siteUrl);
  void _observeSettings(String site) {
    if (_settingsListeners.containsKey(site)) return;
    final source = siteState.siteConfigListenableFor?.call(site);
    if (source == null) return;
    var wasEnabled = enabled(site);
    void changedSettings() {
      final nowEnabled = enabled(site);
      if (nowEnabled == wasEnabled) return;
      wasEnabled = nowEnabled;
      forget(site);
    }

    source.addListener(changedSettings);
    _settingsListeners[site] = (source, changedSettings);
  }

  @override
  void activatePluginSite(String siteUrl, {required bool connected}) =>
      _observeSettings(siteUrl);
  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) {
    _trackers[siteUrl] = channels;
    for (final entry in _entries.values.where(
      (entry) => entry.site == siteUrl,
    )) {
      entry._subscription?.cancel();
      entry._subscription = null;
      entry._subscribe();
    }
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    for (final entry in _entries.values.toList()) {
      entry._subscription?.cancel();
      entry._subscription = null;
      if (foreground) {
        entry._subscribe();
        unawaited(entry.refresh());
      }
    }
  }

  @override
  bool handlesPluginRoute(String routeId) =>
      routeId == 'boards' || routeId.startsWith('boards/');
  @override
  Future<void> hydratePluginRoute(
    String siteUrl,
    String routeId, {
    bool force = false,
  }) async {
    if (!enabled(siteUrl)) {
      forget(siteUrl);
      return;
    }
    if (routeId == 'boards') {
      await loadDirectory(siteUrl);
      return;
    }
    final id = int.tryParse(routeId.split('/').elementAtOrNull(1) ?? '');
    if (id != null) {
      final entry = _entries[(siteUrl, id)];
      if (entry != null) await entry.refresh();
    }
  }

  @override
  void dispose() {
    for (final listener in _settingsListeners.values) {
      listener.$1.removeListener(listener.$2);
    }
    _settingsListeners.clear();
    for (final entry in _entries.values.toList()) {
      entry._retire();
    }
    _entries.clear();
    super.dispose();
  }
}

final class BoardHandle extends ChangeNotifier {
  BoardHandle._(this.owner, this.site, this.id);
  final BoardsController owner;
  final String site;
  final int id;
  BoardSnapshot? snapshot;
  String? error;
  bool reading = false, writing = false;
  int _references = 0, _generation = 0;
  bool _disposed = false, _dirty = false;
  Future<void>? _read;
  Object? _readToken;
  PluginLiveChannelSubscription? _subscription;
  bool get enabled => !_disposed && owner.enabled(site);
  bool get canWrite =>
      enabled && !reading && !writing && snapshot?.canWrite == true;
  bool _current(PluginSiteLease lease, int generation) =>
      enabled && lease.isCurrent && generation == _generation;
  void _changed() {
    if (!_disposed) {
      notifyListeners();
      owner.changed();
    }
  }

  void _subscribe() {
    if (!enabled || !owner._foreground || _subscription != null) return;
    _subscription = (owner._trackers[site] ?? owner.trackers(site))?.subscribe(
      '/boards/$id',
      (_, _) => unawaited(refresh()),
    );
  }

  void release() => owner._release(this);
  void _reset() {
    _generation++;
    _readToken = null;
    _read = null;
    reading = false;
    writing = false;
    _dirty = false;
    snapshot = null;
    error = null;
    _subscription?.cancel();
    _subscription = null;
    _changed();
    if (enabled) {
      _subscribe();
      unawaited(refresh());
    }
  }

  void _retire() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    snapshot = null;
    _subscription?.cancel();
    _subscription = null;
    dispose();
  }

  Future<void> refresh() {
    if (!enabled) {
      snapshot = null;
      return Future.value();
    }
    if (writing) {
      _dirty = true;
      return Future.value();
    }
    if (reading) {
      _dirty = true;
      _generation++;
      return _read!;
    }
    reading = true;
    final token = Object();
    _readToken = token;
    _read = _readLoop(token);
    _changed();
    return _read!;
  }

  Future<void> _readLoop(Object token) async {
    do {
      _dirty = false;
      final generation = ++_generation;
      final lease = owner.requests.capture(site);
      try {
        final credentials = await owner.requests.credentialsFor(site);
        if (!_current(lease, generation) || !identical(_readToken, token)) {
          continue;
        }
        final board = await credentials.run(
          () => owner.api.read(site, id, credentials),
        );
        if (!_current(lease, generation) || !identical(_readToken, token)) {
          continue;
        }
        lease.commit(() {
          snapshot = board;
          error = null;
        });
      } catch (failure) {
        if (!_current(lease, generation) || !identical(_readToken, token)) {
          continue;
        }
        lease.commit(() {
          error = failure.toString();
          if (failure is SiteLookupException &&
                  (failure.statusCode == 403 || failure.statusCode == 404) ||
              failure is WriteException &&
                  failure.failure == WriteFailure.forbidden) {
            snapshot = null;
          }
        });
      }
    } while (_dirty && enabled && identical(_readToken, token));
    if (identical(_readToken, token)) {
      reading = false;
      _read = null;
      _readToken = null;
      _changed();
    }
  }

  Future<BoardWriteResult> _write(
    Future<Map<String, dynamic>> Function(PluginRequestCredentials credentials)
    operation, {
    int? topicId,
  }) async {
    if (!canWrite) return const BoardWriteResult(BoardWriteState.refused);
    writing = true;
    _generation++;
    final generation = _generation;
    final lease = owner.requests.capture(site);
    _changed();
    var saved = false;
    BoardWriteResult? result;
    try {
      final credential = await owner.requests.writeCredentialFor(site);
      if (!_current(lease, generation)) {
        return const BoardWriteResult(BoardWriteState.cancelled);
      }
      if (credential.failure case final failure?) throw failure;
      final credentials = credential.credentials;
      if (credentials == null) {
        return const BoardWriteResult(BoardWriteState.refused);
      }
      await credentials.run(() => operation(credentials));
      if (!_current(lease, generation)) {
        return const BoardWriteResult(BoardWriteState.cancelled);
      }
      saved = true;
    } catch (failure) {
      if (!_current(lease, generation)) {
        return const BoardWriteResult(BoardWriteState.cancelled);
      }
      result = BoardWriteResult(
        failure is WriteException &&
                failure.failure == WriteFailure.unreachable &&
                !failure.notSent
            ? BoardWriteState.unknown
            : BoardWriteState.refused,
        failure.toString(),
      );
    } finally {
      if (!_disposed && generation == _generation) {
        writing = false;
        _changed();
      }
    }
    if (!enabled || !lease.isCurrent) {
      return const BoardWriteResult(BoardWriteState.cancelled);
    }
    await refresh();
    if (saved && topicId != null && enabled && lease.isCurrent) {
      try {
        final repair = owner.topics.refreshAfterMutation;
        if (repair != null) {
          final result = await repair(
            siteUrl: site,
            topicId: topicId,
            lease: lease,
          );
          if (result != PluginTopicRefreshResult.refreshed) {
            return const BoardWriteResult(BoardWriteState.refreshNeeded);
          }
        } else {
          await owner.topics.reloadTopic(site, topicId);
        }
      } catch (_) {
        return const BoardWriteResult(BoardWriteState.refreshNeeded);
      }
    }
    return result ??
        BoardWriteResult(
          error == null ? BoardWriteState.saved : BoardWriteState.refreshNeeded,
        );
  }

  bool composing(int columnId, {int? cardId}) =>
      owner._composing.contains((site, id, cardId ?? -columnId));
  int? createdTopic(int columnId, {int? cardId}) =>
      owner._createdTopics[(site, id, cardId ?? -columnId)];

  Future<OpenComposerResult> createTopic(
    String sourceRouteId,
    int columnId, {
    int? cardId,
  }) async {
    final composer = owner.composer;
    final board = snapshot;
    final column = board?.column(columnId);
    final card = cardId == null ? null : board?.card(cardId);
    final key = (site, id, cardId ?? -columnId);
    if (!canWrite ||
        composer == null ||
        board == null ||
        column == null ||
        owner._composing.contains(key) ||
        cardId != null && card?.kind != BoardCardKind.standalone) {
      return OpenComposerResult.unavailable;
    }
    final lease = owner.requests.capture(site);
    owner._composing.add(key);
    _references++;
    _changed();
    var completed = false;
    Future<void> finish(PluginTopicCreationOutcome outcome) async {
      if (completed) return;
      completed = true;
      owner._composing.remove(key);
      try {
        if (!enabled || !lease.isCurrent) return;
        if (outcome case PluginTopicCreated(:final topicId)) {
          owner._createdTopics[key] = topicId;
          await attachCreatedTopic(columnId, cardId: cardId, lease: lease);
        }
      } finally {
        _changed();
        release();
      }
    }

    try {
      final result = await composer.openNewTopic(
        OpenNewTopicComposerRequest(
          siteUrl: site,
          sourceRouteId: sourceRouteId,
          seed: ComposerSeed(raw: card?.notes ?? ''),
          initialTitle: card?.title,
          initialCategoryId:
              column.moveCategoryId ?? board.categoryIds.firstOrNull,
          initialTags: {
            ...?card?.tags,
            ...board.tagNames,
            if (column.tagName.isNotEmpty) column.tagName,
          }.toList(),
          sourceStillCurrent: () =>
              enabled &&
              lease.isCurrent &&
              (cardId == null || snapshot?.card(cardId) != null),
          onCompleted: (outcome) => unawaited(finish(outcome)),
        ),
      );
      if (result != OpenComposerResult.opened) {
        await finish(const PluginTopicCreationCancelled());
      }
      return result;
    } catch (_) {
      await finish(const PluginTopicCreationCancelled());
      return OpenComposerResult.unavailable;
    }
  }

  Future<BoardWriteResult> attachCreatedTopic(
    int columnId, {
    int? cardId,
    PluginSiteLease? lease,
  }) async {
    final key = (site, id, cardId ?? -columnId);
    final topicId = owner._createdTopics[key];
    if (topicId == null || !enabled || lease != null && !lease.isCurrent) {
      return const BoardWriteResult(BoardWriteState.cancelled);
    }
    if (reading) await _read;
    if (lease != null && !lease.isCurrent) {
      return const BoardWriteResult(BoardWriteState.cancelled);
    }
    if (!canWrite ||
        cardId != null &&
            snapshot?.card(cardId)?.kind != BoardCardKind.standalone) {
      return const BoardWriteResult(BoardWriteState.refused);
    }
    final result = await _write(
      (credentials) => owner.api.write(
        site,
        'boards/$id/cards${cardId == null ? '' : '/$cardId'}',
        credentials,
        method: cardId == null ? 'POST' : 'PUT',
        body: {
          'card': {
            'topic_id': topicId,
            if (cardId == null) 'column_id': columnId,
          },
        },
      ),
      topicId: topicId,
    );
    if (result.saved) owner._createdTopics.remove(key);
    _changed();
    return result;
  }

  Future<BoardWriteResult> move(
    int cardId,
    int columnId,
    CardPlacement placement, {
    required BoardMoveReviewer review,
  }) async {
    final board = snapshot;
    final card = board?.card(cardId);
    final target = board?.column(columnId);
    if (!canWrite ||
        board == null ||
        card == null ||
        target == null ||
        card.kind == BoardCardKind.unsupported ||
        target.order == BoardColumnOrder.unsupported ||
        (card.columnId == columnId &&
            target.order == BoardColumnOrder.recency)) {
      return const BoardWriteResult(BoardWriteState.refused);
    }
    if (placement case PlaceAfter(:final cardId)) {
      if (target.cards.every((card) => card.id != cardId) || cardId == card.id) {
        return const BoardWriteResult(BoardWriteState.refused);
      }
    }
    final lease = owner.requests.capture(site);
    final generation = _generation;
    BoardRepair? repair;
    try {
      final credentials = await owner.requests.credentialsFor(site);
      if (!_current(lease, generation)) {
        return const BoardWriteResult(BoardWriteState.cancelled);
      }
      final check = card.topicId != null && card.columnId != columnId
          ? await credentials.run(
              () => owner.api.constraints(
                site,
                id,
                card.topicId!,
                columnId,
                credentials,
              ),
            )
          : const BoardConstraintCheck();
      if (!_current(lease, generation)) {
        return const BoardWriteResult(BoardWriteState.cancelled);
      }
      if (check.needsRepair ||
          board.requireConfirmation && card.columnId != columnId) {
        repair = await review(board, target, check);
        if (repair == null || !_current(lease, generation)) {
          return const BoardWriteResult(BoardWriteState.cancelled);
        }
      }
    } catch (failure) {
      return BoardWriteResult(BoardWriteState.refused, failure.toString());
    }
    return _write(
      (credentials) => owner.api.write(
        site,
        'boards/$id/cards/$cardId',
        credentials,
        method: 'PUT',
        body: {
          'card': {
            'column_id': columnId,
            ...boardPlacement(board, card, target, placement),
          },
          if (repair != null) 'constraint_fix': repair.json,
        },
      ),
      topicId: card.topicId,
    );
  }

  Future<BoardWriteResult> saveStandalone(
    int columnId,
    String title,
    String notes, {
    int? cardId,
    List<String> tags = const [],
  }) {
    if (title.trim().isEmpty ||
        snapshot?.column(columnId) == null ||
        cardId != null &&
            snapshot?.card(cardId)?.kind != BoardCardKind.standalone) {
      return Future.value(const BoardWriteResult(BoardWriteState.refused));
    }
    return _write(
      (credentials) => owner.api.write(
        site,
        'boards/$id/cards${cardId == null ? '' : '/$cardId'}',
        credentials,
        method: cardId == null ? 'POST' : 'PUT',
        body: {
          'card': {
            'column_id': columnId,
            'title': title.trim(),
            'notes': notes,
            'tag_names': tags,
          },
        },
      ),
    );
  }

  Future<BoardWriteResult> removeCard(int cardId) => _write(
    (credentials) => owner.api.write(
      site,
      'boards/$id/cards/$cardId',
      credentials,
      method: 'DELETE',
      body: const {},
    ),
    topicId: snapshot?.card(cardId)?.topicId,
  );

  Future<BoardWriteResult> addTopic(
    int topicId,
    int columnId, {
    required BoardMoveReviewer review,
  }) async {
    final board = snapshot;
    final column = board?.column(columnId);
    if (!canWrite || board == null || column == null || topicId <= 0) {
      return const BoardWriteResult(BoardWriteState.refused);
    }
    final lease = owner.requests.capture(site);
    final generation = _generation;
    BoardRepair? repair;
    try {
      final credentials = await owner.requests.credentialsFor(site);
      if (!_current(lease, generation)) {
        return const BoardWriteResult(BoardWriteState.cancelled);
      }
      final check = await credentials.run(
        () => owner.api.constraints(site, id, topicId, columnId, credentials),
      );
      if (!_current(lease, generation)) {
        return const BoardWriteResult(BoardWriteState.cancelled);
      }
      if (check.needsRepair || board.requireConfirmation) {
        repair = await review(board, column, check);
        if (repair == null || !_current(lease, generation)) {
          return const BoardWriteResult(BoardWriteState.cancelled);
        }
      }
    } catch (failure) {
      return BoardWriteResult(BoardWriteState.refused, failure.toString());
    }
    return _write(
      (credentials) => owner.api.write(
        site,
        'boards/$id/cards',
        credentials,
        method: 'POST',
        body: {
          'card': {'column_id': columnId, 'topic_id': topicId},
          if (repair != null) 'constraint_fix': repair.json,
        },
      ),
      topicId: topicId,
    );
  }
}
