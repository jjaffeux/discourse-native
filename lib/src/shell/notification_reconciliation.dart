import 'package:flutter/foundation.dart';

import '../data/site_lifecycle.dart';
import '../models/bookmark_feed.dart';
import '../models/notification.dart';
import '../models/notification_feed.dart';
import '../models/notification_totals.dart';
import '../models/notification_type_counts.dart';
import '../plugin_api/notification_counters.dart';

final class NotificationFeedSlot<T> {
  const NotificationFeedSlot._(this.empty, this._projection, this._notify);

  static NotificationFeedSlot<NotificationFeed> notifications(
    VoidCallback notify,
  ) => NotificationFeedSlot._(
    const NotificationFeed(),
    const _NotificationProjection(),
    notify,
  );

  static NotificationFeedSlot<BookmarkFeed> reminders(VoidCallback notify) =>
      NotificationFeedSlot._(
        const BookmarkFeed(),
        const _ReminderProjection(),
        notify,
      );

  final T empty;
  final _FeedProjection<T> _projection;
  final VoidCallback _notify;
}

final class LiveNotificationCounts {
  const LiveNotificationCounts({
    this.allUnread,
    this.personal,
    this.grouped = NotificationTypeCounts.unavailable,
  });

  final int? allUnread;
  final int? personal;
  final NotificationTypeCounts grouped;

  bool get isAvailable =>
      allUnread != null || personal != null || grouped.isAvailable;
}

typedef _GroupedAuthority = ({
  int snapshot,
  Map<NotificationTypeId, int> types,
});

final class NotificationRead {
  NotificationRead._(
    this._owner,
    this._notification,
    this._dismissalCoverageRevision,
    this._wasPinned,
    this._groupedAuthority,
    this._decremented,
  );

  final NotificationReconciliation _owner;
  final DiscourseNotification _notification;
  final int _dismissalCoverageRevision;
  final bool _wasPinned;
  final _GroupedAuthority _groupedAuthority;
  final bool _decremented;
  bool _settled = false;
}

final class NotificationDismissal {
  NotificationDismissal._(this._owner, this._types, this._ids, this._authority);

  final NotificationReconciliation _owner;
  final Set<NotificationTypeId> _types;
  final Set<int> _ids;
  final _GroupedAuthority _authority;
  bool _settled = false;
}

final class NotificationTotalsTicket {
  NotificationTotalsTicket._(this._owner)
    : _before = _owner.totals ?? const NotificationTotals(),
      _fields = Map.of(_owner._fieldRevisions),
      _counters = Map.of(_owner._counterRevisions);

  final NotificationReconciliation _owner;
  final NotificationTotals _before;
  final Map<NotificationTotalsField, int> _fields;
  final Map<PluginNotificationCounterId, int> _counters;
  bool _settled = false;
}

final class NotificationReconciliation {
  NotificationReconciliation({
    required this.lease,
    required this._totalsChanged,
    required this._totalsAspectChanged,
    required this._changed,
    required this._groupedUnreadAuthorityAdvanced,
  });

  final SiteLease lease;
  final void Function(NotificationTotals) _totalsChanged;
  final VoidCallback _totalsAspectChanged;
  final VoidCallback _changed;
  final VoidCallback _groupedUnreadAuthorityAdvanced;
  final Map<Object, _RegisteredFeed> _feeds = {};
  final Set<int> _readIds = {};
  final Map<int, int> _dismissalCoverageRevisions = {};
  int _snapshotRevision = 0;
  final Map<NotificationTypeId, int> _typeRevisions = {};
  final Map<NotificationTotalsField, int> _fieldRevisions = {};
  final Map<PluginNotificationCounterId, int> _counterRevisions = {};
  NotificationTotals? _totals;
  bool _retired = false;
  bool _dispatching = false;
  final Set<VoidCallback> _pendingFeeds = {};
  NotificationTotals? _pendingTotals;

