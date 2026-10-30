/// Resource limits and concurrency used while decoding an AVIF image.
final class AvifDecodeOptions {
  const AvifDecodeOptions({
    this.maxThreads = 4,
    this.maxDimension = 32768,
    this.maxPixels = 268435456,
    this.maxInputBytes = 268435456,
  }) : assert(maxThreads > 0),
       assert(maxDimension > 0),
       assert(maxPixels > 0),
       assert(maxInputBytes > 0);

  /// Maximum number of codec worker threads.
  ///
  /// `Avif.decodeSync` may use this complete allowance. `Avif.decode` may use
  /// fewer threads to preserve CPU capacity for the application event loop and
  /// renderer while multiple native workers are active.
  final int maxThreads;

  /// Maximum accepted width or height in pixels.
  final int maxDimension;

  /// Maximum accepted pixel count.
  final int maxPixels;

  /// Maximum accepted encoded input size in bytes.
  final int maxInputBytes;

  void validate() {
    if (maxThreads <= 0 || maxThreads > 0x7fffffff) {
      throw ArgumentError.value(
        maxThreads,
        'maxThreads',
        'must be between 1 and 2147483647',
      );
    }
    if (maxDimension <= 0 || maxDimension > 0xffffffff) {
      throw ArgumentError.value(
        maxDimension,
        'maxDimension',
        'must be between 1 and 4294967295',
      );
    }
    if (maxPixels <= 0 || maxPixels > 0xffffffff) {
      throw ArgumentError.value(
        maxPixels,
        'maxPixels',
        'must be between 1 and 4294967295',
      );
    }
    if (maxInputBytes <= 0) {
      throw ArgumentError.value(
        maxInputBytes,
        'maxInputBytes',
        'must be positive',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AvifDecodeOptions &&
      other.maxThreads == maxThreads &&
      other.maxDimension == maxDimension &&
      other.maxPixels == maxPixels &&
      other.maxInputBytes == maxInputBytes;

  @override
  int get hashCode =>
      Object.hash(maxThreads, maxDimension, maxPixels, maxInputBytes);
}
