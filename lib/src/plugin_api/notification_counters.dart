import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

import '../models/json.dart';
import 'preserved_json.dart';

/// The identity is independent of the server field name so a plugin may own
/// wire migrations without teaching core about the feature.
@immutable
final class PluginNotificationCounterId {
  const PluginNotificationCounterId({required this.owner, required this.name});

  final PluginId owner;
  final String name;

  String get id => '${owner.value}/$name';

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationCounterId &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => id;
}

@immutable
final class PluginNotificationCounter {
  const PluginNotificationCounter({
    required this.id,
    required this.wireName,
    this.contributesToBadge = true,
  });

  final PluginNotificationCounterId id;
  final String wireName;
  final bool contributesToBadge;

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationCounter &&
      other.id == id &&
      other.wireName == wireName &&
      other.contributesToBadge == contributesToBadge;

  @override
  int get hashCode => Object.hash(id, wireName, contributesToBadge);
}

@immutable
final class PluginNotificationCounterState {
  const PluginNotificationCounterState({
    required this.counter,
    required this.count,
    required this.available,
  });

  final PluginNotificationCounter counter;
  final int count;

  /// Zero is a valid available count. Absence is kept separately so plugin UI
  /// does not accidentally advertise a feature which this site did not send.
  final bool available;

  @override
  bool operator ==(Object other) =>
      other is PluginNotificationCounterState &&
      other.counter == counter &&
      other.count == count &&
      other.available == available;

  @override
  int get hashCode => Object.hash(counter, count, available);
}

@immutable
final class PluginNotificationCounters {
  const PluginNotificationCounters._(this._states, this._preservedNamespaces);

  static const PluginNotificationCounters none = PluginNotificationCounters._(
    <PluginNotificationCounterId, PluginNotificationCounterState>{},
    <String, Object?>{},
  );

  final Map<PluginNotificationCounterId, PluginNotificationCounterState>
  _states;
  final Map<String, Object?> _preservedNamespaces;

  factory PluginNotificationCounters.fromLive(
    Iterable<PluginNotificationCounter> counters,
    Map<String, dynamic> json,
  ) {
    final states =
        <PluginNotificationCounterId, PluginNotificationCounterState>{};
    for (final counter in counters) {
      final parsed = jsonIntOrNull(json[counter.wireName]);
      states[counter.id] = PluginNotificationCounterState(
        counter: counter,
        count: _count(parsed),
        available: parsed != null,
      );
    }
    return _from(states, const {});
  }

  factory PluginNotificationCounters.fromStored(
    Iterable<PluginNotificationCounter> counters,
    Object? value,
  ) {
    final preserved = preserveJsonNamespaces(value);
    final states =
        <PluginNotificationCounterId, PluginNotificationCounterState>{};
    for (final counter in counters) {
      final hasValue = preserved.containsKey(counter.id.id);
      final parsed = jsonIntOrNull(preserved.remove(counter.id.id));
      states[counter.id] = PluginNotificationCounterState(
        counter: counter,
        count: _count(parsed),
        available: hasValue && parsed != null,
      );
    }
    return _from(states, preserved);
  }

  factory PluginNotificationCounters.single(
    PluginNotificationCounter counter, {
    int count = 0,
    bool available = true,
  }) => _from({
    counter.id: PluginNotificationCounterState(
      counter: counter,
      count: _count(count),
      available: available,
    ),
  }, const {});

  factory PluginNotificationCounters.preserveNamespaces(Object? value) {
    final preserved = preserveJsonNamespaces(value);
    return preserved.isEmpty ? none : _from(const {}, preserved);
  }

  PluginNotificationCounterState? state(PluginNotificationCounterId id) =>
      _states[id];

  int count(PluginNotificationCounterId id) => _states[id]?.count ?? 0;

  bool isAvailable(PluginNotificationCounterId id) =>
      _states[id]?.available ?? false;

  bool get isEmpty => _states.isEmpty && _preservedNamespaces.isEmpty;

