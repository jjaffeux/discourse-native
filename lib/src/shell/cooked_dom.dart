/// Searching cooked HTML for the pieces Discourse gives meaning to with its
/// stylesheet rather than with its markup.
///
/// `querySelector` cannot express most of what the builders ask — a class
/// combination, a tag and a class together, an attribute and a class at once —
/// so the walk is written out. Iteratively, and once: cooked HTML is
/// arbitrarily deep, and every one of these runs inside a `customWidgetBuilder`
/// on the frame that draws the post.
library;

import 'package:html/dom.dart' as dom;

void _pushReversed(List<dom.Element> pending, List<dom.Element> children) {
  for (var index = children.length - 1; index >= 0; index--) {
    pending.add(children[index]);
  }
}

/// The first descendant of [root] matching [test], in document order.
dom.Element? descendantWhere(
  dom.Element root,
  bool Function(dom.Element) test,
) {
  final pending = <dom.Element>[];
  _pushReversed(pending, root.children);
  while (pending.isNotEmpty) {
    final child = pending.removeLast();
    if (test(child)) return child;
    _pushReversed(pending, child.children);
  }
  return null;
}

/// Every descendant of [root] matching [test], in document order.
List<dom.Element> descendantsWhere(
  dom.Element root,
  bool Function(dom.Element) test,
) {
  final found = <dom.Element>[];
  final pending = <dom.Element>[];
  _pushReversed(pending, root.children);
  while (pending.isNotEmpty) {
    final child = pending.removeLast();
    if (test(child)) found.add(child);
    _pushReversed(pending, child.children);
  }
  return found;
}
