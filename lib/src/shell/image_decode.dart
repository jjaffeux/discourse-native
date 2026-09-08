import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

Size? safeImageLayoutSize(double? width, double? height) {
  if (width == null ||
      height == null ||
      !width.isFinite ||
      !height.isFinite ||
      width < 1 ||
      height < 1) {
    return null;
  }

  const maximumWidth = 10000.0;
  const minimumAspectRatio = 1 / 4;
  const maximumAspectRatio = 4.0;
  final ratio = width / height;
  if (!ratio.isFinite || ratio <= 0) return null;
  final safeWidth = width.clamp(1.0, maximumWidth).toDouble();
  final safeRatio = ratio
      .clamp(minimumAspectRatio, maximumAspectRatio)
      .toDouble();
  return Size(safeWidth, safeWidth / safeRatio);
}

Size? parseSafeImageLayoutSize(String? width, String? height) =>
    safeImageLayoutSize(
      double.tryParse(width ?? ''),
      double.tryParse(height ?? ''),
    );

Size? parseSafeImageInformationSize(String? text) {
  if (text == null) return null;
  final dimensions = text.trim().split(' ').first;
  final parts = dimensions.split(RegExp('x|×'));
  if (parts.length != 2) return null;
  return parseSafeImageLayoutSize(parts[0], parts[1]);
}

int imagePhysicalPixels(BuildContext context, double logicalPixels) {
  final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  return math.max(1, (logicalPixels * devicePixelRatio).ceil());
}

ResizeImage memoryImageForLayout(
  BuildContext context,
  Uint8List bytes, {
  required Size logicalSize,
}) {
  return ResizeImage(
    MemoryImage(bytes),
    width: imagePhysicalPixels(context, logicalSize.width),
    height: imagePhysicalPixels(context, logicalSize.height),
    policy: ResizeImagePolicy.fit,
  );
}

ImageProvider<Object> imageForCover(
  BuildContext context,
  ImageProvider<Object> provider, {
  required Size logicalSize,
}) => _CoverImage(
  provider,
  imagePhysicalPixels(context, logicalSize.width),
  imagePhysicalPixels(context, logicalSize.height),
);

@immutable
final class _CoverImage extends ImageProvider<_CoverImageKey> {
  const _CoverImage(this.provider, this.width, this.height);

  final ImageProvider<Object> provider;
  final int width;
  final int height;

  @override
  Future<_CoverImageKey> obtainKey(ImageConfiguration configuration) => provider
      .obtainKey(configuration)
      .then((key) => _CoverImageKey(key, width, height));

  @override
  ImageStreamCompleter loadImage(
    _CoverImageKey key,
    ImageDecoderCallback decode,
  ) {
    final completer = provider.loadImage(key.providerKey, (
      buffer, {
      getTargetSize,
    }) {
      assert(getTargetSize == null);
      return decode(
        buffer,
        getTargetSize: (intrinsicWidth, intrinsicHeight) {
          // Cover needs the larger scale, including pixels outside the crop.
          // One target dimension preserves the poster's own aspect ratio;
          // clamping it avoids decoding an upscale of a small source.
          return key.width * intrinsicHeight >= key.height * intrinsicWidth
              ? ui.TargetImageSize(width: math.min(key.width, intrinsicWidth))
              : ui.TargetImageSize(
                  height: math.min(key.height, intrinsicHeight),
                );
        },
      );
    });
    completer.addEphemeralErrorListener((_, _) {
      // A synchronous failure can precede ImageCache registering this key.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is _CoverImage &&
      provider == other.provider &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(provider, width, height);
}

@immutable
final class _CoverImageKey {
  const _CoverImageKey(this.providerKey, this.width, this.height);

  final Object providerKey;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _CoverImageKey &&
      providerKey == other.providerKey &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(providerKey, width, height);
}
