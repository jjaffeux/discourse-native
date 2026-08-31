library;

import 'package:html/dom.dart' as dom;

Iterable<dom.Element> childElements(dom.Element parent) sync* {
  for (final node in parent.nodes) {
    if (node is dom.Element) yield node;
  }
}

dom.Element? childWhere(dom.Element parent, bool Function(dom.Element) test) {
  for (final node in parent.nodes) {
    if (node is dom.Element && test(node)) return node;
  }
  return null;
}

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

void _pushReversed(List<dom.Element> pending, dom.Element parent) {
  final nodes = parent.nodes;
  for (var index = nodes.length - 1; index >= 0; index--) {
    final node = nodes[index];
    if (node is dom.Element) pending.add(node);
  }
}

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
