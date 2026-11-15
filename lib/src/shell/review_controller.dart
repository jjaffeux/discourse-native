import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/review_api.dart';
import '../data/site_lifecycle.dart';
import '../data/site_lookup_failure.dart';
import '../data/write_failure.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/reviewable.dart';

/// Why a read of the queue or of one item produced nothing.
enum ReviewFailure {
  /// The site refused this account.
  forbidden,

  /// The item is gone, or was never visible to this account.
  missing,

  unavailable,
}

/// The outcome of the last action, said once beside the list or item.
sealed class ReviewNotice {
  const ReviewNotice();
}

final class ReviewPerformed extends ReviewNotice {
  const ReviewPerformed(this.message);

  /// The site's own completion wording; null when it sent none.
  final String? message;
}

/// Someone else acted first. The item on screen is the site's current one.
final class ReviewConflict extends ReviewNotice {
  const ReviewConflict();
}

final class ReviewActionFailed extends ReviewNotice {
  const ReviewActionFailed(this.message);
  final String message;
}

final class ReviewState {
  ReviewState({
    this.filters = const ReviewFilters(),
    List<Reviewable> items = const [],
    List<String> types = const [],
    this.nextOffset,
    this.loaded = false,
    this.loading = false,
    this.loadingMore = false,
    this.failure,
    this.selectedId,
    this.selected,
    this.selectedLoading = false,
    this.selectedFailure,
    this.performing,
    this.notice,
  }) : items = List.unmodifiable(items),
       types = List.unmodifiable(types);

  final ReviewFilters filters;
  final List<Reviewable> items;

  /// The reviewable classes the site last listed for its type filter.
  final List<String> types;
  final int? nextOffset;

  /// Whether a first page for [filters] has landed.
  final bool loaded;
  final bool loading;
  final bool loadingMore;
  final ReviewFailure? failure;

  /// The open item, which may still be loading.
  final int? selectedId;
  final Reviewable? selected;
  final bool selectedLoading;
  final ReviewFailure? selectedFailure;

  /// The id of the action being sent; every action is held while one is.
  final String? performing;
  final ReviewNotice? notice;

  bool get hasMore => nextOffset != null;

  ReviewState _with({
    List<Reviewable>? items,
    List<String>? types,
    int? Function()? nextOffset,
    bool? loaded,
    bool? loading,
    bool? loadingMore,
    ReviewFailure? Function()? failure,
    int? Function()? selectedId,
    Reviewable? Function()? selected,
    bool? selectedLoading,
    ReviewFailure? Function()? selectedFailure,
    String? Function()? performing,
    ReviewNotice? Function()? notice,
  }) => ReviewState(
    filters: filters,
    items: items ?? this.items,
    types: types ?? this.types,
    nextOffset: nextOffset == null ? this.nextOffset : nextOffset(),
    loaded: loaded ?? this.loaded,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    failure: failure == null ? this.failure : failure(),
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    selected: selected == null ? this.selected : selected(),
    selectedLoading: selectedLoading ?? this.selectedLoading,
    selectedFailure: selectedFailure == null
        ? this.selectedFailure
        : selectedFailure(),
    performing: performing == null ? this.performing : performing(),
    notice: notice == null ? this.notice : notice(),
  );
}

/// Owns one mounted review queue: its filters, the pages read so far, the
/// open item and the single action in flight.
///
/// Three orderings are kept apart. A list read belongs to the filters and
/// refresh that started it. An item read belongs to the selection that
/// started it. And neither may undo an action that finished while it was in
/// flight: a row the site settled stays settled until a read that *started*
/// after the action says otherwise.
final class ReviewController extends FrameSafeNotifier {
  ReviewController({
    required this.api,
    required this.credentials,
    required this.lease,
    required this.siteUrl,
    required this.permitted,
    this.onUnseenCount,
  }) {
    _detach = lease.onRetire(() {
      _listGeneration++;
      _itemGeneration++;
      _state = ReviewState();
      if (!isDisposed) notifySafely();
    });
  }

  final ReviewApi api;
  final ApiCredentialReader credentials;
  final SiteLease lease;
  final String siteUrl;

  /// Whether the account may see the queue at all. Nothing is requested for
  /// one that may not.
  final bool permitted;

  /// The account's unseen total, whenever a response states it.
  final void Function(int count)? onUnseenCount;

  void Function()? _detach;
  int _listGeneration = 0;
  int _itemGeneration = 0;
  int _actionRevision = 0;

  /// The action revision at which each id was last changed by an action.
  final Map<int, int> _changedAt = {};
  final Set<int> _removed = {};

  ReviewState _state = ReviewState();
  ReviewState get state => _state;
  bool get _current => !isDisposed && lease.isCurrent && permitted;

  void _publish(ReviewState value) {
    if (!_current) return;
    lease.commit(() {
      _state = value;
      notifySafely();
    });
  }

