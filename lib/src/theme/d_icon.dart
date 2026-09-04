import 'package:flutter/widgets.dart';

@immutable
class DIconData {
  const DIconData(this.name, this.data);

  final String name;
  final IconData data;

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
    assert(
      icon.data.fontPackage == 'lucide_flutter',
      '${icon.name} is not backed by Lucide.',
    );
    final iconTheme = IconTheme.of(context);
    final box = size ?? iconTheme.size ?? 24;
    final tint = color ?? iconTheme.color ?? const Color(0xFF000000);

    final glyph = SizedBox.square(
      dimension: box,
      child: Center(
        child: Icon(icon.data, size: box * glyphScale, color: tint),
      ),
    );

    if (semanticLabel == null) return glyph;
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: glyph),
    );
  }
}
