import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:relative_time/relative_time.dart';
import 'package:timezone/timezone.dart' as tz;

import 'local_date_environment.dart';

final RegExp _wallDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _wallTimePattern = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');
final RegExp _recurrencePattern = RegExp(
  r'^(\d+)\.(years?|quarters?|months?|weeks?|days?|hours?|minutes?|seconds?|milliseconds?)$',
);

/// The immutable meaning of one server-cooked `span.discourse-local-date`.
///
/// Strings are retained instead of eagerly parsing them so malformed or
/// forward-compatible markup can fall back to the server's cooked text.
@immutable
class LocalDateSpec {
  const LocalDateSpec({
    required this.date,
    required this.fallbackText,
    this.time,
    this.timezone,
    this.range,
    this.format,
    this.calendar,
    this.recurring,
    this.countdown = false,
    this.displayedTimezone,
    this.timezones = const [],
    this.ics,
  });

  factory LocalDateSpec.fromDataAttributes(
    Map<String, String> attributes, {
    required String fallbackText,
  }) {
    String? data(String name) => attributes['data-$name'];
    final rawCalendar = data('calendar');
    final rawCountdown = data('countdown');
    return LocalDateSpec(
      date: data('date') ?? '',
      fallbackText: fallbackText,
      time: _nonEmpty(data('time')),
      timezone: _nonEmpty(data('timezone')),
      range: _nonEmpty(data('range')),
      format: _nonEmpty(data('format')),
      calendar: switch (rawCalendar) {
        'on' => true,
        'off' => false,
        _ => null,
      },
      recurring: _nonEmpty(data('recurring')),
      countdown:
          rawCountdown != null &&
          !const {'false', 'off', '0'}.contains(rawCountdown.toLowerCase()),
      displayedTimezone: _nonEmpty(data('displayed-timezone')),
      timezones: List.unmodifiable(
        (data('timezones') ?? '')
            .split('|')
            .map((zone) => zone.trim())
            .where((zone) => zone.isNotEmpty),
      ),
      ics: _nonEmpty(data('ics')),
    );
  }

  final String date;
  final String fallbackText;
  final String? time;
  final String? timezone;
  final String? range;
  final String? format;
  final bool? calendar;
  final String? recurring;
  final bool countdown;
  final String? displayedTimezone;
  final List<String> timezones;

  /// Retained for compatibility. Native calendar export is intentionally not
  /// an action offered by this change.
  final String? ics;

  bool get hasTime => time != null;
  bool get usesCalendar => calendar ?? format == null;

  @override
  bool operator ==(Object other) =>
      other is LocalDateSpec &&
      other.date == date &&
      other.fallbackText == fallbackText &&
      other.time == time &&
      other.timezone == timezone &&
      other.range == range &&
      other.format == format &&
      other.calendar == calendar &&
      other.recurring == recurring &&
      other.countdown == countdown &&
      other.displayedTimezone == displayedTimezone &&
      listEquals(other.timezones, timezones) &&
      other.ics == ics;

  @override
  int get hashCode => Object.hash(
    date,
    fallbackText,
    time,
    timezone,
    range,
    format,
    calendar,
    recurring,
    countdown,
    displayedTimezone,
    Object.hashAll(timezones),
    ics,
  );
}

@immutable
class LocalDateResolved {
  const LocalDateResolved({
    required this.spec,
    required this.source,
    required this.displayed,
    required this.readerTimezone,
    required this.sourceTimezone,
    required this.displayedTimezone,
    required this.formatted,
    required this.past,
  });

  final LocalDateSpec spec;
  final tz.TZDateTime source;
  final tz.TZDateTime displayed;
  final String readerTimezone;
  final String sourceTimezone;
  final String displayedTimezone;
  final String formatted;
  final bool past;
}

@immutable
class LocalDatePreview {
  const LocalDatePreview({
    required this.timezone,
    required this.label,
    required this.formatted,
    this.current = false,
    this.source = false,
  });

