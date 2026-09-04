import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter_test/flutter_test.dart';

/// `find.byIcon` for [DIcon].
///
/// The icons are SVG rather than font glyphs, so `byIcon` — which matches on
/// [Icon.icon] — cannot see them.
extension DIconFinders on CommonFinders {
  Finder dIcon(DIconData icon) => byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == icon,
    description: 'DIcon(${icon.name})',
  );
}
