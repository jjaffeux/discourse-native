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

/// [parent]'s direct child elements, in document order.
///
/// This is the direct-child counterpart to [descendantsWhere]. It deliberately
/// walks `nodes` for the same reason: `Element.children` repeatedly filters the
/// full node list while an ordinary iterable is consumed.
Iterable<dom.Element> childElements(dom.Element parent) sync* {
  for (final node in parent.nodes) {
    if (node is dom.Element) yield node;
  }
}

/// The first direct child of [parent] matching [test], in document order.
dom.Element? childWhere(dom.Element parent, bool Function(dom.Element) test) {
  for (final node in parent.nodes) {
    if (node is dom.Element && test(node)) return node;
  }
  return null;
}

/// Every direct child of [parent] matching [test], in document order.
List<dom.Element> childrenWhere(
  dom.Element parent,
  bool Function(dom.Element) test,
) {
  final found = <dom.Element>[];
  for (final node in parent.nodes) {
    if (node is dom.Element && test(node)) found.add(node);
  }
  return found;
}

/// Pushes [parent]'s child elements so the stack pops them in document order.
///
/// Reads `nodes` rather than `children`: `children` is a `FilteredElementList`
/// that rebuilds itself out of `nodes` on every `length` and every `[]`, so
/// walking it by index is quadratic in the number of children and allocates a
/// list per step. A onebox with a few hundred rows in it is enough to feel.
void _pushReversed(List<dom.Element> pending, dom.Element parent) {
  final nodes = parent.nodes;
  for (var index = nodes.length - 1; index >= 0; index--) {
    final node = nodes[index];
    if (node is dom.Element) pending.add(node);
  }
}

/// The first descendant of [root] matching [test], in document order.
dom.Element? descendantWhere(
  dom.Element root,
  bool Function(dom.Element) test,
) {
  final pending = <dom.Element>[];
  _pushReversed(pending, root);
  while (pending.isNotEmpty) {
    final child = pending.removeLast();
    if (test(child)) return child;
    _pushReversed(pending, child);
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
  _pushReversed(pending, root);
  while (pending.isNotEmpty) {
    final child = pending.removeLast();
    if (test(child)) found.add(child);
    _pushReversed(pending, child);
  }
  return found;
}