  final String timezone;
  final String label;
  final String formatted;
  final bool current;
  final bool source;
}

/// Strict, DST-aware resolution and Moment-compatible display formatting.
class LocalDateFormatter {
  const LocalDateFormatter({required this.environment});

  final LocalDateEnvironment environment;

  LocalDateResolved? resolve(
    LocalDateSpec spec, {
    required Locale locale,
    String? accountTimezone,
    DateTime? now,
    bool sameLocalDayAsFrom = false,
  }) {
    final sourceName = environment.canonicalTimezone(spec.timezone ?? 'UTC');
    if (sourceName == null) return null;
    final sourceLocation = environment.location(sourceName);
    if (sourceLocation == null) return null;

    final parts = _parseWallTime(spec);
    if (parts == null) return null;
    var source = tz.TZDateTime(
      sourceLocation,
      parts.year,
      parts.month,
      parts.day,
      parts.hour,
      parts.minute,
      parts.second,
    );
    // timezone normalizes a nonexistent DST wall time. Treat normalization as
    // invalid instead of silently inventing a different instant.
    if (!_sameWallTime(source, parts)) return null;

    final instantNow = now ?? DateTime.now();
    if (spec.recurring != null && source.isBefore(instantNow)) {
      source = _advanceRecurring(source, spec.recurring!, instantNow) ?? source;
    }

    final readerName = environment.readerTimezone(accountTimezone);
    final displayedName = environment.canonicalTimezone(
      spec.displayedTimezone ?? (spec.hasTime ? readerName : sourceName),
    );
    if (displayedName == null) return null;
    final displayedLocation = environment.location(displayedName);
    if (displayedLocation == null) return null;
    final displayed = tz.TZDateTime.from(source, displayedLocation);
    final formatted = _formatResolved(
      spec,
      source: source,
      displayed: displayed,
      readerName: readerName,
      displayedName: displayedName,
      locale: locale,
      now: instantNow,
      sameLocalDayAsFrom: sameLocalDayAsFrom,
    );
    return LocalDateResolved(
      spec: spec,
      source: source,
      displayed: displayed,
      readerTimezone: readerName,
      sourceTimezone: sourceName,
      displayedTimezone: displayedName,
      formatted: formatted,
      past: spec.recurring == null && source.isBefore(instantNow),
    );
  }

  List<LocalDatePreview> previews(
    LocalDateSpec spec, {
    required Locale locale,
    String? accountTimezone,
    Iterable<String> defaultTimezones = const [],
    DateTime? now,
  }) {
    final resolved = resolve(
      spec,
      locale: locale,
      accountTimezone: accountTimezone,
      now: now,
    );
    if (resolved == null) return const [];

    final requested = spec.timezones.isEmpty
        ? defaultTimezones
        : spec.timezones;
    final zones = [
      resolved.readerTimezone,
      resolved.sourceTimezone,
    ].followedBy(requested);
    final seenZones = <String>{};
    final seenOffsets = <String>{};
    final previews = <LocalDatePreview>[];
    for (final requestedZone in zones) {
      final zone = environment.canonicalTimezone(requestedZone);
      if (zone == null || !seenZones.add(zone)) continue;
      final location = environment.location(zone);
      if (location == null) continue;
      final value = tz.TZDateTime.from(resolved.source, location);
      // Match web's useful de-duplication: canonical identity first, then the
      // same abbreviation/offset at the event instant.
      final key = '${value.timeZoneOffset.inMinutes}/${value.timeZoneName}';
      if (!seenOffsets.add(key) && zone != resolved.sourceTimezone) continue;
      previews.add(
        LocalDatePreview(
          timezone: zone,
          label: zoneLabel(zone),
          formatted: formatMoment(value, 'LLLL', locale),
          current: zone == resolved.readerTimezone,
          source: zone == resolved.sourceTimezone,
        ),
      );
    }
    return List.unmodifiable(previews);
  }

