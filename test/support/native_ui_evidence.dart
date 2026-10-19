import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _boundary = GlobalKey();
final _directory = Platform.environment['NATIVE_UI_EVIDENCE_DIR'];
bool _fontsLoaded = false;

Widget nativeUiEvidenceBuilder(BuildContext context, Widget? child) =>
    _directory == null ? child! : RepaintBoundary(key: _boundary, child: child);

Future<void> prepareNativeUiEvidence(WidgetTester tester) async {
  if (_directory == null || _fontsLoaded) return;
  await tester.runAsync(() async {
    final font = File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync();
    for (final family in [
      '.AppleSystemUIFont',
      'Roboto',
      'SF Pro Text',
      'SF Pro Display',
    ]) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    }
  });
  _fontsLoaded = true;
}

Future<void> captureNativeUi(WidgetTester tester, String name) async {
  final directoryPath = _directory;
  if (directoryPath == null) return;
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(directoryPath)..createSync(recursive: true);
      File(
        '${directory.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
