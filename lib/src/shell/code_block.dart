import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../theme/app_theme.dart';
import 'syntax.dart';

/// Renders `<pre>` natively, for both post code fences and oneboxes.
///
/// [HtmlWidget] draws a `<pre>` as preformatted text, which is right until
/// something structural is nested inside it. Discourse's git blob oneboxes put
/// a numbered `<ol class="lines">` in there (`githubblob.mustache`), so every
/// newline the template indents with survives into the output and the block
/// renders as list items separated by blank lines.
///
/// This reads either shape, highlights it, and draws lines itself.
class CodeBlockData {
  const CodeBlockData({required this.lines, this.language});

  final List<CodeLine> lines;

  /// What the markup said the language is, before alias resolution — kept for
  /// debugging and tests rather than for rendering.
  final String? language;

  /// Reads [pre], which must be the `<pre>` element itself.
  static CodeBlockData from(dom.Element pre) {
    final code = _descendant(pre, (e) => e.localName == 'code');
    final language = _language(code ?? pre);

    final ol = _descendant(pre, (e) => e.localName == 'ol');
    final lines = ol != null ? _numbered(ol) : _plain((code ?? pre).text);

    return CodeBlockData(
      lines: _highlighted(lines, language),
      language: language,
    );
  }

  /// Discourse writes the language as a `lang-` prefixed class.
  static String? _language(dom.Element code) {
    for (final className in code.classes) {
      if (className.startsWith('lang-')) {
        return className.substring('lang-'.length);
      }
    }
    return null;
  }

  /// A git blob onebox: one `<li>` per line, numbered from `start`.
  static List<CodeLine> _numbered(dom.Element ol) {
    final start = int.tryParse(ol.attributes['start'] ?? '');
    final items = ol.children.where((e) => e.localName == 'li').toList();

    return [
      for (final (index, li) in items.indexed)
        CodeLine(
          // Not trimmed: leading whitespace is the indentation.
          tokens: [CodeToken(li.text)],
          number: start == null ? null : start + index,
          isSelected: li.classes.contains('selected'),
        ),
    ];
  }

  /// An ordinary code fence, where the text is the code.
  static List<CodeLine> _plain(String text) {
    final lines = text.split('\n');
    // `<pre>` swallows one newline after the open tag, and cooked code fences
    // carry a trailing one. Neither is a line the author wrote.
    if (lines.isNotEmpty && lines.first.trim().isEmpty) lines.removeAt(0);
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return [
      for (final line in lines) CodeLine(tokens: [CodeToken(line)]),
    ];
  }

  /// Highlights the whole block at once, then puts the tokens back on their
  /// lines — the line numbers and selection belong to the markup, not to the
  /// highlighter, so they are carried across rather than recomputed.
  static List<CodeLine> _highlighted(List<CodeLine> lines, String? language) {
    if (lines.isEmpty) return lines;

    final tokenized = highlightLines(
      lines.map((line) => line.text).join('\n'),
      language,
    );
    if (tokenized.length != lines.length) return lines;

    return [
      for (final (index, line) in lines.indexed)
        CodeLine(
          tokens: tokenized[index],
          number: line.number,
          isSelected: line.isSelected,
        ),
    ];
  }

  static dom.Element? _descendant(
    dom.Element root,
    bool Function(dom.Element) test,
  ) {
    final pending = <dom.Element>[];
    void pushReversed(List<dom.Element> children) {
      for (var index = children.length - 1; index >= 0; index--) {
        pending.add(children[index]);
      }
    }

    pushReversed(root.children);
    while (pending.isNotEmpty) {
      final child = pending.removeLast();
      if (test(child)) return child;
      pushReversed(child.children);
    }
    return null;
  }
}

class CodeLine {
  const CodeLine({required this.tokens, this.number, this.isSelected = false});

  /// The line's runs of source, scoped by the highlighter. A line the
  /// highlighter had nothing to say about is one unscoped token.
  final List<CodeToken> tokens;

  /// The line's number in the original file, when the markup said.
  final int? number;

  /// Git blob oneboxes mark the lines the link pointed at.
  final bool isSelected;

  String get text => tokens.map((token) => token.text).join();
}

/// The face Discourse loads for `code`, `pre`, and `kbd`.
///
/// It is bundled rather than left to the platform: otherwise macOS would draw
/// Menlo, Windows Consolas, and Android its default body face. Regular and bold
/// are the same two weights the web app ships.
const String monospaceFontFamily = 'JetBrains Mono';

/// Discourse's fallback stack, for glyphs JetBrains Mono does not contain.
const List<String> monospaceFallback = ['Consolas', 'Monaco', 'monospace'];

/// `font-variant-ligatures: none`, as set by Discourse for JetBrains Mono.
///
/// Coding ligatures would make the painted characters disagree with the
/// markdown source the reader or composer is looking at.
const List<FontFeature> monospaceFontFeatures = [
  FontFeature.disable('liga'),
  FontFeature.disable('clig'),
  FontFeature.disable('dlig'),
  FontFeature.disable('hlig'),
  FontFeature.disable('calt'),
];