  String _formatResolved(
    LocalDateSpec spec, {
    required tz.TZDateTime source,
    required tz.TZDateTime displayed,
    required String readerName,
    required String displayedName,
    required Locale locale,
    required DateTime now,
    required bool sameLocalDayAsFrom,
  }) {
    if (spec.countdown) {
      if (!source.isAfter(now)) {
        final l10n = RelativeTime.locale(locale).localizations;
        return l10n.secondsPast(0, l10n.digit0, 'false');
      }
      return _countdown(source.difference(now));
    }

    if (sameLocalDayAsFrom) {
      return '${formatMoment(displayed, 'LT', locale)} '
          '(${zoneLabel(displayedName)})';
    }

    final readerLocation = environment.location(readerName)!;
    final readerNow = tz.TZDateTime.from(now, readerLocation);
    final sameReaderZone = _zonesEquivalent(displayedName, readerName, source);
    if (spec.usesCalendar && sameReaderZone) {
      final days = _calendarDayDifference(displayed, readerNow);
      if (days >= -1 && days <= 1) {
        if (spec.hasTime && displayed.hour == 0 && displayed.minute == 0) {
          return DateFormat.EEEE(_localeName(locale)).format(displayed);
        }
        final natural = _relativeDay(locale, days);
        return spec.hasTime
            ? '$natural ${formatMoment(displayed, 'LT', locale)}'
            : natural;
      }
    }

    final format = spec.format ?? (spec.hasTime ? 'LLL' : 'LL');
    final result = formatMoment(displayed, format, locale);
    if (!sameReaderZone) return '$result (${zoneLabel(displayedName)})';
    return result;
  }

  bool _zonesEquivalent(String a, String b, tz.TZDateTime instant) {
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final aDate = tz.TZDateTime.from(instant, environment.location(a)!);
    final bDate = tz.TZDateTime.from(instant, environment.location(b)!);
    return aDate.timeZoneOffset == bDate.timeZoneOffset;
  }

  static String zoneLabel(String timezone) {
    final withoutPrefix = timezone.replaceFirst('Etc/', '');
    final parts = withoutPrefix.split('/');
    return parts.last.replaceAll('_', ' ');
  }

  static String formatMoment(DateTime value, String format, Locale locale) {
    final localeName = _localeName(locale);
    final aliases = <String, String Function()>{
      'LT': () => DateFormat.jm(localeName).format(value),
      'LTS': () => DateFormat.jms(localeName).format(value),
      'L': () => DateFormat.yMd(localeName).format(value),
      'l': () => DateFormat.yMd(localeName).format(value),
      'LL': () => DateFormat.yMMMMd(localeName).format(value),
      'll': () => DateFormat.yMMMd(localeName).format(value),
      'LLL': () => DateFormat.yMMMMd(localeName).add_jm().format(value),
      'lll': () => DateFormat.yMMMd(localeName).add_jm().format(value),
      'LLLL': () => DateFormat.yMMMMEEEEd(localeName).add_jm().format(value),
      'llll': () => DateFormat.yMMMEd(localeName).add_jm().format(value),
    };
    final wholeAlias = aliases[format];
    if (wholeAlias != null) return wholeAlias();

    final output = StringBuffer();
    var index = 0;
    while (index < format.length) {
      if (format[index] == '[') {
        final end = format.indexOf(']', index + 1);
        if (end == -1) {
          output.write(format.substring(index + 1));
          break;
        }
        output.write(format.substring(index + 1, end));
        index = end + 1;
        continue;
      }
      if (format[index] == r'\' && index + 1 < format.length) {
        output.write(format[index + 1]);
        index += 2;
        continue;
      }
      if (_isAsciiLetter(format.codeUnitAt(index)) &&
          !_tokenLetters.contains(format[index])) {
        var end = index + 1;
        while (end < format.length &&
            _isAsciiLetter(format.codeUnitAt(end)) &&
            !_tokenLetters.contains(format[end])) {
          end += 1;
        }
        // Moment passes a lone unrecognized letter through and keeps
        // formatting the token letters after it (the T in YYYY-MM-DDTHH:mm).
        // A run of two or more unrecognized letters marks a literal word, so
        // the rest of that word stays literal too: unescaped words such as
        // FUTURE must survive intact even when they end in a token letter.
        if (end - index > 1) {
          while (end < format.length &&
              _isAsciiLetter(format.codeUnitAt(end))) {
            end += 1;
          }
        }
        output.write(format.substring(index, end));
        index = end;
        continue;
      }
      final alias = _longestAt(format, index, aliases.keys);
      if (alias != null) {
        output.write(aliases[alias]!());
        index += alias.length;
        continue;
      }
      final compound = _longestAt(format, index, const [
        'DDDo',
        'Do',
        'Qo',
        'wo',
        'Wo',
      ]);
      if (compound != null) {
        output.write(_formatToken(value, compound, localeName));
        index += compound.length;
        continue;
      }
      if (_isAsciiLetter(format.codeUnitAt(index))) {
        var end = index + 1;
        while (end < format.length &&
            format[end] == format[index] &&
            _isAsciiLetter(format.codeUnitAt(end))) {
          end += 1;
        }
        final token = format.substring(index, end);
        output.write(_formatToken(value, token, localeName));
        index = end;
        continue;
      }
      output.write(format[index]);
      index += 1;
    }
    return output.toString();
  }

