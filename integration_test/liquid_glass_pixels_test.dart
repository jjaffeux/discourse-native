import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlass.precache);
  for (final simulatedView in [false, true]) {
    for (final savedClip in [false, true]) {
      testWidgets(
        'glass paints inside clips (simulated view $simulatedView, saved $savedClip)',
        (tester) async {
          if (simulatedView) {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(800, 600);
            addTearDown(tester.view.reset);
          }
          const box = ValueKey('glass-pixels');
          Widget child = SizedBox(
            width: 300,
            height: 200,
            child: Center(
              child: DMaterialSurface(
                color: Colors.white,
                radius: BorderRadius.circular(12),
                child: const SizedBox(key: box, width: 120, height: 40),
              ),
            ),
          );
          if (savedClip) {
            child = ClipRRect(
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: child,
            );
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: DMaterialTheme.apply(
                ThemeData.dark(),
                DAppearanceMaterial.liquidGlass,
              ),
              home: ColoredBox(
                color: const Color(0xff607080),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(80),
                    child: child,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final bounds = tester.getRect(find.byKey(box));
          final ratio = MediaQuery.devicePixelRatioOf(
            tester.element(find.byKey(box)),
          );
          final view = tester.binding.renderViews.first;
          await tester.runAsync(() async {
            final builder = ui.SceneBuilder();
            view.debugLayer!.addToScene(builder);
            final scene = builder.build();
            final image = await scene.toImage(
              (view.size.width * ratio).round(),
              (view.size.height * ratio).round(),
            );
            try {
              final bytes = (await image.toByteData())!.buffer.asUint8List();
              var contrast = 0;
              for (
                var y = (bounds.top * ratio).ceil();
                y < bounds.bottom * ratio;
                y++
              ) {
                for (
                  var x = (bounds.left * ratio).ceil();
                  x < bounds.right * ratio;
                  x++
                ) {
                  final pixel = (y * image.width + x) * 4;
                  for (var channel = 0; channel < 3; channel++) {
                    final delta =
                        (bytes[pixel + channel] - [96, 112, 128][channel])
                            .abs();
                    if (delta > contrast) contrast = delta;
                  }
                }
              }
              expect(contrast, greaterThan(8));
            } finally {
              image.dispose();
              scene.dispose();
            }
          });
          expect(find.byType(FakeGlass), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
