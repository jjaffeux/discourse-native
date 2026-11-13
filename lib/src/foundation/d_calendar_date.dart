import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

/// A date without a time-of-day or timezone.
///
/// An instant must be converted with [DCalendarDate.fromInstant]. A selected
/// day exposes [dateTimeUtc] for calendar arithmetic.
@immutable
class DCalendarDate implements Comparable<DCalendarDate> {
  DCalendarDate(int year, int month, int day)
    : _value = DateTime.utc(year, month, day) {
    if (_value.year != year || _value.month != month || _value.day != day) {
      throw ArgumentError.value('$year-$month-$day', 'date', 'Invalid date');
    }
  }

  const DCalendarDate._(this._value);

  factory DCalendarDate.fromDateTime(DateTime value) =>
      DCalendarDate(value.year, value.month, value.day);

  factory DCalendarDate.fromInstant(DateTime instant, tz.Location location) {
    final local = tz.TZDateTime.from(instant, location);
    return DCalendarDate(local.year, local.month, local.day);
  }

  final DateTime _value;
  int get year => _value.year;
  int get month => _value.month;
  int get day => _value.day;
  int get weekday => _value.weekday;

  DCalendarDate addDays(int days) =>
      DCalendarDate._(_value.add(Duration(days: days)));

  DCalendarDate addMonths(int months) {
    final first = DateTime.utc(year, month + months);
    final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
    return DCalendarDate(first.year, first.month, math.min(day, lastDay));
  }

  DateTime get dateTimeUtc => _value;

  @override
  int compareTo(DCalendarDate other) => _value.compareTo(other._value);
  bool isBefore(DCalendarDate other) => compareTo(other) < 0;
  bool isAfter(DCalendarDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is DCalendarDate && other._value == _value;
  @override
  int get hashCode => _value.hashCode;
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