  static String _formatToken(DateTime value, String token, String locale) {
    String intl(String pattern) => DateFormat(pattern, locale).format(value);
    return switch (token) {
      'Y' || 'YYYY' => intl('yyyy'),
      'YY' => intl('yy'),
      'M' => '${value.month}',
      'MM' => intl('MM'),
      'MMM' => intl('MMM'),
      'MMMM' => intl('MMMM'),
      'D' => '${value.day}',
      'DD' => intl('dd'),
      'Do' => _ordinal(value.day),
      'DDD' => '${_dayOfYear(value)}',
      'DDDD' => _dayOfYear(value).toString().padLeft(3, '0'),
      'DDDo' => _ordinal(_dayOfYear(value)),
      'd' => '${value.weekday % 7}',
      'dd' => intl('EEEEE'),
      'ddd' => intl('EEE'),
      'dddd' => intl('EEEE'),
      'e' => '${value.weekday % 7}',
      'E' => '${value.weekday}',
      'w' || 'W' => '${_isoWeek(value)}',
      'ww' || 'WW' => _isoWeek(value).toString().padLeft(2, '0'),
      'wo' || 'Wo' => _ordinal(_isoWeek(value)),
      'gg' || 'GG' => '${_isoWeekYear(value) % 100}'.padLeft(2, '0'),
      'gggg' || 'GGGG' => '${_isoWeekYear(value)}',
      'Q' => '${((value.month - 1) ~/ 3) + 1}',
      'Qo' => _ordinal(((value.month - 1) ~/ 3) + 1),
      'H' => '${value.hour}',
      'HH' => value.hour.toString().padLeft(2, '0'),
      'h' => '${value.hour % 12 == 0 ? 12 : value.hour % 12}',
      'hh' => (value.hour % 12 == 0 ? 12 : value.hour % 12).toString().padLeft(
        2,
        '0',
      ),
      'k' => '${value.hour == 0 ? 24 : value.hour}',
      'kk' => (value.hour == 0 ? 24 : value.hour).toString().padLeft(2, '0'),
      'm' => '${value.minute}',
      'mm' => value.minute.toString().padLeft(2, '0'),
      's' => '${value.second}',
      'ss' => value.second.toString().padLeft(2, '0'),
      'S' => '${value.millisecond ~/ 100}',
      'SS' => (value.millisecond ~/ 10).toString().padLeft(2, '0'),
      'SSS' => value.millisecond.toString().padLeft(3, '0'),
      'A' => intl('a'),
      'a' => intl('a').toLowerCase(),
      'Z' => _offset(value, colon: true),
      'ZZ' => _offset(value, colon: false),
      'z' || 'zz' => value.timeZoneName,
      'X' => '${value.millisecondsSinceEpoch ~/ 1000}',
      'x' => '${value.millisecondsSinceEpoch}',
      _ => token,
    };
  }

