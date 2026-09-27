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
  if (value > 999999) return '${_tenths(value / 1000000)}M';
  if (value > 99999) return '${(value / 1000).floor()}k';
  if (value > 999) return '${_tenths(value / 1000)}k';
  if (value is int) return '$value';
  // A negative fraction rounds to a negative zero whose sign the web drops.
  return value == 0 ? '0' : value.toStringAsFixed(0);
}

String _tenths(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
