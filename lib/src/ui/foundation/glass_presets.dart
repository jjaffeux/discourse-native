import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Sharing is limited to sibling surfaces over the same painted content.
class DGlassBackdrop extends InheritedWidget {
  const DGlassBackdrop({
    super.key,
    required this.backdropKey,
    this.captureSurface = false,
    required super.child,
  });

  final BackdropKey? backdropKey;
  final bool captureSurface;

  static BackdropKey? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DGlassBackdrop>()?.backdropKey;

  static bool captureOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DGlassBackdrop>()
          ?.captureSurface ??
      false;

  @override
  bool updateShouldNotify(DGlassBackdrop oldWidget) =>
      oldWidget.backdropKey != backdropKey ||
      oldWidget.captureSurface != captureSurface;
}

/// Each surface paints in place, including inside recessed control wells.
/// A shared key saves backdrop copies without moving glass behind those wells.
class DGlassSurface extends StatelessWidget {
  const DGlassSurface({
    super.key,
    required this.radius,
    required this.brightness,
    required this.child,
    this.tint,
    this.frost,
    this.saturation = 1.4,
  });

  final double radius;
  final Brightness brightness;
  final Widget child;
  final Color? tint;
  final double? frost;
  final double saturation;

  @override
  Widget build(BuildContext context) {
    final capture = DGlassBackdrop.captureOf(context);
    final glass = LiquidGlass.withOwnLayer(
      settings: LiquidGlassSettings.ios27Regular(
        brightness: brightness,
        frost: frost,
      ),
      appearance: tint == null
          ? LiquidGlassAppearance.ios27Regular(brightness: brightness)
          : LiquidGlassAppearance(
              tint: tint!,
              colorModel: LiquidGlassColorModel.direct(saturation: saturation),
            ),
      backdropKey: capture ? null : DGlassBackdrop.of(context),
      shape: LiquidRoundedRectangle(borderRadius: radius),
      child: child,
    );
    return capture ? LiquidGlassCapture(child: glass) : glass;
  }
}