  static String _offset(DateTime value, {required bool colon}) {
    final minutes = value.timeZoneOffset.inMinutes;
    final sign = minutes < 0 ? '-' : '+';
    final absolute = minutes.abs();
    final hour = (absolute ~/ 60).toString().padLeft(2, '0');
    final minute = (absolute % 60).toString().padLeft(2, '0');
    return colon ? '$sign$hour:$minute' : '$sign$hour$minute';
  }

  static String _relativeDay(Locale locale, int difference) {
    final l10n = RelativeTime.locale(locale).localizations;
    return switch (difference) {
      -1 => l10n.daysPast(1, l10n.digit1, 'false'),
      0 => l10n.daysFuture(0, l10n.digit0, 'false'),
      1 => l10n.daysFuture(1, l10n.digit1, 'false'),
      _ => '',
    };
  }

  // Upstream renders countdowns with moment.duration(diff).humanize(): per-
  // unit totals rounded and compared against moment's default thresholds
  // (44s, 45min, 22h, 26d, 11 months, no weeks bucket) with no "in" prefix.
  // The CLDR strings in package:relative_time cannot express that bare form
  // (their numeric variants always carry a prefix), so the moment default-
  // locale strings are emitted directly.
  static String _countdown(Duration duration) {
    final milliseconds = duration.inMilliseconds;
    final seconds = (milliseconds / 1000).round();
    final minutes = (milliseconds / 60000).round();
    final hours = (milliseconds / 3600000).round();
    final days = (milliseconds / 86400000).round();
    // Moment converts days to months with the mean Gregorian month: 146097
    // days per 400 years of 4800 months.
    final monthsExact = milliseconds / 86400000 * 4800 / 146097;
    final months = monthsExact.round();
    final years = (monthsExact / 12).round();
    if (seconds <= 44) return 'a few seconds';
    if (minutes <= 1) return 'a minute';
    if (minutes < 45) return '$minutes minutes';
    if (hours <= 1) return 'an hour';
    if (hours < 22) return '$hours hours';
    if (days <= 1) return 'a day';
    if (days < 26) return '$days days';
    if (months <= 1) return 'a month';
    if (months < 11) return '$months months';
    if (years <= 1) return 'a year';
    return '$years years';
  }

  static int _calendarDayDifference(DateTime value, DateTime reference) =>
      DateTime.utc(value.year, value.month, value.day)
          .difference(
            DateTime.utc(reference.year, reference.month, reference.day),
          )
          .inDays;

