import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../foundation/icons/d_icon_data.dart';
import '../foundation/icons/d_icon_sets.dart';
import '../ui/foundation/tokens.dart';
import 'd_icon_glyph.dart';

// Mapping paints while compiling avoids a saveLayer for every icon paint.
@immutable
final class _DIconColorMapper extends ColorMapper {
  const _DIconColorMapper(
    this.tint, {
    this.preserveColors = false,
    this.opacity = 1,
  });

  final Color tint;
  final bool preserveColors;
  final double opacity;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => preserveColors ? color.withValues(alpha: color.a * opacity) : tint;

  @override
  bool operator ==(Object other) =>
      other is _DIconColorMapper &&
      other.tint == tint &&
      other.preserveColors == preserveColors &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(tint, preserveColors, opacity);
}

/// A subtree may preview another family without changing the app preference.
class DIconSetScope extends InheritedWidget {
  const DIconSetScope({super.key, required this.iconSet, required super.child});
  final DIconSet iconSet;
  static DIconSet of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DIconSetScope>()?.iconSet ??
      DIconSet.defaultSet;
  @override
  bool updateShouldNotify(DIconSetScope oldWidget) =>
      iconSet != oldWidget.iconSet;
}

/// Controls optical glyph insets and optional natural SVG layout widths.
/// Reference controls use full-size glyphs; ordinary controls retain the inset.
class DIconGlyphTheme extends InheritedWidget {
  const DIconGlyphTheme({
    super.key,
    required this.scale,
    this.naturalWidth = false,
    required super.child,
  });

  final double scale;
  final bool naturalWidth;

  static bool naturalWidthOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DIconGlyphTheme>()
          ?.naturalWidth ??
      false;

  static double scaleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DIconGlyphTheme>()?.scale ??
      DIcon.glyphScale;

  @override
  bool updateShouldNotify(DIconGlyphTheme oldWidget) =>
      scale != oldWidget.scale || naturalWidth != oldWidget.naturalWidth;
}

class DIcon extends StatelessWidget {
  const DIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final DIconData icon;

  final double? size;

  final Color? color;
  final String? semanticLabel;

  static const double glyphScale = 0.875;

  static final _viewBox = RegExp(
    r'''viewBox=["']\s*([\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)\s*["']''',
  );

  static final _colorVariable = RegExp(
    r'var\(\s*--([\w-]+)\s*(?:,\s*([^()]+))?\)',
  );

  String _svg(BuildContext context, DIconData resolvedIcon) {
    final svg = resolvedIcon.tintableSvg;
    if (!resolvedIcon.preserveColors || !svg.contains('var(')) return svg;
    final tokens = DTokens.of(context);
    return svg.replaceAllMapped(_colorVariable, (match) {
      final color = switch (match[1]) {
        'primary' => tokens.foreground,
        'secondary' => tokens.background,
        'tertiary' => tokens.primary,
        'quaternary' => tokens.colors.secondary,
        'danger' => tokens.destructive,
        'success' => tokens.success,
        'float-kit-arrow-stroke-color' => tokens.border,
        'float-kit-arrow-fill-color' => tokens.surface,
        _ => null,
      };
      if (color == null) return match[2]?.trim() ?? 'currentColor';
      return 'rgba(${(color.r * 255).round()},${(color.g * 255).round()},'
          '${(color.b * 255).round()},${color.a})';
    });
  }

  @override
  Widget build(BuildContext context) {
    final set = DIconSetScope.of(context);
    final replacement = icon.preserveColors
        ? null
        : alternateIconSvg(set, icon.name);
    final resolvedIcon = replacement == null
        ? icon
        : DIconData(icon.name, replacement);
    final iconTheme = IconTheme.of(context);
    final box = size ?? iconTheme.size ?? 24;
    final glyphScale = DIconGlyphTheme.scaleOf(context);
    final viewBox = DIconGlyphTheme.naturalWidthOf(context)
        ? _viewBox.firstMatch(resolvedIcon.svg)
        : null;
    final width = viewBox == null
        ? box
        : (box * double.parse(viewBox[3]!) / double.parse(viewBox[4]!))
              .roundToDouble();
    final tint = color ?? iconTheme.color ?? const Color(0xFF000000);
    final opacity = iconTheme.opacity ?? 1.0;
    final resolvedTint = opacity == 1.0
        ? tint
        : tint.withValues(alpha: tint.a * opacity);
    final glyphHeight =
        box * glyphScale * (replacement == null ? 1 : set.scale);
    final glyph = resolvedIcon.preserveColors
        ? null
        : TintableGlyph.of(
            resolvedIcon.svg,
            resolvedTint.toARGB32() >>> 24,
            () => resolvedIcon.tintableSvg,
          );

    if (glyph != null) {
      return TintedIconGlyph(
        glyph: glyph,
        color: resolvedTint,
        height: glyphHeight,
        box: Size(width, box),
        semanticLabel: semanticLabel,
      );
    }

    return SizedBox(
      width: width,
      height: box,
      child: Center(
        child: SvgPicture.string(
          _svg(context, resolvedIcon),
          width: width * glyphScale * (replacement == null ? 1 : set.scale),
          height: glyphHeight,
          fit: BoxFit.contain,
          // Edge strokes and fractional scaling may paint past the
          // viewBox, as they do in the monochrome glyph renderer.
          allowDrawingOutsideViewBox: true,
          clipBehavior: Clip.none,
          theme: SvgTheme(
            currentColor: resolvedIcon.preserveColors ? tint : resolvedTint,
          ),
          colorMapper: _DIconColorMapper(
            resolvedTint,
            preserveColors: resolvedIcon.preserveColors,
            opacity: opacity,
          ),
          semanticsLabel: semanticLabel,
        ),
      ),
    );
  }
}
