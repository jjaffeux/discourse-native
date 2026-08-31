import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('full reminders obey cutoffs and the weekend setting', () {
    final location = environment.location('Etc/UTC')!;
    final thursdayEvening = DateTime.utc(2026, 8, 27, 18);
    expect(
      BookmarkReminderCalculator.fullSuggestions(
        now: thursdayEvening,
        location: location,
        suggestWeekends: true,
      ).map((suggestion) => suggestion.label),
      ['Tomorrow', 'This weekend', 'Next Monday', 'Next month'],
    );
    expect(
      BookmarkReminderCalculator.fullSuggestions(
        now: thursdayEvening,
        location: location,
        suggestWeekends: false,
      ).map((suggestion) => suggestion.label),
      ['Tomorrow', 'Next Monday', 'Next month'],
    );
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
