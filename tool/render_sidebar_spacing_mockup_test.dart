// Render the design study with the real Native components and local macOS fonts.
// flutter test tool/render_sidebar_spacing_mockup_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sidebar_spacing_mockup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Roboto', '.SF UI Text', '.SF UI Display']) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('/System/Library/Fonts/SFNS.ttf').readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
    }
  });

  testWidgets('render the spacing comparison', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1120);
    addTearDown(tester.view.reset);
    final output = Directory('docs/mockups/sidebar-spacing')
      ..createSync(recursive: true);
    for (final dark in [true, false]) {
      await tester.pumpWidget(
        SidebarSpacingMockup(key: ValueKey(dark), initialDark: dark),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final layer =
            tester.binding.renderViews.single.debugLayer! as OffsetLayer;
        final image = await layer.toImage(
          Offset.zero & tester.view.physicalSize,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Messages').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Comfortable').first);
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
