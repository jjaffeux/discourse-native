import 'package:flutter/material.dart';

import '../foundation/tokens.dart';

/// The physical position of an editor represented inside a layout glyph.
enum DLayoutGlyphDock { left, right, bottom, full }

/// Passive artwork showing the visible panels and an optional editor dock.
///
/// Panel identities follow reading direction; [changingPanel] emphasizes the
/// panel affected by the accompanying action. The host control owns hover,
/// focus, sizing and semantics, and can supply a second glyph as its preview.
/// The 20×15 frame scales with the ambient icon width. Panel changes ease over
/// 280ms, or happen immediately when the host requests reduced motion.
class DLayoutGlyph extends StatelessWidget {
  const DLayoutGlyph({
    super.key,
    required this.mainVisible,
    required this.secondaryVisible,
    required this.changingPanel,
    this.dock,
  }) : assert(changingPanel == 0 || changingPanel == 1),
       assert(mainVisible || secondaryVisible);

  final bool mainVisible;
  final bool secondaryVisible;
  final int changingPanel;
  final DLayoutGlyphDock? dock;

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final size = icon.size ?? 20;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size * .75,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: secondaryVisible ? (mainVisible ? .5 : 1.0) : 0.0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: const Cubic(.4, 0, .2, 1),
          builder: (context, secondaryShare, _) => CustomPaint(
            painter: _LayoutPainter(
              secondaryShare: secondaryShare,
              changingPanel: changingPanel,
              dock: dock,
              direction: Directionality.of(context),
              color: icon.color ?? DTokens.of(context).foreground,
              accent: DTokens.of(context).primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LayoutPainter extends CustomPainter {
  const _LayoutPainter({
    required this.secondaryShare,
    required this.changingPanel,
    required this.dock,
    required this.direction,
    required this.color,
    required this.accent,
  });

  final double secondaryShare;
  final int changingPanel;
  final DLayoutGlyphDock? dock;
  final TextDirection direction;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 20;
    canvas.save();
    canvas.scale(scale);
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(.75, .75, 18.5, 13.5),
      const Radius.circular(3.25),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    var area = const Rect.fromLTWH(3, 3, 14, 9);
    void fill(Rect rect, Color ink, [double radius = 1.5]) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = ink,
    );
    switch (dock) {
      case DLayoutGlyphDock.full:
        fill(area, accent);
        canvas.restore();
        return;
      case DLayoutGlyphDock.left:
        fill(Rect.fromLTWH(area.left, area.top, 3, area.height), accent, 1);
        area = Rect.fromLTRB(
          area.left + 4.5,
          area.top,
          area.right,
          area.bottom,
        );
      case DLayoutGlyphDock.right:
        fill(
          Rect.fromLTWH(area.right - 3, area.top, 3, area.height),
          accent,
          1,
        );
        area = Rect.fromLTRB(
          area.left,
          area.top,
          area.right - 4.5,
          area.bottom,
        );
      case DLayoutGlyphDock.bottom:
        fill(
          Rect.fromLTWH(area.left, area.bottom - 2.5, area.width, 2.5),
          accent,
          1,
        );
        area = Rect.fromLTRB(area.left, area.top, area.right, area.bottom - 4);
      case null:
        break;
    }
    final gap = 1.5 * (1 - (2 * secondaryShare - 1).abs());
    final ordered = direction == TextDirection.ltr ? [0, 1] : [1, 0];
    var left = area.left;
    for (final panel in ordered) {
      final share = panel == 1 ? secondaryShare : 1 - secondaryShare;
      final width = (area.width - gap) * share;
      if (width > 0) {
        fill(
          Rect.fromLTWH(left, area.top, width, area.height),
          color.withValues(alpha: panel == changingPanel ? .7 : .3),
        );
      }
      left += width + gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayoutPainter oldDelegate) =>
      secondaryShare != oldDelegate.secondaryShare ||
      changingPanel != oldDelegate.changingPanel ||
      dock != oldDelegate.dock ||
      direction != oldDelegate.direction ||
      color != oldDelegate.color ||
      accent != oldDelegate.accent;
}
