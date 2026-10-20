import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void expectStockGlass(
  WidgetTester tester,
  Finder glass, {
  double? frost,
  Color? tint,
  double saturation = 1.4,
}) {
  final brightness = Theme.of(tester.element(glass)).brightness;
  final layer = tester.widget<LiquidGlassLayer>(
    find.descendant(of: glass, matching: find.byType(LiquidGlassLayer)).first,
  );
  expect(
    layer.settings,
    LiquidGlassSettings.ios27Regular(brightness: brightness, frost: frost),
  );
  final appearance = tester.widget<LiquidGlass>(glass).appearance;
  expect(
    appearance,
    tint == null
        ? LiquidGlassAppearance.ios27Regular(brightness: brightness)
        : LiquidGlassAppearance(
            tint: tint,
            colorModel: LiquidGlassColorModel.direct(saturation: saturation),
          ),
  );
  expect(tester.widget<LiquidGlass>(glass).shadows, isEmpty);
}
