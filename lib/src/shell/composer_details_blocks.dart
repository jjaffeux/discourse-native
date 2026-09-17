import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'markdown_highlight.dart';

@immutable
class ComposerDetailsBlock {
  const ComposerDetailsBlock._({
    required this.start,
    required this.source,
    required this.summary,
    required this.open,
    required this.bodyStart,
    required this.bodyEnd,
    required this.summaryStart,
    required this.summaryEnd,
  });

  final int start;
  final String source;
  final String summary;
  final bool open;
  final int bodyStart, bodyEnd, summaryStart, summaryEnd;

  int get end => start + source.length;
  String get body => source.substring(bodyStart, bodyEnd);

  /// Replaces only the requested field, retaining attributes and line endings.
  String withSummary(String value) {
    if (value == summary) return source;
    final rendered = value.isEmpty ? '' : '=${_quoteSummary(value)}';
    return source.replaceRange(summaryStart, summaryEnd, rendered);
  }

  String withBody(String value, {bool multiline = false}) {
    if (value == body && !multiline) return source;
    final newline = source.contains('\r\n') ? '\r\n' : '\n';
    value = value.replaceAll(RegExp(r'\r\n?|\n'), newline);
    // A one-line block becomes a proper block when its body gains newlines.
    if (!source.contains('\n') && (multiline || value.contains('\n'))) {
      value = '$newline$value$newline';
    } else if (source.contains('\n') &&
        bodyStart == bodyEnd &&
        !source.substring(bodyEnd).startsWith(newline) &&
        value.isNotEmpty) {
      value = '$value$newline';
    }
    return source.replaceRange(bodyStart, bodyEnd, value);
  }
}

// These are the quotation pairs recognized by Discourse's BBCode parser.
const _quotes = ['""', "''", '«»', '“”', '””', '‘’', '„“', '‚’', '‹›'];

String _quoteSummary(String value) {
  if (value.contains(RegExp(r'[\r\n]'))) {
    throw const FormatException('Use a single line for the summary.');
  }
  for (final pair in _quotes) {
    if (!value.contains(pair[1])) return '${pair[0]}$value${pair[1]}';
  }
  throw const FormatException(
    'The summary contains too many quotation styles.',
  );
}

/// Complete outer blocks only. Incomplete markup and code examples stay text.
List<ComposerDetailsBlock> parseComposerDetails(String source) {
  if (!source.toLowerCase().contains('[details')) return const [];
  final code = CodeRanges.of(scanMarkdown(source));
  final blocks = <ComposerDetailsBlock>[];
  final stack = <_DetailsTag>[];
  var offset = 0;
  while (offset < source.length) {
    final start = source.indexOf('[', offset);
    if (start < 0) break;
    offset = start + 1;
    if (code.contains(start)) continue;
    final tag = _tagAt(source, start);
    if (tag == null) continue;
    offset = tag.end;
    final lineStart = start == 0 ? 0 : source.lastIndexOf('\n', start - 1) + 1;
    final indent = source.substring(lineStart, start);
    final startsLine = RegExp(r'^ {0,3}$').hasMatch(indent);
    final lineEnd = source.indexOf('\n', tag.end);
    final tail = source.substring(
      tag.end,
      lineEnd < 0 ? source.length : lineEnd,
    );
    final endsLine = tail.trim().isEmpty;
    if (!tag.closing) {
      if (!startsLine) continue;
      if (stack.isNotEmpty && !endsLine) continue;
      stack.add(tag);
      continue;
    }
    if (stack.isEmpty || !endsLine) continue;
    final opening = stack.last;
    final inline = !source.substring(opening.end, tag.start).contains('\n');
    if (!inline && !startsLine) continue;
    stack.removeLast();
    if (stack.isNotEmpty) continue;
    var bodyStart = opening.end;
    var bodyEnd = tag.start;
    if (!inline) {
      final openingLineEnd = source.indexOf('\n', opening.end);
      if (source.substring(opening.end, openingLineEnd).trim().isNotEmpty) {
        continue;
      }
      bodyStart = openingLineEnd + 1;
      bodyEnd = lineStart;
      if (bodyEnd > bodyStart && source[bodyEnd - 1] == '\n') bodyEnd--;
      if (bodyEnd > bodyStart && source[bodyEnd - 1] == '\r') bodyEnd--;
    }
    blocks.add(
      ComposerDetailsBlock._(
        start: opening.start,
        source: source.substring(opening.start, tag.end),
        summary: opening.summary,
        open: opening.open,
        bodyStart: bodyStart - opening.start,
        bodyEnd: bodyEnd - opening.start,
        summaryStart: opening.summaryStart - opening.start,
        summaryEnd: opening.summaryEnd - opening.start,
      ),
    );
  }
  return List.unmodifiable(blocks);
}

