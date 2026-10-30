import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'avif_decode_options.dart';
import 'avif_exception.dart';
import 'avif_frame.dart';
import 'native_bindings.dart';
import 'native_support.dart';

/// Entry point for decoding AVIF images.
abstract final class Avif {
  static Future<void>? _warmUpFuture;

  /// The linked libavif version.
  static String get nativeVersion {
    checkNativeAbi();
    final version = lavifLibavifVersion();
    if (version == nullptr) {
      throw StateError('The native decoder returned no libavif version.');
    }
    return version.cast<Utf8>().toDartString();
  }

  /// Versions of the native codecs linked into libavif.
  static String get nativeCodecVersions {
    checkNativeAbi();
    final versions = lavifCodecVersions();
    if (versions == nullptr) {
      throw StateError('The native decoder returned no codec versions.');
    }
    return versions.cast<Utf8>().toDartString();
  }

  /// Native acceleration features linked into this decoder build.
  static String get nativeFeatures {
    checkNativeAbi();
    final features = lavifFeatures();
    if (features == nullptr) {
      throw StateError('The native decoder returned no feature information.');
    }
    return features.cast<Utf8>().toDartString();
  }

  /// Number of persistent native workers used by [decode].
  static int get asyncWorkerCount {
    checkNativeAbi();
    return lavifAsyncWorkerCount();
  }

  /// Maximum codec threads assigned to each asynchronous worker.
  static int get asyncThreadsPerWorker {
    checkNativeAbi();
    return lavifAsyncThreadsPerWorker();
  }

  /// Prepares the persistent native decode workers off the calling isolate.
  ///
  /// Applications may await this during startup to remove worker creation from
  /// the first decode. Repeated calls share the same initialization.
  static Future<void> warmUp() =>
      _warmUpFuture ??= Isolate.run(_warmUpNativeWorkers);

  /// Decodes [bytes] off the calling isolate.
  static Future<AvifFrame> decode(
    Uint8List bytes, {
    AvifDecodeOptions options = const AvifDecodeOptions(),
    int? targetWidth,
    int? targetHeight,
  }) {
    return startDecode(
      bytes,
      options: options,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    ).result;
  }