/// Shared by rendered code, the composer, and monospace onebox fragments.
const TextStyle monospaceTextStyle = TextStyle(
  fontFamily: monospaceFontFamily,
  fontFamilyFallback: monospaceFallback,
  fontFeatures: monospaceFontFeatures,
);

/// Maps a highlight.js scope onto one of the six colors the theme defines.
///
/// highlight.js emits around forty class names; grouping them keeps a block
/// readable instead of turning it into confetti, and means a language nobody
/// anticipated still lands somewhere sensible. Null leaves the token in the
/// default foreground.
Color? scopeColor(String? scope, CodeColors colors) => switch (scope) {
  'keyword' ||
  'built_in' ||
  'builtin-name' ||
  'type' ||
  'literal' ||
  'operator' ||
  'selector-tag' ||
  'tag' => colors.keyword,

  'string' ||
  'regexp' ||
  'symbol' ||
  'char' ||
  'quote' ||
  'addition' ||
  'selector-attr' => colors.string,

  'comment' || 'doctag' => colors.comment,

  'number' || 'deletion' => colors.number,

  'title' ||
  'class' ||
  'function' ||
  'name' ||
  'section' ||
  'attr' ||
  'attribute' ||
  'variable' ||
  'template-variable' ||
  'selector-id' ||
  'selector-class' ||
  'bullet' => colors.name,

  'meta' ||
  'meta-keyword' ||
  'meta-string' ||
  'subst' ||
  'link' ||
  'formula' => colors.meta,

  _ => null,
};

/// Hands `<pre>` to [CodeBlock], for [HtmlWidget.customWidgetBuilder].
Widget? codeBlockWidgetBuilder(dom.Element element) {
  if (element.localName != 'pre') return null;
  return CodeBlock(data: CodeBlockData.from(element));
}

class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.data});

  final CodeBlockData data;

  /// Room under the code for the horizontal scrollbar, so the thumb sits below
  /// the last line rather than over it.
  static const double _scrollbarLane = 12;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  /// Shared with the [Scrollbar] so it has something to draw and to drag.
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.shell;
    final data = widget.data;

    if (data.lines.isEmpty) return const SizedBox();

    final style = monospaceTextStyle.copyWith(
      fontSize: 12,
      height: 1.4,
      color: theme.colorScheme.onSurface,
    );
    final gutterStyle = style.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      // The HTML column left-aligns its children, so a block would otherwise
      // shrink to its widest line and sit there looking like a stray box.
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.code.blockBackground,
        border: Border.all(color: shell.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      // Code does not wrap — it scrolls, like every other code viewer, since
      // wrapping makes indentation lie about structure. The scrollbar stays up
      // whenever there is somewhere to scroll: a clipped line otherwise reads
      // as a rendering bug rather than as an invitation to scroll.
      child: LayoutBuilder(
        builder: (context, constraints) => Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(
              top: 8,
              bottom: CodeBlock._scrollbarLane,
            ),
            // At least as wide as the block, so a selected line highlights all
            // the way across; wider when a line is longer than that.
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in data.lines)
                      _Line(
                        line: line,
                        style: style,
                        gutterStyle: gutterStyle,
                        gutterWidth: _gutterWidth,
                        highlight: theme.colorScheme.tertiary.withValues(
                          alpha: 0.14,
                        ),
                        scopeColor: (scope) => scopeColor(scope, theme.code),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sized from the widest number so the code column does not step sideways.
  double? get _gutterWidth {
    final widest = widget.data.lines
        .map((line) => line.number?.toString().length ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    return widest == 0 ? null : widest * 8 + 12;
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.line,
    required this.style,
    required this.gutterStyle,
    required this.gutterWidth,
    required this.highlight,
    required this.scopeColor,
  });

  final CodeLine line;
  final TextStyle style;
  final TextStyle gutterStyle;
  final double? gutterWidth;
  final Color highlight;
  final Color? Function(String?) scopeColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: line.isSelected ? highlight : Colors.transparent,
      child: Row(
        children: [
          if (gutterWidth != null)
            SizedBox(
              width: gutterWidth,
              child: Text(
                line.number?.toString() ?? '',
                textAlign: TextAlign.right,
                style: gutterStyle,
              ),
            ),
          const SizedBox(width: 8),
          Text.rich(TextSpan(children: _spans), style: style),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  List<TextSpan> get _spans {
    // A zero-width space keeps an empty line the height of a full one.
    if (line.text.isEmpty) return const [TextSpan(text: '​')];

    return [
      for (final token in line.tokens)
        TextSpan(
          text: token.text,
          style: switch (scopeColor(token.scope)) {
            final color? => TextStyle(color: color),
            null => null,
          },
        ),
    ];
  }
}
