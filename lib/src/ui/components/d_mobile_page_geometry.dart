import 'package:flutter/widgets.dart';

/// The page corner shape shared by a mobile shell and its retained sheets.
class DMobilePageGeometry extends InheritedWidget {
  const DMobilePageGeometry({
    super.key,
    required this.bottomRadius,
    required super.child,
  });

  final Radius bottomRadius;

  static BorderRadius borderRadiusOf(BuildContext context) {
    const top = Radius.circular(22);
    final bottom =
        context
            .dependOnInheritedWidgetOfExactType<DMobilePageGeometry>()
            ?.bottomRadius ??
        top;
    return BorderRadius.only(
      topLeft: top,
      topRight: top,
      bottomLeft: bottom,
      bottomRight: bottom,
    );
  }

  @override
  bool updateShouldNotify(DMobilePageGeometry oldWidget) =>
      bottomRadius != oldWidget.bottomRadius;
}