  Future<AccountRequestCredentials> _auth() async {
    final auth = await AccountRequestSession(
      siteUrl,
      lease,
    ).credentials(credentials);
    if (auth.apiKey == null) {
      throw StateError('The review queue requires a connected account.');
    }
    return auth;
  }

  static ReviewFailure _readFailure(Object error) => switch (error) {
    SiteLookupException(statusCode: 403) => ReviewFailure.forbidden,
    SiteLookupException(statusCode: 404) => ReviewFailure.missing,
    _ => ReviewFailure.unavailable,
  };

  bool _changedSince(int id, int revision) => (_changedAt[id] ?? 0) > revision;

  /// Rows from a read that began at [revision], without those an action has
  /// settled since.
  Iterable<Reviewable> _reconciled(
    Iterable<Reviewable> rows,
    int revision,
  ) sync* {
    for (final row in rows) {
      if (!_changedSince(row.id, revision)) {
        yield row;
      } else if (!_removed.contains(row.id)) {
        // The row survived the action; the copy on screen already carries
        // its outcome, which this older read cannot know.
        yield _state.items.where((held) => held.id == row.id).firstOrNull ??
            row;
      }
    }
  }

  Future<void> setFilters(ReviewFilters filters) async {
    if (!_current || filters == _state.filters) return;
    _listGeneration++;
    _publish(
      ReviewState(
        filters: filters,
        types: _state.types,
        selectedId: _state.selectedId,
        selected: _state.selected,
        selectedLoading: _state.selectedLoading,
        selectedFailure: _state.selectedFailure,
        performing: _state.performing,
      ),
    );
    await refresh();
  }

  Future<void> refresh() async {
    if (!_current) return;
    final generation = ++_listGeneration;
    final revision = _actionRevision;
    final filters = _state.filters;
    bool owns() => _current && generation == _listGeneration;
    _publish(
      _state._with(loading: true, loadingMore: false, failure: () => null),
    );
    if (!owns()) return;
    try {
      final auth = await _auth();
      if (!owns()) return;
      final page = await auth.run(
        () => api.list(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          filters: filters,
        ),
      );
      if (!owns()) return;
      if (page.unseenCount case final count?) onUnseenCount?.call(count);
      _publish(
        _state._with(
          items: _reconciled(page.items, revision).toList(),
          types: page.types.isEmpty ? _state.types : page.types,
          nextOffset: () => page.nextOffset,
          loaded: true,
          loading: false,
          failure: () => null,
        ),
      );
    } catch (error) {
      if (owns()) {
        _publish(
          _state._with(loading: false, failure: () => _readFailure(error)),
        );
      }
    }
  }

  Future<void> loadMore() async {
    final offset = _state.nextOffset;
    if (!_current ||
        offset == null ||
        _state.loading ||
        _state.loadingMore ||
        !_state.loaded) {
      return;
    }
    final generation = _listGeneration;
    final revision = _actionRevision;
    final filters = _state.filters;
    bool owns() => _current && generation == _listGeneration;
    _publish(_state._with(loadingMore: true, failure: () => null));
    if (!owns()) return;
    try {
      final auth = await _auth();
      if (!owns()) return;
      final page = await auth.run(
        () => api.list(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          filters: filters,
          offset: offset,
        ),
      );
      if (!owns()) return;
      // Offsets shift when the queue changes between pages, so a row can
      // arrive twice; the copy already on screen wins.
      final held = {for (final item in _state.items) item.id};
      _publish(
        _state._with(
          items: [
            ..._state.items,
            for (final item in _reconciled(page.items, revision))
              if (held.add(item.id)) item,
          ],
          nextOffset: () => page.nextOffset,
          loadingMore: false,
        ),
      );
    } catch (error) {
      if (owns()) {
        _publish(
          _state._with(loadingMore: false, failure: () => _readFailure(error)),
        );
      }
    }
  }

  /// Opens one item. The list's copy shows at once and is replaced by the
  /// site's current one.
  Future<void> open(int id) async {
    if (!_current || id <= 0) return;
    final held = _state.items.where((item) => item.id == id).firstOrNull;
    _publish(
      _state._with(
        selectedId: () => id,
        selected: () => held,
        selectedFailure: () => null,
        notice: () => null,
      ),
    );
    await _readItem(id);
  }

  void close() {
    if (!_current || _state.selectedId == null) return;
    _itemGeneration++;
    _publish(
      _state._with(
        selectedId: () => null,
        selected: () => null,
        selectedLoading: false,
        selectedFailure: () => null,
      ),
    );
  }

  void dismissNotice() {
    if (_current && _state.notice != null) {
      _publish(_state._with(notice: () => null));
    }
  }

