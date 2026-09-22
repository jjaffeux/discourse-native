import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/forum_background.dart';
import '../theme/app_theme.dart';

/// Paints the shared window canvas behind the title bar, rail and panel gaps.
class ForumWindowBackground extends StatefulWidget {
  const ForumWindowBackground({super.key, required this.child});

  final Widget child;

  @override
  State<ForumWindowBackground> createState() => _ForumWindowBackgroundState();
}

class _ForumWindowBackgroundState extends State<ForumWindowBackground>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final background = Theme.of(
      context,
    ).extension<ForumThemeEffects>()?.background;
    final animate =
        background?.effect == ForumBackgroundEffect.lava &&
        background!.strength > 0 &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!animate) {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effects = theme.extension<ForumThemeEffects>();
    final background = effects?.background;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background == null
            ? theme.scaffoldBackgroundColor
            : Color.lerp(
                theme.scaffoldBackgroundColor,
                background.color,
                background.strength * .45,
              ),
        gradient: background == null ? effects?.windowGradient : null,
      ),
      child:
          background == null ||
              background.effect == ForumBackgroundEffect.normal ||
              background.strength == 0
          ? widget.child
          : Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _BackgroundPainter(background, _motion),
                      ),
                    ),
                  ),
                ),
                widget.child,
              ],
            ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.background, this.motion) : super(repaint: motion);
  final ForumBackground background;
  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (background.effect == ForumBackgroundEffect.noise) {
      final random = math.Random(73);
      final count = (size.width * size.height / 70).round().clamp(100, 14000);
      final light = Paint()
        ..color = Colors.white.withValues(alpha: background.strength * .16);
      final dark = Paint()
        ..color = Colors.black.withValues(alpha: background.strength * .12);
      for (var i = 0; i < count; i++) {
        canvas.drawCircle(
          Offset(
            random.nextDouble() * size.width,
            random.nextDouble() * size.height,
          ),
          .45 + random.nextDouble() * .5,
          i.isEven ? light : dark,
        );
      }
    } else {
      final phase = motion.value * math.pi * 2;
      final base = HSLColor.fromColor(background.color);
      for (var i = 0; i < 4; i++) {
        final angle = phase + i * math.pi / 2;
        final center = Offset(
          size.width * (.5 + .4 * math.sin(angle)),
          size.height * (.5 + .4 * math.cos(angle + i)),
        );
        final radius = size.longestSide * (.38 + .06 * math.sin(angle));
        final tint = base.withHue((base.hue + i * 22) % 360).toColor();
        final rect = Rect.fromCircle(center: center, radius: radius);
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                tint.withValues(alpha: background.strength * .55),
                tint.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) =>
      oldDelegate.background != background || oldDelegate.motion != motion;
}

/// Applies navigation colors through the Native kit's existing theme boundary.
class ForumSidebarTheme extends StatelessWidget {
  const ForumSidebarTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sidebar = theme.extension<ForumThemeEffects>()?.sidebarTheme;
    if (sidebar == null) return child;
    return Theme(
      data: sidebar.copyWith(platform: theme.platform),
      child: child,
    );
  }
}
