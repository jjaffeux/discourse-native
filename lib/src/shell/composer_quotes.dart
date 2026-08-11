import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'markdown_highlight.dart';

/// One complete Discourse `[quote]` block in a composer document.
///
/// The offsets and [source] are deliberately lossless. The composer only
/// projects this range visually; drafts and submission continue to carry the
/// exact BBCode the site expects.
@immutable
class ComposerQuoteBlock {
  const ComposerQuoteBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.contents,
    required this.username,
    required this.displayName,
    required this.postNumber,
    required this.topicId,
    required this.full,
  });

  final int start;
  final int end;
  final String source;
  final String contents;
  final String? username;
  final String? displayName;
  final int? postNumber;
  final int? topicId;
  final bool full;

  int get length => end - start;
  String? get title => displayName ?? username;

  bool containsOffset(int offset, {bool includeEnd = false}) =>
      offset >= start && (includeEnd ? offset <= end : offset < end);
}

/// Finds complete block-level quote BBCode outside code.
///
/// This mirrors the important parts of core's `bbcode-block` and `quotes`
/// features: up to three spaces of indentation, paired straight/curly quote
/// marks around the default value, legacy unquoted values, nested quotes, and
/// the display-name/username metadata emitted by `buildQuote`.
List<ComposerQuoteBlock> parseComposerQuotes(String source) {
  if (source.isEmpty ||
      !RegExp(r'\[quote', caseSensitive: false).hasMatch(source)) {
    return const [];
  }

  final codeRanges = [
    for (final run in scanMarkdown(source))
      if (run.has(Md.code) || run.has(Md.codeBlock)) (run.start, run.end),
  ];
  final blocks = <ComposerQuoteBlock>[];
  var offset = 0;

  while (offset < source.length) {
    final opening = source.indexOf('[', offset);
    if (opening == -1) break;
    if (_insideAny(opening, codeRanges) || !_startsBlock(source, opening)) {
      offset = opening + 1;
      continue;
    }

    final openTag = _quoteTagAt(source, opening);
    if (openTag == null || openTag.closing) {
      offset = opening + 1;
      continue;
    }

    final closeTag = _matchingClose(source, openTag.end, codeRanges);
    if (closeTag == null) {
      // As in core, an unmatched outer opener makes the rest ambiguous. Do
      // not turn a plausible inner quote into an editable-looking fragment.
      break;
    }

    final metadata = _metadata(openTag.value);
    final end = _blockEnd(source, closeTag.end);
    blocks.add(
      ComposerQuoteBlock(
        start: opening,
        end: end,
        source: source.substring(opening, end),
        contents: source.substring(openTag.end, closeTag.start).trim(),
        username: metadata.username,
        displayName: metadata.displayName,
        postNumber: metadata.postNumber,
        topicId: metadata.topicId,
        full: metadata.full,
      ),
    );
    offset = end;
  }

  return List.unmodifiable(blocks);
}

/// Core serializes a quote with two trailing line endings. They are structural
/// separation rather than user-authored prose, so the atomic range owns them:
/// removing an only-quote reply leaves a genuinely empty composer, while a
/// quote between paragraphs leaves the preceding blank-line separator intact.
int _blockEnd(String source, int tagEnd) {
  var end = tagEnd;
  for (var line = 0; line < 2; line++) {
    var cursor = end;
    while (cursor < source.length &&
        (source[cursor] == ' ' || source[cursor] == '\t')) {
      cursor++;
    }
    if (cursor < source.length && source[cursor] == '\r') cursor++;
    if (cursor >= source.length || source[cursor] != '\n') break;
    end = cursor + 1;
  }
  return end;
}

ComposerQuoteBlock? quoteAtComposerOffset(
  Iterable<ComposerQuoteBlock> blocks,
  int offset,
) {
  for (final block in blocks) {
    if (block.containsOffset(offset)) return block;
  }
  return null;
}

/// Expands a selection to quote boundaries and keeps a collapsed caret out of
/// immutable quote source.
TextSelection quoteSafeSelection(
  Iterable<ComposerQuoteBlock> blocks,
  TextSelection selection,
  TextSelection previous,
) {
  if (!selection.isValid) return selection;
  if (selection.isCollapsed) {
    final offset = selection.extentOffset;
    for (final block in blocks) {
      if (offset <= block.start || offset >= block.end) continue;
      final oldOffset = previous.isValid ? previous.extentOffset : block.end;
      final boundary = oldOffset <= block.start
          ? block.end
          : oldOffset >= block.end
          ? block.start
          : block.end;
      return TextSelection.collapsed(offset: boundary);
    }
    return selection;
  }

  var start = selection.start;
  var end = selection.end;
  for (final block in blocks) {
    if (start >= block.end || end <= block.start) continue;
    start = math.min(start, block.start);
    end = math.max(end, block.end);
  }
  if (start == selection.start && end == selection.end) return selection;
  return selection.isDirectional &&
          selection.baseOffset > selection.extentOffset
      ? TextSelection(baseOffset: end, extentOffset: start, isDirectional: true)
      : TextSelection(
          baseOffset: start,
          extentOffset: end,
          isDirectional: selection.isDirectional,
        );
}

