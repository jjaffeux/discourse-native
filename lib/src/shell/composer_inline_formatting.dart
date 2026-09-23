import 'package:flutter/services.dart';

import 'composer_link.dart';
import 'composer_marks.dart';
import 'markdown_highlight.dart';

typedef ComposerInlineFormat = ({
  int start,
  int contentStart,
  int contentEnd,
  int end,
  String kind,
});

/// Recognized inline wrappers, excluding literal syntax inside code spans.
List<ComposerInlineFormat> composerInlineFormats(String source) {
  final runs = scanMarkdown(source);
  final code = CodeRanges.of(runs);
  bool marker(int at) =>
      runs.any((run) => run.start <= at && run.end > at && run.has(Md.marker));
  final formats = <ComposerInlineFormat>[];
  for (final (delimiter, flag) in const [
    ('***', Md.bold | Md.italic),
    ('**', Md.bold),
    ('*', Md.italic),
    ('___', Md.bold | Md.italic),
    ('__', Md.bold),
    ('_', Md.italic),
    ('~~', Md.strikethrough),
  ]) {
    for (final (start, end) in markdownPairs(
      source,
      delimiter,
      wordBounded: delimiter.startsWith('_'),
      spokenFor: code.contains,
    )) {
      if (!marker(start) || !marker(end - 1)) continue;
      if (!runs.any(
        (run) =>
            run.start < end - delimiter.length &&
            run.end > start + delimiter.length &&
            run.mask & flag == flag,
      )) {
        continue;
      }
      if (delimiter.length == 3) {
        formats.add((
          start: start,
          contentStart: start + 2,
          contentEnd: end - 2,
          end: end,
          kind: '**',
        ));
        formats.add((
          start: start + 2,
          contentStart: start + 3,
          contentEnd: end - 3,
          end: end - 2,
          kind: '*',
        ));
        continue;
      }
      formats.add((
        start: start,
        contentStart: start + delimiter.length,
        contentEnd: end - delimiter.length,
        end: end,
        kind: delimiter.replaceAll('_', '*'),
      ));
    }
  }
  void tags(String text, int offset) {
    for (final match in _tags.allMatches(text)) {
      final start = offset + match.start;
      final end = offset + match.end;
      if (code.contains(start)) continue;
      // The scanner decides whether HTML really is formatting (escapes, etc.).
      if (!marker(start)) continue;
      final group = match.group(1) == null ? 5 : 1;
      final contentStart = start + match.group(group)!.length;
      final contentEnd = end - match.group(group + 3)!.length;
      formats.add((
        start: start,
        contentStart: contentStart,
        contentEnd: contentEnd,
        end: end,
        kind: match.group(group + 1)!.toLowerCase(),
      ));
      tags(source.substring(contentStart, contentEnd), contentStart);
    }
  }

  tags(source, 0);
  for (final link in parseComposerLinks(source, enableLinkify: false)) {
    // Images have a separate editing owner.
    if (link.start > 0 && source[link.start - 1] == '!') continue;
    formats.add((
      start: link.start,
      contentStart: link.start + 1,
      contentEnd: link.start + 1 + link.anchor.length,
      end: link.end,
      kind: 'link',
    ));
  }
  for (final (start, end) in code.ranges) {
    if (runs.any(
      (r) => r.start < end && r.end > start && r.has(Md.codeBlock),
    )) {
      continue;
    }
    var openingStart = start;
    while (openingStart > 0 &&
        source[openingStart - 1] == '`' &&
        marker(openingStart - 1)) {
      openingStart--;
    }
    final width = start - openingStart;
    if (width == 0 || end + width > source.length) continue;
    var contentStart = start;
    var contentEnd = end;
    if (contentEnd - contentStart > 2 &&
        source[contentStart] == ' ' &&
        source[contentEnd - 1] == ' ') {
      contentStart++;
      contentEnd--;
    }
    formats.add((
      start: openingStart,
      contentStart: contentStart,
      contentEnd: contentEnd,
      end: end + width,
      kind: 'code',
    ));
  }
  return formats..sort((a, b) => (a.end - a.start).compareTo(b.end - b.start));
}

