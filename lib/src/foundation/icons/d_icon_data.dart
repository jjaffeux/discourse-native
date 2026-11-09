import 'package:flutter/foundation.dart';

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
