import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';
import '../foundation/touch_target.dart';

/// A branch from the leading edge to a reply's header.
///
/// [junction] is measured from the top of the bounded slot. The curve and
/// optional continuation mirror in right-to-left layouts.
class DThreadConnector extends StatefulWidget {
  const DThreadConnector({
    super.key,
    required this.width,
    required this.junction,
    this.continuesBelow = false,
    this.radius = 8,
    this.onPressed,
    this.semanticLabel,
  }) : assert(onPressed == null || semanticLabel != null);

  final double width;
  final double junction;
  final bool continuesBelow;
  final double radius;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  State<DThreadConnector> createState() => _DThreadConnectorState();
}

class _DThreadConnectorState extends State<DThreadConnector> {
  final _focus = FocusNode();
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
      final width = widget.width.isFinite ? math.max(0.0, widget.width) : 0.0;
      final tokens = DTokens.of(context);
      final active = widget.onPressed != null && height > 0 && width > 0;
      final painter = _ConnectorPainter(
        color: active && _focused
            ? tokens.focusRing
            : active && (_hovered || _pressed)
            ? tokens.foreground
            : tokens.border,
        junction: widget.junction,
        radius: widget.radius,
        continuesBelow: widget.continuesBelow,
        rtl: Directionality.of(context) == TextDirection.rtl,
        size: Size(width, height),
      );
      Widget line = CustomPaint(painter: painter, size: Size(width, height));
      if (active) {
        void activate() {
          _focus.requestFocus();
          widget.onPressed?.call();
        }

        line = Semantics(
          button: true,
          label: widget.semanticLabel,
          onTap: widget.onPressed,
          child: FocusableActionDetector(
            focusNode: _focus,
            mouseCursor: SystemMouseCursors.click,
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            onShowHoverHighlight: (value) => setState(() => _hovered = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  activate();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              excludeFromSemantics: true,
              onTap: activate,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: line,
            ),
          ),
        );
      } else {
        line = IgnorePointer(child: line);
      }
      return SizedBox(
        width: width,
        height: height,
        child: _ThreadHitRegion(painter: painter, child: line),
      );
    },
  );
}

class _ThreadHitRegion extends SingleChildRenderObjectWidget {
  const _ThreadHitRegion({required this.painter, required super.child});
  final _ConnectorPainter painter;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderThreadHitRegion(painter);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderThreadHitRegion renderObject,
  ) => renderObject.painter = painter;
}

class _RenderThreadHitRegion extends RenderProxyBox {
  _RenderThreadHitRegion(this.painter);
  _ConnectorPainter painter;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      painter.hitTest(position) == true &&
      super.hitTest(result, position: position);
}

class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter({
    required this.color,
    required this.junction,
    required this.radius,
    required this.continuesBelow,
    required this.rtl,
    required this.size,
  });
  final Color color;
  final double junction;
  final double radius;
  final bool continuesBelow;
  final bool rtl;
  final Size size;

  @override
  bool? hitTest(Offset position) {
    if (size.isEmpty) return false;
    final point = rtl
        ? Offset(size.width - position.dx, position.dy)
        : position;
    final y = junction.isFinite ? junction.clamp(0.0, size.height) : 0.0;
    final r = radius.isFinite
        ? math.max(0.0, math.min(radius, math.min(y, size.width - 1)))
        : 0.0;
    bool near(Offset a, Offset b) {
      final delta = b - a;
      final length2 = delta.distanceSquared;
      final t = length2 == 0
          ? 0.0
          : (((point - a).dx * delta.dx + (point - a).dy * delta.dy) / length2)
                .clamp(0.0, 1.0);
      return (point - (a + delta * t)).distanceSquared <= 1;
    }

    if (near(
      const Offset(1, 0),
      Offset(1, continuesBelow ? size.height : y - r),
    )) {
      return true;
    }
    var previous = Offset(1, y - r);
    for (var i = 1; i <= 16; i++) {
      final t = i / 16;
      final next = Offset(1 + r * t * t, y - r * (1 - t) * (1 - t));
      if (near(previous, next)) return true;
      previous = next;
    }
    return near(Offset(1 + r, y), Offset(size.width, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final y = junction.isFinite ? junction.clamp(0.0, size.height) : 0.0;
    final r = radius.isFinite
        ? math.max(0.0, math.min(radius, math.min(y, size.width - 1)))
        : 0.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(1, 0)
      ..lineTo(1, y - r)
      ..quadraticBezierTo(1, y, 1 + r, y)
      ..lineTo(size.width, y);
    canvas.drawPath(path, paint);
    if (continuesBelow) {
      canvas.drawLine(const Offset(1, 0), Offset(1, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      color != old.color ||
      junction != old.junction ||
      radius != old.radius ||
      continuesBelow != old.continuesBelow ||
      rtl != old.rtl;
}

/// A centered thread line. A callback makes only its visible stroke clickable.
/// The phone target is supplied by [DTouchTargets]. Supply a finite height.
class DThreadRail extends StatefulWidget {
  const DThreadRail({super.key, this.onPressed, this.semanticLabel})
    : assert(onPressed == null || semanticLabel != null);
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  State<DThreadRail> createState() => _DThreadRailState();
}

class _DThreadRailState extends State<DThreadRail> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
      final tokens = DTokens.of(context);
      final active = widget.onPressed != null;
      final color = _focused
          ? tokens.focusRing
          : (_hovered || _pressed) && active
          ? tokens.foreground
          : tokens.border;
      Widget line = SizedBox(
        width: 2,
        height: height,
        child: ColoredBox(color: color),
      );
      if (active && height > 0) {
        line = Semantics(
          button: true,
          label: widget.semanticLabel,
          onTap: widget.onPressed,
          child: FocusableActionDetector(
            focusNode: _focus,
            mouseCursor: SystemMouseCursors.click,
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            onShowHoverHighlight: (value) => setState(() => _hovered = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  widget.onPressed?.call();
                  return null;
                },
              ),
            },
            child: DTouchTarget(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () {
                  _focus.requestFocus();
                  widget.onPressed?.call();
                },
                onTapDown: (_) => setState(() => _pressed = true),
                onTapUp: (_) => setState(() => _pressed = false),
                onTapCancel: () => setState(() => _pressed = false),
                child: line,
              ),
            ),
          ),
        );
      }
      return SizedBox(
        height: height,
        child: Center(child: line),
      );
    },
  );
}
