import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Whether the reader set their device to a 24-hour clock. When they have
/// not, [clockTime] follows their locale, as web's moment `LT` does.
bool use24HourClockOf(BuildContext context) =>
    MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;

/// [value]'s time of day as the reader's clock writes it: 24-hour when
/// [use24HourClock], otherwise in [locale]'s own convention.
///
/// Only the format is decided here. [value]'s own fields are read, so the
/// caller has already chosen the zone: `toLocal()` for the device's, a
/// `TZDateTime` for the account's.
String clockTime(
  DateTime value, {
  required bool use24HourClock,
  String? locale,
}) {
  // A locale without date symbols falls back to the default one rather than
  // throwing from a label.
  final known = Intl.verifiedLocale(
    locale,
    DateFormat.localeExists,
    onFailure: (_) => null,
  );
  final format = (_formats[(known, use24HourClock)] ??= use24HourClock
      ? DateFormat.Hm(known)
      : DateFormat.jm(known));
  // CLDR separates the day period with a narrow no-break space; web's `LT`
  // and Material's time format use a plain one.
  return format.format(value).replaceAll('\u202f', ' ');
}

/// [clockTime] in the reader's clock and locale.
String clockTimeLabel(BuildContext context, DateTime value) => clockTime(
  value,
  use24HourClock: use24HourClockOf(context),
  locale: Localizations.maybeLocaleOf(context)?.toString(),
);

/// Keyed by verified locale, so a locale whose symbols arrive later is not
/// held to the fallback it was first formatted with.
final _formats = <(String?, bool), DateFormat>{};
