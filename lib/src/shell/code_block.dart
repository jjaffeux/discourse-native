import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;

import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'cooked_dom.dart';
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

  static final RegExp _clipboardWhitespace = RegExp(
    r'[\f\v\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]',
  );

  final List<CodeLine> lines;

  /// What the markup said the language is, before alias resolution — kept for
  /// debugging and tests rather than for rendering.
  final String? language;

  /// The code as the author wrote it, without line-number markup.
  String get text => lines.map((line) => line.text).join('\n');

  /// The web client normalizes non-standard spaces before copying so pasted
  /// code behaves like ordinary source in editors and terminals.
  String get clipboardText => text.replaceAll(_clipboardWhitespace, ' ').trim();

  /// Reads [pre], which must be the `<pre>` element itself.
  static CodeBlockData from(dom.Element pre) {
    final code = descendantWhere(pre, (e) => e.localName == 'code');
    final language = _language(code ?? pre);

    final ol = descendantWhere(pre, (e) => e.localName == 'ol');
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
    final items = childrenWhere(ol, (e) => e.localName == 'li');

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
    // carry a trailing one. Neither is a line the author wrote — but only one
    // of each, and only a truly empty one. Blank lines beyond that, and lines
    // holding whitespace, are the author's: a fence that ends on deliberate
    // spacing kept it, and a stripping pass cannot tell that from padding.
    if (lines.isNotEmpty && lines.first.isEmpty) lines.removeAt(0);
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
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
///
/// Flutter prefixes fonts contributed by a dependency package. The full app
/// consumes core as `discourse_native`, while the core app is the root package,
/// so keeping both family names here makes the same text style correct in both
/// build compositions without copying font assets into the full profile.
const List<String> monospaceFallback = [
  'packages/discourse_native/JetBrains Mono',
  'Consolas',
  'Monaco',
  'monospace',
];

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
  const CodeBlock({super.key, required this.data, this.showFullscreen = true});

  final CodeBlockData data;
  final bool showFullscreen;

  /// Room under the code for the horizontal scrollbar, so the thumb sits below
  /// the last line rather than over it.
  static const double _scrollbarLane = 12;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  /// Shared with the [Scrollbar] so it has something to draw and to drag.
  final ScrollController _horizontal = ScrollController();
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.data.clipboardText));
    } catch (_) {
      if (mounted) _notice("Couldn't copy code.");
      return;
    }
    if (!mounted) return;

    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _notice(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _openFullscreen() {
    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'code-block-fullscreen'),
          fullscreenDialog: true,
          builder: (context) => CodeBlockFullscreen(data: widget.data),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    if (data.lines.isEmpty) return const SizedBox();

    final style = monospaceTextStyle.copyWith(
      fontSize: DiscourseTypography.code,
      height: DiscourseTypography.codeLineHeight,
      color: theme.discourse.primaryVeryHigh,
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
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      // Code does not wrap — it scrolls, like every other code viewer, since
      // wrapping makes indentation lie about structure. The scrollbar stays up
      // whenever there is somewhere to scroll: a clipped line otherwise reads
      // as a rendering bug rather than as an invitation to scroll.
      child: Stack(
        children: [
          LayoutBuilder(
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
                // At least as wide as the block, so a selected line highlights
                // all the way across; wider when a line is longer than that.
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
                            highlight: theme.colorScheme.tertiaryContainer,
                            scopeColor: (scope) =>
                                scopeColor(scope, theme.code),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: ColoredBox(
              color: theme.code.blockBackground.withValues(alpha: 0.94),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DButton.iconOnly(
                    key: const ValueKey('code-block-copy'),
                    onPressed: _copied ? null : () => unawaited(_copy()),
                    tooltip: _copied ? 'Copied!' : 'Copy code',
                    semanticLabel: _copied ? 'Code copied' : 'Copy code',
                    variant: DButtonVariant.flat,
                    size: DButtonSize.small,
                    icon: DIcon(
                      _copied ? DIcons.check : DIcons.copy,
                      size: 14,
                      color: _copied ? theme.colorScheme.primary : null,
                    ),
                  ),
                  if (widget.showFullscreen)
                    DButton.iconOnly(
                      key: const ValueKey('code-block-fullscreen'),
                      onPressed: _openFullscreen,
                      tooltip: 'View code full screen',
                      semanticLabel: 'View code full screen',
                      variant: DButtonVariant.flat,
                      size: DButtonSize.small,
                      icon: const DIcon(DIcons.expand, size: 14),
                    ),
                ],
              ),
            ),
          ),
        ],
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

/// A focused, scrollable view of one code block, matching Discourse's
/// full-screen code modal. Copy remains available here; opening another viewer
/// does not.
class CodeBlockFullscreen extends StatefulWidget {
  const CodeBlockFullscreen({super.key, required this.data});

  final CodeBlockData data;

  @override
  State<CodeBlockFullscreen> createState() => _CodeBlockFullscreenState();
}

class _CodeBlockFullscreenState extends State<CodeBlockFullscreen> {
  final ScrollController _vertical = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('code-block-fullscreen-view'),
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('code-block-fullscreen-close'),
          onPressed: Navigator.of(context).pop,
          tooltip: 'Close',
          icon: const DIcon(DIcons.xmark, size: 18),
        ),
        title: const Text('View code'),
      ),
      body: SafeArea(
        child: Scrollbar(
          controller: _vertical,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _vertical,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: CodeBlock(data: widget.data, showFullscreen: false),
          ),
        ),
      ),
    );
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