final _tags = RegExp(
  r'(<(ins|del|sup|sub|kbd|mark|small|big)>)([\s\S]*?)(</\2>)'
  r'|(\[(color|bgcolor)=[#a-z0-9]+\])([\s\S]*?)(\[/\6\])',
  caseSensitive: false,
);

bool composerSelectionHasFormat(TextEditingValue value, String kind) {
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return false;
  return composerInlineFormats(value.text).any(
    (format) =>
        _matchesKind(format.kind, kind) &&
        selection.start >= format.start &&
        selection.end <= format.end,
  );
}

/// The innermost color enclosing the entire selection, or the default color.
String? composerSelectionColor(
  TextEditingValue value, {
  bool background = false,
}) {
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return null;
  for (final format in composerInlineFormats(value.text)) {
    if (format.kind == (background ? 'bgcolor' : 'color') &&
        selection.start >= format.start &&
        selection.end <= format.end) {
      final opening = value.text.substring(format.start, format.contentStart);
      final color = opening
          .substring(opening.indexOf('=') + 1, opening.length - 1)
          .toLowerCase();
      if (color.startsWith('#') && color.length == 4) {
        return '#${color.substring(1).split('').map((c) => '$c$c').join()}';
      }
      return color;
    }
  }
  return null;
}

bool _matchesKind(String format, String kind) =>
    format == kind ||
    switch (kind) {
      '**' => ['***', '__', '___'].contains(format),
      '*' => ['***', '_', '___'].contains(format),
      _ => false,
    };

TextEditingValue wrapComposerSelection(
  TextEditingValue value,
  String opening,
  String closing,
) {
  final selection = value.selection;
  if (!selection.isValid ||
      selection.isCollapsed ||
      selection.end > value.text.length) {
    return value;
  }
  return TextEditingValue(
    text: value.text.replaceRange(
      selection.start,
      selection.end,
      '$opening${selection.textInside(value.text)}$closing',
    ),
    selection: selection.copyWith(
      baseOffset: selection.baseOffset + opening.length,
      extentOffset: selection.extentOffset + opening.length,
    ),
  );
}

TextEditingValue toggleComposerTag(TextEditingValue value, String tag) =>
    composerSelectionHasFormat(value, tag)
    ? clearComposerInlineFormatting(value, kind: tag)
    : wrapComposerSelection(value, '<$tag>', '</$tag>');

TextEditingValue toggleComposerInlineMark(
  TextEditingValue value,
  ComposerMark mark,
) {
  final kind = mark == ComposerMark.inlineCode ? 'code' : mark.marker;
  return composerSelectionHasFormat(value, kind)
      ? clearComposerInlineFormatting(value, kind: kind)
      : toggleMarkdownMark(value, mark.marker);
}

TextEditingValue setComposerColor(
  TextEditingValue value,
  String? color, {
  bool background = false,
}) {
  final tag = background ? 'bgcolor' : 'color';
  final cleared = clearComposerInlineFormatting(value, kind: tag);
  return color == null
      ? cleared
      : wrapComposerSelection(cleared, '[$tag=$color]', '[/$tag]');
}

