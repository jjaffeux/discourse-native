import 'package:discourse_native/l10n/strings.dart';
import 'package:intl/intl.dart';

/// A count abbreviated as Discourse's `number` formatter abbreviates it, for
/// the figures the web draws through that helper: a users directory cell and
/// a link's click badge.
///
/// Thousands keep one decimal up to 99,999 ("10.5k"); from 100,000 they are
/// floored to whole thousands, so 999,999 reads "999k" rather than rounding up
/// to a "1000k" the web never shows; millions keep one decimal again ("1.5M").
/// A fraction is rounded to a whole count first, anything below 1,000 —
/// negative counts included — is left whole, and not-a-number reads "0".
///
/// Unlike the web, a decimal that comes out as ".0" is dropped ("1k", "1M").
String shortNumber(num count) {
  if (count.isNaN) return '0';
  // Kept a double: an integer conversion would saturate a finite value beyond
  // the 64-bit range instead of carrying its magnitude through.
  final value = count is int ? count : count.roundToDouble();
  if (value > 999999) return appL10n.compactMillions(_tenths(value / 1000000));
  if (value > 99999) {
    return appL10n.compactThousands(_whole((value / 1000).floor()));
  }
  if (value > 999) return appL10n.compactThousands(_tenths(value / 1000));
  if (value is int) return _whole(value);
  // A negative fraction rounds to a negative zero whose sign the web drops.
  return _whole(value == 0 ? 0 : value);
}

String _whole(num value) => NumberFormat('0', appL10n.localeName).format(value);

String _tenths(double value) {
  // Preserve Discourse's scientific notation for counts outside fixed precision.
  if (value.abs() >= 1e21) return value.toStringAsFixed(1);
  return NumberFormat('0.#', appL10n.localeName).format(value);
}
