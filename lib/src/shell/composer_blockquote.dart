import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'markdown_highlight.dart';
import 'quote_panel.dart';

final _prefix = RegExp(r'^ {0,3}>+(?:[ \t]>+)*[ \t]', multiLine: true);

List<TextRange> composerBlockquotePrefixes(
  String source, {
  CodeRanges? knownCodeRanges,
}) {
  final matches = _prefix.allMatches(source).toList();
  if (matches.isEmpty) return const [];
  final code = knownCodeRanges ?? CodeRanges.of(scanMarkdown(source));
  return [
    for (final match in matches)
      if (!code.overlaps(match.start, match.end))
        TextRange(start: match.start, end: match.end),
  ];
}

/// Replaces only the Markdown prefix so the quoted body stays editable.
class ComposerBlockquoteMarker extends StatelessWidget {
  const ComposerBlockquoteMarker({
    super.key,
    required this.baseStyle,
    required this.depth,
  });

  final TextStyle baseStyle;
  final int depth;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Quote',
    child: IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var level = 0; level < depth; level++)
            QuotePanel(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.only(right: 9),
              child: SizedBox(
                height: (baseStyle.fontSize ?? 14) * (baseStyle.height ?? 1.2),
              ),
            ),
        ],
      ),
    ),
  );
}

class ComposerBlockquoteInputFormatter extends TextInputFormatter {
  const ComposerBlockquoteInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        !newValue.selection.isCollapsed ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }

    final caret = selection.extentOffset;
    if (caret > oldValue.text.length ||
        newValue.selection.extentOffset != caret + 1 ||
        newValue.text.length != oldValue.text.length + 1 ||
        newValue.text != oldValue.text.replaceRange(caret, caret, '\n')) {
      return newValue;
    }

    final lineStart = caret == 0
        ? 0
        : oldValue.text.lastIndexOf('\n', caret - 1) + 1;
    for (final range in composerBlockquotePrefixes(oldValue.text)) {
      if (range.start != lineStart || range.end > caret) continue;
      final lineEnd = oldValue.text.indexOf('\n', caret);
      final body = oldValue.text.substring(
        range.end,
        lineEnd == -1 ? oldValue.text.length : lineEnd,
      );
      if (body.trim().isEmpty) {
        // The second Enter exits the quote without leaving an empty quote row.
        final end = lineEnd == -1 ? oldValue.text.length : lineEnd;
        return TextEditingValue(
          text: oldValue.text.replaceRange(lineStart, end, ''),
          selection: TextSelection.collapsed(offset: lineStart),
        );
      }

      final prefix = range.textInside(oldValue.text);
      return TextEditingValue(
        text: newValue.text.replaceRange(caret + 1, caret + 1, prefix),
        selection: TextSelection.collapsed(offset: caret + 1 + prefix.length),
      );
    }
    return newValue;
  }
}
