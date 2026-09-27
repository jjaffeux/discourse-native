import 'dart:collection';

import 'package:flutter/foundation.dart';

abstract mixin class Storable<T extends Storable<T>> {
  Object get storeId;

  T merge(covariant T incoming) => incoming;
}

/// Bounds an identity store while keeping sites and record kinds from
/// monopolizing its retained working set.
@immutable
final class StorePolicy {
  const StorePolicy({
    required this.maxEntries,
    this.maxEntriesPerSite,
    this.maxEntriesPerSiteAndType,
  }) : assert(maxEntries > 0),
       assert(maxEntriesPerSite == null || maxEntriesPerSite > 0),
       assert(maxEntriesPerSiteAndType == null || maxEntriesPerSiteAndType > 0);

  final int maxEntries;

  /// A hard site share. Observed refs may temporarily exceed it.
  final int? maxEntriesPerSite;

  /// A hard share for one `(site, record type)` partition.
  final int? maxEntriesPerSiteAndType;
}

typedef StorePartition = ({String siteUrl, Type type});

/// A point-in-time cache snapshot exposed only to focused tests.
@visibleForTesting
@immutable
final class StoreStatistics {
  const StoreStatistics({
    required this.entries,
    required this.records,
    required this.observedEntries,
    required this.evictions,
    required this.recordEvictions,
    required this.policy,
    required this.entriesBySite,
    required this.entriesByPartition,
  });

  final int entries;
  final int records;
  final int observedEntries;
  final int evictions;
  final int recordEvictions;
  final StorePolicy? policy;
  final Map<String, int> entriesBySite;
  final Map<StorePartition, int> entriesByPartition;

  int get overCapacity => switch (policy) {
    null => 0,
    final policy => (entries - policy.maxEntries).clamp(0, entries),
  };

  int entriesFor<T extends Storable<T>>(String siteUrl) =>
      entriesByPartition[(siteUrl: siteUrl, type: T)] ?? 0;
}

class Ref<T extends Object> extends ChangeNotifier
    implements ValueListenable<T?> {
  Ref._(this._value);

  T? _value;

  @override
  T? get value => _value;

  bool get _isObserved => hasListeners;

  void _set(T? next) {
    if (identical(_value, next)) return;
    _value = next;
    notifyListeners();
  }
}

/// A held ref's place in its `(site, record type)` partition, linked in
/// least-recently-used order so the partition's oldest ref is its first.
final class _Slot extends LinkedListEntry<_Slot> {
  _Slot(this.key, this.ref, this.lastUse);

  final (String, Type, Object) key;
  final Ref<Object> ref;

  /// The store's use count at this ref's creation or last touch, which orders
  /// the refs of different partitions by recency.
  int lastUse;
}

class Store {
  Store({int? maxEntries, StorePolicy? policy})
    : assert(maxEntries == null || maxEntries > 0),
      assert(
        maxEntries == null || policy == null,
        'Use either maxEntries or policy, not both.',
      ),
      policy =
          policy ??
          (maxEntries == null ? null : StorePolicy(maxEntries: maxEntries));

  /// A safety ceiling for records which are not currently observed by the UI.
  /// Observed refs are pinned so eviction can never detach a mounted widget
  /// from future store updates.
  int? get maxEntries => policy?.maxEntries;

  final StorePolicy? policy;

  final LinkedHashMap<(String, Type, Object), _Slot> _refs = LinkedHashMap();

  /// The same slots by site and record type. A store at capacity evicts for
  /// every new record, so choosing a victim reads the head of each partition
  /// rather than walking every held ref.
  final Map<String, Map<Type, LinkedList<_Slot>>> _partitions = {};
  int _uses = 0;

  final Map<(String, Type), int> _generations = {};
  final Map<String, int> _entriesBySite = {};

  int _evictions = 0;
  int _recordEvictions = 0;

  int generationOf<T extends Storable<T>>(String siteUrl) =>
      _generations[(siteUrl, T)] ?? 0;

  void _bump(String siteUrl, Type type) {
    final key = (siteUrl, type);
    _generations[key] = (_generations[key] ?? 0) + 1;
  }

  Ref<T> ref<T extends Storable<T>>(String siteUrl, Object id) =>
      _cell<T>(siteUrl, id);

