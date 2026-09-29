import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A complete fenced block, retaining its original delimiters and line endings.
@immutable
class ComposerCodeBlock {
  const ComposerCodeBlock({
    required this.start,
    required this.source,
    required this.bodyStart,
    required this.bodyEnd,
    required this.fence,
    required this.infoStart,
    required this.infoEnd,
    required this.closingStart,
    required this.closingLength,
  });

  final int start, bodyStart, bodyEnd, infoStart, infoEnd;
  final int closingStart, closingLength;
  final String source, fence;
  int get end => start + source.length;
  String get body => source.substring(bodyStart, bodyEnd);
  String get language => source.substring(infoStart, infoEnd);
  String get newline => source.contains('\r\n') ? '\r\n' : '\n';

  String withLanguage(String value) =>
      source.replaceRange(infoStart, infoEnd, value);

  String withBody(String value) {
    value = value.replaceAll(RegExp(r'\r\n?|\n'), newline);
    if (value == body) return source;
    // Pasted fence lines are code too. Lengthen both delimiters if necessary.
    final requiredLength = _safeFenceLength(value, fence[0], fence.length);
    final delimiter = fence[0] * requiredLength;
    final closing = source
        .substring(bodyEnd)
        .replaceRange(
          closingStart - bodyEnd,
          closingStart - bodyEnd + closingLength,
          fence[0] *
              (requiredLength > closingLength ? requiredLength : closingLength),
        );
    final opening = source
        .substring(0, bodyStart)
        .replaceRange(
          source.indexOf(fence),
          source.indexOf(fence) + fence.length,
          delimiter,
        );
    final separator = bodyStart == bodyEnd && !closing.startsWith(newline)
        ? newline
        : '';
    return '$opening$value$separator$closing';
  }
}

int _safeFenceLength(String body, String character, int minimum) {
  var length = minimum;
  for (final match in RegExp(
    '^ {0,3}($character{3,})[ \\t]*\\r?\$',
    multiLine: true,
  ).allMatches(body)) {
    if (match.group(1)!.length >= length) length = match.group(1)!.length + 1;
  }
  return length;
}

String composerCodeMarkdown(String body, {String newline = '\n'}) {
  body = body.replaceAll(RegExp(r'\r\n?|\n'), newline);
  final fence = '`' * _safeFenceLength(body, '`', 3);
  return '${fence}text$newline$body$newline$fence';
}

List<ComposerCodeBlock> parseComposerCodeBlocks(String source) {
  if (!source.contains('```') && !source.contains('~~~')) return const [];
  final blocks = <ComposerCodeBlock>[];
  final openingPattern = RegExp(r'^ {0,3}(`{3,}|~{3,})([^\r\n]*)$');
  RegExpMatch? opening;
  var start = 0;
  var bodyStart = 0;
  var offset = 0;
  for (final rawLine in source.split('\n')) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (opening == null) {
      final match = openingPattern.firstMatch(line);
      if (match != null &&
          !(match.group(1)!.startsWith('`') && match.group(2)!.contains('`'))) {
        opening = match;
        start = offset;
        bodyStart = offset + rawLine.length + 1;
      }
    } else {
      final fence = opening.group(1)!;
      final closing = RegExp(
        '^ {0,3}(${fence[0]}{${fence.length},})[ \\t]*\$',
      ).firstMatch(line);
      if (closing != null) {
        final openingLine = source.substring(start, bodyStart);
        final fenceStart = openingLine.indexOf(fence);
        final info = opening.group(2)!;
        final leading = info.length - info.trimLeft().length;
        final infoStart = fenceStart + fence.length + leading;
        var bodyEnd = offset;
        if (bodyEnd > bodyStart && source[bodyEnd - 1] == '\n') bodyEnd--;
        if (bodyEnd > bodyStart && source[bodyEnd - 1] == '\r') bodyEnd--;
        blocks.add(
          ComposerCodeBlock(
            start: start,
            source: source.substring(start, offset + line.length),
            bodyStart: bodyStart - start,
            bodyEnd: bodyEnd - start,
            fence: fence,
            infoStart: infoStart,
            infoEnd: infoStart + info.trim().length,
            closingStart: offset - start + line.indexOf(fence[0]),
            closingLength: closing.group(1)!.length,
          ),
        );
        opening = null;
      }
    }
    offset += rawLine.length + 1;
  }
  return blocks;
}

/// Hidden fences can be replaced as a whole, but not partially edited by IME.
class ComposerCodeInputFormatter extends TextInputFormatter {
  const ComposerCodeInputFormatter();

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
    for (final block in parseComposerCodeBlocks(oldValue.text)) {
      if (block.language.toLowerCase() == 'mermaid') continue;
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
            parseComposerCodeBlocks(newValue.text).any(
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
