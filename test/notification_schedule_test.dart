import 'package:discourse_native/src/models/notification_schedule.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wire = <String, Object?>{
    'enabled': true,
    for (var i = 0; i < 7; i++) ...{
      'day_${i}_start_time': i < 5 ? 540 + i * 30 : -1,
      'day_${i}_end_time': i < 5 ? 1080 : -1,
    },
  };
  test(
    'reads core Monday-first minute values without flattening custom hours',
    () {
      final preferences = UserPreferences.fromJson({
        'username': 'reader',
        'user_notification_schedule': wire,
        'user_option': const {'timezone': 'Europe/Paris'},
      });
      final schedule = preferences.notificationSchedule!;
      expect(schedule.activeDays, [0, 1, 2, 3, 4]);
      expect(schedule.days[0], (start: 540, end: 1080));
      expect(schedule.days[4], (start: 660, end: 1080));
      expect(schedule.days[6], (start: -1, end: -1));
      expect(preferences.payloadFor(PreferenceSection.notificationSchedule), {
        'user_notification_schedule': wire,
      });
      expect(
        UserPreferences.fromJson(const {}, fallback: preferences),
        preferences,
      );
      expect(() => schedule.days.clear(), throwsUnsupportedError);
      expect(() => schedule.wireValues.clear(), throwsUnsupportedError);
    },
  );
  test('malformed schedules preserve the last confirmed value', () {
    final fallback = UserPreferences(
      notificationSchedule: NotificationSchedule.read(wire),
    );
    for (final value in [
      null,
      false,
      <Object?>[],
      <String, Object?>{},
      {...wire, 'enabled': 'true'},
      {...wire, 'day_0_start_time': 1440},
      {...wire, 'day_1_end_time': 1500},
      {...wire, 'day_2_end_time': 1},
      {...wire, 'day_3_start_time': double.infinity},
    ]) {
      expect(
        UserPreferences.fromJson({
          'user_notification_schedule': value,
        }, fallback: fallback),
        fallback,
      );
    }
  });
  test('midnight is 1440 and a disabled schedule retains all stored hours', () {
    final schedule = NotificationSchedule.read({
      ...wire,
      'day_4_end_time': 1440,
    })!;
    final disabled = schedule.copyWith(enabled: false);
    expect(disabled.days[4].end, 1440);
    expect(disabled.days, schedule.days);
    expect(disabled.wireValues['enabled'], false);
    expect(schedule.copyWith(), schedule);
    expect(schedule.copyWith().hashCode, schedule.hashCode);
  });
  test(
    'a schedule confirmation leaves other preference sections untouched',
    () {
      const initial = UserPreferences(
        timezone: 'Europe/Paris',
        notifyOnLinkedPosts: false,
      );
      final confirmed = UserPreferences(
        timezone: 'UTC',
        notifyOnLinkedPosts: true,
        notificationSchedule: NotificationSchedule.read(wire),
      );
      final merged = initial.withSectionFrom(
        PreferenceSection.notificationSchedule,
        confirmed,
      );
      expect(merged.timezone, 'Europe/Paris');
      expect(merged.notifyOnLinkedPosts, false);
      expect(merged.notificationSchedule, confirmed.notificationSchedule);
      expect(
        merged.withSectionFrom(PreferenceSection.notificationSchedule, initial),
        initial,
      );
    },
  );
}
