import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The edge at which a gradient blur reaches its full strength.
enum DGradientBlurEdge { top, bottom }

/// A decorative backdrop that progressively blurs toward one vertical edge.
///
/// Place this in a bounded stack after scrolling content and before foreground
/// controls. It preserves the backdrop's colors, ignores pointer events, and
/// contributes no semantics.
class DGradientBlur extends StatelessWidget {
  const DGradientBlur({
    super.key,
    this.edge = DGradientBlurEdge.top,
    this.sigma = 12,
    this.fullStrengthExtent = 0,
  }) : assert(sigma >= 0 && sigma < double.infinity),
       assert(fullStrengthExtent >= 0 && fullStrengthExtent < double.infinity);

  /// The edge from which the full-strength region extends.
  final DGradientBlurEdge edge;

  /// The combined Gaussian blur sigma at the strongest edge.
  final double sigma;

  /// The distance from [edge] that stays fully blurred, in logical pixels.
  ///
  /// The remaining height fades toward the opposite edge. Set this to the
  /// keyboard inset to continue a footer's blur underneath the keyboard without
  /// stretching its fade. Values at least as tall as the widget blur the entire
  /// bounds at full strength.
  final double fullStrengthExtent;

  @override
  Widget build(BuildContext context) {
    if (sigma == 0) return const SizedBox.expand();
    final alignment = edge == DGradientBlurEdge.top
        ? Alignment.topCenter
        : Alignment.bottomCenter;
    // Successive Gaussian variances add. These four passes reach the requested
    // sigma together, with stronger passes restricted closer to the edge.
    final unit = sigma / math.sqrt(85);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            if (height == 0) return const SizedBox.expand();
            final plateau = math.min(fullStrengthExtent, height);
            final fade = height - plateau;
            return Stack(
              fit: StackFit.expand,
              children: [
                for (var pass = 0; pass < 4; pass++)
                  Align(
                    alignment: alignment,
                    child: SizedBox(
                      width: double.infinity,
                      height: plateau + fade * (4 - pass) / 4,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: unit * (1 << pass),
                            sigmaY: unit * (1 << pass),
                          ),
                          child: CustomPaint(
                            painter: _BlurMask(
                              edge: edge,
                              transitionStart:
                                  (plateau + fade * (3 - pass) / 4) /
                                  (plateau + fade * (4 - pass) / 4),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BlurMask extends CustomPainter {
  const _BlurMask({required this.edge, required this.transitionStart});

  final DGradientBlurEdge edge;
  final double transitionStart;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // Paint into the backdrop filter's own layer. A ShaderMask around the
    // filter would introduce an empty layer and lose the underlying content.
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: edge == DGradientBlurEdge.top
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          end: edge == DGradientBlurEdge.top
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [transitionStart, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_BlurMask oldDelegate) =>
      edge != oldDelegate.edge ||
      transitionStart != oldDelegate.transitionStart;
}
