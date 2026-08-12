import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Treats remote image dimensions as bounded layout hints.
///
/// Cooked HTML and plugin payloads are not trusted to supply finite, positive
/// pixel dimensions. Keeping ratios within 1:4–4:1 prevents a tiny/huge pair
/// from reserving an effectively unbounded scroll extent, while the 10k width
/// ceiling keeps arithmetic and constraints well inside useful display sizes.
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

/// Parses a cooked-HTML width/height pair through [safeImageLayoutSize].
Size? parseSafeImageLayoutSize(String? width, String? height) =>
    safeImageLayoutSize(
      double.tryParse(width ?? ''),
      double.tryParse(height ?? ''),
    );

/// Converts a logical image bound into the decoder's physical-pixel hint.
int imagePhysicalPixels(BuildContext context, double logicalPixels) {
  final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  return math.max(1, (logicalPixels * devicePixelRatio).ceil());
}

/// Keeps a memory-backed raster at the physical size its layout can display.
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
