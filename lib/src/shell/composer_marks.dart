import 'package:flutter/material.dart';

/// A mark the toolbar can turn on and off.
///
/// The composer writes markdown and nothing else, so a mark is a pair of
/// characters in the text — there is no document model that would mean anything
/// else by it.
enum ComposerMark {
  bold('**'),
  italic('*');

  const ComposerMark(this.marker);

  /// What wraps the text in markdown.
  final String marker;
}

/// Wraps the selection in [marker], or unwraps it if it is already wrapped.
///
/// Pure, so the fiddly part — what counts as already wrapped — is testable
/// without a widget. A collapsed selection inserts the pair and puts the caret
/// between them, which is what someone pressing bold before typing expects.
TextEditingValue toggleMarkdownMark(TextEditingValue value, String marker) {
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);

  final start = selection.start;
  final end = selection.end;
  final selected = text.substring(start, end);
  final before = text.substring(0, start);
  final after = text.substring(end);

  // Already wrapped, with the markers inside the selection.
  if (_isWrapped(selected, marker)) {
    final inner = selected.substring(
      marker.length,
      selected.length - marker.length,
    );
    return TextEditingValue(
      text: '$before$inner$after',
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + inner.length,
      ),
    );
  }

  // Already wrapped, with the markers just outside it — which is what you get
  // by double-clicking a bold word.
  if (_endsWithMark(before, marker) && _startsWithMark(after, marker)) {
    final trimmedBefore = before.substring(0, before.length - marker.length);
    return TextEditingValue(
      text: '$trimmedBefore$selected${after.substring(marker.length)}',
      selection: TextSelection(
        baseOffset: trimmedBefore.length,
        extentOffset: trimmedBefore.length + selected.length,
      ),
    );
  }

  final caret = start + marker.length;
  return TextEditingValue(
    text: '$before$marker$selected$marker$after',
    selection: selection.isCollapsed
        ? TextSelection.collapsed(offset: caret)
        : TextSelection(
            baseOffset: caret,
            extentOffset: caret + selected.length,
          ),
  );
}

bool _isWrapped(String text, String marker) {
  if (text.length < marker.length * 2) return false;
  if (!text.startsWith(marker) || !text.endsWith(marker)) return false;
  // `**bold**` is not italic text, so pressing italic on it must add a mark
  // rather than peel one off a longer run.
  return !_continuesRun(text.substring(marker.length), marker);
}

bool _endsWithMark(String before, String marker) =>
    before.endsWith(marker) &&
    !_continuesRun(
      before
          .substring(0, before.length - marker.length)
          .split('')
          .reversed
          .join(),
      marker,
    );

bool _startsWithMark(String after, String marker) =>
    after.startsWith(marker) &&
    !_continuesRun(after.substring(marker.length), marker);

/// Whether [rest] carries on a run of the marker's character, which would mean
/// the marker found is part of a longer one.
bool _continuesRun(String rest, String marker) =>
    marker.length == 1 && rest.startsWith(marker);
