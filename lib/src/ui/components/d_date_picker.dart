import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

final _dateFormattingInitialization = initializeDateFormatting();

/// Converts between a displayed date string and a date-only [DateTime].
///
/// Implementations must return a local civil date with its time fields cleared.
/// A date-only value is not an instant and must not be converted with
/// [DateTime.toUtc]. Application adapters remain responsible for resolving a
/// chosen day and time in the site's timezone, including daylight-saving gaps.
abstract interface class DDateTextCodec {
  const DDateTextCodec();

  String format(DateTime date, Locale locale);

  DateTime? tryParse(String text, Locale locale);
}

/// Locale-aware strict date formatting for editable date-picker fields.
///
/// The default display matches the documented shadcn input example
/// (`June 01, 2025`). Parsing also accepts the locale's short date form and an
/// unambiguous ISO civil date. Impossible dates such as February 29, 2025 are
/// rejected instead of being normalized into March.
class DIntlDateTextCodec implements DDateTextCodec {
  const DIntlDateTextCodec({
    this.formatPattern = 'MMMM dd, y',
    this.additionalParsePatterns = const <String>[],
    this.useLocaleDateOrder = true,
  });

  final String formatPattern;
  final List<String> additionalParsePatterns;
  final bool useLocaleDateOrder;

  @override
  String format(DateTime date, Locale locale) {
    _ensureDateFormattingInitialized();
    final localeName = _localeName(locale);
    final format = useLocaleDateOrder && locale.languageCode != 'en'
        ? DateFormat.yMMMMd(localeName)
        : DateFormat(formatPattern, localeName);
    return format.format(_dateOnly(date));
  }

  @override
  DateTime? tryParse(String text, Locale locale) {
    _ensureDateFormattingInitialized();
    final value = text.trim();
    if (value.isEmpty) return null;
    final localeName = _localeName(locale);
    final formats = <DateFormat>[
      DateFormat(formatPattern, localeName),
      DateFormat.yMd(localeName),
      DateFormat('yyyy-MM-dd', localeName),
      DateFormat('MMM dd, y', localeName),
      for (final pattern in additionalParsePatterns)
        DateFormat(pattern, localeName),
    ];
    for (final format in formats) {
      try {
        return _dateOnly(format.parseStrict(value));
      } on FormatException {
        // Try the next explicitly supported representation.
      }
    }
    return null;
  }
}

/// Parses natural-language input relative to an explicit clock value.
///
/// Requiring [reference] makes examples and tests deterministic. Results are
/// civil dates; parsers do not invent a timezone or preserve a wall-clock time.
abstract interface class DNaturalDateParser {
  const DNaturalDateParser();

  DateTime? tryParse(
    String text, {
    required DateTime reference,
    required Locale locale,
  });
}

/// A deterministic English natural-date adapter with strict explicit-date
/// fallback.
///
/// Supported phrases are `today`, `tomorrow`, `yesterday`, `next week`,
/// `next month`, `next year`, `in N days/weeks/months/years`, and
/// `this|next <weekday>`. Applications needing a richer vocabulary or another
/// language can supply their own [DNaturalDateParser] without changing picker
/// state or presentation.
class DEnglishNaturalDateParser implements DNaturalDateParser {
  const DEnglishNaturalDateParser({
    this.explicitDateCodec = const DIntlDateTextCodec(),
  });

  final DDateTextCodec explicitDateCodec;

  @override
  DateTime? tryParse(
    String text, {
    required DateTime reference,
    required Locale locale,
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final explicit = explicitDateCodec.tryParse(raw, locale);
    if (explicit != null) return explicit;
    if (locale.languageCode.toLowerCase() != 'en') return null;

    final input = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[,!.]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final today = _dateOnly(reference);
    switch (input) {
      case 'today':
        return today;
      case 'tomorrow':
        return _addDays(today, 1);
      case 'day after tomorrow':
        return _addDays(today, 2);
      case 'yesterday':
        return _addDays(today, -1);
      case 'next week':
        return _addDays(today, 7);
      case 'next month':
        return _addMonths(today, 1);
      case 'next year':
        return _addYears(today, 1);
    }

    final relative = RegExp(
      r'^in\s+(\d+)\s+(day|days|week|weeks|month|months|year|years)$',
    ).firstMatch(input);
    if (relative != null) {
      final amount = int.parse(relative.group(1)!);
      if (amount > 10000) return null;
      final result = switch (relative.group(2)!) {
        'day' || 'days' => _addDays(today, amount),
        'week' || 'weeks' => _addDays(today, amount * 7),
        'month' || 'months' => _addMonths(today, amount),
        'year' || 'years' => _addYears(today, amount),
        _ => null,
      };
      return result != null && result.year <= 9999 ? result : null;
    }

    final weekday = RegExp(
      r'^(this|next)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$',
    ).firstMatch(input);
    if (weekday != null) {
      final target = _weekdays[weekday.group(2)!]!;
      var days = (target - today.weekday) % 7;
      if (weekday.group(1) == 'next' && days == 0) days = 7;
      return _addDays(today, days);
    }
    return null;
  }
}

/// A validated wall-clock time used by Date Picker's time composition.
///
/// It intentionally contains no date or timezone. Resolve it in an application
/// timezone adapter so nonexistent and ambiguous daylight-saving times can be
/// handled using domain policy rather than silently normalized by [DateTime].
@immutable
class DTimeValue {
  const DTimeValue({required this.hour, required this.minute, this.second = 0})
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59),
      assert(second >= 0 && second <= 59);

  factory DTimeValue.fromTimeOfDay(TimeOfDay value, {int second = 0}) =>
      DTimeValue(hour: value.hour, minute: value.minute, second: second);

  static DTimeValue? tryParse(String text) {
    final match = RegExp(
      r'^(?:([01]\d|2[0-3])):([0-5]\d)(?::([0-5]\d))?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    return DTimeValue(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
      second: int.tryParse(match.group(3) ?? '') ?? 0,
    );
  }

  final int hour;
  final int minute;
  final int second;

  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  String format({bool includeSeconds = true}) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(hour)}:${two(minute)}'
        '${includeSeconds ? ':${two(second)}' : ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is DTimeValue &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

String _localeName(Locale locale) =>
    locale.toLanguageTag().replaceAll('-', '_');

void _ensureDateFormattingInitialized() {
  // initializeDateFormatting installs the bundled symbol tables synchronously;
  // its Future only preserves the cross-platform loader contract.
  unawaited(_dateFormattingInitialization);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

DateTime _addMonths(DateTime date, int months) {
  final zeroBased = date.month - 1 + months;
  final year = date.year + zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  final day = date.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, day);
}

DateTime _addYears(DateTime date, int years) {
  final year = date.year + years;
  final day = date.day.clamp(1, _daysInMonth(year, date.month));
  return DateTime(year, date.month, day);
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

const _weekdays = <String, int>{
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};
