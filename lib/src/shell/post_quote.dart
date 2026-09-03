import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/post.dart';

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

String postQuoteContentsFromSelection(String cooked, String plainText) {
  return PostQuoteSelectionResolver(cooked).contentsFor(plainText);
}

final class PostTextSelectionResolution {
  const PostTextSelectionResolution({
    required this.markdown,
    required this.supportsFastEdit,
  });

  final String markdown;
  final bool supportsFastEdit;
}

final class PostQuoteSelectionResolver {
  PostQuoteSelectionResolver(String cooked)
    : _source = cooked.isEmpty ? null : _CookedSelectionSource.fromHtml(cooked);

  static const int maximumFastEditSelectionLength = 10000;

  final _CookedSelectionSource? _source;

  String contentsFor(String plainText) => resolve(plainText).markdown;

  PostTextSelectionResolution resolve(
    String plainText, {
    bool isLocalized = false,
  }) {
    final selected = plainText.trim();
    final source = _source;
    if (selected.isEmpty || source == null) {
      return PostTextSelectionResolution(
        markdown: selected,
        supportsFastEdit: false,
      );
    }

    var match = source.match(selected);
    if (match == null) {
      final compact = selected.replaceAll(_selectionLineBreaks, '');
      match = source.match(compact);
    }
    if (match == null) {
      return PostTextSelectionResolution(
        markdown: selected,
        supportsFastEdit: false,
      );
    }

    final markdown = source.markdown(match.start, match.end);
    return PostTextSelectionResolution(
      markdown: markdown,
      supportsFastEdit:
          !isLocalized &&
          match.unique &&
          markdown.isNotEmpty &&
          markdown.length <= maximumFastEditSelectionLength &&
          !markdown.contains('|') &&
          !markdown.contains(_selectionLineBreaks) &&
          !_problematicFastEditCharacters.hasMatch(markdown) &&
          source.fastEditable(match.start, match.end),
    );
  }
}

final RegExp _selectionLineBreaks = RegExp(r'[\r\n]');
final RegExp _problematicFastEditCharacters = RegExp('[‚‘’„“”«»‹›™±…→←↔¶]');

typedef _MarkdownMark = ({String open, String close});

final RegExp _collapsibleWhitespace = RegExp(r'[ \t\r\n\f]+');

class _CookedSelectionCharacter {
  const _CookedSelectionCharacter(
    this.value,
    this.marks, [
    this.preformatted = false,
    this.fastEditable = true,
  ]);

  final String value;
  final List<_MarkdownMark> marks;
  final bool preformatted;
  final bool fastEditable;
}

class _CookedSelectionSource {
  _CookedSelectionSource(this.characters, this.breaks)
    : plainText = characters.map((character) => character.value).join(),
      foldedPlainText = characters
          .map((character) => character.value)
          .join()
          .toLowerCase();

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
          ({
            dom.Node node,
            List<_MarkdownMark> marks,
            bool exiting,
            bool pre,
            bool fastEditBlocked,
          })
        >[];
    void pushNodes(
      List<dom.Node> nodes,
      List<_MarkdownMark> marks,
      bool pre,
      bool fastEditBlocked,
    ) {
      for (var index = nodes.length - 1; index >= 0; index--) {
        pending.add((
          node: nodes[index],
          marks: marks,
          exiting: false,
          pre: pre,
          fastEditBlocked: fastEditBlocked,
        ));
      }
    }

    pushNodes(fragment.nodes, const [], false, false);
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
            _CookedSelectionCharacter(
              value[index],
              frame.marks,
              frame.pre,
              !frame.fastEditBlocked && frame.marks.isEmpty,
            ),
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
      final fastEditBlocked =
          frame.fastEditBlocked || _fastEditBlockedElement(node);
      pending.add((
        node: node,
        marks: childMarks,
        exiting: true,
        pre: pre,
        fastEditBlocked: fastEditBlocked,
      ));
      pushNodes(node.nodes, childMarks, pre, fastEditBlocked);
    }
    return _CookedSelectionSource._trimmed(characters, breaks);
  }

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
  final String foldedPlainText;

  ({int start, int end, bool unique})? match(String selected) {
    if (selected.isEmpty) return null;
    final start = plainText.indexOf(selected);
    if (start < 0) return null;
    final foldedSelected = selected.toLowerCase();
    final foldedStart = foldedPlainText.indexOf(foldedSelected);
    return (
      start: start,
      end: start + selected.length,
      unique:
          foldedStart >= 0 &&
          foldedPlainText.indexOf(foldedSelected, foldedStart + 1) < 0,
    );
  }

  bool fastEditable(int start, int end) {
    if (start < 0 || end <= start || end > characters.length) return false;
    for (var offset = start; offset < end; offset++) {
      if (!characters[offset].fastEditable) return false;
    }
    return true;
  }

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

bool _fastEditBlockedElement(dom.Element element) =>
    element.localName == 'table' ||
    (element.localName == 'aside' &&
        (element.classes.contains('quote') ||
            element.classes.contains('onebox'))) ||
    element.classes.contains('cooked-date');

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
