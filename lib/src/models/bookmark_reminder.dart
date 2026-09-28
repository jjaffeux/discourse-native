import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

enum BookmarkReminderPreset {
  laterToday,
  tomorrow,
  inThreeDays,
  laterThisWeek,
  thisWeekend,
  nextMonday,
  nextMonth,
}

@immutable
final class BookmarkReminderSuggestion {
  const BookmarkReminderSuggestion({
    required this.preset,
    required this.label,
    required this.instant,
  });

  final BookmarkReminderPreset preset;
  final String label;
  final DateTime instant;
}

final class BookmarkReminderCalculator {
  const BookmarkReminderCalculator._();

  static List<BookmarkReminderSuggestion> quickSuggestions({
    required DateTime now,
    required tz.Location location,
  }) {
    final wallNow = tz.TZDateTime.from(now, location);
    return [
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.laterToday,
        label: appL10n.in2Hours,
        instant: now.add(const Duration(hours: 2)).toUtc(),
      ),
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.tomorrow,
        label: appL10n.tomorrow,
        instant: _instant(_dayAtEight(wallNow, 1)),
      ),
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.inThreeDays,
        label: appL10n.in3Days,
        instant: _instant(_dayAtEight(wallNow, 3)),
      ),
    ];
  }

  static List<BookmarkReminderSuggestion> fullSuggestions({
    required DateTime now,
    required tz.Location location,
    required bool suggestWeekends,
  }) {
    final wallNow = tz.TZDateTime.from(now, location);
    final suggestions = <BookmarkReminderSuggestion>[];
    if (wallNow.hour < 17) {
      var candidate = wallNow.add(const Duration(hours: 3));
      final roundUp = candidate.minute >= 30;
      candidate = tz.TZDateTime(
        location,
        candidate.year,
        candidate.month,
        candidate.day,
        candidate.hour + (roundUp ? 1 : 0),
      );
      final six = tz.TZDateTime(
        location,
        wallNow.year,
        wallNow.month,
        wallNow.day,
        18,
      );
      if (candidate.isAfter(six)) candidate = six;
      suggestions.add(
        BookmarkReminderSuggestion(
          preset: BookmarkReminderPreset.laterToday,
          label: appL10n.laterToday,
          instant: _instant(candidate),
        ),
      );
    }
    suggestions.add(
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.tomorrow,
        label: appL10n.tomorrow,
        instant: _instant(_dayAtEight(wallNow, 1)),
      ),
    );
    if (wallNow.weekday <= DateTime.wednesday) {
      suggestions.add(
        BookmarkReminderSuggestion(
          preset: BookmarkReminderPreset.laterThisWeek,
          label: appL10n.laterThisWeek,
          instant: _instant(_dayAtEight(wallNow, 2)),
        ),
      );
    }
    if (suggestWeekends && wallNow.weekday <= DateTime.thursday) {
      final untilSaturday = DateTime.saturday - wallNow.weekday;
      suggestions.add(
        BookmarkReminderSuggestion(
          preset: BookmarkReminderPreset.thisWeekend,
          label: appL10n.thisWeekend,
          instant: _instant(_dayAtEight(wallNow, untilSaturday)),
        ),
      );
    }
    // The web's start of next business week: the Monday of the Sunday-first
    // week one week from now. On Sunday that is eight days out rather than
    // the Monday Tomorrow already offers, and only on Sunday and Monday does
    // it pass over the coming Monday, so only then is it "Next Monday".
    final untilMonday = wallNow.weekday == DateTime.sunday
        ? 8
        : 8 - wallNow.weekday;
    suggestions.add(
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.nextMonday,
        label: untilMonday >= 7 ? appL10n.nextMonday : appL10n.monday,
        instant: _instant(_dayAtEight(wallNow, untilMonday)),
      ),
    );
    final nextMonth = wallNow.month == DateTime.december
        ? tz.TZDateTime(location, wallNow.year + 1, DateTime.january, 1, 8)
        : tz.TZDateTime(location, wallNow.year, wallNow.month + 1, 1, 8);
    suggestions.add(
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.nextMonth,
        label: appL10n.nextMonth,
        instant: _instant(nextMonth),
      ),
    );
    return List.unmodifiable(suggestions);
  }

  /// Eight o'clock on the next calendar day in [location]: the "Tomorrow"
  /// every time-shortcut picker offers, bookmark or status, as web's
  /// `timeShortcuts(timezone).tomorrow()`.
  static DateTime tomorrow({
    required DateTime now,
    required tz.Location location,
  }) => _instant(_dayAtEight(tz.TZDateTime.from(now, location), 1));

  static DateTime? resolveWallTime({
    required tz.Location location,
    required DateTime date,
    required int hour,
    required int minute,
  }) {
    final value = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );
    if (value.year != date.year ||
        value.month != date.month ||
        value.day != date.day ||
        value.hour != hour ||
        value.minute != minute) {
      return null;
    }
    return _instant(value);
  }

  /// Instants leave as plain UTC [DateTime]s. A [tz.TZDateTime] answers
  /// `toLocal()` in the timezone package's own local zone, which is never set,
  /// so a caller showing the instant in the device zone would show UTC.
  static DateTime _instant(tz.TZDateTime value) =>
      DateTime.fromMicrosecondsSinceEpoch(
        value.microsecondsSinceEpoch,
        isUtc: true,
      );

  static tz.TZDateTime _dayAtEight(tz.TZDateTime now, int days) =>
      tz.TZDateTime(now.location, now.year, now.month, now.day + days, 8);
}
