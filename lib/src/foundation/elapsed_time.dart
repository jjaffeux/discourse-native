/// How long ago [start] was at [now], to compare against a window.
///
/// The wall clock can be set backward, by the reader or by a time sync, which
/// leaves a recorded moment in the future. Its age is then unknowable, and a
/// negative one would read as younger than every window, holding a cooldown
/// shut or an entry fresh until the clock caught up. Such a [start] answers
/// longer than any window, so the caller's own expiry applies at once.
///
/// Comparisons only. Code that adds or subtracts a measured amount has to
/// decide for itself what a negative one means.
Duration elapsedSince(DateTime start, {required DateTime now}) {
  final elapsed = now.difference(start);
  return elapsed.isNegative ? _longerThanAnyWindow : elapsed;
}

const _longerThanAnyWindow = Duration(microseconds: 0x7FFFFFFFFFFFFFFF);

int? timeGapDaysBetween(DateTime? earlier, DateTime? later) {
  if (earlier == null || later == null) return null;
  return later.difference(earlier).inDays;
}
