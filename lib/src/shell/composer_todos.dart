import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';

import 'composer_todo_source.dart';

export 'composer_todo_source.dart';

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
  final bullet = RegExp(
    r'^( *)([-+*])[ \t]+',
  ).firstMatch(value.text.substring(start));
  final end = start + (bullet?.end ?? prefix?.end ?? 0);
  final replacement = bullet == null ? '- [ ] ' : '${bullet[0]}[ ] ';
  return TextEditingValue(
    text: value.text.replaceRange(start, end, replacement),
    selection: TextSelection.collapsed(
      offset:
          replacement.length + (caret < end ? start : caret - (end - start)),
    ),
  );
}

/// Mobile and desktop input share marker shortcuts, continuation and deletion.
class ComposerTodoInputFormatter extends TextInputFormatter {
  const ComposerTodoInputFormatter({this.referenceMarkers = const {}});
  final Set<String> referenceMarkers;

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
      final completed =
          composerTodos(newValue.text, referenceMarkers: referenceMarkers)
              .where(
                (item) =>
                    item.contentStart == caret + 1 && item.end == caret + 1,
              )
              .firstOrNull;
      if (completed != null) {
        // Make the body immediately editable without exposing a required space.
        final marker = newValue.text.substring(
          completed.markerStart,
          caret + 1,
        );
        final normalized = marker == '[]' ? '[ ]' : marker;
        final prefix = completed.isListItem ? '' : '- ';
        return TextEditingValue(
          text: newValue.text
              .replaceRange(completed.markerStart, caret + 1, '$normalized ')
              .replaceRange(completed.start, completed.start, prefix),
          selection: TextSelection.collapsed(
            offset:
                caret + 2 + prefix.length + normalized.length - marker.length,
          ),
        );
      }
    }
    final todos = composerTodos(
      oldValue.text,
      referenceMarkers: referenceMarkers,
    );
    final deletedLength = oldValue.text.length - newValue.text.length;
    final deletionStart = newValue.selection.extentOffset;
    if (deletedLength > 0 &&
        newValue.selection.isValid &&
        newValue.selection.isCollapsed &&
        (caret == deletionStart || caret == deletionStart + deletedLength)) {
      for (final todo in todos) {
        if (deletionStart >= todo.start &&
            deletionStart + deletedLength <= todo.contentStart &&
            newValue.text ==
                oldValue.text.replaceRange(
                  deletionStart,
                  deletionStart + deletedLength,
                  '',
                )) {
          // The rendered checkbox is one control, including its hidden source.
          return TextEditingValue(
            text: oldValue.text.replaceRange(todo.start, todo.contentStart, ''),
            selection: TextSelection.collapsed(offset: todo.start),
          );
        }
      }
    }
    final todo = todos.reversed
        .where(
          (item) =>
              caret >= item.contentStart && caret <= (item.itemEnd ?? item.end),
        )
        .firstOrNull;
    if (todo == null) return newValue;
    final newline = oldValue.text.contains('\r\n') ? '\r\n' : '\n';
    if (newValue.text == oldValue.text.replaceRange(caret, caret, newline) &&
        newValue.selection ==
            TextSelection.collapsed(offset: caret + newline.length)) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (!todo.isListItem) return newValue;
        final insertion = '$newline${todo.continuationIndent}';
        return TextEditingValue(
          text: oldValue.text.replaceRange(caret, caret, insertion),
          selection: TextSelection.collapsed(offset: caret + insertion.length),
        );
      }
      if (oldValue.text
          .substring(todo.contentStart, todo.itemEnd ?? todo.end)
          .trim()
          .isEmpty) {
        return TextEditingValue(
          text: oldValue.text.replaceRange(todo.start, todo.end, ''),
          selection: TextSelection.collapsed(offset: todo.start),
        );
      }
      final prefix =
          '${oldValue.text.substring(todo.start, todo.markerStart)}[ ] ';
      return TextEditingValue(
        text: oldValue.text.replaceRange(caret, caret, '$newline$prefix'),
        selection: TextSelection.collapsed(
          offset: caret + newline.length + prefix.length,
        ),
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
  Widget build(BuildContext context) => FocusScope(
    // Inline controls must not make EditableText think it still owns focus.
    // Otherwise tapping the text leaves Space routed to the last checkbox.
    parentNode: FocusScope.of(context),
    child: TextFieldTapRegion(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DCheckbox(
            inline: true,
            size: DControlStyle.isTouch(context)
                ? DCheckboxSize.large
                : DCheckboxSize.standard,
            value: checked,
            semanticLabel: label.isEmpty ? context.l10n.toDo : label,
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
                    context.l10n.toDo,
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
    ),
  );
}
