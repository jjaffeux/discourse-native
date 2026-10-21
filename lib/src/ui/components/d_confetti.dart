import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundation/native_glass.dart';
import '../foundation/tokens.dart';

/// Celebrates when its visible anchor is first seen. The host owns session memory.
class DConfetti extends StatefulWidget {
  const DConfetti({
    super.key,
    required this.child,
    this.enabled = true,
    this.onSeen,
  });
  final Widget child;
  final bool enabled;
  final VoidCallback? onSeen;
  @override
  State<DConfetti> createState() => _DConfettiState();
}

class _DConfettiState extends State<DConfetti>
    with SingleTickerProviderStateMixin {
  late final _animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _remove();
      });
  OverlayEntry? _entry;
  bool _seen = false;
  void _remove() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.stop();
      _remove();
    }
    _schedule();
  }

  @override
  void didUpdateWidget(DConfetti old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  void _schedule() {
    if (!widget.enabled || _seen || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _seen ||
          !widget.enabled ||
          !TickerMode.valuesOf(context).enabled) {
        return;
      }
      final box = context.findRenderObject();
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (box is! RenderBox || !box.hasSize || overlay == null) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (!rect.overlaps(Offset.zero & MediaQuery.sizeOf(context))) return;
      _seen = true;
      widget.onSeen?.call();
      if (MediaQuery.disableAnimationsOf(context)) return;
      final overlayBox = overlay.context.findRenderObject()! as RenderBox;
      final origin = overlayBox.globalToLocal(rect.center);
      final tokens = DTokens.of(context);
      final colors = [
        tokens.primary,
        tokens.colors.tertiary,
        tokens.colors.error,
        const Color(0xffedb850),
        tokens.foreground,
      ];
      _entry = OverlayEntry(
        builder: (_) => NativeGlassOccluder(
          child: Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (_, _) => CustomPaint(
                    painter: _ConfettiPaint(origin, colors, _animation.value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(_entry!);
      _animation.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _remove();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ConfettiPaint extends CustomPainter {
  _ConfettiPaint(this.origin, this.colors, this.progress);
  final Offset origin;
  final List<Color> colors;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final t = progress * 1.5;
    for (var i = 0; i < 42; i++) {
      final angle = -math.pi / 2 + (random.nextDouble() - .5) * 2.4;
      final speed = 160 + random.nextDouble() * 220;
      final spin = (random.nextDouble() - .5) * 15;
      canvas.save();
      canvas.translate(
        origin.dx + math.cos(angle) * speed * t,
        origin.dy + math.sin(angle) * speed * t + 260 * t * t,
      );
      canvas.rotate(spin * t);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: 5 + random.nextDouble() * 4,
          height: 3 + random.nextDouble() * 3,
        ),
        Paint()
          ..color = colors[i % colors.length].withValues(
            alpha: (1 - ((progress - .6) / .4)).clamp(0, 1),
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPaint old) => old.progress != progress;
}