  bool get isCurrent => !_retired && lease.isCurrent;
  NotificationTotals? get totals => _totals;

  T feed<T>(NotificationFeedSlot<T> slot) =>
      (_feeds[slot] as _FeedSnapshot<T>?)?.value ?? slot.empty;

  bool hasPublished<T>(NotificationFeedSlot<T> slot) =>
      _feeds.containsKey(slot);

  void restoreTotals(NotificationTotals totals) {
    if (isCurrent) _totals = totals;
  }

  void publish<T>(NotificationFeedSlot<T> slot, T snapshot) {
    if (!isCurrent) return;
    _feeds[slot] = _FeedSnapshot(
      slot,
      slot._projection.overlay(snapshot, _readIds),
    );
    _pendingFeeds.add(slot._notify);
    _flush();
  }

  NotificationRead? beginRead(DiscourseNotification notification) {
    if (!isCurrent || notification.read) return null;
    _groupedUnreadAuthorityAdvanced();
    if (!isCurrent) return null;
    final authority = _captureGrouped({notification.typeId});
    final wasPinned = _readIds.contains(notification.id);
    final rowRevision = _dismissalCoverageRevisions[notification.id] ?? 0;
    final decremented = _adjustGroupedLocally(notification.typeId, -1);
    final attempt = NotificationRead._(
      this,
      notification,
      rowRevision,
      wasPinned,
      authority,
      decremented,
    );
    _pin({notification.id});
    _flush();
    return attempt;
  }

  void confirmRead(NotificationRead attempt) {
    if (!_accepts(attempt._owner) || attempt._settled) return;
    attempt._settled = true;
    _groupedUnreadAuthorityAdvanced();
  }

  void failRead(NotificationRead attempt) {
    if (!_accepts(attempt._owner) || attempt._settled) return;
    attempt._settled = true;
    final id = attempt._notification.id;
    if (!attempt._wasPinned &&
        (_dismissalCoverageRevisions[id] ?? 0) ==
            attempt._dismissalCoverageRevision) {
      _readIds.remove(id);
      _mark({id}, read: false);
    }
    if (attempt._decremented && _groupedIsCurrent(attempt._groupedAuthority)) {
      _adjustGroupedLocally(attempt._notification.typeId, 1);
    }
    _flush();
  }

  NotificationDismissal? beginDismiss({
    required List<NotificationWireType> types,
    List<NotificationTypeName>? names,
    NotificationFeedSlot<NotificationFeed>? source,
  }) {
    if (!isCurrent) return null;
    _groupedUnreadAuthorityAdvanced();
    if (!isCurrent) return null;
    final typeIds = {for (final type in types) NotificationTypeId(type.wireId)};
    final typeNames =
        names?.toSet() ??
        {for (final type in types) NotificationTypeName(type.wireName)};
    final ids = <int>{};
    for (final entry in _feeds.entries) {
      for (final row in entry.value.rows) {
        if (source == null ||
            identical(entry.key, source) ||
            typeNames.contains(row.typeName) ||
            typeIds.contains(row.typeId)) {
          ids.add(row.id);
        }
      }
    }
    return NotificationDismissal._(
      this,
      typeIds,
      ids,
      _captureGrouped(typeIds),
    );
  }

  void confirmDismiss(NotificationDismissal attempt) {
    if (!_accepts(attempt._owner) || attempt._settled) return;
    attempt._settled = true;
    _groupedUnreadAuthorityAdvanced();
    if (!isCurrent) return;
    final clearCounts = _groupedIsCurrent(attempt._authority);
    if (_totals?.groupedUnreadNotifications.isAvailable == true) {
      _advanceField(NotificationTotalsField.groupedUnreadNotifications);
    }
    for (final type in attempt._types) {
      _typeRevisions.update(
        type,
        (revision) => revision + 1,
        ifAbsent: () => 1,
      );
    }
    for (final id in attempt._ids) {
      _dismissalCoverageRevisions.update(
        id,
        (revision) => revision + 1,
        ifAbsent: () => 1,
      );
    }
    _pin(attempt._ids);
    if (clearCounts) _clearGrouped(attempt._types);
    _flush();
  }

