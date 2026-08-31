import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Mapping paints while compiling avoids a saveLayer for every icon paint.
@immutable
final class _DIconColorMapper extends ColorMapper {
  const _DIconColorMapper(this.tint);

  final Color tint;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => tint;

  @override
  bool operator ==(Object other) =>
      other is _DIconColorMapper && other.tint == tint;

  @override
  int get hashCode => tint.hashCode;
}

@immutable
class DIconData {
  const DIconData(this.name, this.svg);

  final String name;
  final String svg;

  String get tintableSvg => svg.contains('fill=')
      ? svg
      : svg.replaceFirst('<svg ', '<svg fill="currentColor" ');

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
          icon.tintableSvg,
          width: box * glyphScale,
          height: box * glyphScale,
          fit: BoxFit.contain,
          theme: SvgTheme(currentColor: resolvedTint),
          colorMapper: _DIconColorMapper(resolvedTint),
          semanticsLabel: semanticLabel,
        ),
      ),
    );
  }
}
