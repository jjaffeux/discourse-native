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

  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds.clamp(0, maximum.inSeconds));
  }

  final date = _tryParseHttpDate(value);
  if (date == null) return null;
  final reference = _tryParseHttpDate(serverDate) ?? now.toUtc();
  final delay = date.difference(reference);
  if (delay <= Duration.zero) return Duration.zero;
  return delay > maximum ? maximum : delay;
}

DateTime? _tryParseHttpDate(String? value) {
  if (value == null) return null;
  try {
    return HttpDate.parse(value.trim());
  } on HttpException {
    return null;
  }
}