  /// Starts a cancellable decode on the bounded native worker pool.
  ///
  /// Cancellation removes queued work immediately. A decode that has already
  /// entered the codec is allowed to finish, but its result is discarded.
  static AvifDecodeOperation startDecode(
    Uint8List bytes, {
    AvifDecodeOptions options = const AvifDecodeOptions(),
    int? targetWidth,
    int? targetHeight,
  }) {
    options.validate();
    validateAvifTargetSize(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    validateAvifInput(bytes, options);
    checkNativeAbi();
    return _AsyncDecodeDispatcher.instance.decode(
      bytes,
      options: options,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
  }

  /// Decodes [bytes] on the calling isolate.
  ///
  /// Prefer [decode] in applications because native decoding may take long
  /// enough to block a UI or event-loop isolate.
  static AvifFrame decodeSync(
    Uint8List bytes, {
    AvifDecodeOptions options = const AvifDecodeOptions(),
    int? targetWidth,
    int? targetHeight,
  }) {
    options.validate();
    validateAvifTargetSize(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    checkNativeAbi();

    validateAvifInput(bytes, options);

    final nativeBytes = malloc<Uint8>(bytes.length);
    try {
      nativeBytes.asTypedList(bytes.length).setAll(0, bytes);
      final resultPointer = lavifDecodeRgba8(
        nativeBytes,
        bytes.length,
        options.maxThreads,
        options.maxDimension,
        options.maxPixels,
        targetWidth ?? 0,
        targetHeight ?? 0,
      );
      if (resultPointer == nullptr) {
        throw const AvifException(
          AvifErrorCode.internal,
          'The native decoder returned no result.',
        );
      }

      try {
        final result = resultPointer.ref;
        if (result.status != 0) {
          throw AvifException(
            avifErrorCode(result.status),
            readNativeError(result.error, result.errorLength),
          );
        }
        if (result.pixels == nullptr || result.pixelsLength == 0) {
          throw const AvifException(
            AvifErrorCode.internal,
            'The native decoder returned an empty pixel buffer.',
          );
        }

        return _frameFromResult(resultPointer);
      } finally {
        lavifDecodeResultRelease(resultPointer);
      }
    } finally {
      malloc.free(nativeBytes);
    }
  }

  static AvifFrame _takeAsyncResult(Pointer<LavifDecodeResult> resultPointer) {
    try {
      final result = resultPointer.ref;
      if (result.status != 0) {
        throw AvifException(
          avifErrorCode(result.status),
          readNativeError(result.error, result.errorLength),
        );
      }
      if (result.pixels == nullptr || result.pixelsLength == 0) {
        throw const AvifException(
          AvifErrorCode.internal,
          'The native decoder returned an empty pixel buffer.',
        );
      }
      return _frameFromResult(resultPointer);
    } finally {
      lavifDecodeResultRelease(resultPointer);
    }
  }
}

void _warmUpNativeWorkers() {
  checkNativeAbi();
  if (lavifAsyncWorkerCount() <= 0 || lavifAsyncThreadsPerWorker() <= 0) {
    throw StateError('Could not start the native AVIF decode worker pool.');
  }
}

/// One asynchronous AVIF decode that can be cancelled by its owner.
final class AvifDecodeOperation {
  AvifDecodeOperation._(this.result, this._cancel);

  final Future<AvifFrame> result;
  final bool Function() _cancel;

  /// Returns whether pending work was cancelled by this call.
  bool cancel() => _cancel();
}

AvifFrame _frameFromResult(Pointer<LavifDecodeResult> pointer) {
  final result = pointer.ref;
  final pixels = result.pixels;
  final pixelsLength = result.pixelsLength;
  final width = result.width;
  final height = result.height;
  final rowBytes = result.rowBytes;
  final sourceBitDepth = result.sourceBitDepth;
  final hasAlpha = result.hasAlpha != 0;
  final owner = lavifDecodeResultTakePixels(pointer);
  if (owner == nullptr) {
    throw const AvifException(
      AvifErrorCode.internal,
      'The native decoder did not transfer its pixel buffer.',
    );
  }
  try {
    return AvifFrame(
      pixels: pixels.asTypedList(
        pixelsLength,
        finalizer: lavifPixelsReleaseAddress,
        token: owner,
      ),
      width: width,
      height: height,
      rowBytes: rowBytes,
      sourceBitDepth: sourceBitDepth,
      hasAlpha: hasAlpha,
    );
  } catch (_) {
    lavifPixelsRelease(owner);
    rethrow;
  }
}

final class _AsyncDecodeDispatcher {
  _AsyncDecodeDispatcher() : _workerCount = lavifAsyncWorkerCount() {
    if (_workerCount <= 0 || lavifAsyncThreadsPerWorker() <= 0) {
      throw StateError('Could not start the native AVIF decode worker pool.');
    }
    _port = RawReceivePort(_handleResult)..keepIsolateAlive = false;
  }

  static final _AsyncDecodeDispatcher instance = _AsyncDecodeDispatcher();
  static const _maximumPendingDecodes = 256;
  static const _maximumPendingInputBytes = 512 * 1024 * 1024;

  final int _workerCount;
  final ListQueue<_PendingDecode> _queue = ListQueue<_PendingDecode>();
  final Map<int, _PendingDecode> _active = <int, _PendingDecode>{};
  late final RawReceivePort _port;
  var _nextRequestId = 1;
  var _reservedInputBytes = 0;

  AvifDecodeOperation decode(
    Uint8List bytes, {
    required AvifDecodeOptions options,
    required int? targetWidth,
    required int? targetHeight,
  }) {
    if (_queue.length + _active.length >= _maximumPendingDecodes ||
        _reservedInputBytes + bytes.length > _maximumPendingInputBytes) {
      final future = Future<AvifFrame>.error(
        const AvifException(
          AvifErrorCode.resourceExhausted,
          'The native AVIF decode queue is full.',
        ),
      );
      return AvifDecodeOperation._(future, () => false);
    }

    final input = lavifInputAllocate(bytes.length);
    if (input == nullptr) {
      final future = Future<AvifFrame>.error(
        const AvifException(
          AvifErrorCode.outOfMemory,
          'Could not allocate the native AVIF input buffer.',
        ),
      );
      return AvifDecodeOperation._(future, () => false);
    }
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
    } catch (_) {
      lavifInputRelease(input, bytes.length);
      rethrow;
    }

    final request = _PendingDecode(
      id: _nextRequestId++,
      input: input,
      length: bytes.length,
      options: options,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    _reservedInputBytes += bytes.length;
    _queue.addLast(request);
    _dispatch();
    return AvifDecodeOperation._(
      request.completer.future,
      () => _cancel(request),
    );
  }

  bool _cancel(_PendingDecode request) {
    if (request.cancelled || request.completer.isCompleted) return false;
    request.cancelled = true;
    final wasQueued = _queue.remove(request);
    if (wasQueued) {
      lavifInputRelease(request.input, request.length);
      _reservedInputBytes -= request.length;
    }
    request.completer.completeError(
      const AvifException(AvifErrorCode.cancelled, 'AVIF decode cancelled.'),
    );
    if (wasQueued) _dispatch();
    return true;
  }

  void _dispatch() {
    while (_active.length < _workerCount && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      _active[request.id] = request;
      _port.keepIsolateAlive = true;
      final status = lavifDecodeRgba8Async(
        request.input,
        request.length,
        request.options.maxThreads,
        request.options.maxDimension,
        request.options.maxPixels,
        request.targetWidth ?? 0,
        request.targetHeight ?? 0,
        _port.sendPort.nativePort,
        NativeApi.postCObject,
        request.id,
      );
      if (status != 0) {
        _active.remove(request.id);
        _reservedInputBytes -= request.length;
        request.completer.completeError(
          AvifException(
            avifErrorCode(status),
            'Could not submit AVIF decode work to the native worker pool.',
          ),
        );
        if (_active.isEmpty && _queue.isEmpty) {
          _port.keepIsolateAlive = false;
        }
      }
    }
  }

  void _handleResult(Object? message) {
    if (message is! int || message == 0) {
      Zone.current.handleUncaughtError(
        StateError('The native AVIF worker returned an invalid message.'),
        StackTrace.current,
      );
      return;
    }
    final resultPointer = Pointer<LavifDecodeResult>.fromAddress(message);
    final request = _active.remove(resultPointer.ref.requestId);
    if (request == null) {
      lavifDecodeResultRelease(resultPointer);
      Zone.current.handleUncaughtError(
        StateError('The native AVIF worker returned an unknown request.'),
        StackTrace.current,
      );
      return;
    }
    _reservedInputBytes -= request.length;
    if (request.cancelled) {
      lavifDecodeResultRelease(resultPointer);
      _dispatch();
      if (_active.isEmpty && _queue.isEmpty) {
        _port.keepIsolateAlive = false;
      }
      return;
    }
    try {
      request.completer.complete(Avif._takeAsyncResult(resultPointer));
    } catch (error, stackTrace) {
      request.completer.completeError(error, stackTrace);
    }
    _dispatch();
    if (_active.isEmpty && _queue.isEmpty) {
      _port.keepIsolateAlive = false;
    }
  }
}

final class _PendingDecode {
  _PendingDecode({
    required this.id,
    required this.input,
    required this.length,
    required this.options,
    required this.targetWidth,
    required this.targetHeight,
  });

  final int id;
  final Pointer<Uint8> input;
  final int length;
  final AvifDecodeOptions options;
  final int? targetWidth;
  final int? targetHeight;
  final Completer<AvifFrame> completer = Completer<AvifFrame>();
  bool cancelled = false;
}