class _DetailsTag {
  const _DetailsTag({
    required this.start,
    required this.end,
    this.closing = false,
    this.summary = '',
    this.open = false,
    this.summaryStart = 0,
    this.summaryEnd = 0,
  });
  final int start, end, summaryStart, summaryEnd;
  final bool closing, open;
  final String summary;
}

final _tagName = RegExp(r'\[(/?)details(?=[=\s\]])', caseSensitive: false);
final _attribute = RegExp(r'[-\w]+');

_DetailsTag? _tagAt(String source, int start) {
  final name = _tagName.matchAsPrefix(source, start);
  if (name == null) return null;
  var at = name.end;
  if (name[1] == '/') {
    return at < source.length && source[at] == ']'
        ? _DetailsTag(start: start, end: at + 1, closing: true)
        : null;
  }
  final summaryStart = at;
  var summaryEnd = at;
  var summary = '';
  var open = false;
  String? readValue() {
    if (at >= source.length) return null;
    final pair = _quotes.where((pair) => pair[0] == source[at]).firstOrNull;
    final from = at;
    if (pair != null) {
      final end = source.indexOf(pair[1], at + 1);
      if (end < 0 || source.substring(at, end).contains('\n')) return null;
      at = end + 1;
      return source.substring(from + 1, end);
    }
    while (at < source.length && !RegExp(r'[\s\]]').hasMatch(source[at])) {
      at++;
    }
    return at == from ? null : source.substring(from, at);
  }

  if (at < source.length && source[at] == '=') {
    at++;
    // The legacy unquoted default consumes the entire title up to ']'.
    if (at < source.length && !_quotes.any((pair) => pair[0] == source[at])) {
      final end = source.indexOf(']', at);
      if (end < 0 || source.substring(at, end).contains('\n')) return null;
      summary = source.substring(at, end).trim();
      if (summary.isEmpty) return null;
      at = end;
    } else {
      final value = readValue();
      if (value == null) return null;
      summary = value.trim();
    }
    summaryEnd = at;
  }
  while (at < source.length) {
    if (source[at] == ']') {
      return _DetailsTag(
        start: start,
        end: at + 1,
        summary: summary,
        open: open,
        summaryStart: summaryStart,
        summaryEnd: summaryEnd,
      );
    }
    if (source[at] != ' ' && source[at] != '\t') return null;
    while (at < source.length && (source[at] == ' ' || source[at] == '\t')) {
      at++;
    }
    if (at < source.length && source[at] == ']') continue;
    final attribute = _attribute.matchAsPrefix(source, at);
    if (attribute == null) return null;
    at = attribute.end;
    var value = '';
    if (at < source.length && source[at] == '=') {
      at++;
      final parsed = readValue();
      if (parsed == null) return null;
      value = parsed;
    }
    if (attribute[0] == 'open') open = value.isEmpty;
  }
  return null;
}

/// Hidden delimiters are atomic to platform edits; the embedded fields own
/// changes inside the block. Complete replacements and history remain valid.
class ComposerDetailsInputFormatter extends TextInputFormatter {
  const ComposerDetailsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;
    var start = 0;
    var end = oldValue.text.length;
    var newEnd = newValue.text.length;
    final selection = oldValue.selection;
    if (selection.isValid &&
        !selection.isCollapsed &&
        newValue.text.startsWith(oldValue.text.substring(0, selection.start)) &&
        newValue.text.endsWith(oldValue.text.substring(selection.end))) {
      start = selection.start;
      end = selection.end;
    } else {
      while (start < end &&
          start < newEnd &&
          oldValue.text[start] == newValue.text[start]) {
        start++;
      }
      while (end > start &&
          newEnd > start &&
          oldValue.text[end - 1] == newValue.text[newEnd - 1]) {
        end--;
        newEnd--;
      }
    }
    for (final block in parseComposerDetails(oldValue.text)) {
      if (oldValue.isComposingRangeValid &&
          !oldValue.composing.isCollapsed &&
          oldValue.composing.start < block.end &&
          oldValue.composing.end > block.start) {
        continue;
      }
      if (start == end
          ? start > block.start && start < block.end
          : start < block.end &&
                end > block.start &&
                (start > block.start || end < block.end)) {
        final delta = newValue.text.length - oldValue.text.length;
        bool outside(TextEditingValue value, int end) =>
            value.selection.isValid &&
            value.selection.isCollapsed &&
            (value.selection.extentOffset <= block.start ||
                value.selection.extentOffset >= end);
        if (outside(oldValue, block.end) &&
            outside(newValue, block.end + delta) &&
            parseComposerDetails(newValue.text).any(
              (next) =>
                  next.start == block.start && next.end == block.end + delta,
            )) {
          continue;
        }
        return oldValue;
      }
    }
    return newValue;
  }
}