  int get badge => _states.values.fold(
    0,
    (sum, state) =>
        sum +
        (state.available && state.counter.contributesToBadge ? state.count : 0),
  );

  /// Presence is response-authoritative. A delta arriving before the first
  /// response updates the held count but must not advertise the feature.
  PluginNotificationCounters update(
    PluginNotificationCounter counter,
    int Function(int current) reduce,
  ) {
    final held = _states[counter.id];
    final updated = _count(reduce(held?.count ?? 0));
    final states =
        Map<PluginNotificationCounterId, PluginNotificationCounterState>.of(
          _states,
        );
    states[counter.id] = PluginNotificationCounterState(
      counter: counter,
      count: updated,
      available: held?.available ?? false,
    );
    return _from(states, _preservedNamespaces);
  }

  /// Response presence is authoritative. A count changed since [before]
  /// remains live; otherwise the response wins.
  static PluginNotificationCounters mergeRefresh({
    required PluginNotificationCounters response,
    required PluginNotificationCounters before,
    required PluginNotificationCounters live,
  }) {
    final states =
        <PluginNotificationCounterId, PluginNotificationCounterState>{};
    for (final responseState in response._states.values) {
      final id = responseState.counter.id;
      final beforeCount = before.count(id);
      final liveCount = live.count(id);
      states[id] = PluginNotificationCounterState(
        counter: responseState.counter,
        count: liveCount != beforeCount ? liveCount : responseState.count,
        available: responseState.available,
      );
    }

    final preserved = <String, Object?>{
      ...before._preservedNamespaces,
      ...live._preservedNamespaces,
      ...response._preservedNamespaces,
    };
    return _from(states, preserved);
  }

  Map<String, Object?> toStored(
    Iterable<PluginNotificationCounter> installedCounters,
  ) {
    final result = Map<String, Object?>.of(_preservedNamespaces);
    for (final counter in installedCounters) {
      result.remove(counter.id.id);
      final state = _states[counter.id];
      if (state?.available ?? false) result[counter.id.id] = state!.count;
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  static PluginNotificationCounters _from(
    Map<PluginNotificationCounterId, PluginNotificationCounterState> states,
    Map<String, Object?> preserved,
  ) {
    if (states.isEmpty && preserved.isEmpty) return none;
    return PluginNotificationCounters._(
      Map<
        PluginNotificationCounterId,
        PluginNotificationCounterState
      >.unmodifiable(states),
      Map<String, Object?>.unmodifiable(preserved),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginNotificationCounters &&
          mapEquals(other._states, _states) &&
          deepJsonEquals(other._preservedNamespaces, _preservedNamespaces);

  @override
  int get hashCode => Object.hashAllUnordered([
    ..._states.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ..._preservedNamespaces.entries.map(
      (entry) => Object.hash(entry.key, deepJsonHash(entry.value)),
    ),
  ]);
}

abstract interface class PluginNotificationCounterCodec {
  List<PluginNotificationCounter> get notificationCounters;

  PluginNotificationCounters readLiveNotificationCounters(
    Map<String, dynamic> json,
  );

  PluginNotificationCounters readStoredNotificationCounters(Object? value);

  Map<String, Object?> writeStoredNotificationCounters(
    PluginNotificationCounters counters,
  );
}

final class EmptyPluginNotificationCounterCodec
    implements PluginNotificationCounterCodec {
  const EmptyPluginNotificationCounterCodec();

  @override
  List<PluginNotificationCounter> get notificationCounters => const [];

  @override
  PluginNotificationCounters readLiveNotificationCounters(
    Map<String, dynamic> json,
  ) => PluginNotificationCounters.none;

  @override
  PluginNotificationCounters readStoredNotificationCounters(Object? value) =>
      PluginNotificationCounters.preserveNamespaces(value);

  @override
  Map<String, Object?> writeStoredNotificationCounters(
    PluginNotificationCounters counters,
  ) => counters.toStored(const []);
}

int _count(int? value) => value == null || value < 0 ? 0 : value;
