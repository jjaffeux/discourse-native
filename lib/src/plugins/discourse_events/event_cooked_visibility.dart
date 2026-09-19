import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

/// Attendance is absent from generic cooked fragments. Never infer permission
/// to reveal livestream-only content from markup, author identity or settings.
Widget? eventHiddenCookedElement(dom.Element element) =>
    const {'div', 'span'}.contains(element.localName) &&
        element.classes.contains('hidden')
    ? const SizedBox.shrink()
    : null;

/// Plain-text fallbacks consume descendants without the ordinary element hook.
/// Remove concealed descendants before extracting their text or attributes.
dom.Element eventVisibleCookedElement(dom.Element element) {
  final visible = element.clone(true);
  for (final hidden in visible.querySelectorAll('div.hidden, span.hidden')) {
    hidden.remove();
  }
  return visible;
}
