import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

import '../foundation/bounded_lru_cache.dart';

/// A single-colour icon's geometry, parsed once and painted in whatever colour
/// its tint has when it paints.
///
/// Baking the tint into a compiled picture keeps icons off `saveLayer`, but it
/// makes every new tint a new SVG compile, each on a fresh isolate that shares
/// the UI isolate's heap. Recolouring the app (a theme preview, a forum
/// switch, a hover crossfade) did that for every icon on every frame. Here the
/// colour is written into the paints instead, so a new tint only repaints.
///
/// The parse is keyed by the tint's alpha, the one part of the colour the SVG
/// parser folds into fill and stroke opacities. The monochrome mapper gives
/// every paint the tint's colour, so painting with the live RGB and the parsed
/// alpha draws exactly what the compiled picture would.
@immutable
final class TintableGlyph {
  const TintableGlyph._(this.size, this._draws);

  /// The SVG's viewBox.
  final Size size;
  final List<_GlyphDraw> _draws;

  static final _glyphs = BoundedLruCache<(String, int), TintableGlyph?>(512);

  /// The glyph of [svg] tinted with a colour whose alpha is [alpha], or null
  /// when the SVG needs more than tinted fills and strokes: gradients,
  /// patterns, images, text, layers, clips or masks keep the compiled picture,
  /// which also reports an SVG that does not parse.
  ///
  /// [source] names the SVG across builds, so the lookup hashes one constant
  /// string rather than the markup [svg] derives from it each time.
  static TintableGlyph? of(String source, int alpha, String Function() svg) {
    final key = (source, alpha);
    if (_glyphs.containsKey(key)) return _glyphs.read(key);
    final glyph = _parse(svg(), alpha);
    _glyphs.put(key, glyph);
    return glyph;
  }

  static TintableGlyph? _parse(String svg, int alpha) {
    // Black, so a paint the mapper did not produce is recognisable by its RGB.
    final tint = vg.Color.fromARGB(alpha, 0, 0, 0);
    final vg.VectorInstructions instructions;
    try {
      instructions = vg.parseWithoutOptimizers(
        svg,
        theme: vg.SvgTheme(currentColor: tint),
        colorMapper: _Tint(tint),
      );
    } catch (_) {
      return null;
    }
    if (instructions.width <= 0 ||
        instructions.height <= 0 ||
        instructions.images.isNotEmpty ||
        instructions.drawImages.isNotEmpty ||
        instructions.text.isNotEmpty ||
        instructions.textPositions.isNotEmpty ||
        instructions.vertices.isNotEmpty ||
        instructions.patternData.isNotEmpty) {
      return null;
    }
    final paths = List<ui.Path?>.filled(instructions.paths.length, null);
    final draws = <_GlyphDraw>[];
    for (final command in instructions.commands) {
      if (command.type != vg.DrawCommandType.path ||
          command.patternId != null) {
        return null;
      }
      // The encoder draws nothing for a path without a paint.
      final paintId = command.paintId;
      if (paintId == null) continue;
      final paint = instructions.paints[paintId];
      final path = paths[command.objectId!] ??= _path(
        instructions.paths[command.objectId!],
      );
      // A command draws its fill, then its stroke, as the encoder writes them.
      if (paint.fill case final fill?) {
        if (fill.shader != null || !_tinted(fill.color)) return null;
        draws.add(_GlyphDraw(path, _paint(paint.blendMode), fill.color.a));
      }
      if (paint.stroke case final stroke?) {
        if (stroke.shader != null || !_tinted(stroke.color)) return null;
        draws.add(
          _GlyphDraw(
            path,
            _paint(paint.blendMode, stroke: stroke),
            stroke.color.a,
          ),
        );
      }
    }
    return TintableGlyph._(
      Size(instructions.width, instructions.height),
      List.unmodifiable(draws),
    );
  }

  static bool _tinted(vg.Color color) =>
      color.r == 0 && color.g == 0 && color.b == 0;

  // The compiled picture stores coordinates, widths and miter limits as
  // 32-bit floats; rounding the same way keeps edges on the same pixels.
  static final _float = Float32List(1);
  static double _f32(double value) => (_float..[0] = value)[0];

