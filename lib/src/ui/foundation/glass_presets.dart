import 'package:liquid_glass_easy/liquid_glass_easy.dart';

final LiquidGlassStyle buttonGlassStyle = LiquidGlassButton.defaultStyle
    .copyWith(
      glow: const LiquidGlassLight.glow(
        angle: 129,
        thickness: 5,
        intensity: 1,
        spread: .85,
      ),
    );