  NotificationTotalsTicket beginTotalsRefresh() =>
      NotificationTotalsTicket._(this);

  NotificationTotals? acceptTotalsRefresh(
    NotificationTotalsTicket ticket,
    NotificationTotals response,
  ) {
    if (!_accepts(ticket._owner) || ticket._settled) return null;
    ticket._settled = true;
    final current = _totals;
    final updatedFields = {
      for (final field in NotificationTotalsField.values)
        if ((_fieldRevisions[field] ?? 0) != (ticket._fields[field] ?? 0))
          field,
    };
    final resolved = current == null
        ? response
        : NotificationTotals.mergeRefresh(
            response: response,
            before: ticket._before,
            live: current,
            updatedFields: updatedFields,
            updatedPluginCounters: {
              for (final entry in _counterRevisions.entries)
                if (entry.value != (ticket._counters[entry.key] ?? 0))
                  entry.key,
            },
          );
    if (response.groupedUnreadNotifications.isAvailable &&
        !updatedFields.contains(
          NotificationTotalsField.groupedUnreadNotifications,
        ) &&
        (current == null ||
            current.groupedUnreadNotifications ==
                ticket._before.groupedUnreadNotifications)) {
      _advanceSnapshot();
    }
    if (current != resolved) _publishTotals(resolved);
    _flush();
    return resolved;
  }

  void applyCounts(NotificationTotals Function(NotificationTotals) fold) {
    if (!isCurrent) return;
    final held = _totals ?? const NotificationTotals();
    final updated = fold(held);
    if (!isCurrent || updated == held) return;
    if (updated.unreadNotifications != held.unreadNotifications) {
      _advanceField(NotificationTotalsField.unreadNotifications);
    }
    if (updated.unreadPersonalMessages != held.unreadPersonalMessages) {
      _advanceField(NotificationTotalsField.unreadPersonalMessages);
    }
    if (updated.unseenReviewables != held.unseenReviewables) {
      _advanceField(NotificationTotalsField.unseenReviewables);
    }
    for (final id in {
      ...held.pluginCounters.ids,
      ...updated.pluginCounters.ids,
    }) {
      if (updated.pluginCounter(id) != held.pluginCounter(id)) {
        _advanceCounter(id);
      }
    }
    if (updated.groupedUnreadNotifications != held.groupedUnreadNotifications) {
      _advanceSnapshot();
    }
    _publishTotals(updated);
    _flush();
  }

  void applyGroupedSnapshot(NotificationTypeCounts counts) {
    if (!isCurrent || !counts.isAvailable) return;
    _advanceSnapshot();
    final held = _totals ?? const NotificationTotals();
    final updated = held.withGroupedUnreadNotifications(counts);
    if (updated != held) _publishTotals(updated);
    _flush();
  }

  void applyLiveCounts(LiveNotificationCounts counts) {
    if (!isCurrent || !counts.isAvailable) return;
    if (counts.allUnread != null) {
      _advanceField(NotificationTotalsField.unreadNotifications);
    }
    if (counts.personal != null) {
      _advanceField(NotificationTotalsField.unreadPersonalMessages);
    }
    if (counts.grouped.isAvailable) _advanceSnapshot();
    final held = _totals ?? const NotificationTotals();
    final personal = counts.personal ?? held.unreadPersonalMessages;
    final all = counts.allUnread;
    final updated = held.copyWith(
      unreadNotifications: all == null ? null : (all - personal).clamp(0, all),
      unreadPersonalMessages: personal,
      groupedUnreadNotifications: counts.grouped.isAvailable
          ? counts.grouped
          : null,
    );
    _totals = updated;
    if (updated != held) _pendingTotals = updated;
    _flush();
  }

