import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Pointer<Void> Function(Size, Size, Size)>(symbol: 'dc_create')
external Pointer<Void> _create(int memory, int stack, int output);
@Native<Void Function(Pointer<Void>)>(symbol: 'dc_destroy')
external void _destroy(Pointer<Void> runtime);
@Native<
  Int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Size,
    Uint64,
    Pointer<Pointer<Utf8>>,
    Pointer<Size>,
  )
>(symbol: 'dc_evaluate')
external int _evaluate(
  Pointer<Void> runtime,
  Pointer<Utf8> source,
  int length,
  int timeoutMicros,
  Pointer<Pointer<Utf8>> output,
  Pointer<Size> outputLength,
);
@Native<Void Function(Pointer<Utf8>)>(symbol: 'dc_free')
external void _free(Pointer<Utf8> output);
@Native<Int64 Function(Pointer<Void>)>(symbol: 'dc_memory')
external int _memory(Pointer<Void> runtime);

enum NativeCookingError {
  javascript,
  timeout,
  outputLimit,
  allocation,
  nonString,
}

final class NativeCookingException implements Exception {
  const NativeCookingException(this.kind, this.message);
  final NativeCookingError kind;
  final String message;
  @override
  String toString() => 'NativeCookingException($kind): $message';
}

/// A synchronous, persistent, bare JavaScript VM. Own it on a worker isolate.
///
/// No native functions, modules, filesystem, network or event loop are exposed
/// to JavaScript. The caller must dispose after a failure before reusing state.
final class NativeCookingRuntime implements Finalizable {
  static final _finalizer = NativeFinalizer(Native.addressOf(_destroy));
  NativeCookingRuntime({
    int memoryLimitBytes = 64 * 1024 * 1024,
    int maxStackBytes = 512 * 1024,
    int maxOutputBytes = 2 * 1024 * 1024,
    this.maxInputBytes = 8 * 1024 * 1024,
  }) {
    if (memoryLimitBytes <= 0 ||
        maxStackBytes <= 0 ||
        maxOutputBytes <= 0 ||
        maxInputBytes <= 0) {
      throw ArgumentError('Runtime limits must be positive');
    }
    _handle = _create(memoryLimitBytes, maxStackBytes, maxOutputBytes);
    if (_handle == nullptr) {
      throw const NativeCookingException(
        NativeCookingError.allocation,
        'Unable to create JavaScript runtime',
      );
    }
    _finalizer.attach(
      this,
      _handle,
      detach: this,
      externalSize: memoryLimitBytes,
    );
  }

  final int maxInputBytes;
  late Pointer<Void> _handle;
  bool _failed = false;

  String evaluate(String source, {required Duration timeout}) {
    _checkOpen();
    if (_failed) throw StateError('Dispose failed runtime before further use');
    if (timeout.inMicroseconds <= 0 || timeout > const Duration(minutes: 1)) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be in (0, 1 minute]');
    }
    if (source.length > maxInputBytes) {
      throw ArgumentError('JavaScript source exceeds input limit');
    }
    // C receives an explicit length; embedded NUL cannot truncate the source.
    final bytes = utf8.encode(source);
    if (bytes.length > maxInputBytes) {
      throw ArgumentError('JavaScript source exceeds input byte limit');
    }
    final input = calloc<Uint8>(bytes.length + 1);
    final output = calloc<Pointer<Utf8>>();
    final outputLength = calloc<Size>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final status = _evaluate(
        _handle,
        input.cast(),
        bytes.length,
        timeout.inMicroseconds,
        output,
        outputLength,
      );
      final result = output.value == nullptr
          ? ''
          : output.value.toDartString(length: outputLength.value);
      if (status != 0) {
        _failed = true;
        throw NativeCookingException(
          NativeCookingError.values[status - 1],
          result.isEmpty
              ? 'JavaScript evaluation failed (status $status)'
              : result,
        );
      }
      return result;
    } finally {
      if (output.value != nullptr) _free(output.value);
      calloc.free(input);
      calloc.free(output);
      calloc.free(outputLength);
    }
  }

  /// QuickJS allocated heap bytes; excludes Dart and allocator overhead.
  int get memoryUsageBytes {
    _checkOpen();
    return _memory(_handle);
  }

  void dispose() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    _destroy(_handle);
    _handle = nullptr;
  }

  void _checkOpen() {
    if (_handle == nullptr) throw StateError('Runtime is disposed');
  }
}
