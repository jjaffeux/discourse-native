import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart' as editor;
import 'package:html/dom.dart' as dom;

import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'cooked_dom.dart';
import 'syntax.dart';

class CodeBlockData {
  const CodeBlockData({
    required this.lines,
    this.language,
    this.highlightDeferred = false,
  });

  static final RegExp _clipboardWhitespace = RegExp(
    r'[\f\v\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]',
  );

  final List<CodeLine> lines;

  final String? language;

  final bool highlightDeferred;

  String get text => lines.map((line) => line.text).join('\n');

  String get clipboardText => text.replaceAll(_clipboardWhitespace, ' ').trim();

  static CodeBlockData from(dom.Element pre) {
    final code = descendantWhere(pre, (e) => e.localName == 'code');
    final language = _language(code ?? pre);

    final ol = descendantWhere(pre, (e) => e.localName == 'ol');
    final lines = ol != null ? _numbered(ol) : _plain((code ?? pre).text);

    final source = lines.map((line) => line.text).join('\n');
    final deferHighlight = highlightShouldRunInBackground(source, language);
    return CodeBlockData(
      lines: deferHighlight ? lines : _highlighted(lines, language),
      language: language,
      highlightDeferred: deferHighlight,
    );
  }

  CodeBlockData _withTokens(List<List<CodeToken>> tokenized) {
    if (tokenized.length != lines.length) {
      return CodeBlockData(lines: lines, language: language);
    }
    return CodeBlockData(
      language: language,
      lines: [
        for (final (index, line) in lines.indexed)
          CodeLine(
            tokens: tokenized[index],
            number: line.number,
            isSelected: line.isSelected,
          ),
      ],
    );
  }

  static String? _language(dom.Element code) {
    for (final className in code.classes) {
      if (className.startsWith('lang-')) {
        return className.substring('lang-'.length);
      }
    }
    return null;
  }

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

  static List<CodeLine> _plain(String text) {
    final lines = text.split('\n');
    // Remove only the single empty boundary lines added by `<pre>` and cooked
    // fences; whitespace-only and additional blank lines are authored code.
    if (lines.isNotEmpty && lines.first.isEmpty) lines.removeAt(0);
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return [
      for (final line in lines) CodeLine(tokens: [CodeToken(line)]),
    ];
  }

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

  final List<CodeToken> tokens;

  final int? number;

  final bool isSelected;

  String get text => tokens.map((token) => token.text).join();
}

const String monospaceFontFamily = 'JetBrains Mono';

const List<String> monospaceFallback = [
  'packages/discourse_native/JetBrains Mono',
  'Consolas',
  'Monaco',
  'monospace',
];

const List<FontFeature> monospaceFontFeatures = [
  FontFeature.disable('liga'),
  FontFeature.disable('clig'),
  FontFeature.disable('dlig'),
  FontFeature.disable('hlig'),
  FontFeature.disable('calt'),
];

const TextStyle monospaceTextStyle = TextStyle(
  fontFamily: monospaceFontFamily,
  fontFamilyFallback: monospaceFallback,
  fontFeatures: monospaceFontFeatures,
);

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

const Map<String, String> _languageLabels = {
  'bash': 'Bash',
  'c': 'C',
  'clojure': 'Clojure',
  'coffee': 'CoffeeScript',
  'coffeescript': 'CoffeeScript',
  'cpp': 'C++',
  'cs': 'C#',
  'csharp': 'C#',
  'css': 'CSS',
  'dart': 'Dart',
  'diff': 'Diff',
  'dockerfile': 'Dockerfile',
  'elixir': 'Elixir',
  'erb': 'ERB',
  'go': 'Go',
  'graphql': 'GraphQL',
  'handlebars': 'Handlebars',
  'hbs': 'Handlebars',
  'html': 'HTML',
  'html.hbs': 'Handlebars',
  'java': 'Java',
  'javascript': 'JavaScript',
  'js': 'JavaScript',
  'json': 'JSON',
  'jsx': 'JSX',
  'kotlin': 'Kotlin',
  'kt': 'Kotlin',
  'markdown': 'Markdown',
  'md': 'Markdown',
  'objectivec': 'Objective-C',
  'php': 'PHP',
  'plaintext': 'Plain text',
  'python': 'Python',
  'py': 'Python',
  'rb': 'Ruby',
  'ruby': 'Ruby',
  'rust': 'Rust',
  'scss': 'SCSS',
  'shell': 'Shell',
  'sql': 'SQL',
  'swift': 'Swift',
  'text': 'Plain text',
  'tsx': 'TSX',
  'typescript': 'TypeScript',
  'ts': 'TypeScript',
  'xml': 'XML',
  'yaml': 'YAML',
  'yml': 'YAML',
};

