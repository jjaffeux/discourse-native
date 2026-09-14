import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<ui.Color>> samplePixels(
  WidgetTester tester,
  Finder boundaryFinder,
  List<ui.Offset> points,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  return (await tester.runAsync(() async {
    const scale = 4.0;
    final image = await boundary.toImage(pixelRatio: scale);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();
      return points.map((point) {
        final offset =
            ((point.dy * scale).floor() * image.width +
                (point.dx * scale).floor()) *
            4;
        return ui.Color.fromARGB(
          bytes[offset + 3],
          bytes[offset],
          bytes[offset + 1],
          bytes[offset + 2],
        );
      }).toList();
    } finally {
      image.dispose();
    }
  }))!;
}
