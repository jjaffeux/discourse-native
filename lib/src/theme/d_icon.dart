import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Applies an icon's tint while flutter_svg compiles the picture.
///
/// A runtime [ColorFilter] makes vector_graphics wrap every icon paint in a
/// canvas saveLayer. Icons appear throughout scrolling rows, so that turns a
/// handful of tiny glyphs into a handful of offscreen buffers every frame.
/// Mapping the SVG's paints up front produces the same monochrome glyph with
/// no compositing layer at paint time.
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

/// One icon from Discourse's SVG sprite.
///
/// [name] is the name Discourse uses — `gear`, `far-heart`, `discourse-text` —
/// which is also what its payloads carry, so a name off the wire can be looked
/// up in `DIcons.byName` without a translation table in between.
///
/// [svg] is a standalone document rather than a path string because the
/// `discourse-*` icons are not all single paths: some carry groups, clip paths
/// and their own fills.
@immutable
class DIconData {
  const DIconData(this.name, this.svg);

  final String name;
  final String svg;

  /// SVG's initial fill is black. Make icons without an explicit root fill
  /// inherit the requested tint just like sprite symbols that already use
  /// `currentColor`.
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

/// Draws a [DIconData] the way [Icon] draws an [IconData]: square, sized and
/// tinted from [IconTheme] unless told otherwise.
///
/// The glyph is centred in the square rather than stretched to it. Font Awesome
/// viewBoxes are not all square — `arrow-right-from-bracket` is 512x512 but
/// `hand-point-right` is 448x512 — and Discourse itself lets them keep their
/// aspect ratio inside a fixed box.
class DIcon extends StatelessWidget {
  const DIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final DIconData icon;

  /// The edge of the square the glyph is centred in, not the glyph itself.
  final double? size;

  final Color? color;
  final String? semanticLabel;

  /// Font Awesome fills its viewBox; Material's icons are drawn on a 24pt grid
  /// with padding baked in, so the same number means a visibly larger icon.
  /// Scaling the glyph down inside its box matches both Material's optical size
  /// and the 0.86em Discourse gives `.d-icon` on the web.
  /// Public because a caller that has been given a *glyph* size — a pill, whose
  /// dimensions come from Discourse's stylesheet — has to divide by this to get
  /// the box size this widget wants.
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