String codeLanguageLabel(String? language) {
  final normalized = language?.trim().toLowerCase();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized == 'auto' ||
      normalized == 'nohighlight') {
    return 'Code';
  }

  return _languageLabels[normalized] ??
      normalized
          .split(RegExp(r'[-_.]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
}

Widget? codeBlockWidgetBuilder(dom.Element element) {
  if (element.localName != 'pre') return null;
  return CodeBlock(data: CodeBlockData.from(element));
}

class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.data, this.showFullscreen = true});

  final CodeBlockData data;
  final bool showFullscreen;

  static const double _scrollbarLane = 12;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  final ScrollController _horizontal = ScrollController();
  late CodeBlockData _data;
  int _highlightGeneration = 0;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    _scheduleDeferredHighlight();
  }

  @override
  void didUpdateWidget(CodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.data, widget.data)) return;
    _highlightGeneration++;
    _data = widget.data;
    _scheduleDeferredHighlight();
  }

  void _scheduleDeferredHighlight() {
    final data = _data;
    if (!data.highlightDeferred) return;
    final generation = ++_highlightGeneration;
    unawaited(_highlightInBackground(data, generation));
  }

  Future<void> _highlightInBackground(
    CodeBlockData data,
    int generation,
  ) async {
    try {
      final source = data.text;
      final highlighted = await highlightLinesInBackground(
        source,
        data.language,
      );
      if (!mounted || generation != _highlightGeneration) return;
      setState(() => _data = data._withTokens(highlighted));
    } catch (_) {
      // Syntax colour is optional; plain code is already visible and usable.
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  void _openFullscreen() {
    unawaited(
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'code-block-fullscreen'),
          fullscreenDialog: true,
          builder: (context) => CodeBlockFullscreen(data: _data),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;

    if (data.lines.isEmpty) return const SizedBox();

    final style = monospaceTextStyle.copyWith(
      fontSize: DiscourseTypography.fontDown1,
      height: DiscourseTypography.codeLineHeight,
      color: theme.discourse.primaryVeryHigh,
    );
    final gutterStyle = style.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.code.blockBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CodeBlockHeader(
            language: data.language,
            actions: [
              _CodeCopyButton(text: data.clipboardText),
              if (widget.showFullscreen)
                DButton.iconOnly(
                  key: const ValueKey('code-block-fullscreen'),
                  onPressed: _openFullscreen,
                  tooltip: 'View code full screen',
                  semanticLabel: 'View code full screen',
                  variant: DButtonVariant.flat,
                  size: DButtonSize.small,
                  icon: const DIcon(DIcons.expand, size: 16),
                ),
            ],
          ),
          // Code does not wrap — it scrolls, like every other code viewer,
          // since wrapping makes indentation lie about structure. The
          // scrollbar stays up whenever there is somewhere to scroll.
          LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _horizontal,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(
                  top: 4,
                  bottom: CodeBlock._scrollbarLane,
                ),
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
        ],
      ),
    );
  }

  double? get _gutterWidth {
    final widest = _data.lines
        .map((line) => line.number?.toString().length ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    return widest == 0 ? null : widest * 8 + 12;
  }
}

class CodeBlockFullscreen extends StatefulWidget {
  const CodeBlockFullscreen({super.key, required this.data});

  final CodeBlockData data;

  @override
  State<CodeBlockFullscreen> createState() => _CodeBlockFullscreenState();
}

