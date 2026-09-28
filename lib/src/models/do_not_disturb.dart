import 'package:discourse_native/l10n/strings.dart';
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
  halfHour(DoNotDisturbDuration.minutes(30)),
  oneHour(DoNotDisturbDuration.minutes(60)),
  twoHours(DoNotDisturbDuration.minutes(120)),
  tomorrow(DoNotDisturbDuration.untilTomorrow());

  const DoNotDisturbOption(this.duration);

  String get label => switch (this) {
    halfHour => appL10n.message30Minutes,
    oneHour => appL10n.message1Hour,
    twoHours => appL10n.message2Hours,
    tomorrow => appL10n.untilTomorrow,
  };
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
  final remaining = until.toUtc().difference((now ?? DateTime.now()).toUtc());
  if (remaining <= Duration.zero) {
    throw ArgumentError.value(until, 'until', 'must be in the future');
  }
  // The API accepts whole minutes; round up so the pause covers the expiry.
  final minutes =
      (remaining.inMicroseconds + Duration.microsecondsPerMinute - 1) ~/
      Duration.microsecondsPerMinute;
  return DoNotDisturbDuration.minutes(minutes);
}

String doNotDisturbRemainingLabel(DateTime until, {DateTime? now}) {
  final remaining = until.difference(now ?? DateTime.now());
  if (remaining <= Duration.zero) return appL10n.relativeNow;
  final minutes = (remaining.inSeconds / Duration.secondsPerMinute).ceil();
  if (minutes >= Duration.minutesPerDay) {
    return appL10n.relativeDays((minutes / Duration.minutesPerDay).ceil());
  }
  if (minutes >= Duration.minutesPerHour) {
    return appL10n.relativeHours((minutes / Duration.minutesPerHour).ceil());
  }
  return appL10n.relativeMinutes(minutes);
}

@immutable
final class DoNotDisturbState {
  const DoNotDisturbState({this.until, this.saving = false});

  final DateTime? until;
  final bool saving;

  bool isActiveAt(DateTime now) => until?.isAfter(now) ?? false;
  bool get isEternal => isEternalDoNotDisturb(until);
}
