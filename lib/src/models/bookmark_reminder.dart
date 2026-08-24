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

/// Pure wall-time calculations shared by the quick menu and full editor.
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
        label: 'In 2 hours',
        instant: now.add(const Duration(hours: 2)).toUtc(),
      ),
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.tomorrow,
        label: 'Tomorrow',
        instant: _dayAtEight(wallNow, 1).toUtc(),
      ),
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.inThreeDays,
        label: 'In 3 days',
        instant: _dayAtEight(wallNow, 3).toUtc(),
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
          label: 'Later today',
          instant: candidate.toUtc(),
        ),
      );
    }
    suggestions.add(
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.tomorrow,
        label: 'Tomorrow',
        instant: _dayAtEight(wallNow, 1).toUtc(),
      ),
    );
    if (wallNow.weekday <= DateTime.wednesday) {
      suggestions.add(
        BookmarkReminderSuggestion(
          preset: BookmarkReminderPreset.laterThisWeek,
          label: 'Later this week',
          instant: _dayAtEight(wallNow, 2).toUtc(),
        ),
      );
    }
    if (suggestWeekends && wallNow.weekday <= DateTime.thursday) {
      final untilSaturday = DateTime.saturday - wallNow.weekday;
      suggestions.add(
        BookmarkReminderSuggestion(
          preset: BookmarkReminderPreset.thisWeekend,
          label: 'This weekend',
          instant: _dayAtEight(wallNow, untilSaturday).toUtc(),
        ),
      );
    }
    final mondayDelta = (DateTime.monday - wallNow.weekday + 7) % 7;
    final untilMonday = mondayDelta == 0 ? 7 : mondayDelta;
    suggestions.add(
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.nextMonday,
        label: 'Next Monday',
        instant: _dayAtEight(wallNow, untilMonday).toUtc(),
      ),
    );
    final nextMonth = wallNow.month == DateTime.december
        ? tz.TZDateTime(location, wallNow.year + 1, DateTime.january, 1, 8)
        : tz.TZDateTime(location, wallNow.year, wallNow.month + 1, 1, 8);
    suggestions.add(
      BookmarkReminderSuggestion(
        preset: BookmarkReminderPreset.nextMonth,
        label: 'Next month',
        instant: nextMonth.toUtc(),
      ),
    );
    return List.unmodifiable(suggestions);
  }

  /// Null means the selected civil time falls in a daylight-saving gap.
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
    return value.toUtc();
  }

  static tz.TZDateTime _dayAtEight(tz.TZDateTime now, int days) =>
      tz.TZDateTime(now.location, now.year, now.month, now.day + days, 8);
}
