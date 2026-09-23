import 'package:flutter/services.dart';

import 'composer_list_source.dart';

/// Turns the current line into a list item, retaining its content and caret.
TextEditingValue insertComposerList(
  TextEditingValue value, {
  required bool ordered,
}) {
  final caret = value.selection.isValid
      ? value.selection.extentOffset
      : value.text.length;
  final start = caret == 0 ? 0 : value.text.lastIndexOf('\n', caret - 1) + 1;
  final items = composerListItems(value.text);
  for (final outer in items) {
    if (start <= outer.start || caret > outer.end) continue;
    final body = insertComposerList(
      TextEditingValue(
        text: outer.body.text,
        selection: TextSelection.collapsed(
          offset: outer.body.localOffset(caret),
        ),
      ),
      ordered: ordered,
    );
    final text = value.text.replaceRange(
      outer.start,
      outer.end,
      outer.body.replace(body.text),
    );
    final updated = composerListItems(
      text,
    ).firstWhere((item) => item.start == outer.start);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: updated.body.sourceOffset(body.selection.extentOffset),
      ),
    );
  }
  final item = items.where((item) => item.start == start).firstOrNull;
  final heading = RegExp(
    r'^ {0,3}#{1,6}(?:[ \t]+|$)',
  ).firstMatch(value.text.substring(start));
  final end = item?.contentStart ?? start + (heading?.end ?? 0);
  final prefix = ordered ? '1. ' : '- ';
  // Re-encode continuation indentation if the new marker has another width.
  final replacement = item == null
      ? prefix
      : '$prefix${item.body.text.replaceAll('\n', '${item.newline}${' ' * prefix.length}')}';
  final bodyCaret = item?.body.localOffset(caret) ?? 0;
  final lineCount = item == null
      ? 0
      : '\n'.allMatches(item.body.text.substring(0, bodyCaret)).length;
  return TextEditingValue(
    text: value.text.replaceRange(start, item?.end ?? end, replacement),
    selection: TextSelection.collapsed(
      offset: item == null
          ? prefix.length + (caret < end ? start : caret - (end - start))
          : start +
                prefix.length +
                bodyCaret +
                lineCount * (prefix.length + item.newline.length - 1),
    ),
  );
}
