import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'avif.dart';
import 'avif_decode_options.dart';
import 'avif_exception.dart';
import 'avif_frame.dart';
import 'native_bindings.dart';
import 'native_support.dart';

/// How an AVIF sequence declares repeated playback.
enum AvifRepetitionKind { finite, infinite, unknown }

/// Repetition metadata for one AVIF sequence.
final class AvifRepetition {
  const AvifRepetition._(this.kind, this.totalPlayCount);

  /// A sequence that plays [totalPlayCount] times.
  factory AvifRepetition.finite(int totalPlayCount) {
    if (totalPlayCount <= 0) {
      throw ArgumentError.value(
        totalPlayCount,
        'totalPlayCount',
        'must be positive',
      );
    }
    return AvifRepetition._(AvifRepetitionKind.finite, totalPlayCount);
  }

  /// A sequence that repeats without a declared end.
  static const infinite = AvifRepetition._(AvifRepetitionKind.infinite, null);

  /// A sequence whose container does not declare repetition behavior.
  static const unknown = AvifRepetition._(AvifRepetitionKind.unknown, null);

  final AvifRepetitionKind kind;

  /// Total play count for [AvifRepetitionKind.finite], otherwise `null`.
  final int? totalPlayCount;

  @override
  bool operator ==(Object other) =>
      other is AvifRepetition &&
      other.kind == kind &&
      other.totalPlayCount == totalPlayCount;

  @override
  int get hashCode => Object.hash(kind, totalPlayCount);

  @override
  String toString() => switch (kind) {
    AvifRepetitionKind.finite => 'AvifRepetition.finite($totalPlayCount)',
    AvifRepetitionKind.infinite => 'AvifRepetition.infinite',
    AvifRepetitionKind.unknown => 'AvifRepetition.unknown',
  };
}

/// Parsed dimensions, timing, and repetition metadata for an AVIF sequence.
final class AvifSequenceInfo {
  const AvifSequenceInfo({
    required this.width,
    required this.height,
    required this.sourceBitDepth,
    required this.hasAlpha,
    required this.frameCount,
    required this.duration,
    required this.repetition,
  });

  final int width;
  final int height;
  final int sourceBitDepth;
  final bool hasAlpha;
  final int frameCount;
  final Duration duration;
  final AvifRepetition repetition;

  bool get isAnimated => frameCount > 1;
}

/// One decoded frame from an [AvifSequenceDecoder].
final class AvifSequenceFrame {
  const AvifSequenceFrame({
    required this.image,
    required this.index,
    required this.duration,
  });

  final AvifFrame image;
  final int index;
  final Duration duration;
}

/// A cancellable asynchronous sequence-open operation.
final class AvifSequenceOpenOperation {
  AvifSequenceOpenOperation._(this.result, this._cancel);

  final Future<AvifSequenceDecoder> result;
  final bool Function() _cancel;

  bool cancel() => _cancel();
}

/// Stateful decoder for one still or animated AVIF source.
final class AvifSequenceDecoder {
  AvifSequenceDecoder._(this._handle, this.info, this._prefetchedFrame);

  final int _handle;
  final AvifSequenceInfo info;
  AvifSequenceFrame? _prefetchedFrame;
  _NativeSequenceOperation? _activeOperation;
  var _disposed = false;

  /// Opens [bytes] on the bounded native worker pool.
  ///
  /// When [prefetchFirstFrame] is true, opening also decodes frame zero and
  /// the first [nextFrame] call returns that prefetched frame without another
  /// native worker submission. The default preserves metadata-only opening.
  static Future<AvifSequenceDecoder> open(
    Uint8List bytes, {
    AvifDecodeOptions options = const AvifDecodeOptions(),
    int? targetWidth,
    int? targetHeight,
    bool prefetchFirstFrame = false,
  }) => startOpen(
    bytes,
    options: options,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    prefetchFirstFrame: prefetchFirstFrame,
  ).result;

