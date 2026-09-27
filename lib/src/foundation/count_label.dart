library;

/// [count] followed by the noun it counts: [singular] for exactly one and
/// [plural] for every other count, zero included — "1 reply", "0 replies".
///
/// [plural] defaults to [singular] plus an "s", so a noun that does not form
/// its plural that way ("reply", "person") must name it. [number] is how the
/// count is written where a surface groups or abbreviates it ("1,204",
/// "1.2K"); the noun still agrees with [count], never with that text.
String countLabel(
  int count,
  String singular, {
  String? plural,
  String? number,
}) => '${number ?? count} ${countNoun(count, singular, plural: plural)}';

/// The noun alone that [countLabel] would write after [count], for a layout
/// that sets the number apart from it.
String countNoun(int count, String singular, {String? plural}) =>
    count == 1 ? singular : plural ?? '${singular}s';