  Ref<T> _cell<T extends Storable<T>>(String siteUrl, Object id) {
    final key = (siteUrl, T, id);
    final held = _refs[key];
    if (held != null) {
      _touch(held);
      return held.ref as Ref<T>;
    }

    final created = Ref<T>._(null);
    _hold(key, created);
    _trim(keep: key);
    return created;
  }

  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    final slot = _refs[(siteUrl, T, id)];
    if (slot == null) return null;
    _touch(slot);
    return (slot.ref as Ref<T>).value;
  }

  /// Answers without changing least-recently-used order or allocating a ref.
  ///
  /// Consumers which retain record IDs separately from this bounded store use
  /// this to validate that their window is still backed before reusing it.
  bool containsRecord<T extends Storable<T>>(String siteUrl, Object id) =>
      _refs[(siteUrl, T, id)]?.ref.value != null;

  T put<T extends Storable<T>>(String siteUrl, T record) {
    final cell = _cell<T>(siteUrl, record.storeId);
    final held = cell.value;
    final merged = held == null ? record : held.merge(record);
    if (!identical(held, merged)) _bump(siteUrl, T);
    cell._set(merged);
    _trim(keep: (siteUrl, T, record.storeId));
    return merged;
  }

  List<T> putAll<T extends Storable<T>>(String siteUrl, Iterable<T> records) =>
      [for (final record in records) put(siteUrl, record)];

  void update<T extends Storable<T>>(
    String siteUrl,
    Object id,
    T Function(T held) change,
  ) {
    final cell = _refs[(siteUrl, T, id)]?.ref as Ref<T>?;
    final held = cell?.value;
    if (cell == null || held == null) return;
    final next = change(held);
    if (!identical(held, next)) _bump(siteUrl, T);
    cell._set(next);
  }

  void remove<T extends Storable<T>>(String siteUrl, Object id) {
    final key = (siteUrl, T, id);
    final cell = _refs[key]?.ref as Ref<T>?;
    if (cell?.value != null) _bump(siteUrl, T);
    cell?._set(null);
    if (cell != null && !cell._isObserved) _removeRef(key);
  }

  /// Clears matching records, including refs retained by mounted readers.
  void removeMatching<T extends Storable<T>>(
    String siteUrl,
    bool Function(T) matches,
  ) {
    final ids = [
      for (final entry in _refs.entries)
        if (entry.key.$1 == siteUrl && entry.key.$2 == T)
          if (entry.value.ref.value case final T record)
            if (matches(record)) entry.key.$3,
    ];
    for (final id in ids) {
      remove<T>(siteUrl, id);
    }
  }

  void _touch(_Slot slot) {
    _refs.remove(slot.key);
    _refs[slot.key] = slot;
    final partition = slot.list!;
    slot.unlink();
    partition.add(slot);
    slot.lastUse = ++_uses;
  }

  void _trim({required (String, Type, Object) keep}) {
    final activePolicy = policy;
    if (activePolicy == null) return;

    final partitionLimit = activePolicy.maxEntriesPerSiteAndType;
    if (partitionLimit != null) {
      while (_partitionLength(keep.$1, keep.$2) > partitionLimit &&
          _evict(
            _oldestEvictable(keep: keep, siteUrl: keep.$1, type: keep.$2),
          )) {}
    }

    final siteLimit = activePolicy.maxEntriesPerSite;
    if (siteLimit != null) {
      while (_siteLength(keep.$1) > siteLimit &&
          _evict(_fairTypeVictim(keep: keep, siteUrl: keep.$1))) {}
    }

    while (_refs.length > activePolicy.maxEntries &&
        _evict(_fairSiteAndTypeVictim(keep: keep))) {}
  }

  int _siteLength(String siteUrl) => _entriesBySite[siteUrl] ?? 0;

  int _partitionLength(String siteUrl, Type type) =>
      _partitions[siteUrl]?[type]?.length ?? 0;

  (String, Type, Object)? _oldestEvictable({
    required (String, Type, Object) keep,
    required String siteUrl,
    required Type type,
  }) => switch (_partitions[siteUrl]?[type]) {
    null => null,
    final partition => _oldestEvictableIn(partition, keep: keep)?.key,
  };

  /// Observed refs and `keep` are the only slots passed over.
  _Slot? _oldestEvictableIn(
    LinkedList<_Slot> partition, {
    required (String, Type, Object) keep,
  }) {
    for (final slot in partition) {
      if (slot.ref._isObserved || slot.key == keep) continue;
      return slot;
    }
    return null;
  }

  /// Takes the oldest candidate of the site's largest record-type partition.
  (String, Type, Object)? _fairTypeVictim({
    required (String, Type, Object) keep,
    required String siteUrl,
  }) {
    final types = _partitions[siteUrl];
    if (types == null) return null;
    _Slot? victim;
    var victimShare = 0;
    for (final partition in types.values) {
      final candidate = _oldestEvictableIn(partition, keep: keep);
      if (candidate == null) continue;
      if (victim == null ||
          _yieldsFirst(
            partition.length,
            candidate.lastUse,
            victimShare,
            victim.lastUse,
          )) {
        victim = candidate;
        victimShare = partition.length;
      }
    }
    return victim?.key;
  }

  /// Takes from the site holding the most refs, then from its largest
  /// record-type partition.
  (String, Type, Object)? _fairSiteAndTypeVictim({
    required (String, Type, Object) keep,
  }) {
    String? victimSite;
    var victimShare = 0;
    var victimUse = 0;
    for (final MapEntry(key: siteUrl, value: types) in _partitions.entries) {
      int? oldestUse;
      for (final partition in types.values) {
        final use = _oldestEvictableIn(partition, keep: keep)?.lastUse;
        if (use != null && (oldestUse == null || use < oldestUse)) {
          oldestUse = use;
        }
      }
      if (oldestUse == null) continue;
      final share = _siteLength(siteUrl);
      if (victimSite == null ||
          _yieldsFirst(share, oldestUse, victimShare, victimUse)) {
        victimSite = siteUrl;
        victimShare = share;
        victimUse = oldestUse;
      }
    }
    return victimSite == null
        ? null
        : _fairTypeVictim(keep: keep, siteUrl: victimSite);
  }

  /// A larger share yields first; equal shares fall back to the
  /// least-recently-used order of their oldest candidates.
  static bool _yieldsFirst(int share, int use, int thanShare, int thanUse) =>
      share > thanShare || (share == thanShare && use < thanUse);

  bool _evict((String, Type, Object)? key) {
    if (key == null) return false;
    final evicted = _removeRef(key);
    if (evicted == null) return false;
    _evictions++;
    if (evicted.value != null) {
      _recordEvictions++;
      _bump(key.$1, key.$2);
    }
    return true;
  }

  void _hold((String, Type, Object) key, Ref<Object> ref) {
    final slot = _Slot(key, ref, ++_uses);
    _refs[key] = slot;
    ((_partitions[key.$1] ??= {})[key.$2] ??= LinkedList()).add(slot);
    _entriesBySite[key.$1] = (_entriesBySite[key.$1] ?? 0) + 1;
  }

  Ref<Object>? _removeRef((String, Type, Object) key) {
    final removed = _refs.remove(key);
    if (removed == null) return null;
    final types = _partitions[key.$1]!;
    final partition = removed.list!;
    removed.unlink();
    if (partition.isEmpty) types.remove(key.$2);
    final siteCount = _entriesBySite[key.$1]! - 1;
    if (siteCount == 0) {
      _entriesBySite.remove(key.$1);
      _partitions.remove(key.$1);
    } else {
      _entriesBySite[key.$1] = siteCount;
    }
    return removed.ref;
  }

  void forget(String siteUrl) {
    final _ = _generations.removeWhere((key, _) => key.$1 == siteUrl);
    _entriesBySite.remove(siteUrl);
    _partitions.remove(siteUrl);
    final forgotten = <Ref<Object>>[];
    _refs.removeWhere((key, slot) {
      if (key.$1 != siteUrl) return false;
      forgotten.add(slot.ref);
      return true;
    });
    // Detach every ref before notifying. A listener may synchronously look up
    // another record, and mutating a map from inside removeWhere would throw.
    for (final ref in forgotten) {
      ref._set(null);
    }
  }

  @visibleForTesting
  int get length => _refs.length;

  @visibleForTesting
  StoreStatistics get statisticsForTesting {
    var records = 0;
    var observedEntries = 0;
    for (final slot in _refs.values) {
      if (slot.ref.value != null) records++;
      if (slot.ref._isObserved) observedEntries++;
    }
    return StoreStatistics(
      entries: _refs.length,
      records: records,
      observedEntries: observedEntries,
      evictions: _evictions,
      recordEvictions: _recordEvictions,
      policy: policy,
      entriesBySite: Map.unmodifiable(_entriesBySite),
      entriesByPartition: Map.unmodifiable({
        for (final MapEntry(key: siteUrl, value: types) in _partitions.entries)
          for (final MapEntry(key: type, value: partition) in types.entries)
            (siteUrl: siteUrl, type: type): partition.length,
      }),
    );
  }
}
