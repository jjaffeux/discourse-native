import 'dart:io';

/// Reads either form of Retry-After without allowing an untrusted response to
/// suspend an origin indefinitely. An elapsed HTTP date permits an immediate
/// retry; an unreadable value lets the caller use its own fallback policy.
///
/// A readable response Date supplies the reference for HTTP dates to tolerate
/// device clock skew. Date approximates message origination, so this is a
/// resilience choice, not an RFC requirement or a measure of response transit
/// time. Missing or unreadable Date values fall back to [now].
Duration? parseRetryAfter(
  String? header, {
  required Duration maximum,
  required DateTime now,
  String? serverDate,
}) {
  final value = header?.trim();
  if (value == null || value.isEmpty) return null;

  final delta = _parseDelta(value, maximum);
  if (delta != null) return delta;

  final date = _tryParseHttpDate(value);
  if (date == null) return null;
  final reference = _tryParseHttpDate(serverDate) ?? now.toUtc();
  final delay = date.difference(reference);
  if (delay <= Duration.zero) return Duration.zero;
  return delay > maximum ? maximum : delay;
}

final _decimalDigits = RegExp(r'^[0-9]+$');
final _leadingZeros = RegExp(r'^0+');

Duration? _parseDelta(String value, Duration maximum) {
  final limit = maximum.inSeconds;
  if (maximum.isNegative) {
    if (!_decimalDigits.hasMatch(value)) return null;
    final digits = value.replaceFirst(_leadingZeros, '');
    if (digits.isEmpty) return Duration.zero;
    final oldLimit = limit.toString();
    if (digits.length > oldLimit.length ||
        (digits.length == oldLimit.length && digits.compareTo(oldLimit) > 0)) {
      return maximum;
    }
    return Duration(seconds: int.parse(digits));
  }

  var seconds = 0;
  var capped = false;
  for (var index = 0; index < value.length; index++) {
    final digit = value.codeUnitAt(index) - 0x30;
    if (digit < 0 || digit > 9) return null;
    if (capped) continue;
    if (digit > limit || seconds > (limit - digit) ~/ 10) {
      capped = true;
    } else {
      seconds = seconds * 10 + digit;
    }
  }
  return capped ? maximum : Duration(seconds: seconds);
}

DateTime? _tryParseHttpDate(String? value) {
  if (value == null) return null;
  try {
    return HttpDate.parse(value.trim());
  } on HttpException {
    return null;
  }
}
