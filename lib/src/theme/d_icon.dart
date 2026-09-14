import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../ui/foundation/tokens.dart';

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

@immutable
class DIconData {
  const DIconData(this.name, this.svg, {this.preserveColors = false});

  final String name;
  final String svg;

  /// Retains explicit SVG colors while `currentColor` follows the icon theme.
  /// Discourse's palette variables are resolved from the Native theme at build
  /// time, so composite badges retain their background and foreground parts.
  final bool preserveColors;

  static final _svgTag = RegExp(r'<svg\b[^>]*>');
  static final _fillAttribute = RegExp(r'\sfill\s*=');

  String get tintableSvg {
    final match = _svgTag.firstMatch(svg);
    if (match == null || _fillAttribute.hasMatch(match[0]!)) return svg;
    return svg.replaceRange(
      match.start,
      match.start + 4,
      '<svg fill="currentColor"',
    );
  }

  @override
  bool operator ==(Object other) => other is DIconData && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'DIconData($name)';
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

  static final _colorVariable = RegExp(
    r'var\(\s*--([\w-]+)\s*(?:,\s*([^()]+))?\)',
  );

  String _svg(BuildContext context) {
    final svg = icon.tintableSvg;
    if (!icon.preserveColors || !svg.contains('var(')) return svg;
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
    final iconTheme = IconTheme.of(context);
    final box = size ?? iconTheme.size ?? 24;
    final tint = color ?? iconTheme.color ?? const Color(0xFF000000);
    final opacity = iconTheme.opacity ?? 1.0;
    final resolvedTint = opacity == 1.0
        ? tint
        : tint.withValues(alpha: tint.a * opacity);

    return SizedBox.square(
      dimension: box,
      child: Center(
        child: SvgPicture.string(
          _svg(context),
          width: box * glyphScale,
          height: box * glyphScale,
          fit: BoxFit.contain,
          theme: SvgTheme(
            currentColor: icon.preserveColors ? tint : resolvedTint,
          ),
          colorMapper: _DIconColorMapper(
            resolvedTint,
            preserveColors: icon.preserveColors,
            opacity: opacity,
          ),
          semanticsLabel: semanticLabel,
        ),
      ),
    );
  }
}