  /// Starts a cancellable sequence-open operation.
  ///
  /// [prefetchFirstFrame] has the same behavior as in [open].
  static AvifSequenceOpenOperation startOpen(
    Uint8List bytes, {
    AvifDecodeOptions options = const AvifDecodeOptions(),
    int? targetWidth,
    int? targetHeight,
    bool prefetchFirstFrame = false,
  }) {
    options.validate();
    validateAvifTargetSize(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    validateAvifInput(bytes, options);
    checkNativeAbi();
    final operation = _SequenceDispatcher.instance.open(
      bytes,
      options: options,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      prefetchFirstFrame: prefetchFirstFrame,
    );
    return AvifSequenceOpenOperation._(
      operation.result.then(_decoderFromOpenResult),
      operation.cancel,
    );
  }

  /// Decodes the next frame, or returns `null` after the final frame.
  Future<AvifSequenceFrame?> nextFrame() async {
    _ensureAvailable();
    final prefetchedFrame = _prefetchedFrame;
    if (prefetchedFrame != null) {
      _prefetchedFrame = null;
      return prefetchedFrame;
    }
    final operation = _SequenceDispatcher.instance.next(_handle);
    _activeOperation = operation;
    try {
      final pointer = await operation.result;
      return _frameFromSequenceResult(pointer);
    } finally {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    }
  }

  /// Rewinds the decoder to before its first frame.
  Future<void> reset() async {
    _ensureAvailable();
    _prefetchedFrame = null;
    final operation = _SequenceDispatcher.instance.reset(_handle);
    _activeOperation = operation;
    try {
      final pointer = await operation.result;
      try {
        final result = pointer.ref;
        if (result.status != 0) throw _sequenceException(result);
      } finally {
        lavifSequenceResultRelease(pointer);
      }
    } finally {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    }
  }

  /// Cancels pending work and releases the native sequence.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _prefetchedFrame = null;
    _activeOperation?.cancel();
    lavifSequenceRelease(_handle);
  }

  void _ensureAvailable() {
    if (_disposed) {
      throw StateError('The AVIF sequence decoder has been disposed.');
    }
    if (_activeOperation != null) {
      throw StateError('An AVIF sequence operation is already in progress.');
    }
  }
}

AvifSequenceDecoder _decoderFromOpenResult(
  Pointer<LavifSequenceResult> pointer,
) {
  var handle = 0;
  try {
    final result = pointer.ref;
    if (result.status != 0) throw _sequenceException(result);
    handle = result.handle;
    if (handle == 0 || result.frameCount == 0) {
      throw const AvifException(
        AvifErrorCode.internal,
        'The native decoder returned invalid sequence metadata.',
      );
    }
    final repetition = result.frameCount == 1
        ? AvifRepetition.finite(1)
        : switch (result.repetitionCount) {
            -1 => AvifRepetition.infinite,
            -2 => AvifRepetition.unknown,
            final count when count >= 0 => AvifRepetition.finite(count + 1),
            _ => throw const AvifException(
              AvifErrorCode.invalidInput,
              'The AVIF sequence has an invalid repetition count.',
            ),
          };
    final info = AvifSequenceInfo(
      width: result.width,
      height: result.height,
      sourceBitDepth: result.sourceBitDepth,
      hasAlpha: result.hasAlpha != 0,
      frameCount: result.frameCount,
      duration: _scaledDuration(result.durationInTimescales, result.timescale),
      repetition: repetition,
    );
    final prefetchedFrame = result.pixels == nullptr
        ? null
        : _takeSequenceFrame(pointer);
    return AvifSequenceDecoder._(handle, info, prefetchedFrame);
  } catch (_) {
    if (handle != 0) lavifSequenceRelease(handle);
    rethrow;
  } finally {
    lavifSequenceResultRelease(pointer);
  }
}

AvifSequenceFrame? _frameFromSequenceResult(
  Pointer<LavifSequenceResult> pointer,
) {
  try {
    final result = pointer.ref;
    if (result.status == 7) return null;
    if (result.status != 0) throw _sequenceException(result);
    return _takeSequenceFrame(pointer);
  } finally {
    lavifSequenceResultRelease(pointer);
  }
}

