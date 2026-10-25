import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/plugins/boards/boards_directory_test.dart' as directory;
import '../test/plugins/boards/boards_widget_test.dart' as boards;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('boards-native-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final data = binding.reportData ??= <String, dynamic>{};
      final screenshots =
          data.putIfAbsent('screenshots', () => <Map<String, dynamic>>[])
              as List;
      screenshots.add({
        'screenshotName': name,
        'bytes': bytes!.buffer.asUint8List().toList(),
      });
    } finally {
      image.dispose();
    }
  }

  boards.boardsWidgetTests(nativeView: true, onCapture: capture);
  directory.boardsDirectoryWidgetTests(nativeView: true, onCapture: capture);
}