  static _WallTime? _parseWallTime(LocalDateSpec spec) {
    final dateMatch = _wallDatePattern.firstMatch(spec.date);
    if (dateMatch == null) return null;
    final year = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);
    var hour = 0;
    var minute = 0;
    var second = 0;
    if (spec.time != null) {
      final timeMatch = _wallTimePattern.firstMatch(spec.time!);
      if (timeMatch == null) return null;
      hour = int.parse(timeMatch.group(1)!);
      minute = int.parse(timeMatch.group(2)!);
      second = int.parse(timeMatch.group(3) ?? '0');
    }
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > _daysInMonth(year, month) ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    return _WallTime(year, month, day, hour, minute, second);
  }

  static bool _sameWallTime(tz.TZDateTime value, _WallTime parts) =>
      value.year == parts.year &&
      value.month == parts.month &&
      value.day == parts.day &&
      value.hour == parts.hour &&
      value.minute == parts.minute &&
      value.second == parts.second;

  static tz.TZDateTime? _advanceRecurring(
    tz.TZDateTime start,
    String recurring,
    DateTime now,
  ) {
    final match = _recurrencePattern.firstMatch(recurring);
    if (match == null) return null;
    final amount = int.tryParse(match.group(1)!);
    final unit = match.group(2)!;
    if (amount == null ||
        amount <= 0 ||
        amount > _maximumRecurrenceAmount(unit)) {
      return null;
    }
    var repetitions = _estimatedRepetitions(start, now, amount, unit);
    repetitions = math.max(1, repetitions);
    var candidate = _addWall(start, amount * repetitions, unit);
    while (candidate.isBefore(now)) {
      repetitions += 1;
      candidate = _addWall(start, amount * repetitions, unit);
    }
    while (repetitions > 1) {
      final prior = _addWall(start, amount * (repetitions - 1), unit);
      if (prior.isBefore(now)) break;
      repetitions -= 1;
      candidate = prior;
    }
    return candidate;
  }

  /// The furthest one recurrence step may reach, in days.
  ///
  /// `recurring` is author-written markup that arrives here verbatim, and the
  /// digits in front of the unit are unbounded. Beyond this the arithmetic
  /// below stops saying anything true: `int.parse` throws on a number wider
  /// than 64 bits, and a `Duration` built from a merely enormous one wraps
  /// rather than overflows, so the advance loop compares against a date it
  /// invented. A hundred thousand years is far past any recurrence anyone
  /// means and still leaves every intermediate inside its own range — the
  /// source year is capped at four digits by [_wallDatePattern], so the
  /// furthest step lands around the year 110,000, well short of the roughly
  /// 273,000 `DateTime` allows.
  static const int _maximumRecurrenceDays = 100000 * 366;

  /// The largest [_maximumRecurrenceDays]-worth of [unit], never multiplied
  /// out so the bound itself cannot overflow what it is bounding.
  static int _maximumRecurrenceAmount(String unit) => switch (unit) {
    final value when value.startsWith('year') => _maximumRecurrenceDays ~/ 366,
    final value when value.startsWith('quarter') =>
      _maximumRecurrenceDays ~/ 92,
    final value when value.startsWith('month') => _maximumRecurrenceDays ~/ 31,
    final value when value.startsWith('week') => _maximumRecurrenceDays ~/ 7,
    final value when value.startsWith('day') => _maximumRecurrenceDays,
    final value when value.startsWith('hour') => _maximumRecurrenceDays * 24,
    final value when value.startsWith('minute') =>
      _maximumRecurrenceDays * 1440,
    final value when value.startsWith('second') =>
      _maximumRecurrenceDays * 86400,
    _ => _maximumRecurrenceDays * 86400000,
  };

  static int _estimatedRepetitions(
    tz.TZDateTime start,
    DateTime now,
    int amount,
    String unit,
  ) {
    if (unit.startsWith('year')) {
      return ((now.year - start.year) / amount).floor();
    }
    if (unit.startsWith('quarter') || unit.startsWith('month')) {
      final months = (now.year - start.year) * 12 + now.month - start.month;
      final size = unit.startsWith('quarter') ? amount * 3 : amount;
      return (months / size).floor();
    }
    final milliseconds = switch (unit) {
      final value when value.startsWith('week') => Duration(
        days: amount * 7,
      ).inMilliseconds,
      final value when value.startsWith('day') => Duration(
        days: amount,
      ).inMilliseconds,
      final value when value.startsWith('hour') => Duration(
        hours: amount,
      ).inMilliseconds,
      final value when value.startsWith('minute') => Duration(
        minutes: amount,
      ).inMilliseconds,
      final value when value.startsWith('second') => Duration(
        seconds: amount,
      ).inMilliseconds,
      _ => amount,
    };
    return now.difference(start).inMilliseconds ~/ milliseconds;
  }

  static tz.TZDateTime _addWall(tz.TZDateTime start, int amount, String unit) {
    var year = start.year;
    var month = start.month;
    var day = start.day;
    var hour = start.hour;
    var minute = start.minute;
    var second = start.second;
    var millisecond = start.millisecond;
    if (unit.startsWith('year')) {
      year += amount;
      day = math.min(day, _daysInMonth(year, month));
    } else if (unit.startsWith('quarter') || unit.startsWith('month')) {
      final addedMonths = unit.startsWith('quarter') ? amount * 3 : amount;
      final zeroBased = year * 12 + month - 1 + addedMonths;
      year = zeroBased ~/ 12;
      month = zeroBased % 12 + 1;
      day = math.min(day, _daysInMonth(year, month));
    } else {
      final naive =
          DateTime.utc(
            year,
            month,
            day,
            hour,
            minute,
            second,
            millisecond,
          ).add(switch (unit) {
            final value when value.startsWith('week') => Duration(
              days: amount * 7,
            ),
            final value when value.startsWith('day') => Duration(days: amount),
            final value when value.startsWith('hour') => Duration(
              hours: amount,
            ),
            final value when value.startsWith('minute') => Duration(
              minutes: amount,
            ),
            final value when value.startsWith('second') => Duration(
              seconds: amount,
            ),
            _ => Duration(milliseconds: amount),
          });
      year = naive.year;
      month = naive.month;
      day = naive.day;
      hour = naive.hour;
      minute = naive.minute;
      second = naive.second;
      millisecond = naive.millisecond;
    }
    return tz.TZDateTime(
      start.location,
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
    );
  }

  static int _daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  // Moment derives day-of-year and ISO-week values from calendar fields, so
  // these helpers must too: [value] carries a displayed-zone wall clock, and
  // instant arithmetic against device-local dates (or exact 24h day steps
  // across a DST change) lands on the wrong calendar day. Rebuilding the
  // wall date in UTC keeps every day exactly 24h and no zone involved.
  static int _dayOfYear(DateTime value) =>
      DateTime.utc(
        value.year,
        value.month,
        value.day,
      ).difference(DateTime.utc(value.year)).inDays +
      1;

  static int _isoWeek(DateTime value) {
    final thursday = DateTime.utc(
      value.year,
      value.month,
      value.day,
    ).add(Duration(days: 4 - value.weekday));
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    return 1 +
        (thursday.difference(firstThursday).inDays -
                (4 - firstThursday.weekday)) ~/
            7;
  }

  static int _isoWeekYear(DateTime value) => DateTime.utc(
    value.year,
    value.month,
    value.day,
  ).add(Duration(days: 4 - value.weekday)).year;

  static String _ordinal(int value) {
    final mod100 = value % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${value}th';
    return switch (value % 10) {
      1 => '${value}st',
      2 => '${value}nd',
      3 => '${value}rd',
      _ => '${value}th',
    };
  }

  static String? _longestAt(
    String source,
    int index,
    Iterable<String> candidates,
  ) {
    String? match;
    for (final candidate in candidates) {
      if (source.startsWith(candidate, index) &&
          (match == null || candidate.length > match.length)) {
        match = candidate;
      }
    }
    return match;
  }

  static bool _isAsciiLetter(int value) =>
      (value >= 65 && value <= 90) || (value >= 97 && value <= 122);

  /// Letters that can begin a moment formatting token handled by
  /// [_formatToken] or the localized aliases.
  static const Set<String> _tokenLetters = {
    'Y',
    'M',
    'D',
    'd',
    'e',
    'E',
    'w',
    'W',
    'g',
    'G',
    'Q',
    'H',
    'h',
    'k',
    'm',
    's',
    'S',
    'A',
    'a',
    'Z',
    'z',
    'X',
    'x',
    'L',
    'l',
  };

  static String _localeName(Locale locale) => locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
}

@immutable
class _WallTime {
  const _WallTime(
    this.year,
    this.month,
    this.day,
    this.hour,
    this.minute,
    this.second,
  );

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
