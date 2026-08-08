import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

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
