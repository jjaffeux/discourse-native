/// Stable error categories reported by the native decoder.
enum AvifErrorCode {
  invalidInput,
  decodeFailed,
  limitExceeded,
  unsupported,
  outOfMemory,
  resourceExhausted,
  cancelled,
  internal,
}

/// An AVIF decode failure.
final class AvifException implements Exception {
  const AvifException(this.code, this.message);

  final AvifErrorCode code;
  final String message;

  @override
  String toString() => 'AvifException(${code.name}): $message';
}
