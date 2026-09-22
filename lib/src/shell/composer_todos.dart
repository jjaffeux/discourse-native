import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';

import 'markdown_highlight.dart';

/// A checklist line keeps its original Markdown as the editable source.
class ComposerTodo {
  const ComposerTodo({
    required this.start,
    required this.markerStart,
    required this.contentStart,
    required this.end,
    required this.checked,
  });

  final int start;
  final int markerStart;
  final int contentStart;
  final int end;
  final bool checked;
}

final _todoPrefix = RegExp(
  r'^( {0,3}(?:[-+*][ \t]+)?)(\[[ xX]?\])(?:[ \t]+|(?=\r?$))',
  multiLine: true,
);

List<ComposerTodo> composerTodos(String source, {CodeRanges? codeRanges}) {
  final matches = _todoPrefix.allMatches(source).toList();
  if (matches.isEmpty) return const [];
  final code = codeRanges ?? CodeRanges.of(scanMarkdown(source));
  final references = RegExp(
    r'^ {0,3}\[([ xX]?)\]:[ \t]*\S',
    multiLine: true,
  ).allMatches(source).map((match) => '[${match[1]!.toLowerCase()}]').toSet();
  return [
    for (final match in matches)
      if (!code.overlaps(match.start, match.end) &&
          !references.contains(match[2]!.toLowerCase()))
        ComposerTodo(
          start: match.start,
          markerStart: match.start + match[1]!.length,
          contentStart: match.end,
          end: _lineEnd(source, match.end),
          checked: match[2]!.toLowerCase() == '[x]',
        ),
  ];
}

TextSelection composerTodoLineStartSelection(
  TextEditingValue before,
  TextEditingValue after,
) {
  final selection = after.selection;
  if (before.text != after.text ||
      !selection.isValid ||
      !before.composing.isCollapsed ||
      !after.composing.isCollapsed) {
    return selection;
  }
  final todos = composerTodos(after.text);
  int visible(int offset) {
    for (final todo in todos) {
      if (offset >= todo.start && offset < todo.contentStart) {
        return todo.contentStart;
      }
    }
    return offset;
  }

  return selection.copyWith(
    baseOffset:
        selection.isCollapsed ||
            selection.baseOffset != before.selection.baseOffset
        ? visible(selection.baseOffset)
        : selection.baseOffset,
    extentOffset:
        selection.isCollapsed ||
            selection.extentOffset != before.selection.extentOffset
        ? visible(selection.extentOffset)
        : selection.extentOffset,
  );
}

int _lineEnd(String source, int start) {
  final newline = source.indexOf('\n', start);
  final end = newline < 0 ? source.length : newline;
  return end > start && source[end - 1] == '\r' ? end - 1 : end;
}

TextEditingValue insertComposerTodo(TextEditingValue value) {
  final caret = value.selection.isValid
      ? value.selection.extentOffset
      : value.text.length;
  final start = caret == 0 ? 0 : value.text.lastIndexOf('\n', caret - 1) + 1;
  final existing = composerTodos(
    value.text,
  ).where((todo) => todo.start == start).firstOrNull;
  if (existing != null) {
    return value.copyWith(
      selection: TextSelection.collapsed(
        offset: caret.clamp(existing.contentStart, existing.end),
      ),
    );
  }
  final prefix = RegExp(
    r'^ {0,3}(?:#{1,6}|[-+*]|\d{1,9}[.)])(?:[ \t]+|$)',
  ).firstMatch(value.text.substring(start));
  final end = start + (prefix?.end ?? 0);
  return TextEditingValue(
    text: value.text.replaceRange(start, end, '[ ] '),
    selection: TextSelection.collapsed(
      offset: 4 + (caret < end ? start : caret - (end - start)),
    ),
  );
}

/// Mobile and desktop input share marker shortcuts, continuation and deletion.
class ComposerTodoInputFormatter extends TextInputFormatter {
  const ComposerTodoInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        !oldValue.composing.isCollapsed ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }
    final caret = oldValue.selection.extentOffset;
    if (newValue.text == oldValue.text.replaceRange(caret, caret, ']') &&
        newValue.selection == TextSelection.collapsed(offset: caret + 1)) {
      final completed = composerTodos(
        newValue.text,
      ).any((item) => item.contentStart == caret + 1 && item.end == caret + 1);
      if (completed) {
        // Make the body immediately editable without exposing a required space.
        return TextEditingValue(
          text: newValue.text.replaceRange(caret + 1, caret + 1, ' '),
          selection: TextSelection.collapsed(offset: caret + 2),
        );
      }
    }
    final todo = composerTodos(oldValue.text)
        .where((item) => caret >= item.contentStart && caret <= item.end)
        .firstOrNull;
    if (todo == null) return newValue;
    if (newValue.text == oldValue.text.replaceRange(caret, caret, '\n') &&
        newValue.selection == TextSelection.collapsed(offset: caret + 1)) {
      if (HardwareKeyboard.instance.isShiftPressed) return newValue;
      if (oldValue.text.substring(todo.contentStart, todo.end).trim().isEmpty) {
        return TextEditingValue(
          text: oldValue.text.replaceRange(todo.start, todo.end, ''),
          selection: TextSelection.collapsed(offset: todo.start),
        );
      }
      final prefix =
          '${oldValue.text.substring(todo.start, todo.markerStart)}[ ] ';
      return TextEditingValue(
        text: oldValue.text.replaceRange(caret, caret, '\n$prefix'),
        selection: TextSelection.collapsed(offset: caret + 1 + prefix.length),
      );
    }
    if (caret == todo.contentStart &&
        newValue.text == oldValue.text.replaceRange(caret - 1, caret, '') &&
        newValue.selection == TextSelection.collapsed(offset: caret - 1)) {
      return TextEditingValue(
        text: oldValue.text.replaceRange(todo.start, todo.contentStart, ''),
        selection: TextSelection.collapsed(offset: todo.start),
      );
    }
    return newValue;
  }
}

/// Projects the marker through the Native checkbox without another text field.
class ComposerTodoMarker extends StatelessWidget {
  const ComposerTodoMarker({
    super.key,
    required this.checked,
    required this.label,
    required this.onChanged,
    required this.style,
  });

  final bool checked;
  final String label;
  final VoidCallback? onChanged;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DCheckbox(
          value: checked,
          semanticLabel: label.isEmpty ? 'To-do' : label,
          readOnly: onChanged == null,
          onChanged: (_) => onChanged?.call(),
        ),
        if (label.isEmpty)
          SizedBox(
            width: 0,
            child: OverflowBox(
              fit: OverflowBoxFit.deferToChild,
              alignment: AlignmentDirectional.centerStart,
              minWidth: 0,
              maxWidth: double.infinity,
              child: IgnorePointer(
                child: Text(
                  'To-do',
                  maxLines: 1,
                  style: style.copyWith(
                    color: DTokens.of(context).mutedForeground,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
