import 'package:flutter/services.dart';

import 'html_comments.dart';
import 'markdown_highlight.dart';

typedef ComposerSlashQuery = ({int start, int end, String query});

/// Slash commands start at a word boundary, never inside URLs or code.
ComposerSlashQuery? composerSlashQuery(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid ||
      !selection.isCollapsed ||
      selection.end > value.text.length ||
      !value.composing.isCollapsed) {
    return null;
  }
  final before = value.text.substring(0, selection.end);
  final match = RegExp(r'(?:^|\s)/([a-zA-Z0-9-]{0,40})$').firstMatch(before);
  if (match == null) return null;
  final start = before.lastIndexOf('/');
  if (selection.end < value.text.length &&
      !RegExp(r'\s').hasMatch(value.text[selection.end])) {
    return null;
  }
  final lineStart = start == 0 ? 0 : before.lastIndexOf('\n', start - 1) + 1;
  final line = before.substring(lineStart, start);
  if (RegExp(r'^(?: {4}|\t)').hasMatch(line)) return null;
  final literals = ComposerLiteralContainers(value.text);
  if (literals.contains(start)) return null;
  final syntax = literals.mask(value.text);
  if (markdownCodeRanges(syntax).contains(start) ||
      _backtickOrEscape
          .allMatches(syntax.substring(lineStart, start))
          .where((match) => match[0] == '`')
          .length
          .isOdd) {
    return null;
  }
  return (start: start, end: selection.end, query: match.group(1)!);
}

final _backtickOrEscape = RegExp(r'\\.|`');