class _CodeBlockFullscreenState extends State<CodeBlockFullscreen> {
  late final editor.CodeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = editor.CodeController(
      text: widget.data.text,
      language: highlightMode(widget.data.text, widget.data.language),
      readOnly: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = monospaceTextStyle.copyWith(
      fontSize: DiscourseTypography.fontDown1,
      height: DiscourseTypography.codeLineHeight,
      color: theme.discourse.primaryVeryHigh,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: const ValueKey('code-block-fullscreen-view'),
          backgroundColor: theme.code.blockBackground,
          body: SafeArea(
            child: Column(
              children: [
                _CodeBlockHeader(
                  language: widget.data.language,
                  centerLanguage: true,
                  languageKey: const ValueKey('code-block-fullscreen-language'),
                  actions: [
                    _CodeCopyButton(text: widget.data.clipboardText),
                    DButton.iconOnly(
                      key: const ValueKey('code-block-fullscreen-close'),
                      onPressed: Navigator.of(context).pop,
                      tooltip: 'Close',
                      semanticLabel: 'Close code viewer',
                      variant: DButtonVariant.flat,
                      size: DButtonSize.small,
                      icon: const DIcon(DIcons.xmark, size: 18),
                    ),
                  ],
                ),
                Expanded(
                  child: editor.CodeTheme(
                    data: editor.CodeThemeData(styles: _editorStyles(theme)),
                    child: editor.CodeField(
                      key: const ValueKey('code-block-fullscreen-editor'),
                      controller: _controller,
                      readOnly: true,
                      expands: true,
                      wrap: false,
                      background: theme.code.blockBackground,
                      textStyle: style,
                      gutterStyle: editor.GutterStyle(
                        width: 56,
                        margin: 12,
                        showErrors: false,
                        showFoldingHandles: false,
                        textStyle: style.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      textSelectionTheme: TextSelectionThemeData(
                        selectionColor: theme.colorScheme.primary.withValues(
                          alpha: 0.28,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeBlockHeader extends StatelessWidget {
  const _CodeBlockHeader({
    required this.language,
    required this.actions,
    this.centerLanguage = false,
    this.languageKey,
  });

  final String? language;
  final List<Widget> actions;
  final bool centerLanguage;
  final Key? languageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final languageLabel = Row(
      key: languageKey,
      mainAxisSize: centerLanguage ? MainAxisSize.min : MainAxisSize.max,
      children: [
        DIcon(DIcons.code, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            codeLanguageLabel(language),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.discourse.primaryVeryHigh,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    if (centerLanguage) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              // Reserve equal space on both sides so the title stays centered
              // in the window and clear of both macOS controls and our actions.
              padding: const EdgeInsets.symmetric(horizontal: 96),
              child: Center(child: languageLabel),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        child: Row(
          children: [
            Expanded(child: languageLabel),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _CodeCopyButton extends StatefulWidget {
  const _CodeCopyButton({required this.text});

  final String text;

  @override
  State<_CodeCopyButton> createState() => _CodeCopyButtonState();
}

class _CodeCopyButtonState extends State<_CodeCopyButton> {
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text("Couldn't copy code.")));
      }
      return;
    }
    if (!mounted) return;

    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DButton.iconOnly(
      key: const ValueKey('code-block-copy'),
      onPressed: _copied ? null : () => unawaited(_copy()),
      tooltip: _copied ? 'Copied!' : 'Copy code',
      semanticLabel: _copied ? 'Code copied' : 'Copy code',
      variant: DButtonVariant.flat,
      size: DButtonSize.small,
      icon: DIcon(
        _copied ? DIcons.check : DIcons.copy,
        size: 16,
        color: _copied ? theme.colorScheme.primary : null,
      ),
    );
  }
}

Map<String, TextStyle> _editorStyles(ThemeData theme) {
  final colors = theme.code;
  TextStyle color(Color color) => TextStyle(color: color);

  return {
    'root': TextStyle(
      color: theme.discourse.primaryVeryHigh,
      backgroundColor: colors.blockBackground,
    ),
    for (final scope in const [
      'keyword',
      'built_in',
      'builtin-name',
      'type',
      'literal',
      'operator',
      'selector-tag',
      'tag',
    ])
      scope: color(colors.keyword),
    for (final scope in const [
      'string',
      'regexp',
      'symbol',
      'char',
      'quote',
      'addition',
      'selector-attr',
    ])
      scope: color(colors.string),
    for (final scope in const ['comment', 'doctag'])
      scope: color(colors.comment),
    for (final scope in const ['number', 'deletion'])
      scope: color(colors.number),
    for (final scope in const [
      'title',
      'class',
      'function',
      'name',
      'section',
      'attr',
      'attribute',
      'variable',
      'template-variable',
      'selector-id',
      'selector-class',
      'bullet',
    ])
      scope: color(colors.name),
    for (final scope in const [
      'meta',
      'meta-keyword',
      'meta-string',
      'subst',
      'link',
      'formula',
    ])
      scope: color(colors.meta),
  };
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
