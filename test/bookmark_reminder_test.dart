import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark_reminder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final environment = TimezoneEnvironment.instance..ensureDatabase();

  test('quick reminders use absolute hours and account-zone mornings', () {
    final location = environment.location('Europe/Paris')!;
    final now = DateTime.utc(2026, 8, 24, 14);
    final suggestions = BookmarkReminderCalculator.quickSuggestions(
      now: now,
      location: location,
    );

    expect(suggestions[0].instant, DateTime.utc(2026, 8, 24, 16));
    expect(suggestions[1].instant, DateTime.utc(2026, 8, 25, 6));
    expect(suggestions[2].instant, DateTime.utc(2026, 8, 27, 6));
  });

  test('tomorrow is eight o\'clock on the next account-zone day', () {
    for (final scenario in [
      (
        zone: 'Pacific/Kiritimati',
        now: DateTime.utc(2026, 1, 1, 23, 30),
        tomorrow: DateTime.utc(2026, 1, 2, 18),
      ),
      (
        zone: 'America/Los_Angeles',
        now: DateTime.utc(2026, 1, 2, 0, 30),
        tomorrow: DateTime.utc(2026, 1, 2, 16),
      ),
    ]) {
      final location = environment.location(scenario.zone)!;
      final tomorrow = BookmarkReminderCalculator.tomorrow(
        now: scenario.now,
        location: location,
      );

      expect(tomorrow, scenario.tomorrow, reason: scenario.zone);
      expect(
        BookmarkReminderCalculator.quickSuggestions(
          now: scenario.now,
          location: location,
        ).singleWhere((s) => s.preset == BookmarkReminderPreset.tomorrow),
        isA<BookmarkReminderSuggestion>().having(
          (s) => s.instant,
          'instant',
          tomorrow,
        ),
      );
    }
  });

  test('instants leave as plain UTC DateTimes', () {
    // A TZDateTime would answer toLocal() in UTC rather than the device zone,
    // so a status saved from one would show its expiry in UTC.
    final location = environment.location('Europe/Paris')!;
    final now = DateTime.utc(2026, 8, 24, 10);
    final instants = [
      for (final suggestion in [
        ...BookmarkReminderCalculator.quickSuggestions(
          now: now,
          location: location,
        ),
        ...BookmarkReminderCalculator.fullSuggestions(
          now: now,
          location: location,
          suggestWeekends: true,
        ),
      ])
        suggestion.instant,
      BookmarkReminderCalculator.tomorrow(now: now, location: location),
      BookmarkReminderCalculator.resolveWallTime(
        location: location,
        date: DateTime(2026, 8, 25),
        hour: 9,
        minute: 15,
      )!,
    ];

    for (final instant in instants) {
      expect(instant, isNot(isA<tz.TZDateTime>()));
      expect(instant.isUtc, isTrue);
    }
  });

  test('full reminders obey cutoffs and the weekend setting', () {
    final location = environment.location('Etc/UTC')!;
    final thursdayEvening = DateTime.utc(2026, 8, 27, 18);
    expect(
      BookmarkReminderCalculator.fullSuggestions(
        now: thursdayEvening,
        location: location,
        suggestWeekends: true,
      ).map((suggestion) => suggestion.label),
      ['Tomorrow', 'This weekend', 'Monday', 'Next month'],
    );
    expect(
      BookmarkReminderCalculator.fullSuggestions(
        now: thursdayEvening,
        location: location,
        suggestWeekends: false,
      ).map((suggestion) => suggestion.label),
      ['Tomorrow', 'Monday', 'Next month'],
    );
  });

  test('on Sunday, next Monday is the one after tomorrow', () {
    final location = environment.location('Europe/Paris')!;
    final sundayMorning = DateTime.utc(2026, 9, 27, 8);
    final suggestions = BookmarkReminderCalculator.fullSuggestions(
      now: sundayMorning,
      location: location,
      suggestWeekends: true,
    );
    BookmarkReminderSuggestion preset(BookmarkReminderPreset value) =>
        suggestions.singleWhere((suggestion) => suggestion.preset == value);

    expect(
      preset(BookmarkReminderPreset.tomorrow).instant,
      DateTime.utc(2026, 9, 28, 6),
    );
    expect(
      preset(BookmarkReminderPreset.nextMonday).instant,
      DateTime.utc(2026, 10, 5, 6),
    );
    expect(preset(BookmarkReminderPreset.nextMonday).label, 'Next Monday');
  });

  test('next Monday matches the web business-week start on every weekday', () {
    final location = environment.location('Europe/Paris')!;
    // Mornings at 10:00 in Paris, Monday 28 September to Sunday 4 October,
    // then a moment that is still Sunday in UTC but already Monday on the
    // reader's wall.
    final cases = <(String, DateTime, DateTime, String)>[
      (
        'Monday',
        DateTime.utc(2026, 9, 28, 8),
        DateTime.utc(2026, 10, 5, 6),
        'Next Monday',
      ),
      (
        'Tuesday',
        DateTime.utc(2026, 9, 29, 8),
        DateTime.utc(2026, 10, 5, 6),
        'Monday',
      ),
      (
        'Wednesday',
        DateTime.utc(2026, 9, 30, 8),
        DateTime.utc(2026, 10, 5, 6),
        'Monday',
      ),
      (
        'Thursday',
        DateTime.utc(2026, 10, 1, 8),
        DateTime.utc(2026, 10, 5, 6),
        'Monday',
      ),
      (
        'Friday',
        DateTime.utc(2026, 10, 2, 8),
        DateTime.utc(2026, 10, 5, 6),
        'Monday',
      ),
      (
        'Saturday',
        DateTime.utc(2026, 10, 3, 8),
        DateTime.utc(2026, 10, 5, 6),
        'Monday',
      ),
      (
        'Sunday',
        DateTime.utc(2026, 10, 4, 8),
        DateTime.utc(2026, 10, 12, 6),
        'Next Monday',
      ),
      (
        'Monday just after midnight',
        DateTime.utc(2026, 10, 4, 22, 30),
        DateTime.utc(2026, 10, 12, 6),
        'Next Monday',
      ),
    ];

    for (final (day, now, instant, label) in cases) {
      final suggestions = BookmarkReminderCalculator.fullSuggestions(
        now: now,
        location: location,
        suggestWeekends: true,
      );
      final tomorrow = suggestions.singleWhere(
        (suggestion) => suggestion.preset == BookmarkReminderPreset.tomorrow,
      );
      final monday = suggestions.singleWhere(
        (suggestion) => suggestion.preset == BookmarkReminderPreset.nextMonday,
      );

      expect(monday.instant, instant, reason: day);
      expect(monday.label, label, reason: day);
      expect(monday.instant, isNot(tomorrow.instant), reason: day);
    }
  });

  test('later today follows the web half-hour cutoff', () {
    final location = environment.location('Etc/UTC')!;

    DateTime laterToday(int minute) =>
        BookmarkReminderCalculator.fullSuggestions(
              now: DateTime.utc(2026, 8, 24, 10, minute),
              location: location,
              suggestWeekends: false,
            )
            .singleWhere(
              (suggestion) =>
                  suggestion.preset == BookmarkReminderPreset.laterToday,
            )
            .instant;

    expect(laterToday(29), DateTime.utc(2026, 8, 24, 13));
    expect(laterToday(30), DateTime.utc(2026, 8, 24, 14));
  });

  test('DST gaps are rejected instead of normalized', () {
    final location = environment.location('Europe/Paris')!;
    expect(
      BookmarkReminderCalculator.resolveWallTime(
        location: location,
        date: DateTime(2026, 3, 29),
        hour: 2,
        minute: 30,
      ),
      isNull,
    );
    expect(
      BookmarkReminderCalculator.resolveWallTime(
        location: location,
        date: DateTime(2026, 3, 29),
        hour: 3,
        minute: 30,
      ),
      DateTime.utc(2026, 3, 29, 1, 30),
    );
  });

  test('DST overlaps resolve deterministically', () {
    final location = environment.location('Europe/Paris')!;

    expect(
      BookmarkReminderCalculator.resolveWallTime(
        location: location,
        date: DateTime(2026, 10, 25),
        hour: 2,
        minute: 30,
      ),
      DateTime.utc(2026, 10, 25, 1, 30),
    );
  });

  test('timezone ownership prefers account, then device, then UTC', () async {
    final device = TimezoneEnvironment.forTesting(
      detectDeviceTimezone: () async => 'America/New_York',
    );
    await device.initialize();

    expect(device.readerTimezone('Europe/Paris'), 'Europe/Paris');
    expect(device.readerTimezone('Invalid/Zone'), 'America/New_York');
    device.setDeviceTimezone('Invalid/Zone');
    expect(device.readerTimezone(), 'Etc/UTC');
  });
}
