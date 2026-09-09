import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The surface a [DButton] is currently transitioning towards.
///
/// The button paints its fill, border and ring as one animated decoration
/// behind its content; this is the resolved target for the current states.
DButtonDecoration buttonSurface(WidgetTester tester, {Finder? of}) {
  final container = find.descendant(
    of: of ?? find.byType(FilledButton),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer && widget.decoration is DButtonDecoration,
    ),
  );
  return tester.widget<AnimatedContainer>(container).decoration!
      as DButtonDecoration;
}
