import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter_test/flutter_test.dart';

/// `find.byIcon` for [DIcon].
extension DIconFinders on CommonFinders {
  Finder dIcon(DIconData icon) => byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == icon,
    description: 'DIcon(${icon.name})',
  );
}
