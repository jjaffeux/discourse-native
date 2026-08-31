import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../foundation/diagnostic_errors.dart';
import '../../shell/code_block.dart';
import '../../shell/image_decode.dart';
import '../../shell/inline_code.dart';
import '../../shell/syntax.dart';
import '../../theme/app_theme.dart';
import 'chat_preview.dart';

/// Renders only provisional typed nodes; canonical server HTML always wins.
class ChatPreviewBody extends StatelessWidget {
  const ChatPreviewBody({
    super.key,
    required this.document,
    required this.textStyle,
    required this.previewEngine,
  });

  final PreviewDocument document;
  final TextStyle? textStyle;
  final ChatPreviewEngine previewEngine;

  @override
  Widget build(BuildContext context) {
    // One missing or broken extension renderer invalidates the whole preview.
    final pluginWidgets = <PluginPreviewNode, Widget>{};
    for (final node in document.nodes.whereType<PluginPreviewNode>()) {
      final widget = previewEngine.buildPreviewNode(context, node);
      if (widget == null) return Text(document.source, style: textStyle);
      pluginWidgets[node] = widget;
    }

    final children = <Widget>[];
    final inline = <ChatPreviewNode>[];

    void flushInline() {
      if (inline.isEmpty) return;
      children.add(
        Text.rich(
          TextSpan(
            style: textStyle,
            children: [
              for (final node in inline) _inlineSpan(node, pluginWidgets),
            ],
          ),
        ),
      );
      inline.clear();
    }

    for (final node in document.nodes) {
      switch (node) {
        case ChatPreviewCodeBlock():
          flushInline();
          children.add(_codeBlock(node));
        case ChatPreviewImage():
          flushInline();
          children.add(_OptimisticGif(node: node, textStyle: textStyle));
        case ChatPreviewText() ||
            ChatPreviewLineBreak() ||
            ChatPreviewSyntax() ||
            PluginPreviewNode():
          inline.add(node);
      }
    }
    flushInline();

    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  InlineSpan _inlineSpan(
    ChatPreviewNode node,
    Map<PluginPreviewNode, Widget> pluginWidgets,
  ) => switch (node) {
    ChatPreviewText(:final text, :final styles)
        when styles.contains(ChatPreviewTextStyle.code) =>
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InlineCode(text: text, baseStyle: textStyle),
      ),
    ChatPreviewText(:final text, :final styles) => TextSpan(
      text: text,
      style: _style(styles),
    ),
    ChatPreviewLineBreak() => const TextSpan(text: '\n'),
    ChatPreviewSyntax() => const TextSpan(),
    PluginPreviewNode() => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: DefaultTextStyle.merge(
        style: _style(node.styles),
        child: pluginWidgets[node]!,
      ),
    ),
    ChatPreviewCodeBlock() || ChatPreviewImage() => const TextSpan(),
  };

  TextStyle _style(Set<ChatPreviewTextStyle> styles) => TextStyle(
    fontWeight: styles.contains(ChatPreviewTextStyle.bold)
        ? FontWeight.bold
        : null,
    fontStyle: styles.contains(ChatPreviewTextStyle.italic)
        ? FontStyle.italic
        : null,
    decoration: styles.contains(ChatPreviewTextStyle.strikethrough)
        ? TextDecoration.lineThrough
        : null,
  );

  CodeBlock _codeBlock(ChatPreviewCodeBlock node) {
    final highlighted = highlightLines(node.code, node.language);
    return CodeBlock(
      data: CodeBlockData(
        language: node.language,
        lines: [for (final tokens in highlighted) CodeLine(tokens: tokens)],
      ),
    );
  }
}

class _OptimisticGif extends StatelessWidget {
  const _OptimisticGif({required this.node, required this.textStyle});

  final ChatPreviewImage node;
  final TextStyle? textStyle;

  static const double _maxWidth = 420;
  static const double _maxHeight = 150;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = node.width / node.height;
    final width = math.min(
      node.width.toDouble().clamp(1, _maxWidth).toDouble(),
      _maxHeight * ratio,
    );
    final fallback = node.title.trim().isEmpty ? node.fallbackText : node.title;

    return Semantics(
      image: true,
      label: fallback,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: _maxHeight),
        child: ColoredBox(
          color: theme.shell.floating,
          child: AspectRatio(
            aspectRatio: ratio,
            child: Image.network(
              node.url.toString(),
              key: const ValueKey('chat-preview-gif'),
              width: double.infinity,
              fit: BoxFit.contain,
              cacheWidth: imagePhysicalPixels(context, width),
              errorBuilder: (context, error, stackTrace) {
                reportImageError(
                  error,
                  stackTrace,
                  operation: 'chat.optimisticGif',
                );
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      fallback,
                      key: const ValueKey('chat-preview-gif-fallback'),
                      style: textStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
