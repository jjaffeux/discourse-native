library;

import 'package:discourse_native/l10n/strings.dart';
import 'package:intl/intl.dart';

/// The reader's midnight at or before [value].
///
/// Topic timelines use this for every post's creation date, regardless of
/// installed plugins. It carries no event or calendar-plugin semantics.
///
/// Local, not the site's: a message written at 23:00 in Sydney is read under
/// yesterday's heading in Paris, and the heading a reader scrolls past has to
/// agree with the clock on their wall.
DateTime? calendarDay(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// What a stream's day separator calls [day]: Today, Yesterday, or its date
/// spelled out. A day still to come is dated rather than named.
String dayLabel(DateTime day, {required DateTime now}) {
  final offset = _calendarDaysFrom(now, day);
  if (offset == 0) return appL10n.todayDcalendarevents;
  if (offset == -1) return appL10n.yesterday;
  return DateFormat(
    appL10n.calendarDatePattern,
    appL10n.localeName,
  ).format(day);
}

/// Today or Tomorrow when [day] is one of them, for a moment the reader is
/// waiting on such as a reminder. Any other day answers null, leaving the
/// caller to date it in its own format.
String? upcomingDayName(DateTime day, {required DateTime now}) =>
    switch (_calendarDaysFrom(now, day)) {
      0 => appL10n.todayDcalendarevents,
      1 => appL10n.tomorrow,
      _ => null,
    };

/// Days are compared as calendar dates, not elapsed time: local midnights on
/// either side of a DST change sit 23 or 25 hours apart, so a truncating
/// duration difference would misname the days after a transition and a
/// midnight plus 24 hours would miss the next one.
int _calendarDaysFrom(DateTime now, DateTime day) {
  final today = DateTime.utc(now.year, now.month, now.day);
  return DateTime.utc(day.year, day.month, day.day).difference(today).inDays;
}

String monthName(int month) =>
    DateFormat.MMMM(appL10n.localeName).format(DateTime(2000, month));

/// Locale-specific abbreviation; some languages do not use three letters.
String shortMonthName(int month) =>
    DateFormat.MMM(appL10n.localeName).format(DateTime(2000, month));