/// Rejects text-input edits which would change only part of a quote.
///
/// Whole-quote selections remain ordinary editor selections, so select-all,
/// cut, and replacement still work. Hardware Backspace/Delete and the visible
/// remove control are handled by the composer panel as atomic removals.
class ComposerQuoteInputFormatter extends TextInputFormatter {
  const ComposerQuoteInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;
    final blocks = parseComposerQuotes(oldValue.text);
    if (blocks.isEmpty) return newValue;

    var prefix = 0;
    final shared = math.min(oldValue.text.length, newValue.text.length);
    while (prefix < shared &&
        oldValue.text.codeUnitAt(prefix) == newValue.text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldValue.text.length - prefix &&
        suffix < newValue.text.length - prefix &&
        oldValue.text.codeUnitAt(oldValue.text.length - suffix - 1) ==
            newValue.text.codeUnitAt(newValue.text.length - suffix - 1)) {
      suffix++;
    }
    final replacedEnd = oldValue.text.length - suffix;

    for (final block in blocks) {
      if (prefix == replacedEnd) {
        if (prefix > block.start && prefix < block.end) return oldValue;
        continue;
      }
      if (prefix >= block.end || replacedEnd <= block.start) continue;
      final coversWholeBlock =
          prefix <= block.start && replacedEnd >= block.end;
      if (!coversWholeBlock) return oldValue;
    }
    return newValue;
  }
}

/// The read-only composer rendering of a quoted post.
///
/// It uses the same panel, accent bar, spacing, attribution hierarchy and body
/// colours as [QuoteBlock] in `quote.dart`. Selected native post text is plain
/// text, so keeping the body as text here is both safe and faithful; the raw
/// BBCode remains underneath for the server to cook on submission.
class ComposerQuotePreview extends StatelessWidget {
  const ComposerQuotePreview({
    super.key,
    required this.block,
    required this.baseStyle,
    this.removeKey,
  });

  final ComposerQuoteBlock block;
  final TextStyle baseStyle;
  final Key? removeKey;

  static const int maximumBodyLines = 4;
  static const double _barWidth = 3;

  static double displayHeight(ComposerQuoteBlock block, TextStyle baseStyle) {
    final lineHeight = (baseStyle.fontSize ?? 14) * (baseStyle.height ?? 1.4);
    final lines = _bodyLines(block.contents).clamp(1, maximumBodyLines);
    final header = block.title == null ? 0.0 : 28.0;
    return 20 + header + lineHeight * lines;
  }

