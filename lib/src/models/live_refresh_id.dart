/// Reads a numeric positive signed 64-bit ID from a live-refresh message.
int? liveRefreshId(Object? value) {
  if (value is int) return value > 0 ? value : null;
  if (value is! double || !value.isFinite || value <= 0) return null;

  // The maximum signed int rounds up to 2^63 as a double. Reject that
  // exclusive bound before toInt can saturate, and fractions before truncation.
  if (value >= 9223372036854775808.0 || value != value.truncateToDouble()) {
    return null;
  }
  return value.toInt();
}
