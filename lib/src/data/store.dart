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

  final LinkedHashMap<(String, Type, Object), Ref<Object>> _refs =
      LinkedHashMap();

  final Map<(String, Type), int> _generations = {};
  final Map<String, int> _entriesBySite = {};
  final Map<(String, Type), int> _entriesByPartition = {};

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
      _touch(key, held);
      return held as Ref<T>;
    }

    final created = Ref<T>._(null);
    _refs[key] = created;
    _incrementCounts(key);
    _trim(keep: key);
    return created;
  }

  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    final key = (siteUrl, T, id);
    final cell = _refs[key] as Ref<T>?;
    if (cell != null) _touch(key, cell);
    return cell?.value;
  }

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
    final cell = _refs[(siteUrl, T, id)] as Ref<T>?;
    final held = cell?.value;
    if (cell == null || held == null) return;
    final next = change(held);
    if (!identical(held, next)) _bump(siteUrl, T);
    cell._set(next);
  }

  void remove<T extends Storable<T>>(String siteUrl, Object id) {
    final key = (siteUrl, T, id);
    final cell = _refs[key] as Ref<T>?;
    if (cell?.value != null) _bump(siteUrl, T);
    cell?._set(null);
    if (cell != null && !cell._isObserved) _removeRef(key);
  }

  void _touch((String, Type, Object) key, Ref<Object> ref) {
    _refs.remove(key);
    _refs[key] = ref;
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
      _entriesByPartition[(siteUrl, type)] ?? 0;

  (String, Type, Object)? _oldestEvictable({
    required (String, Type, Object) keep,
    String? siteUrl,
    Type? type,
  }) {
    for (final entry in _refs.entries) {
      final key = entry.key;
      if (key == keep || entry.value._isObserved) continue;
      if (siteUrl != null && key.$1 != siteUrl) continue;
      if (type != null && key.$2 != type) continue;
      return key;
    }
    return null;
  }

  (String, Type, Object)? _fairTypeVictim({
    required (String, Type, Object) keep,
    required String siteUrl,
  }) {
    final totals = <Type, int>{};
    final candidates = <Type, (String, Type, Object)>{};
    for (final entry in _refs.entries) {
      final key = entry.key;
      if (key.$1 != siteUrl) continue;
      totals[key.$2] = (totals[key.$2] ?? 0) + 1;
      if (key != keep &&
          !entry.value._isObserved &&
          !candidates.containsKey(key.$2)) {
        candidates[key.$2] = key;
      }
    }
    return _largestPartitionCandidate(totals, candidates);
  }

  (String, Type, Object)? _fairSiteAndTypeVictim({
    required (String, Type, Object) keep,
  }) {
    final totals = <String, int>{};
    final oldestCandidates = <String, (String, Type, Object)>{};
    for (final entry in _refs.entries) {
      final key = entry.key;
      totals[key.$1] = (totals[key.$1] ?? 0) + 1;
      if (key != keep &&
          !entry.value._isObserved &&
          !oldestCandidates.containsKey(key.$1)) {
        oldestCandidates[key.$1] = key;
      }
    }
    final site = _largestCandidate(totals, oldestCandidates);
    return site == null ? null : _fairTypeVictim(keep: keep, siteUrl: site);
  }

  (String, Type, Object)? _largestPartitionCandidate(
    Map<Type, int> totals,
    Map<Type, (String, Type, Object)> candidates,
  ) {
    final type = _largestCandidate(totals, candidates);
    return type == null ? null : candidates[type];
  }

  K? _largestCandidate<K, V>(Map<K, int> totals, Map<K, V> candidates) {
    K? largest;
    var largestCount = -1;
    for (final key in candidates.keys) {
      final count = totals[key] ?? 0;
      if (count > largestCount) {
        largest = key;
        largestCount = count;
      }
    }
    return largest;
  }

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

  void _incrementCounts((String, Type, Object) key) {
    _entriesBySite[key.$1] = (_entriesBySite[key.$1] ?? 0) + 1;
    final partition = (key.$1, key.$2);
    _entriesByPartition[partition] = (_entriesByPartition[partition] ?? 0) + 1;
  }

  Ref<Object>? _removeRef((String, Type, Object) key) {
    final removed = _refs.remove(key);
    if (removed == null) return null;
    _decrementCounts(key);
    return removed;
  }

  void _decrementCounts((String, Type, Object) key) {
    final siteCount = _entriesBySite[key.$1]! - 1;
    if (siteCount == 0) {
      _entriesBySite.remove(key.$1);
    } else {
      _entriesBySite[key.$1] = siteCount;
    }
    final partition = (key.$1, key.$2);
    final partitionCount = _entriesByPartition[partition]! - 1;
    if (partitionCount == 0) {
      _entriesByPartition.remove(partition);
    } else {
      _entriesByPartition[partition] = partitionCount;
    }
  }

  void forget(String siteUrl) {
    final _ = _generations.removeWhere((key, _) => key.$1 == siteUrl);
    final forgotten = <Ref<Object>>[];
    _refs.removeWhere((key, ref) {
      if (key.$1 != siteUrl) return false;
      forgotten.add(ref);
      _decrementCounts(key);
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
    for (final entry in _refs.entries) {
      if (entry.value.value != null) records++;
      if (entry.value._isObserved) observedEntries++;
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
        for (final entry in _entriesByPartition.entries)
          (siteUrl: entry.key.$1, type: entry.key.$2): entry.value,
      }),
    );
  }
}
