import 'package:flutter/widgets.dart';

import 'edit_history.dart';

abstract interface class ComposerHistoryHost implements Listenable {
  FocusNode get focus;
  ComposerEditHistory get history;
  bool get isEditing;
}