  Future<void> _readItem(int id) async {
    // Only a read of the open item supersedes other reads. A reread of a row
    // the reader has since left must not cancel the read of the item they
    // moved to, which would never learn that it had finished.
    final selected = _state.selectedId == id;
    final generation = selected ? ++_itemGeneration : null;
    final revision = _actionRevision;
    bool owns() =>
        _current && (generation == null || generation == _itemGeneration);
    if (selected) _publish(_state._with(selectedLoading: true));
    if (!owns()) return;
    try {
      final auth = await _auth();
      if (!owns()) return;
      final item = await auth.run(
        () => api.item(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          id: id,
        ),
      );
      if (!owns()) return;
      if (item == null || item.id != id) {
        if (_state.selectedId == id) {
          _publish(
            _state._with(
              selectedLoading: false,
              selectedFailure: () => ReviewFailure.missing,
            ),
          );
        }
        return;
      }
      // An action that finished while this read was in flight knows more
      // than the read does.
      if (_changedSince(id, revision)) {
        if (_state.selectedId == id) {
          _publish(_state._with(selectedLoading: false));
        }
        return;
      }
      _publish(
        _state._with(
          items: [for (final held in _state.items) held.id == id ? item : held],
          selected: _state.selectedId == id ? () => item : null,
          selectedLoading: _state.selectedId == id ? false : null,
          selectedFailure: _state.selectedId == id ? () => null : null,
        ),
      );
    } catch (error) {
      if (owns() && _state.selectedId == id) {
        _publish(
          _state._with(
            selectedLoading: false,
            selectedFailure: () => _readFailure(error),
          ),
        );
      }
    }
  }

  /// Sends one action once. A failed write is reported, never repeated: the
  /// site may already have applied it.
  Future<void> perform(Reviewable item, ReviewableAction action) async {
    if (!_current ||
        _state.performing != null ||
        item.routeFor(action) == ReviewableActionRoute.browser) {
      return;
    }
    _publish(_state._with(performing: () => action.id, notice: () => null));
    if (!_current) return;
    ReviewNotice notice;
    var reread = false;
    try {
      final auth = await _auth();
      if (!_current) return;
      final result = await auth.run(
        () => api.perform(
          siteUrl: siteUrl,
          apiKey: auth.apiKey!,
          clientId: auth.clientId,
          id: item.id,
          action: action.serverAction,
          version: item.version,
        ),
      );
      if (!_current) return;
      _applyResult(item.id, result);
      notice = ReviewPerformed(action.completedMessage);
      // An action can leave the item pending with different actions on
      // offer, which only the site can list.
      reread = !result.removedIds.contains(item.id);
    } on WriteException catch (error) {
      if (!_current) return;
      notice = error.failure == WriteFailure.conflict
          ? const ReviewConflict()
          : ReviewActionFailed(error.message);
      // Either someone else changed it, or the answer was lost after the
      // site may have applied the action. Only the site knows which.
      reread =
          error.failure == WriteFailure.conflict ||
          (error.failure == WriteFailure.unreachable && !error.notSent);
    } catch (_) {
      if (!_current) return;
      notice = ReviewActionFailed(
        const WriteException(WriteFailure.unreachable).message,
      );
    }
    _publish(_state._with(performing: () => null, notice: () => notice));
    if (reread && _current) await _readItem(item.id);
  }

  void _applyResult(int id, ReviewablePerformResult result) {
    final revision = ++_actionRevision;
    final touched = {id, ...result.removedIds, ...result.statuses.keys};
    for (final touchedId in touched) {
      _changedAt[touchedId] = revision;
    }
    _removed
      ..removeAll(touched)
      ..addAll(result.removedIds);
    if (result.unseenCount case final count?) onUnseenCount?.call(count);

    Reviewable settle(Reviewable held) => held.withOutcome(
      status: result.statuses[held.id],
      version: held.id == id ? result.version : null,
      settled: result.removedIds.contains(held.id),
    );
    final selected = _state.selected;
    final selectedSettled =
        selected != null && result.removedIds.contains(selected.id);
    if (selectedSettled) _itemGeneration++;
    // Rows that left a pending queue shift every later row up by one.
    final left = _state.filters.status == ReviewStatusFilter.pending
        ? _state.items
              .where((held) => result.removedIds.contains(held.id))
              .length
        : 0;
    final nextOffset = _state.nextOffset;
    _publish(
      _state._with(
        nextOffset: nextOffset == null || left == 0
            ? null
            : () => nextOffset > left ? nextOffset - left : 0,
        items: [
          for (final held in _state.items)
            if (!result.removedIds.contains(held.id))
              touched.contains(held.id) ? settle(held) : held,
        ],
        // The settled item has left the queue, so the list takes its place.
        selectedId: selectedSettled ? () => null : null,
        selected: selected == null
            ? null
            : selectedSettled
            ? () => null
            : touched.contains(selected.id)
            ? () => settle(selected)
            : null,
        selectedLoading: selectedSettled ? false : null,
      ),
    );
  }

  @override
  void dispose() {
    _listGeneration++;
    _itemGeneration++;
    _detach?.call();
    _detach = null;
    super.dispose();
  }
}
