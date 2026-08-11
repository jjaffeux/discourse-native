import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/post.dart';

/// Builds the portable BBCode block Discourse uses for a selected post quote.
String buildPostQuote({
  required Post post,
  required int topicId,
  required String contents,
}) {
  final selected = contents.trim();
  if (selected.isEmpty) return '';

  final fullName = post.name?.trim();
  final usesFullName = fullName != null && fullName.isNotEmpty;
  final quotedName = (usesFullName ? fullName : post.username).replaceAll(
    RegExp(r'''["'‘’“”«»‹›]'''),
    '',
  );
  final params = <String>[
    quotedName,
    'post:${post.postNumber}',
    'topic:$topicId',
    if (usesFullName) 'username:${post.username}',
  ];

  return '[quote="${params.join(', ')}"]\n$selected\n[/quote]\n\n';
}

/// Reconstructs the Markdown structure Flutter's selection API leaves out.
///
/// Flutter concatenates independently rendered HTML blocks, so selecting two
/// cooked paragraphs produces `First.Second` even though Discourse quotes the
/// selected HTML as `First.\n\nSecond`. Match that character stream back to
/// the cooked DOM and restore block boundaries and common inline marks.
String postQuoteContentsFromSelection(String cooked, String plainText) {
  final selected = plainText.trim();
  if (selected.isEmpty || cooked.isEmpty) return selected;

  final source = _CookedSelectionSource.fromHtml(cooked);
  final directStart = source.plainText.indexOf(selected);
  if (directStart >= 0) {
    return source.markdown(directStart, directStart + selected.length);
  }

  final compact = selected.replaceAll(RegExp(r'[\r\n]'), '');
  final compactStart = source.plainText.indexOf(compact);
  return compactStart < 0
      ? selected
      : source.markdown(compactStart, compactStart + compact.length);
}

typedef _MarkdownMark = ({String open, String close});

class _CookedSelectionCharacter {
  const _CookedSelectionCharacter(this.value, this.marks);

  final String value;
  final List<_MarkdownMark> marks;
}

class _CookedSelectionSource {
  _CookedSelectionSource(this.characters, this.breaks)
    : plainText = characters.map((character) => character.value).join();

  factory _CookedSelectionSource.fromHtml(String cooked) {
    final characters = <_CookedSelectionCharacter>[];
    final breaks = <int, int>{};

    void addBreak(int lines) {
      if (characters.isEmpty) return;
      final offset = characters.length;
      final current = breaks[offset] ?? 0;
      if (lines > current) breaks[offset] = lines;
    }

    void visit(dom.Node node, List<_MarkdownMark> marks) {
      if (node is dom.Text) {
        final value = node.data;
        for (var index = 0; index < value.length; index++) {
          characters.add(
            _CookedSelectionCharacter(
              value.substring(index, index + 1),
              List.unmodifiable(marks),
            ),
          );
        }
        return;
      }
      if (node is! dom.Element || _ignoredCookedElement(node)) return;
      if (node.localName == 'br') {
        addBreak(1);
        return;
      }

      final block = _cookedBlockElement(node);
      if (block) addBreak(2);
      final mark = _markdownMark(node);
      final childMarks = mark == null ? marks : [...marks, mark];
      for (final child in node.nodes) {
        visit(child, childMarks);
      }
      if (block) addBreak(2);
    }

    final fragment = html.parseFragment(cooked);
    for (final node in fragment.nodes) {
      visit(node, const []);
    }
    return _CookedSelectionSource(characters, breaks);
  }

  final List<_CookedSelectionCharacter> characters;
  final Map<int, int> breaks;
  final String plainText;

  String markdown(int start, int end) {
    if (start < 0 || end <= start || end > characters.length) return '';
    final out = StringBuffer();
    var active = <_MarkdownMark>[];

    void closeTo(int length) {
      for (var index = active.length - 1; index >= length; index--) {
        out.write(active[index].close);
      }
      active = active.sublist(0, length);
    }

    for (var offset = start; offset < end; offset++) {
      final lines = breaks[offset] ?? 0;
      if (offset > start && lines > 0) {
        closeTo(0);
        out.write(lines == 1 ? '\n' : '\n\n');
      }

      final next = characters[offset].marks;
      var shared = 0;
      while (shared < active.length &&
          shared < next.length &&
          active[shared] == next[shared]) {
        shared++;
      }
      closeTo(shared);
      for (var index = shared; index < next.length; index++) {
        out.write(next[index].open);
      }
      active = List.of(next);
      out.write(characters[offset].value);
    }
    closeTo(0);
    return out.toString().trim();
  }
}

bool _ignoredCookedElement(dom.Element element) =>
    const {'script', 'style'}.contains(element.localName) ||
    element.classes.contains('quote-controls');

bool _cookedBlockElement(dom.Element element) => const {
  'address',
  'aside',
  'blockquote',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'ol',
  'p',
  'pre',
  'table',
  'tr',
  'ul',
}.contains(element.localName);

_MarkdownMark? _markdownMark(dom.Element element) {
  switch (element.localName) {
    case 'b':
    case 'strong':
      return (open: '**', close: '**');
    case 'i':
    case 'em':
      return (open: '*', close: '*');
    case 'del':
    case 's':
    case 'strike':
      return (open: '~~', close: '~~');
    case 'code':
      return (open: '`', close: '`');
    case 'a':
      final href = element.attributes['href'];
      return href == null || href.isEmpty
          ? null
          : (open: '[', close: ']($href)');
    case 'kbd':
    case 'mark':
    case 'small':
    case 'big':
    case 'sup':
    case 'sub':
    case 'ins':
      final name = element.localName!;
      return (open: '<$name>', close: '</$name>');
  }
  return null;
}
