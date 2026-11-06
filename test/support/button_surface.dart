import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/ui/foundation/implicit_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The surface a [DButton] is currently transitioning towards.
///
/// The button paints its fill, border and ring as one animated decoration
/// behind its content; this is the resolved target for the current states.
DButtonDecoration buttonSurface(WidgetTester tester, {Finder? of}) {
  final transition = find.descendant(
    of: of ?? find.byType(FilledButton),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DImplicitTransition<Decoration> &&
          widget.value is DButtonDecoration,
    ),
  );
  return tester.widget<DImplicitTransition<Decoration>>(transition).value
      as DButtonDecoration;
}
