import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/post.dart';

/// What a post says as plain words, its blocks run together with a space
/// between them. A post held only as markup, with nothing cooked, gives its
/// markup without the marks around them.
String postPlainText(Post post) => _plainText[post] ??= _read(post);

final _plainText = Expando<String>('post plain text');

const _unread = {'script', 'style'};
const _blocks = {'p', 'div', 'li', 'br'};

String _read(Post post) {
  final words = StringBuffer();
  void walk(dom.Node node) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        words.write(child.data);
      } else if (child is dom.Element && !_unread.contains(child.localName)) {
        walk(child);
        if (_blocks.contains(child.localName)) words.write(' ');
      }
    }
  }

  walk(html.parseFragment(post.cooked));
  final cooked = _collapse(words.toString());
  if (cooked.isNotEmpty) return cooked;
  final raw = post.raw;
  return raw == null ? '' : _collapse(_unmark(raw));
}

String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

// Each bracket class excludes both brackets, so no match rescans past the
// next one: the scan stays linear on unbalanced markup.
final _link = RegExp(r'\[([^\[\]]+)\]\([^()]*\)');
final _marks = RegExp(r'\[date=[^\[\]]*\]|\[/?\w[^\[\]]*\]|[*_~`#>]');

String _unmark(String markup) =>
    markup.replaceAllMapped(_link, (match) => match[1]!).replaceAll(_marks, '');
