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
  return PostQuoteSelectionResolver(cooked).contentsFor(plainText);
}

/// Reuses one cooked-post index while a reader adjusts the same selection.
///
/// Flutter reports a new selection on every pointer move. Parsing the complete
/// cooked DOM for each of those updates makes a long post noticeably lag
/// behind the drag. A mounted post owns one of these until its cooked body
/// changes, while the top-level helper above remains convenient for one-shot
/// callers and tests.
final class PostQuoteSelectionResolver {
  PostQuoteSelectionResolver(String cooked)
    : _source = cooked.isEmpty ? null : _CookedSelectionSource.fromHtml(cooked);

  final _CookedSelectionSource? _source;

  String contentsFor(String plainText) {
    final selected = plainText.trim();
    final source = _source;
    if (selected.isEmpty || source == null) return selected;

    final directStart = source.plainText.indexOf(selected);
    if (directStart >= 0) {
      return source.markdown(directStart, directStart + selected.length);
    }

    final compact = selected.replaceAll(_selectionLineBreaks, '');
    final compactStart = source.plainText.indexOf(compact);
    return compactStart < 0
        ? selected
        : source.markdown(compactStart, compactStart + compact.length);
  }
}

final RegExp _selectionLineBreaks = RegExp(r'[\r\n]');

typedef _MarkdownMark = ({String open, String close});

/// Whitespace the renderer collapses to a single space outside `pre`.
final RegExp _collapsibleWhitespace = RegExp(r'[ \t\r\n\f]+');

class _CookedSelectionCharacter {
  const _CookedSelectionCharacter(
    this.value,
    this.marks, [
    this.preformatted = false,
  ]);

  final String value;
  final List<_MarkdownMark> marks;
  final bool preformatted;
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

    final fragment = html.parseFragment(cooked);
    final pending =
        <
          ({dom.Node node, List<_MarkdownMark> marks, bool exiting, bool pre})
        >[];
    void pushNodes(List<dom.Node> nodes, List<_MarkdownMark> marks, bool pre) {
      for (var index = nodes.length - 1; index >= 0; index--) {
        pending.add((
          node: nodes[index],
          marks: marks,
          exiting: false,
          pre: pre,
        ));
      }
    }

    pushNodes(fragment.nodes, const [], false);
    while (pending.isNotEmpty) {
      final frame = pending.removeLast();
      final node = frame.node;
      if (node is dom.Text) {
        // Markdown cooks whitespace between and inside blocks — `<p>a</p>\n`
        // — that the renderer never draws as written. Collapse it the way CSS
        // does so the index holds the character stream a selection reports;
        // `pre` content keeps its indentation and line structure.
        final value = frame.pre
            ? node.data
            : node.data.replaceAll(_collapsibleWhitespace, ' ');
        for (var index = 0; index < value.length; index++) {
          characters.add(
            _CookedSelectionCharacter(value[index], frame.marks, frame.pre),
          );
        }
        continue;
      }
      if (node is! dom.Element || _ignoredCookedElement(node)) continue;
      final block = _cookedBlockElement(node);
      if (frame.exiting) {
        if (block) addBreak(2);
        continue;
      }
      if (node.localName == 'br') {
        addBreak(1);
        continue;
      }

      if (block) addBreak(2);
      final mark = _markdownMark(node);
      final childMarks = mark == null
          ? frame.marks
          : List<_MarkdownMark>.unmodifiable([...frame.marks, mark]);
      final pre = frame.pre || node.localName == 'pre';
      pending.add((node: node, marks: childMarks, exiting: true, pre: pre));
      pushNodes(node.nodes, childMarks, pre);
    }
    return _CookedSelectionSource._trimmed(characters, breaks);
  }

  /// Drops the collapsed spaces the renderer never draws: those at block
  /// boundaries, at either end of the post, and runs left by adjacent text
  /// nodes. What survives is exactly the rendered character stream, offset by
  /// offset, with the break map rekeyed to match.
  factory _CookedSelectionSource._trimmed(
    List<_CookedSelectionCharacter> characters,
    Map<int, int> breaks,
  ) {
    final kept = <_CookedSelectionCharacter>[];
    final keptBreaks = <int, int>{};

    for (var offset = 0; offset < characters.length; offset++) {
      final lines = breaks[offset];
      if (lines != null && kept.isNotEmpty) {
        final current = keptBreaks[kept.length] ?? 0;
        if (lines > current) keptBreaks[kept.length] = lines;
      }
      final character = characters[offset];
      if (character.value == ' ' &&
          !character.preformatted &&
          (kept.isEmpty ||
              offset == characters.length - 1 ||
              breaks.containsKey(offset) ||
              breaks.containsKey(offset + 1) ||
              (kept.last.value == ' ' && !kept.last.preformatted))) {
        continue;
      }
      kept.add(character);
    }
    return _CookedSelectionSource(kept, keptBreaks);
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
