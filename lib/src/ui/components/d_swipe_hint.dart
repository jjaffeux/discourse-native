import 'dart:math' as math;
import 'dart:ui' as ui show Gradient;
import 'package:flutter/material.dart';
import '../../theme/discourse_typography.dart';
import '../../theme/tokens.dart';

/// What the bar says as it peeks: faded in and risen a little once [up],
/// faded and lowered with no wait as it goes, with a light passing over its
/// text on [clock], the time since the bar went up. A reader is not told
/// it: it says in words what the bar's lift shows.
class DSwipeHint extends StatelessWidget {
  const DSwipeHint({
    super.key,
    required this.label,
    this.animateEntrance = false,
    this.up = true,
    required this.clock,
  });

  static const hold = Duration(milliseconds: 3700);
  static const shineDelay = Duration(milliseconds: 300);
  static const shine = Duration(milliseconds: 1600);

  final String label;
  final bool animateEntrance;
  final bool up;
  final Animation<double> clock;

  /// In after [delay], fading over [fade] and rising [rise] over [risen];
  /// out with no wait, over the same.
  static const delay = 150;
  static const fade = 200;
  static const risen = 300;
  static const rise = 6.0;

  /// Gone, faded and lowered, this long after it starts to go.
  static const goneAfter = Duration(milliseconds: risen);

  /// The light: a band at [angle] degrees, muted at its ends and strong at
  /// its middle, over a gradient three times the text's width, slid from
  /// the gradient's end over the text to its start once a pass.
  static const angle = 100.0;
  static const stops = [.34, .5, .66];

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context) || !animateEntrance;
    Duration over(int milliseconds) => reduced
        ? Duration.zero
        : Duration(milliseconds: up ? delay + milliseconds : milliseconds);
    Curve eased(int milliseconds) => up
        ? Interval(delay / (delay + milliseconds), 1, curve: Curves.ease)
        : Curves.ease;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: DiscourseTypography.control,
        fontWeight: FontWeight.w500,
        color: tokens.mutedForeground,
      ),
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: up ? 1 : 0),
          duration: over(fade),
          curve: eased(fade),
          builder: (context, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: rise, end: up ? 0 : rise),
            duration: over(risen),
            curve: eased(risen),
            builder: (context, y, child) =>
                Transform.translate(offset: Offset(0, y), child: child),
            child: Center(
              child: AnimatedBuilder(
                animation: clock,
                builder: (context, child) => ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => _light(
                    bounds,
                    pass: MediaQuery.disableAnimationsOf(context)
                        ? 0
                        : _pass(clock.value),
                    muted: tokens.mutedForeground,
                    strong: tokens.foreground,
                    rtl: rtl,
                  ),
                  child: child,
                ),
                child: text,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How far through its pass the light is, [time] through the hold: none
  /// before the first pass begins.
  static double _pass(double time) {
    final elapsed = time * DSwipeHint.hold.inMilliseconds;
    final wait = DSwipeHint.shineDelay.inMilliseconds;
    final pass = DSwipeHint.shine.inMilliseconds;
    return elapsed < wait ? 0 : (elapsed - wait) % pass / pass;
  }

  /// The gradient over [bounds], the text, [pass] through a pass: three of
  /// its widths across, from two widths before its start at the beginning
  /// of a pass to level with it at the end, at [angle] as a page's gradient
  /// is drawn, and the other way across for a right-to-left reader.
  static Shader _light(
    Rect bounds, {
    required double pass,
    required Color muted,
    required Color strong,
    required bool rtl,
  }) {
    final width = bounds.width;
    final height = bounds.height;
    final centre = Offset(-2 * width * (1 - pass) + 1.5 * width, height / 2);
    const radians = angle * math.pi / 180;
    final along = Offset(math.sin(radians), -math.cos(radians));
    final length =
        3 * width * math.sin(radians).abs() + height * math.cos(radians).abs();
    Offset placed(Offset at) =>
        bounds.topLeft + (rtl ? Offset(width - at.dx, at.dy) : at);
    return ui.Gradient.linear(
      placed(centre - along * (length / 2)),
      placed(centre + along * (length / 2)),
      [muted, strong, muted],
      stops,
    );
  }
}