  void applyReviewables(int count) {
    if (!isCurrent) return;
    _advanceField(NotificationTotalsField.unseenReviewables);
    final held = _totals ?? const NotificationTotals();
    final updated = held.copyWith(unseenReviewables: count);
    _totals = updated;
    if (updated != held) _pendingTotals = updated;
    _flush();
  }

  void applyPluginCounter(
    PluginNotificationCounter counter,
    int Function(int) reduce,
  ) {
    if (!isCurrent) return;
    final held = _totals ?? const NotificationTotals();
    final updated = held.updatePluginCounter(counter, reduce);
    if (!isCurrent) return;
    _advanceCounter(counter.id);
    _totals = updated;
    if (updated != held) _pendingTotals = updated;
    _flush();
  }

  bool retire({bool notify = false}) {
    if (_retired) return false;
    _retired = true;
    final aspects = [for (final feed in _feeds.values) feed.notify];
    final hadTotals = _totals != null;
    _feeds.clear();
    _totals = null;
    _readIds.clear();
    _dismissalCoverageRevisions.clear();
    _typeRevisions.clear();
    _fieldRevisions.clear();
    _counterRevisions.clear();
    _pendingFeeds.clear();
    _pendingTotals = null;
    final hadState = hadTotals || aspects.isNotEmpty;
    if (!notify) return hadState;
    if (hadTotals) _totalsAspectChanged();
    for (final aspect in aspects) {
      aspect();
    }
    return hadState;
  }

  bool _accepts(NotificationReconciliation owner) =>
      isCurrent && identical(owner, this);

  void _pin(Set<int> ids) {
    _readIds.addAll(ids);
    _mark(ids, read: true);
  }

  void _mark(Set<int> ids, {required bool read}) {
    for (final feed in _feeds.values) {
      if (feed.mark(ids, read: read)) _pendingFeeds.add(feed.notify);
    }
  }

  _GroupedAuthority _captureGrouped(Set<NotificationTypeId> types) => (
    snapshot: _snapshotRevision,
    types: {for (final type in types) type: _typeRevisions[type] ?? 0},
  );

  bool _groupedIsCurrent(_GroupedAuthority authority) =>
      authority.snapshot == _snapshotRevision &&
      authority.types.entries.every(
        (entry) => (_typeRevisions[entry.key] ?? 0) == entry.value,
      );

  bool _adjustGroupedLocally(NotificationTypeId type, int delta) {
    final held = _totals;
    final wire = held?.groupedUnreadNotifications.toJson();
    if (held == null || wire == null) return false;
    final key = '${type.value}';
    final current = wire[key] ?? 0;
    final next = (current + delta).clamp(0, 0x7fffffff);
    if (next == current) return false;
    final updated = Map<String, int>.of(wire);
    if (next == 0) {
      updated.remove(key);
    } else {
      updated[key] = next;
    }
    _advanceField(NotificationTotalsField.groupedUnreadNotifications);
    _publishTotals(
      held.copyWith(
        groupedUnreadNotifications: NotificationTypeCounts.fromWire(updated),
      ),
    );
    return true;
  }

  void _clearGrouped(Set<NotificationTypeId> types) {
    final held = _totals;
    final wire = held?.groupedUnreadNotifications.toJson();
    if (held == null || wire == null || wire.isEmpty) return;
    final updated = Map<String, int>.of(wire);
    for (final type in types) {
      updated.remove('${type.value}');
    }
    if (!mapEquals(updated, wire)) {
      _publishTotals(
        held.copyWith(
          groupedUnreadNotifications: NotificationTypeCounts.fromWire(updated),
        ),
      );
    }
  }

  void _advanceSnapshot() {
    _snapshotRevision++;
    _advanceField(NotificationTotalsField.groupedUnreadNotifications);
  }

  void _advanceField(NotificationTotalsField field) => _fieldRevisions.update(
    field,
    (revision) => revision + 1,
    ifAbsent: () => 1,
  );
  void _advanceCounter(PluginNotificationCounterId id) => _counterRevisions
      .update(id, (revision) => revision + 1, ifAbsent: () => 1);

