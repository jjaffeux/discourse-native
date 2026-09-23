import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/discourse_typography.dart';
import 'composer_inline_formatting.dart';
import 'markdown_highlight.dart';
import 'markdown_style.dart';

const hiddenComposerTagStyle = TextStyle(
  fontSize: 0,
  color: Colors.transparent,
  letterSpacing: 0,
  wordSpacing: 0,
);

TextEditingValue normalizeComposerTagEdit(
  TextEditingValue previous,
  TextEditingValue next,
  List<MarkdownRun> runs,
) {
  if (!previous.composing.isCollapsed ||
      !next.composing.isCollapsed ||
      !next.selection.isValid ||
      !next.selection.isCollapsed) {
    return next;
  }
  final offset = next.selection.extentOffset;
  TextRange? scriptCharacterAt(int position) {
    for (final run in runs) {
      if (position < run.start || position >= run.end) continue;
      if (!run.has(Md.htmlTag) ||
          !(run.detail ?? '')
              .split(',')
              .any((tag) => tag == 'sup' || tag == 'sub')) {
        return null;
      }
      var start = run.start;
      for (final character
          in previous.text.substring(run.start, run.end).characters) {
        final end = start + character.length;
        if (position < end) return TextRange(start: start, end: end);
        start = end;
      }
    }
    return null;
  }

  if (next.text == previous.text) {
    for (final run in runs) {
      if (run.has(Md.hiddenTag) && offset > run.start && offset < run.end) {
        return next.copyWith(
          selection: next.selection.copyWith(
            baseOffset: offset < previous.selection.extentOffset
                ? run.start
                : run.end,
            extentOffset: offset < previous.selection.extentOffset
                ? run.start
                : run.end,
          ),
        );
      }
    }
    final character = scriptCharacterAt(offset);
    if (character != null && offset > character.start) {
      return next.copyWith(
        selection: TextSelection.collapsed(
          offset: offset < previous.selection.extentOffset
              ? character.start
              : character.end,
        ),
      );
    }
    return next;
  }

  // Backspace/Delete at a hidden boundary removes that formatting in one
  // step, rather than exposing a damaged HTML tag character by character.
  final removed = previous.text.length - next.text.length;
  if (!previous.selection.isCollapsed || removed != 1) return next;
  if (next.text != previous.text.replaceRange(offset, offset + removed, '')) {
    return next;
  }
  final character = scriptCharacterAt(offset);
  if (character != null && character.end - character.start > removed) {
    return next.copyWith(
      text: previous.text.replaceRange(character.start, character.end, ''),
      selection: TextSelection.collapsed(offset: character.start),
    );
  }
  if (!runs.any(
    (run) => run.has(Md.hiddenTag) && offset >= run.start && offset < run.end,
  )) {
    return next;
  }
  for (final format in composerInlineFormats(previous.text)) {
    if (!const {'sup', 'sub', 'kbd'}.contains(format.kind)) continue;
    final opening = offset >= format.start && offset < format.contentStart;
    final closing = offset >= format.contentEnd && offset < format.end;
    if (!opening && !closing) continue;
    final text = previous.text
        .replaceRange(format.contentEnd, format.end, '')
        .replaceRange(format.start, format.contentStart, '');
    return next.copyWith(
      text: text,
      selection: TextSelection.collapsed(
        offset: opening
            ? format.start
            : format.start + format.contentEnd - format.contentStart,
      ),
    );
  }
  return next;
}

bool isComposerKeyboardRun(MarkdownRun run) =>
    run.has(Md.htmlTag) && (run.detail ?? '').split(',').contains('kbd');

/// A whole keycap can contain several styled runs (for example bold text).
Iterable<List<MarkdownRun>> composerKeyboardRuns(List<MarkdownRun> runs) sync* {
  var key = <MarkdownRun>[];
  for (final run in runs) {
    if (isComposerKeyboardRun(run)) {
      key.add(run);
    } else if (key.isNotEmpty) {
      yield key;
      key = [];
    }
  }
  if (key.isNotEmpty) yield key;
}

List<InlineSpan> composerKeyboardSpans(
  String source,
  List<MarkdownRun> runs,
  TextStyle base,
  ThemeData theme,
) {
  final content = <InlineSpan>[];
  final label = StringBuffer();
  for (final run in runs) {
    if (run.has(Md.marker)) continue;
    final text = source.substring(run.start, run.end);
    label.write(text);
    final style = markdownStyle(
      run.mask,
      run.detail,
      base,
      theme,
    ).copyWith(backgroundColor: Colors.transparent);
    content.addAll(
      composerScriptSpans(text, run, style) ??
          [TextSpan(text: text, style: style)],
    );
  }
  return [
    TextSpan(
      text: source.substring(runs.first.start, runs.last.end - 1),
      style: hiddenComposerTagStyle,
      semanticsLabel: '',
    ),
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      style: base,
      child: DKbd.child(
        semanticLabel: label.toString(),
        child: Text.rich(TextSpan(children: content)),
      ),
    ),
  ];
}

/// Keeps every source offset while positioning scripts independently of the
/// font's optional OpenType superscript/subscript glyphs. A placeholder per
/// grapheme leaves each character reachable by the outer editor's caret.
List<InlineSpan>? composerScriptSpans(
  String text,
  MarkdownRun run,
  TextStyle style,
) {
  if (!run.has(Md.htmlTag)) return null;
  final scripts = (run.detail ?? '')
      .split(',')
      .where((tag) => tag == 'sup' || tag == 'sub');
  if (scripts.isEmpty) return null;
  final raised = scripts.last == 'sup';
  final shift = (style.fontSize ?? DiscourseTypography.base) * .4;
  return [
    for (final character in text.characters)
      if (character == '\n' || character == '\r\n')
        TextSpan(text: character, style: style)
      else ...[
        if (character.length > 1)
          TextSpan(
            text: '\u200b' * (character.length - 1),
            style: hiddenComposerTagStyle,
            semanticsLabel: '',
          ),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          style: style,
          child: Padding(
            padding: raised
                ? EdgeInsets.only(top: shift)
                : EdgeInsets.only(bottom: shift),
            child: Transform.translate(
              offset: Offset(0, raised ? -shift : shift),
              child: Text(character, style: style),
            ),
          ),
        ),
      ],
  ];
}