AvifSequenceFrame _takeSequenceFrame(Pointer<LavifSequenceResult> pointer) {
  final result = pointer.ref;
  if (result.pixels == nullptr || result.pixelsLength == 0) {
    throw const AvifException(
      AvifErrorCode.internal,
      'The native decoder returned an empty sequence frame.',
    );
  }
  final pixels = result.pixels;
  final pixelsLength = result.pixelsLength;
  final width = result.width;
  final height = result.height;
  final rowBytes = result.rowBytes;
  final sourceBitDepth = result.sourceBitDepth;
  final hasAlpha = result.hasAlpha != 0;
  final frameIndex = result.frameIndex;
  final frameDuration = _scaledDuration(
    result.frameDurationInTimescales,
    result.frameTimescale,
  );
  final owner = lavifSequenceResultTakePixels(pointer);
  if (owner == nullptr) {
    throw const AvifException(
      AvifErrorCode.internal,
      'The native decoder did not transfer its sequence pixel buffer.',
    );
  }
  late final Uint8List dartPixels;
  try {
    dartPixels = pixels.asTypedList(
      pixelsLength,
      finalizer: lavifPixelsReleaseAddress,
      token: owner,
    );
  } catch (_) {
    lavifPixelsRelease(owner);
    rethrow;
  }
  return AvifSequenceFrame(
    image: AvifFrame(
      pixels: dartPixels,
      width: width,
      height: height,
      rowBytes: rowBytes,
      sourceBitDepth: sourceBitDepth,
      hasAlpha: hasAlpha,
    ),
    index: frameIndex,
    duration: frameDuration,
  );
}

Duration _scaledDuration(int units, int timescale) {
  if (units == 0 || timescale == 0) return Duration.zero;
  return Duration(
    microseconds: (units * 1000000 + timescale ~/ 2) ~/ timescale,
  );
}

AvifException _sequenceException(LavifSequenceResult result) => AvifException(
  avifErrorCode(result.status),
  readNativeError(result.error, result.errorLength),
);

enum _SequenceRequestKind { open, next, reset }

final class _NativeSequenceOperation {
  const _NativeSequenceOperation(this.result, this.cancel);

  final Future<Pointer<LavifSequenceResult>> result;
  final bool Function() cancel;
}

final class _SequenceDispatcher {
  _SequenceDispatcher() : _workerCount = Avif.asyncWorkerCount {
    _port = RawReceivePort(_handleResult)..keepIsolateAlive = false;
  }

  static final instance = _SequenceDispatcher();
  static const _maximumPendingOperations = 256;
  static const _maximumPendingInputBytes = 512 * 1024 * 1024;

  final int _workerCount;
  final ListQueue<_SequenceRequest> _queue = ListQueue<_SequenceRequest>();
  final Map<int, _SequenceRequest> _active = <int, _SequenceRequest>{};
  late final RawReceivePort _port;
  var _nextRequestId = 1;
  var _reservedInputBytes = 0;

