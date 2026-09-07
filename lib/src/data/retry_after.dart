import 'dart:io';

/// Reads either form of Retry-After without allowing an untrusted response to
/// suspend an origin indefinitely. An elapsed HTTP date permits an immediate
/// retry; an unreadable value lets the caller use its own fallback policy.
Duration? parseRetryAfter(
  String? header, {
  required Duration maximum,
  required DateTime now,
}) {
  final value = header?.trim();
  if (value == null || value.isEmpty) return null;

  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) {
    return Duration(seconds: seconds.clamp(0, maximum.inSeconds));
  }

  final DateTime date;
  try {
    date = HttpDate.parse(value);
  } on HttpException {
    return null;
  }
  final delay = date.difference(now.toUtc());
  if (delay <= Duration.zero) return Duration.zero;
  return delay > maximum ? maximum : delay;
}
