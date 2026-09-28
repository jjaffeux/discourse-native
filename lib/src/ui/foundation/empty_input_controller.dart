import 'package:flutter/widgets.dart';

/// A temporary native buffer for an empty input's mobile deletion boundary.
///
/// Populated inputs keep their original controller and editing offsets.
class EmptyInputController extends TextEditingController {
  EmptyInputController() : super.fromValue(emptyValue);

  static const boundary = '\u200b';
  static const emptyValue = TextEditingValue(
    text: boundary,
    selection: TextSelection.collapsed(offset: 1),
  );

  TextEditingValue get editingValue =>
      value.text == boundary ? decode(value) : value;

  void reset() => value = emptyValue;

  @override
  set value(TextEditingValue next) {
    // Tapping the empty field must leave the native caret after its boundary.
    super.value = next.text == boundary && next.composing.isCollapsed
        ? emptyValue
        : next;
  }

  static TextEditingValue encode(TextEditingValue value) =>
      value.text.isEmpty && value.composing.isCollapsed ? emptyValue : value;

  static TextEditingValue decode(TextEditingValue value) {
    if (!value.text.startsWith(boundary)) return value;
    int offset(int value) => value < 0 ? value : (value - 1).clamp(0, value);
    return value.copyWith(
      text: value.text.substring(1),
      selection: value.selection.copyWith(
        baseOffset: offset(value.selection.baseOffset),
        extentOffset: offset(value.selection.extentOffset),
      ),
      composing: value.composing.isValid
          ? TextRange(
              start: offset(value.composing.start),
              end: offset(value.composing.end),
            )
          : value.composing,
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => text == boundary
      ? TextSpan(text: boundary, semanticsLabel: '', style: style)
      : super.buildTextSpan(
          context: context,
          style: style,
          withComposing: withComposing,
        );
}