  _NativeSequenceOperation open(
    Uint8List bytes, {
    required AvifDecodeOptions options,
    required int? targetWidth,
    required int? targetHeight,
    required bool prefetchFirstFrame,
  }) {
    if (_isExhausted(bytes.length)) return _exhausted();
    final input = lavifInputAllocate(bytes.length);
    if (input == nullptr) {
      return _failed(
        const AvifException(
          AvifErrorCode.outOfMemory,
          'Could not allocate the native AVIF sequence input buffer.',
        ),
      );
    }
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
    } catch (_) {
      lavifInputRelease(input, bytes.length);
      rethrow;
    }
    final request = _SequenceRequest(
      id: _nextRequestId++,
      kind: _SequenceRequestKind.open,
      input: input,
      inputLength: bytes.length,
      options: options,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      prefetchFirstFrame: prefetchFirstFrame,
    );
    _reservedInputBytes += bytes.length;
    return _enqueue(request);
  }

  _NativeSequenceOperation next(int handle) => _enqueue(
    _SequenceRequest(
      id: _nextRequestId++,
      kind: _SequenceRequestKind.next,
      handle: handle,
    ),
  );

  _NativeSequenceOperation reset(int handle) => _enqueue(
    _SequenceRequest(
      id: _nextRequestId++,
      kind: _SequenceRequestKind.reset,
      handle: handle,
    ),
  );

  bool _isExhausted(int inputLength) =>
      _queue.length + _active.length >= _maximumPendingOperations ||
      _reservedInputBytes + inputLength > _maximumPendingInputBytes;

  _NativeSequenceOperation _enqueue(_SequenceRequest request) {
    if (_queue.length + _active.length >= _maximumPendingOperations) {
      return _exhausted();
    }
    _queue.addLast(request);
    _dispatch();
    return _NativeSequenceOperation(
      request.completer.future,
      () => _cancel(request),
    );
  }

  _NativeSequenceOperation _exhausted() => _failed(
    const AvifException(
      AvifErrorCode.resourceExhausted,
      'The native AVIF sequence queue is full.',
    ),
  );

  _NativeSequenceOperation _failed(Object error) => _NativeSequenceOperation(
    Future<Pointer<LavifSequenceResult>>.error(error),
    () => false,
  );

  bool _cancel(_SequenceRequest request) {
    if (request.cancelled || request.completer.isCompleted) return false;
    request.cancelled = true;
    final wasQueued = _queue.remove(request);
    if (wasQueued) _releaseQueuedInput(request);
    request.completer.completeError(
      const AvifException(
        AvifErrorCode.cancelled,
        'AVIF sequence operation cancelled.',
      ),
    );
    if (wasQueued) _dispatch();
    return true;
  }

  void _releaseQueuedInput(_SequenceRequest request) {
    final input = request.input;
    if (input == null) return;
    lavifInputRelease(input, request.inputLength);
    _reservedInputBytes -= request.inputLength;
  }

  void _dispatch() {
    while (_active.length < _workerCount && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _active[request.id] = request;
      _port.keepIsolateAlive = true;
      final status = switch (request.kind) {
        _SequenceRequestKind.open => lavifSequenceOpenAsync(
          request.input!,
          request.inputLength,
          request.options!.maxThreads,
          request.options!.maxDimension,
          request.options!.maxPixels,
          request.targetWidth ?? 0,
          request.targetHeight ?? 0,
          request.prefetchFirstFrame ? 1 : 0,
          _port.sendPort.nativePort,
          NativeApi.postCObject,
          request.id,
        ),
        _SequenceRequestKind.next => lavifSequenceNextAsync(
          request.handle,
          _port.sendPort.nativePort,
          NativeApi.postCObject,
          request.id,
        ),
        _SequenceRequestKind.reset => lavifSequenceResetAsync(
          request.handle,
          _port.sendPort.nativePort,
          NativeApi.postCObject,
          request.id,
        ),
      };
      if (status != 0) {
        _active.remove(request.id);
        if (request.kind == _SequenceRequestKind.open) {
          _reservedInputBytes -= request.inputLength;
        }
        request.completer.completeError(
          AvifException(
            avifErrorCode(status),
            'Could not submit AVIF sequence work to the native worker pool.',
          ),
        );
      }
    }
    _updatePortLiveness();
  }

  void _handleResult(Object? message) {
    if (message is! int || message == 0) {
      Zone.current.handleUncaughtError(
        StateError(
          'The native AVIF sequence worker returned an invalid message.',
        ),
        StackTrace.current,
      );
      return;
    }
    final pointer = Pointer<LavifSequenceResult>.fromAddress(message);
    final request = _active.remove(pointer.ref.requestId);
    if (request == null) {
      if (pointer.ref.handle != 0) lavifSequenceRelease(pointer.ref.handle);
      lavifSequenceResultRelease(pointer);
      Zone.current.handleUncaughtError(
        StateError(
          'The native AVIF sequence worker returned an unknown request.',
        ),
        StackTrace.current,
      );
      return;
    }
    if (request.kind == _SequenceRequestKind.open) {
      _reservedInputBytes -= request.inputLength;
    }
    if (request.cancelled) {
      if (pointer.ref.handle != 0) lavifSequenceRelease(pointer.ref.handle);
      lavifSequenceResultRelease(pointer);
    } else {
      request.completer.complete(pointer);
    }
    _dispatch();
    _updatePortLiveness();
  }

  void _updatePortLiveness() {
    if (_active.isEmpty && _queue.isEmpty) _port.keepIsolateAlive = false;
  }
}

final class _SequenceRequest {
  _SequenceRequest({
    required this.id,
    required this.kind,
    this.input,
    this.inputLength = 0,
    this.options,
    this.targetWidth,
    this.targetHeight,
    this.prefetchFirstFrame = false,
    this.handle = 0,
  });

  final int id;
  final _SequenceRequestKind kind;
  final Pointer<Uint8>? input;
  final int inputLength;
  final AvifDecodeOptions? options;
  final int? targetWidth;
  final int? targetHeight;
  final bool prefetchFirstFrame;
  final int handle;
  final Completer<Pointer<LavifSequenceResult>> completer = Completer();
  bool cancelled = false;
}
