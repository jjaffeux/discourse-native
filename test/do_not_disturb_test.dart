import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('doNotDisturbRemainingLabel', () {
    final now = DateTime.utc(2030, 1, 1, 12);

    for (final (remaining, label) in [
      (const Duration(microseconds: 1), '1m'),
      (const Duration(minutes: 1), '1m'),
      (const Duration(minutes: 1, microseconds: 1), '2m'),
      (const Duration(hours: 1), '1h'),
      (const Duration(hours: 1, microseconds: 1), '2h'),
      (const Duration(days: 1), '1d'),
      (const Duration(days: 1, microseconds: 1), '2d'),
    ]) {
      test('rounds $remaining up to $label', () {
        expect(doNotDisturbRemainingLabel(now.add(remaining), now: now), label);
      });
    }
  });

  group('doNotDisturbDurationUntil', () {
    final now = DateTime.utc(2030, 1, 1, 12);

    for (final (remaining, minutes) in [
      (const Duration(microseconds: 1), 1),
      (const Duration(seconds: 1), 1),
      (const Duration(seconds: 59), 1),
      (const Duration(minutes: 1, microseconds: -1), 1),
      (const Duration(minutes: 1), 1),
      (const Duration(minutes: 1, microseconds: 1), 2),
      (const Duration(minutes: 30, seconds: 59), 31),
      (const Duration(hours: 1, milliseconds: -500), 60),
      (const Duration(hours: 1), 60),
    ]) {
      test('covers $remaining with $minutes whole minutes', () {
        expect(
          doNotDisturbDurationUntil(now.add(remaining), now: now).wireValue,
          minutes,
        );
      });
    }

    for (final remaining in [
      Duration.zero,
      const Duration(microseconds: -1),
      const Duration(seconds: -59),
      const Duration(minutes: -1),
    ]) {
      test('rejects a non-future expiry at $remaining', () {
        expect(
          () => doNotDisturbDurationUntil(now.add(remaining), now: now),
          throwsArgumentError,
        );
      });
    }

    test('compares instants across UTC and local representations', () {
      final until = now.add(const Duration(seconds: 30)).toLocal();

      expect(doNotDisturbDurationUntil(until, now: now).wireValue, 1);
      expect(
        doNotDisturbDurationUntil(until.toUtc(), now: now.toLocal()).wireValue,
        1,
      );
    });
  });
}