  void _publishTotals(NotificationTotals totals) {
    _totals = totals;
    _pendingTotals = totals;
  }

  void _flush() {
    if (_dispatching || !isCurrent) return;
    _dispatching = true;
    try {
      while (isCurrent &&
          (_pendingTotals != null || _pendingFeeds.isNotEmpty)) {
        final totals = _pendingTotals;
        final aspects = _pendingFeeds.toList();
        _pendingTotals = null;
        _pendingFeeds.clear();
        if (totals != null) {
          _totalsChanged(totals);
          if (!isCurrent) return;
          _totalsAspectChanged();
          if (!isCurrent) return;
        }
        for (final aspect in aspects) {
          aspect();
          if (!isCurrent) return;
        }
        _changed();
      }
    } finally {
      _dispatching = false;
    }
  }
}

abstract interface class _RegisteredFeed {
  Iterable<DiscourseNotification> get rows;
  VoidCallback get notify;
  bool mark(Set<int> ids, {required bool read});
}

final class _FeedSnapshot<T> implements _RegisteredFeed {
  _FeedSnapshot(this.slot, this.value);

  final NotificationFeedSlot<T> slot;
  T value;

  @override
  Iterable<DiscourseNotification> get rows => slot._projection.rows(value);
  @override
  VoidCallback get notify => slot._notify;

  @override
  bool mark(Set<int> ids, {required bool read}) {
    final previous = value;
    for (final id in ids) {
      value = slot._projection.mark(value, id, read: read);
    }
    return !identical(previous, value);
  }
}

abstract interface class _FeedProjection<T> {
  Iterable<DiscourseNotification> rows(T snapshot);
  T mark(T snapshot, int id, {required bool read});
  T overlay(T snapshot, Set<int> ids);
}

List<DiscourseNotification> _overlay(
  List<DiscourseNotification> rows,
  Set<int> ids,
) {
  List<DiscourseNotification>? updated;
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].isUnread && ids.contains(rows[i].id)) {
      updated ??= List.of(rows);
      updated[i] = rows[i].asRead();
    }
  }
  return updated ?? rows;
}

final class _NotificationProjection
    implements _FeedProjection<NotificationFeed> {
  const _NotificationProjection();

  @override
  Iterable<DiscourseNotification> rows(NotificationFeed snapshot) =>
      snapshot.notifications;
  @override
  NotificationFeed mark(
    NotificationFeed snapshot,
    int id, {
    required bool read,
  }) => read ? snapshot.withRead(id) : snapshot.withUnread(id);
  @override
  NotificationFeed overlay(NotificationFeed snapshot, Set<int> ids) {
    final rows = _overlay(snapshot.notifications, ids);
    return identical(rows, snapshot.notifications)
        ? snapshot
        : NotificationFeed(
            notifications: rows,
            loading: snapshot.loading,
            loaded: snapshot.loaded,
            error: snapshot.error,
          );
  }
}

final class _ReminderProjection implements _FeedProjection<BookmarkFeed> {
  const _ReminderProjection();

  @override
  Iterable<DiscourseNotification> rows(BookmarkFeed snapshot) =>
      snapshot.reminders;
  @override
  BookmarkFeed mark(BookmarkFeed snapshot, int id, {required bool read}) =>
      read ? snapshot.withRead(id) : snapshot.withUnread(id);
  @override
  BookmarkFeed overlay(BookmarkFeed snapshot, Set<int> ids) {
    final rows = _overlay(snapshot.reminders, ids);
    return identical(rows, snapshot.reminders)
        ? snapshot
        : BookmarkFeed(
            reminders: rows,
            bookmarks: snapshot.bookmarks,
            loading: snapshot.loading,
            loaded: snapshot.loaded,
            error: snapshot.error,
          );
  }
}
