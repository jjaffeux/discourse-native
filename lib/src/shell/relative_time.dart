import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

String relativeTime(DateTime when, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(when);
  if (delta.inDays >= 365) return appL10n.relativeYears(delta.inDays ~/ 365);
  if (delta.inDays >= 30) return appL10n.relativeMonths(delta.inDays ~/ 30);
  if (delta.inDays >= 1) return appL10n.relativeDays(delta.inDays);
  if (delta.inHours >= 1) return appL10n.relativeHours(delta.inHours);
  if (delta.inMinutes >= 1) return appL10n.relativeMinutes(delta.inMinutes);
  return appL10n.relativeNow;
}

typedef DurationLabel = ({String short, String long});

/// Discourse reading duration thresholds, with locale-owned wording and plurals.
DurationLabel durationLabel(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = (safe / 60).round().clamp(1, 1 << 31);
  if (safe <= 59) {
    return (
      short: appL10n.durationLessThanMinuteShort,
      long: appL10n.durationLessThanMinute,
    );
  }
  if (minutes <= 44) {
    return (
      short: appL10n.relativeMinutes(minutes),
      long: appL10n.durationMinutes(minutes),
    );
  }
  if (minutes <= 89) {
    return (short: appL10n.durationOneHourShort, long: appL10n.durationOneHour);
  }
  if (minutes <= 1409) {
    final count = (minutes / 60).round();
    return (
      short: appL10n.relativeHours(count),
      long: appL10n.durationHours(count),
    );
  }
  if (minutes <= 2519) {
    return (short: appL10n.durationOneDayShort, long: appL10n.durationOneDay);
  }
  if (minutes <= 129599) {
    final count = (minutes / 1440).round();
    return (
      short: appL10n.relativeDays(count),
      long: appL10n.durationDays(count),
    );
  }
  if (minutes <= 525599) {
    final count = (minutes / 43200).round();
    return (
      short: appL10n.relativeDurationMonths(count),
      long: appL10n.durationMonths(count),
    );
  }
  final years = minutes / 525600;
  final remainder = years % 1;
  if (remainder < 0.25) {
    final count = years.floor();
    return (
      short: appL10n.relativeYears(count),
      long: appL10n.durationAboutYears(count),
    );
  }
  if (remainder < 0.75) {
    final count = years.floor();
    return (
      short: appL10n.durationOverYearsShort(count),
      long: appL10n.durationOverYears(count),
    );
  }
  final count = years.floor() + 1;
  return (
    short: appL10n.relativeYears(count),
    long: appL10n.durationAlmostYears(count),
  );
}

/// The first instant after [now] at which [relativeTime] of [when] reads
/// differently.
DateTime _relativeTimeChangesAt(DateTime when, DateTime now) {
  final age = now.difference(when);
  // A future instant, as from a skewed clock, reads "now" until it is a
  // minute old.
  if (age.isNegative) return when.add(const Duration(minutes: 1));
  const year = Duration(days: 365);
  final unit = switch (age.inDays) {
    >= 365 => year,
    >= 30 => const Duration(days: 30),
    >= 1 => const Duration(days: 1),
    _ when age.inHours >= 1 => const Duration(hours: 1),
    _ => const Duration(minutes: 1),
  };
  final next = unit * (age.inMicroseconds ~/ unit.inMicroseconds + 1);
  // Thirty-day months do not divide a year: "12mo" ends at "1y", not at a
  // thirteenth month.
  return when.add(age < year && next > year ? year : next);
}

/// Builds [relativeTime] of [when] and rebuilds only this subtree when that
/// label changes, as the web refreshes every `.relative-date` while a page
/// stays open.
///
/// It wakes once per label change rather than on a fixed tick, and not at
/// all under a disabled [TickerMode]. Re-arming happens only in build, so a
/// backgrounded app, which draws no frames, wakes at most once until it is
/// shown again.
class RelativeTimeBuilder extends StatefulWidget {
  const RelativeTimeBuilder({
    super.key,
    required this.when,
    required this.builder,
    this.now,
  });

  final DateTime when;
  final Widget Function(BuildContext context, String label) builder;
  final DateTime Function()? now;

  @override
  State<RelativeTimeBuilder> createState() => _RelativeTimeBuilderState();
}

class _RelativeTimeBuilderState extends State<RelativeTimeBuilder> {
  Timer? _timer;
  DateTime? _scheduledFor;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? DateTime.now();
    _schedule(
      TickerMode.valuesOf(context).enabled
          ? _relativeTimeChangesAt(widget.when, now)
          : null,
      now,
    );
    return widget.builder(context, relativeTime(widget.when, now: now));
  }

  void _schedule(DateTime? next, DateTime now) {
    final armed = _timer?.isActive ?? false;
    if (next == _scheduledFor && (armed || next == null)) return;
    _timer?.cancel();
    _timer = null;
    _scheduledFor = next;
    if (next == null) return;
    // Timers run in whole milliseconds. Rounding down could wake just before
    // the change and re-arm with no delay.
    final delay = Duration(
      milliseconds: (next.difference(now).inMicroseconds + 999) ~/ 1000,
    );
    _timer = Timer(delay, () {
      if (mounted) setState(() {});
    });
  }
}

/// A [Text] of [relativeTime] that advances while it stays on screen; see
/// [RelativeTimeBuilder].
class RelativeTimeText extends StatelessWidget {
  const RelativeTimeText(
    this.when, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.now,
  });

  final DateTime when;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => RelativeTimeBuilder(
    when: when,
    now: now,
    builder: (context, label) =>
        Text(label, style: style, maxLines: maxLines, overflow: overflow),
  );
}
