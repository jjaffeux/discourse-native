@DefaultAsset('package:libavif/libavif_native')
library;

import 'dart:ffi';

final class LavifDecodeResult extends Struct {
  @Uint64()
  external int requestId;

  @Int32()
  external int status;

  external Pointer<Uint8> pixels;

  @Size()
  external int pixelsLength;

  external Pointer<Void> pixelsOwner;

  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint32()
  external int rowBytes;

  @Uint32()
  external int sourceBitDepth;

  @Uint8()
  external int hasAlpha;

  external Pointer<Uint8> error;

  @Size()
  external int errorLength;
}

final class LavifSequenceResult extends Struct {
  @Uint64()
  external int requestId;

  @Int32()
  external int status;

  @Uint64()
  external int handle;

  external Pointer<Uint8> pixels;

  @Size()
  external int pixelsLength;

  external Pointer<Void> pixelsOwner;

  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint32()
  external int rowBytes;

  @Uint32()
  external int sourceBitDepth;

  @Uint8()
  external int hasAlpha;

  @Uint32()
  external int frameCount;

  @Int32()
  external int repetitionCount;

  @Uint64()
  external int durationInTimescales;

  @Uint64()
  external int timescale;

  @Uint32()
  external int frameIndex;

  @Uint64()
  external int frameDurationInTimescales;

  @Uint64()
  external int frameTimescale;

  external Pointer<Uint8> error;

  @Size()
  external int errorLength;
}

@Native<
  Pointer<LavifDecodeResult> Function(
    Pointer<Uint8>,
    Size,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
  )
>(symbol: 'lavif_decode_rgba8')
external Pointer<LavifDecodeResult> lavifDecodeRgba8(
  Pointer<Uint8> bytes,
  int length,
  int maxThreads,
  int maxDimension,
  int maxPixels,
  int targetWidth,
  int targetHeight,
);

@Native<Void Function(Pointer<LavifDecodeResult>)>(
  symbol: 'lavif_decode_result_release',
)
external void lavifDecodeResultRelease(Pointer<LavifDecodeResult> result);

@Native<Pointer<Void> Function(Pointer<LavifDecodeResult>)>(
  symbol: 'lavif_decode_result_take_pixels',
  isLeaf: true,
)
external Pointer<Void> lavifDecodeResultTakePixels(
  Pointer<LavifDecodeResult> result,
);

typedef LavifPostCObjectNative =
    Int8 Function(Int64 port, Pointer<Dart_CObject> message);

@Native<Uint32 Function()>(symbol: 'lavif_async_worker_count', isLeaf: true)
external int lavifAsyncWorkerCount();

@Native<Uint32 Function()>(
  symbol: 'lavif_async_threads_per_worker',
  isLeaf: true,
)
external int lavifAsyncThreadsPerWorker();

@Native<Pointer<Uint8> Function(Size)>(symbol: 'lavif_input_allocate')
external Pointer<Uint8> lavifInputAllocate(int length);

@Native<Void Function(Pointer<Uint8>, Size)>(symbol: 'lavif_input_release')
external void lavifInputRelease(Pointer<Uint8> input, int length);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Size,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Int64,
    Pointer<NativeFunction<LavifPostCObjectNative>>,
    Uint64,
  )
>(symbol: 'lavif_decode_rgba8_async')
external int lavifDecodeRgba8Async(
  Pointer<Uint8> input,
  int length,
  int maxThreads,
  int maxDimension,
  int maxPixels,
  int targetWidth,
  int targetHeight,
  int port,
  Pointer<NativeFunction<LavifPostCObjectNative>> postCObject,
  int requestId,
);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Size,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint32,
    Uint8,
    Int64,
    Pointer<NativeFunction<LavifPostCObjectNative>>,
    Uint64,
  )
>(symbol: 'lavif_sequence_open_async')
external int lavifSequenceOpenAsync(
  Pointer<Uint8> input,
  int length,
  int maxThreads,
  int maxDimension,
  int maxPixels,
  int targetWidth,
  int targetHeight,
  int prefetchFirstFrame,
  int port,
  Pointer<NativeFunction<LavifPostCObjectNative>> postCObject,
  int requestId,
);

@Native<
  Int32 Function(
    Uint64,
    Int64,
    Pointer<NativeFunction<LavifPostCObjectNative>>,
    Uint64,
  )
>(symbol: 'lavif_sequence_next_async')
external int lavifSequenceNextAsync(
  int handle,
  int port,
  Pointer<NativeFunction<LavifPostCObjectNative>> postCObject,
  int requestId,
);

@Native<
  Int32 Function(
    Uint64,
    Int64,
    Pointer<NativeFunction<LavifPostCObjectNative>>,
    Uint64,
  )
>(symbol: 'lavif_sequence_reset_async')
external int lavifSequenceResetAsync(
  int handle,
  int port,
  Pointer<NativeFunction<LavifPostCObjectNative>> postCObject,
  int requestId,
);

@Native<Void Function(Uint64)>(symbol: 'lavif_sequence_release')
external void lavifSequenceRelease(int handle);

@Native<Void Function(Pointer<LavifSequenceResult>)>(
  symbol: 'lavif_sequence_result_release',
)
external void lavifSequenceResultRelease(Pointer<LavifSequenceResult> result);

@Native<Pointer<Void> Function(Pointer<LavifSequenceResult>)>(
  symbol: 'lavif_sequence_result_take_pixels',
  isLeaf: true,
)
external Pointer<Void> lavifSequenceResultTakePixels(
  Pointer<LavifSequenceResult> result,
);

@Native<Void Function(Pointer<Void>)>(symbol: 'lavif_pixels_release')
external void lavifPixelsRelease(Pointer<Void> owner);

final lavifPixelsReleaseAddress =
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      lavifPixelsRelease,
    );

@Native<Uint32 Function()>(symbol: 'lavif_abi_version', isLeaf: true)
external int lavifAbiVersion();

@Native<Pointer<Char> Function()>(symbol: 'lavif_libavif_version', isLeaf: true)
external Pointer<Char> lavifLibavifVersion();

@Native<Pointer<Char> Function()>(symbol: 'lavif_codec_versions', isLeaf: true)
external Pointer<Char> lavifCodecVersions();

@Native<Pointer<Char> Function()>(symbol: 'lavif_features', isLeaf: true)
external Pointer<Char> lavifFeatures();
