import 'package:flutter/foundation.dart';

@immutable
final class DoNotDisturbDuration {
  const DoNotDisturbDuration.minutes(int minutes)
    : minutes = minutes,
      untilTomorrow = false,
      assert(minutes > 0);

  const DoNotDisturbDuration.untilTomorrow()
    : minutes = null,
      untilTomorrow = true;

  final int? minutes;
  final bool untilTomorrow;

  Object get wireValue => untilTomorrow ? 'tomorrow' : minutes!;

  @override
  bool operator ==(Object other) =>
      other is DoNotDisturbDuration &&
      other.minutes == minutes &&
      other.untilTomorrow == untilTomorrow;

  @override
  int get hashCode => Object.hash(minutes, untilTomorrow);
}

enum DoNotDisturbOption {
  halfHour('30 minutes', DoNotDisturbDuration.minutes(30)),
  oneHour('1 hour', DoNotDisturbDuration.minutes(60)),
  twoHours('2 hours', DoNotDisturbDuration.minutes(120)),
  tomorrow('Until tomorrow', DoNotDisturbDuration.untilTomorrow());

  const DoNotDisturbOption(this.label, this.duration);

  final String label;
  final DoNotDisturbDuration duration;
}

final DateTime eternalDoNotDisturbUntil = DateTime.utc(3000);

bool isEternalDoNotDisturb(DateTime? until) {
  if (until == null) return false;
  final utc = until.toUtc();
  return utc.year == eternalDoNotDisturbUntil.year &&
      utc.month == eternalDoNotDisturbUntil.month &&
      utc.day == eternalDoNotDisturbUntil.day;
}

DoNotDisturbDuration doNotDisturbDurationUntil(
  DateTime until, {
  DateTime? now,
}) {
  final minutes = until
      .toUtc()
      .difference((now ?? DateTime.now()).toUtc())
      .inMinutes;
  if (minutes <= 0) {
    throw ArgumentError.value(
      until,
      'until',
      'must be at least one minute away',
    );
  }
  return DoNotDisturbDuration.minutes(minutes);
}

String doNotDisturbRemainingLabel(DateTime until, {DateTime? now}) {
  final remaining = until.difference(now ?? DateTime.now());
  if (remaining <= Duration.zero) return 'now';
  final minutes = (remaining.inSeconds / Duration.secondsPerMinute).ceil();
  if (minutes >= Duration.minutesPerDay) {
    return '${(minutes / Duration.minutesPerDay).ceil()}d';
  }
  if (minutes >= Duration.minutesPerHour) {
    return '${(minutes / Duration.minutesPerHour).ceil()}h';
  }
  return '${minutes}m';
}

@immutable
final class DoNotDisturbState {
  const DoNotDisturbState({this.until, this.saving = false});

  final DateTime? until;
  final bool saving;

  bool isActiveAt(DateTime now) => until?.isAfter(now) ?? false;
  bool get isEternal => isEternalDoNotDisturb(until);
}