/// Clears only selected inline formatting; block structure and literal code
/// contents survive. Partial selections split wrappers around unselected text.
TextEditingValue clearComposerInlineFormatting(
  TextEditingValue value, {
  String? kind,
}) {
  if (!value.selection.isValid ||
      value.selection.isCollapsed ||
      value.selection.end > value.text.length) {
    return value;
  }
  final formats = composerInlineFormats(value.text)
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart == 0 ? b.end.compareTo(a.end) : byStart;
    });
  if (formats.isEmpty) return value;
  if (!formats.any(
    (format) =>
        (kind == null || format.kind == kind) &&
        format.contentStart < value.selection.end &&
        format.contentEnd > value.selection.start,
  )) {
    return value;
  }
  final hidden = List<bool>.filled(value.text.length, false);
  for (final format in formats) {
    hidden.fillRange(format.start, format.contentStart, true);
    hidden.fillRange(format.contentEnd, format.end, true);
  }
  final offsets = List<int>.filled(value.text.length + 1, 0);
  final plain = StringBuffer();
  for (var i = 0; i < value.text.length; i++) {
    offsets[i] = plain.length;
    if (!hidden[i]) plain.writeCharCode(value.text.codeUnitAt(i));
  }
  offsets[value.text.length] = plain.length;
  final text = plain.toString();
  final start = offsets[value.selection.start];
  final end = offsets[value.selection.end];
  final retained = <({int start, int end, ComposerInlineFormat format})>[];
  for (final format in formats) {
    final from = offsets[format.contentStart];
    final to = offsets[format.contentEnd];
    if ((kind != null && format.kind != kind) || from >= end || to <= start) {
      retained.add((start: from, end: to, format: format));
      continue;
    }
    void retain(int a, int b) {
      if (['***', '**', '*', '___', '__', '_', '~~'].contains(format.kind)) {
        while (a < b && text[a].trim().isEmpty) {
          a++;
        }
        while (b > a && text[b - 1].trim().isEmpty) {
          b--;
        }
      }
      if (b > a) retained.add((start: a, end: b, format: format));
    }

    if (from < start) retain(from, start);
    if (to > end) retain(end, to);
  }
  final output = StringBuffer();
  var active = <ComposerInlineFormat>[];
  var newStart = 0;
  var newEnd = 0;
  int common(List<ComposerInlineFormat> a, List<ComposerInlineFormat> b) {
    var count = 0;
    while (count < a.length && count < b.length && a[count] == b[count]) {
      count++;
    }
    return count;
  }

  void emit(int i, List<ComposerInlineFormat> next) {
    if (i == end) newEnd = output.length;
    final shared = common(active, next);
    for (final format in active.skip(shared).toList().reversed) {
      output.write(value.text.substring(format.contentEnd, format.end));
    }
    for (final format in next.skip(shared)) {
      output.write(value.text.substring(format.start, format.contentStart));
    }
    if (i == start) newStart = output.length;
    if (i < text.length) output.writeCharCode(text.codeUnitAt(i));
    active = next;
  }

  final cuts = <int>{
    0,
    text.length,
    for (final r in retained) ...[r.start, r.end],
  }.toList()..sort();
  final stacks = [
    for (final at in cuts)
      retained
          .where((r) => r.start <= at && r.end > at)
          .map((r) => r.format)
          .toList(),
  ];
  for (var segment = 0; segment + 1 < cuts.length; segment++) {
    final stack = stacks[segment];
    final previous = segment == 0
        ? <ComposerInlineFormat>[]
        : stacks[segment - 1];
    final opening = stack.skip(common(previous, stack)).toSet();
    final closing = stack.skip(common(stack, stacks[segment + 1])).toSet();
    var firstText = cuts[segment];
    var lastText = cuts[segment + 1];
    while (firstText < lastText && text[firstText].trim().isEmpty) {
      firstText++;
    }
    while (lastText > firstText && text[lastText - 1].trim().isEmpty) {
      lastText--;
    }
    for (var i = cuts[segment]; i < cuts[segment + 1]; i++) {
      // Splitting an outer color/tag may also reopen nested emphasis. Keep
      // whitespace outside those new Markdown delimiters so it still cooks.
      final next = stack
          .where(
            (format) =>
                !['*', '**', '~~'].contains(format.kind) ||
                !((i < firstText && opening.contains(format)) ||
                    (i >= lastText && closing.contains(format))),
          )
          .toList();
      emit(i, next);
    }
  }
  emit(text.length, const []);
  final reversed = value.selection.baseOffset > value.selection.extentOffset;
  return TextEditingValue(
    text: output.toString(),
    selection: value.selection.copyWith(
      baseOffset: reversed ? newEnd : newStart,
      extentOffset: reversed ? newStart : newEnd,
    ),
  );
}
