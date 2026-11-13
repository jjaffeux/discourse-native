import 'package:flutter/widgets.dart';

abstract interface class ComposerSelectionFormattingHost {
  TextEditingValue get value;
  FocusNode get focus;
  bool get isEditing;
  void formatSelection(TextEditingValue Function(TextEditingValue) format);
}
