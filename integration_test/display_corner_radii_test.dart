import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UIKit viewport corners reach the Native page sheet', (
    tester,
  ) async {
    BorderRadius? inherited;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DDisplayCornerRadii(child: child!),
        home: Builder(
          builder: (context) {
            inherited = MediaQuery.displayCornerRadiiOf(context);
            return const DSheetViewport(
              content: DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.page,
                pageCorners: DSheetPageCorners.viewport,
                fillAvailableHeight: true,
                showCloseButton: false,
                children: [Expanded(child: SizedBox())],
              ),
            );
          },
        ),
      ),
    );
    for (var frame = 0; frame < 100 && inherited == null; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(inherited, isNotNull, reason: 'Run on an iOS 26+ native host.');
    final native = await const MethodChannel(
      'org.discourse.native/window_geometry',
    ).invokeMapMethod<String, Object?>('geometry');
    expect(native, isNotNull);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect((native!['width']! as num).toDouble(), closeTo(size.width, .01));
    expect((native['height']! as num).toDouble(), closeTo(size.height, .01));
    expect(inherited!.bottomLeft.x, native['bottomLeft']);
    expect(inherited!.bottomRight.x, native['bottomRight']);
    expect(inherited!.bottomLeft.x, greaterThan(0));
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(DSheetContent),
        matching: find.byType(Material),
      ),
    );
    final clip = material.borderRadius! as BorderRadius;
    expect(clip.bottomLeft, inherited!.bottomLeft);
    expect(clip.bottomRight, inherited!.bottomRight);
    expect(clip.topLeft, const Radius.circular(22));
    debugPrint(
      'NATIVE_CORNERS ${jsonEncode({...native, 'dartBottomLeft': inherited!.bottomLeft.x, 'sheetBottomLeft': clip.bottomLeft.x})}',
    );
  }, skip: kIsWeb || defaultTargetPlatform != TargetPlatform.iOS);
}
