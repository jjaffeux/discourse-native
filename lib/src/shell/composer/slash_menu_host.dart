import 'package:flutter/widgets.dart';

abstract interface class ComposerSlashMenuHost implements Listenable {
  TextEditingController get text;
  FocusNode get focus;
  bool get isEditing;
  bool get loadingBody;
}
