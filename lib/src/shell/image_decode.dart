import 'dart:math' as math;
import 'dart:typed_data';

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
