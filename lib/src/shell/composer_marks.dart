import 'package:flutter/material.dart';

enum ComposerMark {
  bold('**'),
  italic('*');

  const ComposerMark(this.marker);

  final String marker;
}

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

bool _continuesRun(String rest, String marker) =>
    marker.length == 1 && rest.startsWith(marker);
