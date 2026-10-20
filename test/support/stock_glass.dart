import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

final LiquidGlassStyle expectedButtonGlassStyle = LiquidGlassButton.defaultStyle
    .copyWith(
      glow: const LiquidGlassLight.glow(
        angle: 129,
        thickness: 5,
        intensity: 1,
        spread: .85,
      ),
    );

void expectStockGlass(LiquidGlassStyle actual, LiquidGlassStyle preset) {
  expect(actual.color, preset.color);
  expect(actual.blur, preset.blur);
  expect(actual.saturation, preset.saturation);
  expect(actual.refractionIndex, preset.refractionIndex);
  expect(actual.refractionWidth, preset.refractionWidth);
  expect(actual.magnification, preset.magnification);
  expect(actual.dispersion, preset.dispersion);
  expect(actual.specular, preset.specular);
  expect(actual.glow, preset.glow);
  expect(actual.shadow, preset.shadow);
  expect(actual.adaptivity, preset.adaptivity);
  expect(actual.liteGlass, preset.liteGlass);
}
