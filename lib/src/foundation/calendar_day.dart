library;

/// The reader's midnight at or before [value].
///
/// Local, not the site's: a message written at 23:00 in Sydney is read under
/// yesterday's heading in Paris, and the heading a reader scrolls past has to
/// agree with the clock on their wall.
DateTime? calendarDay(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Days are compared as calendar dates, not elapsed time: local midnights on
/// either side of a DST change sit 23 or 25 hours apart, and a truncating
/// duration difference would then misname the days after a transition.
String dayLabel(DateTime day, {required DateTime now}) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final start = DateTime.utc(day.year, day.month, day.day);
  final delta = today.difference(start).inDays;
  if (delta == 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  return '${day.day} ${monthName(day.month)} ${day.year}';
}

String monthName(int month) => _months[month - 1];

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
