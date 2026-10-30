import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'avif_decode_options.dart';
import 'avif_exception.dart';
import 'native_bindings.dart';

const expectedNativeAbiVersion = 6;

void checkNativeAbi() {
  final version = lavifAbiVersion();
  if (version != expectedNativeAbiVersion) {
    throw StateError(
      'Unsupported libavif native ABI $version; '
      'expected $expectedNativeAbiVersion.',
    );
  }
}

void validateAvifInput(Uint8List bytes, AvifDecodeOptions options) {
  if (bytes.isEmpty) {
    throw const AvifException(
      AvifErrorCode.invalidInput,
      'AVIF input is empty.',
    );
  }
  if (bytes.length > options.maxInputBytes) {
    throw AvifException(
      AvifErrorCode.limitExceeded,
      'AVIF input is ${bytes.length} bytes, exceeding the configured '
      '${options.maxInputBytes}-byte limit.',
    );
  }
}

void validateAvifTargetSize({
  required int? targetWidth,
  required int? targetHeight,
}) {
  if (targetWidth != null && (targetWidth <= 0 || targetWidth > 0xffffffff)) {
    throw ArgumentError.value(
      targetWidth,
      'targetWidth',
      'must be between 1 and 4294967295',
    );
  }
  if (targetHeight != null &&
      (targetHeight <= 0 || targetHeight > 0xffffffff)) {
    throw ArgumentError.value(
      targetHeight,
      'targetHeight',
      'must be between 1 and 4294967295',
    );
  }
}

AvifErrorCode avifErrorCode(int status) => switch (status) {
  1 => AvifErrorCode.invalidInput,
  2 => AvifErrorCode.decodeFailed,
  3 => AvifErrorCode.limitExceeded,
  4 => AvifErrorCode.unsupported,
  5 => AvifErrorCode.outOfMemory,
  _ => AvifErrorCode.internal,
};

String readNativeError(Pointer<Uint8> error, int length) {
  if (error == nullptr || length == 0) {
    return 'Native AVIF decoding failed without a diagnostic.';
  }
  return utf8.decode(error.asTypedList(length), allowMalformed: true);
}
