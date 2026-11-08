import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/json.dart';
import '../models/post.dart';
import 'composer/markdown_highlight.dart';
import 'composer/markdown_tokens.dart';

/// What a post says as plain words, its blocks run together with a space
/// between them. A post held only as markup, with nothing cooked, gives its
/// markup without the marks around them.
String postPlainText(Post post) => _plainText[post] ??= _read(post);

final _plainText = Expando<String>('post plain text');

const _unread = {'script', 'style'};
const _blocks = {
  'p',
  'div',
  'li',
  'br',
  'blockquote',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'tr',
  'th',
  'td',
};

String _read(Post post) {
  final words = StringBuffer();
  void walk(dom.Node node) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        words.write(child.data);
      } else if (child is dom.Element && !_unread.contains(child.localName)) {
        if (_blocks.contains(child.localName)) words.write(' ');
        if (child.localName == 'img' && child.classes.contains('emoji')) {
          words.write(
            jsonText(child.attributes['alt']) ??
                jsonText(child.attributes['title']) ??
                '',
          );
        }
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
final _previewMarkup = RegExp(
  r'\[date=[^\[\]]*\]'
  r'|\[/?(?:u|b|i|s|quote|details|spoiler|color|bgcolor|center|wrap|poll|event)(?:[= ][^\[\]]*)?\]',
  caseSensitive: false,
);
final _brackets = RegExp(r'[\[\]]');

String _unmark(String markup) {
  // Links are handled here; the formatting scan need not rediscover bracket
  // pairs. Mask them without moving offsets, including on malformed markup.
  late final code = markdownCodeRanges(markup.replaceAll(_brackets, '.'));
  final replacements = <({int start, int end, String text})>[
    for (final token in composerMarkdownLinkCandidates(
      markup,
      excludesBracket: code.contains,
      overlapsCode: code.overlaps,
    ).values)
      if (!code.overlaps(token.labelStart - 1, token.tokenEnd))
        (
          start: token.labelStart - 1,
          end: token.tokenEnd,
          text: markup.substring(token.labelStart, token.labelEnd),
        ),
  ];
  for (final match in _previewMarkup.allMatches(markup)) {
    if (code.overlaps(match.start, match.end)) continue;
    var slashes = 0;
    for (var at = match.start - 1; at >= 0 && markup[at] == '\\'; at--) {
      slashes++;
    }
    if (slashes.isEven) {
      replacements.add((start: match.start, end: match.end, text: ''));
    }
  }
  replacements.sort((a, b) => a.start.compareTo(b.start));
  final unmarked = StringBuffer();
  var offset = 0;
  for (final replacement in replacements) {
    if (replacement.start < offset) continue;
    unmarked.write(markup.substring(offset, replacement.start));
    unmarked.write(replacement.text);
    offset = replacement.end;
  }
  unmarked.write(markup.substring(offset));
  final source = unmarked.toString();
  final words = StringBuffer();
  for (final run in scanMarkdown(
    source.replaceAll(_brackets, '.'),
    shared: false,
    deferHighlight: (_, _) {},
  )) {
    if (!run.has(Md.marker)) words.write(source.substring(run.start, run.end));
  }
  return words.toString();
}
