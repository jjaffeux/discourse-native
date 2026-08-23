/// What day a moment falls on, and what that day is called.
///
/// A topic's stream and a chat channel's both put a date line above each new
/// day, and had each written this out: the same truncation to midnight, the
/// same today/yesterday naming with the same warning about DST above it, and
/// the same table of month names. Nothing about a calendar day differs between
/// the two, so a second copy could only ever drift.
///
/// Pure Dart, because `chat_stream.dart` builds its rows without a binding.
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

/// Today and yesterday by name, everything else by date.
///
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

/// The name of a month numbered the way [DateTime.month] numbers it.
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