  static ui.Path _path(vg.Path source) {
    final path = ui.Path()
      ..fillType = ui.PathFillType.values[source.fillType.index];
    for (final command in source.commands) {
      switch (command) {
        case vg.MoveToCommand(:final x, :final y):
          path.moveTo(_f32(x), _f32(y));
        case vg.LineToCommand(:final x, :final y):
          path.lineTo(_f32(x), _f32(y));
        case vg.CubicToCommand(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x3,
          :final y3,
        ):
          path.cubicTo(
            _f32(x1),
            _f32(y1),
            _f32(x2),
            _f32(y2),
            _f32(x3),
            _f32(y3),
          );
        case vg.CloseCommand():
          path.close();
      }
    }
    return path;
  }

  // Mirrors how vector_graphics decodes a paint, defaults included.
  static ui.Paint _paint(vg.BlendMode blendMode, {vg.Stroke? stroke}) {
    final paint = ui.Paint();
    if (blendMode.index != 0) {
      paint.blendMode = ui.BlendMode.values[blendMode.index];
    }
    if (stroke == null) return paint;
    paint.style = ui.PaintingStyle.stroke;
    final cap = stroke.cap?.index ?? 0;
    if (cap != 0) paint.strokeCap = ui.StrokeCap.values[cap];
    final join = stroke.join?.index ?? 0;
    if (join != 0) paint.strokeJoin = ui.StrokeJoin.values[join];
    final miterLimit = _f32(stroke.miterLimit ?? 4);
    if (miterLimit != 4) paint.strokeMiterLimit = miterLimit;
    // SVG's default stroke width is 1; Flutter's is 0.
    final width = _f32(stroke.width ?? 1);
    if (width != 0) paint.strokeWidth = width;
    return paint;
  }

  /// The colour of each fill and stroke in painting order.
  @visibleForTesting
  List<Color> debugColors(Color tint) => [
    for (final draw in _draws) draw.color(tint),
  ];

  void _paintInto(Canvas canvas, Rect destination, Color tint) {
    canvas
      ..save()
      ..translate(destination.left, destination.top)
      ..scale(destination.width / size.width, destination.height / size.height)
      ..clipRect(Offset.zero & size);
    for (final draw in _draws) {
      canvas.drawPath(draw.path, draw.paint..color = draw.color(tint));
    }
    canvas.restore();
  }
}

final class _GlyphDraw {
  _GlyphDraw(this.path, this.paint, this.alpha);

  final ui.Path path;
  final ui.Paint paint;
  final int alpha;

  // The compiled picture keeps the tint's 8-bit channels.
  Color color(Color tint) =>
      Color((alpha << 24) | (tint.toARGB32() & 0x00FFFFFF));
}

final class _Tint extends vg.ColorMapper {
  _Tint(this.color);

  final vg.Color color;

  @override
  vg.Color substitute(
    String? id,
    String elementName,
    String attributeName,
    vg.Color color,
  ) => this.color;
}

/// Paints a [TintableGlyph] at [height], laid out and announced as the
/// compiled `SvgPicture` it replaces: as wide as the viewBox's aspect ratio
/// allows, and an image in the semantics tree.
class TintedIconGlyph extends StatelessWidget {
  const TintedIconGlyph({
    super.key,
    required this.glyph,
    required this.color,
    required this.height,
    this.semanticLabel,
  });

  final TintableGlyph glyph;
  final Color color;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: semanticLabel != null,
    image: true,
    label: semanticLabel ?? '',
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    child: SizedBox(
      width: height / glyph.size.height * glyph.size.width,
      height: height,
      child: CustomPaint(painter: _TintedGlyphPainter(glyph, color)),
    ),
  );
}

class _TintedGlyphPainter extends CustomPainter {
  const _TintedGlyphPainter(this.glyph, this.color);

  final TintableGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, glyph.size, size);
    glyph._paintInto(
      canvas,
      Alignment.center.inscribe(fitted.destination, Offset.zero & size),
      color,
    );
  }

  @override
  bool shouldRepaint(_TintedGlyphPainter oldDelegate) =>
      !identical(oldDelegate.glyph, glyph) || oldDelegate.color != color;
}
