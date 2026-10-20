import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../test/forum_settings_page_test.dart' as regressions;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(() async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    await LiquidGlass.precache();
  });
  regressions.mobileSettingsPanelClipTests();
  testWidgets('a partially pulled page sheet clips its own rounded border', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const sheetKey = ValueKey('nested-page-sheet');
    await tester.pumpWidget(
      MaterialApp(
        theme: DMaterialTheme.apply(
          AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          DAppearanceMaterial.liquidGlass,
        ),
        home: Padding(
          padding: const EdgeInsets.only(top: 110, bottom: 34),
          child: DPageSurface(
            child: DSheetViewport(
              key: sheetKey,
              onDismiss: () {},
              underlay: const ColoredBox(color: Color(0xff203040)),
              content: DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.page,
                showCloseButton: false,
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: 12,
                      itemBuilder: (context, index) => SizedBox(
                        height: 110,
                        child: DCard(
                          backgroundColor: Color.fromARGB(
                            255,
                            60 + index * 10,
                            70,
                            90,
                          ),
                          child: DButton(
                            label: Text('Card $index'),
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
    );
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pumpAndSettle();
    final sheet = find.descendant(
      of: find.byKey(sheetKey),
      matching: find.byType(DPageSurface),
    );
    final rect = tester.getRect(sheet);
    expect(rect.top, greaterThan(110));
    List<int>? before;
    for (final offset in [0.0, 100.0]) {
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final builder = ui.SceneBuilder();
        tester.binding.renderViews.first.debugLayer!.addToScene(builder);
        final scene = builder.build();
        final image = await scene.toImage(430, 932);
        try {
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          final outside = <int>[];
          for (final x in [rect.left + 4, rect.right - 4]) {
            final corner =
                ((rect.top.ceil() + 1) * image.width + x.floor()) * 4;
            final underlay =
                ((rect.top.floor() - 4) * image.width + x.floor()) * 4;
            for (var channel = 0; channel < 3; channel++) {
              outside.add(bytes[corner + channel]);
              expect(
                bytes[corner + channel],
                closeTo(bytes[underlay + channel], 2),
              );
            }
          }
          if (before == null) {
            before = outside;
          } else {
            expect(outside, before);
          }
        } finally {
          image.dispose();
          scene.dispose();
        }
      });
    }
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
