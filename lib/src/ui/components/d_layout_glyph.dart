import 'package:flutter/material.dart';

import '../foundation/tokens.dart';

/// The physical position of an editor represented inside a layout glyph.
enum DLayoutGlyphDock { left, right, bottom, full }

/// Passive artwork showing the visible panels and an optional editor dock.
///
/// Panel identities follow reading direction; [changingPanel] emphasizes the
/// panel affected by the accompanying action. The host control owns hover,
/// focus, sizing and semantics, and can supply a second glyph as its preview.
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
    final size = icon.size ?? 18;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _LayoutPainter(
            mainVisible: mainVisible,
            secondaryVisible: secondaryVisible,
            changingPanel: changingPanel,
            dock: dock,
            direction: Directionality.of(context),
            color: icon.color ?? DTokens.of(context).foreground,
            accent: DTokens.of(context).primary,
          ),
        ),
      ),
    );
  }
}

class _LayoutPainter extends CustomPainter {
  const _LayoutPainter({
    required this.mainVisible,
    required this.secondaryVisible,
    required this.changingPanel,
    required this.dock,
    required this.direction,
    required this.color,
    required this.accent,
  });

  final bool mainVisible;
  final bool secondaryVisible;
  final int changingPanel;
  final DLayoutGlyphDock? dock;
  final TextDirection direction;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 18;
    canvas.save();
    canvas.scale(scale);
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(.5, 2.5, 17, 13),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = color.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    var area = const Rect.fromLTWH(2, 4, 14, 10);
    void fill(Rect rect, Color ink) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1)),
      Paint()..color = ink,
    );
    switch (dock) {
      case DLayoutGlyphDock.full:
        fill(area, accent);
        canvas.restore();
        return;
      case DLayoutGlyphDock.left:
        fill(Rect.fromLTWH(area.left, area.top, 3, area.height), accent);
        area = Rect.fromLTRB(area.left + 4, area.top, area.right, area.bottom);
      case DLayoutGlyphDock.right:
        fill(Rect.fromLTWH(area.right - 3, area.top, 3, area.height), accent);
        area = Rect.fromLTRB(area.left, area.top, area.right - 4, area.bottom);
      case DLayoutGlyphDock.bottom:
        fill(
          Rect.fromLTWH(area.left, area.bottom - 2.5, area.width, 2.5),
          accent,
        );
        area = Rect.fromLTRB(
          area.left,
          area.top,
          area.right,
          area.bottom - 3.5,
        );
      case null:
        break;
    }
    final panels = [if (mainVisible) 0, if (secondaryVisible) 1];
    final ordered = direction == TextDirection.ltr
        ? panels
        : panels.reversed.toList();
    final width = (area.width - (ordered.length - 1)) / ordered.length;
    for (final (index, panel) in ordered.indexed) {
      fill(
        Rect.fromLTWH(
          area.left + index * (width + 1),
          area.top,
          width,
          area.height,
        ),
        color.withValues(alpha: panel == changingPanel ? .7 : .3),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayoutPainter oldDelegate) =>
      mainVisible != oldDelegate.mainVisible ||
      secondaryVisible != oldDelegate.secondaryVisible ||
      changingPanel != oldDelegate.changingPanel ||
      dock != oldDelegate.dock ||
      direction != oldDelegate.direction ||
      color != oldDelegate.color ||
      accent != oldDelegate.accent;
}
