import 'package:flutter/widgets.dart';

import 'controller.dart';

/// What a component's editor needs from the composer editor drawing it.
///
/// A rich body holds components whose editors embed rich bodies, so a
/// component reaches the editor through the scope it mounts rather than
/// compiling it.
abstract interface class ComposerEditorEmbedding {
  TextStyle? get textStyle;

  Widget richBody({
    Key? key,
    required ComposerController composer,
    required String label,
    required String hintText,
    required VoidCallback onExit,
    KeyEventResult Function(KeyEvent)? onKeyEvent,
    VoidCallback? onEmptyBackspace,
    bool? enableBlockReordering,
  });
}

class ComposerEditorScope extends InheritedWidget {
  const ComposerEditorScope({
    super.key,
    required this.embedding,
    required super.child,
  });

  final ComposerEditorEmbedding embedding;

  static ComposerEditorEmbedding? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ComposerEditorScope>()?.embedding;

  /// Every production composer component renders under a composer editor.
  static ComposerEditorEmbedding of(BuildContext context) {
    final embedding = maybeOf(context);
    if (embedding == null) {
      throw StateError('No ComposerEditor is drawing this component.');
    }
    return embedding;
  }

  @override
  bool updateShouldNotify(ComposerEditorScope oldWidget) =>
      !identical(embedding, oldWidget.embedding);
}