  static int _bodyLines(String contents) {
    if (contents.isEmpty) return 1;
    var lines = 0;
    for (final line in contents.split(RegExp(r'\r?\n'))) {
      lines += math.max(1, (line.runes.length / 68).ceil());
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final title = block.title;
    final bodyStyle = theme.textTheme.bodyMedium
        ?.merge(baseStyle)
        .copyWith(color: muted);

    return Semantics(
      container: true,
      label: title == null ? 'Quote' : 'Quote from $title',
      hint: 'Read only. Use the remove quote button to delete it.',
      child: Container(
        height: displayHeight(block, baseStyle),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: theme.shell.panel,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(3),
            right: Radius.circular(6),
          ),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: _barWidth,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 28),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: Text(
                      block.contents,
                      maxLines: maximumBodyLines,
                      overflow: TextOverflow.ellipsis,
                      style: bodyStyle,
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Tooltip(
                  message: 'Remove quote',
                  child: SizedBox(
                    key: removeKey,
                    width: 24,
                    height: 20,
                    child: Center(
                      child: DIcon(DIcons.xmark, size: 13, color: muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteTag {
  const _QuoteTag({
    required this.start,
    required this.end,
    required this.closing,
    this.value,
  });

  final int start;
  final int end;
  final bool closing;
  final String? value;
}

_QuoteTag? _quoteTagAt(String source, int start) {
  if (start < 0 || start >= source.length || source[start] != '[') return null;
  final closing = start + 1 < source.length && source[start + 1] == '/';
  final nameStart = start + (closing ? 2 : 1);
  const name = 'quote';
  final nameEnd = nameStart + name.length;
  if (nameEnd > source.length ||
      source.substring(nameStart, nameEnd).toLowerCase() != name) {
    return null;
  }

  if (closing) {
    if (nameEnd >= source.length || source[nameEnd] != ']') return null;
    return _QuoteTag(start: start, end: nameEnd + 1, closing: true);
  }
  if (nameEnd >= source.length) return null;
  if (source[nameEnd] == ']') {
    return _QuoteTag(start: start, end: nameEnd + 1, closing: false);
  }
  if (source[nameEnd] != '=') return null;

  final valueStart = nameEnd + 1;
  String? closeQuote;
  var offset = valueStart;
  if (offset < source.length) closeQuote = _closingQuote(source[offset]);
  if (closeQuote != null) offset++;
  for (; offset < source.length; offset++) {
    final character = source[offset];
    if (character == '\n' || character == '\r') return null;
    if (closeQuote != null) {
      if (character != closeQuote) continue;
      final tail = source.indexOf(']', offset + 1);
      if (tail == -1 ||
          source.substring(offset + 1, tail).contains(RegExp(r'[\r\n]')) ||
          source.substring(offset + 1, tail).trim().isNotEmpty) {
        return null;
      }
      return _QuoteTag(
        start: start,
        end: tail + 1,
        closing: false,
        value: source.substring(valueStart + 1, offset),
      );
    }
    if (character == ']') {
      return _QuoteTag(
        start: start,
        end: offset + 1,
        closing: false,
        value: source.substring(valueStart, offset).trim(),
      );
    }
  }
  return null;
}

String? _closingQuote(String character) => switch (character) {
  '"' => '"',
  "'" => "'",
  '“' || '„' || '”' => '”',
  '‘' || '‚' => '’',
  '«' => '»',
  '‹' => '›',
  _ => null,
};

_QuoteTag? _matchingClose(
  String source,
  int offset,
  List<(int, int)> codeRanges,
) {
  var depth = 1;
  while (offset < source.length) {
    final next = source.indexOf('[', offset);
    if (next == -1) return null;
    offset = next + 1;
    if (_insideAny(next, codeRanges)) continue;
    final tag = _quoteTagAt(source, next);
    if (tag == null) continue;
    if (tag.closing) {
      depth--;
      if (depth == 0) return tag;
    } else if (_startsBlock(source, next)) {
      depth++;
    }
    offset = tag.end;
  }
  return null;
}

bool _startsBlock(String source, int offset) {
  final lineStart = offset == 0 ? 0 : source.lastIndexOf('\n', offset - 1) + 1;
  final prefix = source.substring(lineStart, offset);
  return prefix.length <= 3 && prefix.trim().isEmpty;
}

bool _insideAny(int offset, Iterable<(int, int)> ranges) {
  for (final (start, end) in ranges) {
    if (offset >= start && offset < end) return true;
  }
  return false;
}

class _QuoteMetadata {
  const _QuoteMetadata({
    required this.username,
    required this.displayName,
    required this.postNumber,
    required this.topicId,
    required this.full,
  });

  final String? username;
  final String? displayName;
  final int? postNumber;
  final int? topicId;
  final bool full;
}

_QuoteMetadata _metadata(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const _QuoteMetadata(
      username: null,
      displayName: null,
      postNumber: null,
      topicId: null,
      full: false,
    );
  }
  final parts = value.split(RegExp(r',\s*'));
  String? username = parts.first.trim();
  String? displayName;
  int? postNumber;
  int? topicId;
  var full = false;
  var postIndex = -1;

  for (var index = 1; index < parts.length; index++) {
    final part = parts[index].trim();
    final lower = part.toLowerCase();
    if (lower.startsWith('post:')) {
      postNumber = int.tryParse(part.substring(part.indexOf(':') + 1).trim());
      postIndex = index;
    } else if (lower.startsWith('topic:')) {
      topicId = int.tryParse(part.substring(part.indexOf(':') + 1).trim());
    } else if (RegExp(r'^full:\s*true$', caseSensitive: false).hasMatch(part)) {
      full = true;
    } else if (lower.startsWith('username:')) {
      if (postIndex > 0) displayName = parts.take(postIndex).join(', ').trim();
      username = part.substring(part.indexOf(':') + 1).trim();
    }
  }

  return _QuoteMetadata(
    username: _nullIfEmpty(username),
    displayName: _nullIfEmpty(displayName),
    postNumber: postNumber,
    topicId: topicId,
    full: full,
  );
}

String? _nullIfEmpty(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
