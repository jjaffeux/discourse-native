import 'package:flutter/foundation.dart';

import 'json.dart';

/// Minutes after midnight in the account's zone; Monday is day zero in core.
typedef NotificationWindow = ({int start, int end});

@immutable
final class NotificationSchedule {
  NotificationSchedule({
    required this.enabled,
    required List<NotificationWindow> days,
  }) : assert(days.length == 7),
       days = List.unmodifiable(days),
       wireValues = Map.unmodifiable({
         'enabled': enabled,
         for (var day = 0; day < days.length; day++) ...{
           'day_${day}_start_time': days[day].start,
           'day_${day}_end_time': days[day].end,
         },
       });

  factory NotificationSchedule.initial() => NotificationSchedule(
    enabled: false,
    days: List.filled(7, (start: 540, end: 1080)),
  );

  static NotificationSchedule? read(Object? value) {
    final fields = jsonObjectFields(value);
    if (fields == null || fields['enabled'] is! bool) return null;
    final days = <NotificationWindow>[];
    for (var day = 0; day < 7; day++) {
      final start = jsonIntOrNull(fields['day_${day}_start_time']);
      final end = jsonIntOrNull(fields['day_${day}_end_time']);
      if (start == null ||
          end == null ||
          start < -1 ||
          start > 1410 ||
          end < -1 ||
          end > 1440 ||
          start > end) {
        return null;
      }
      days.add((start: start, end: end));
    }
    return NotificationSchedule(enabled: fields['enabled'] as bool, days: days);
  }

  final bool enabled;
  final List<NotificationWindow> days;
  final Map<String, Object?> wireValues;

  List<int> get activeDays => [
    for (var i = 0; i < 7; i++)
      if (days[i].start >= 0) i,
  ];

  NotificationSchedule copyWith({
    bool? enabled,
    List<NotificationWindow>? days,
  }) => NotificationSchedule(
    enabled: enabled ?? this.enabled,
    days: days ?? this.days,
  );

  @override
  bool operator ==(Object other) =>
      other is NotificationSchedule &&
      enabled == other.enabled &&
      listEquals(days, other.days);

  @override
  int get hashCode => Object.hash(enabled, Object.hashAll(days));
}
