import 'package:flutter/foundation.dart';

import 'json.dart';
import 'notification.dart';

@immutable
final class NotificationTypeCounts {
  const NotificationTypeCounts._(this._counts, this._total);

  final Map<NotificationTypeId, int>? _counts;
  final int _total;

  static const unavailable = NotificationTypeCounts._(null, 0);

  static const empty = NotificationTypeCounts._(<NotificationTypeId, int>{}, 0);

  factory NotificationTypeCounts.fromWire(Object? value) {
    if (value is! Map) return unavailable;

    final counts = <NotificationTypeId, int>{};
    for (final entry in value.entries) {
      final id = jsonIntOrNull(entry.key);
      final count = jsonIntOrNull(entry.value);
      if (id == null || id <= 0 || count == null) continue;
      counts[NotificationTypeId(id)] = count < 0 ? 0 : count;
    }
    return counts.isEmpty
        ? empty
        : NotificationTypeCounts._(
            Map<NotificationTypeId, int>.unmodifiable(counts),
            counts.values.fold(0, (total, count) => total + count),
          );
  }

  bool get isAvailable => _counts != null;

  int count(NotificationWireType type) =>
      _counts?[NotificationTypeId(type.wireId)] ?? 0;

  int totalExcluding(Iterable<NotificationTypeId> excluded) {
    final counts = _counts;
    if (counts == null) return 0;
    if (excluded.isEmpty) return _total;
    final omitted = excluded.toSet();
    var total = _total;
    for (final id in omitted) {
      total -= counts[id] ?? 0;
    }
    return total;
  }

  Map<String, int>? toJson() {
    final counts = _counts;
    if (counts == null) return null;
    return Map.unmodifiable({
      for (final entry in counts.entries) '${entry.key.value}': entry.value,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationTypeCounts && mapEquals(other._counts, _counts);

  @override
  int get hashCode => _counts == null
      ? 0
      : Object.hashAllUnordered(
          _counts.entries.map((entry) => Object.hash(entry.key, entry.value)),
        );
}
