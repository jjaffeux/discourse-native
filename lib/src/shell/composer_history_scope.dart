import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'composer_controller.dart';

/// Routes EditableText's overridable actions and iOS undo to source history.
/// EditableText's internal, time-coalesced stack is never used for commands.
class ComposerHistoryScope extends StatefulWidget {
  const ComposerHistoryScope({
    super.key,
    required this.composer,
    required this.child,
  });
  final ComposerController composer;
  final Widget child;

  @override
  State<ComposerHistoryScope> createState() => _ComposerHistoryScopeState();
}

class _ComposerHistoryScopeState extends State<ComposerHistoryScope>
    with UndoManagerClient {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _listen(widget.composer);
  }

  void _listen(ComposerController composer) {
    composer.history.startSession();
    composer.focus.addListener(_scheduleSync);
    composer.history.addListener(_scheduleSync);
    composer.addListener(_scheduleSync);
    _scheduleSync();
  }

  void _unlisten(ComposerController composer) {
    composer.focus.removeListener(_scheduleSync);
    composer.history.removeListener(_scheduleSync);
    composer.removeListener(_scheduleSync);
    composer.history.flush();
    if (identical(UndoManager.client, this)) UndoManager.client = null;
  }

  @override
  void didUpdateWidget(ComposerHistoryScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.composer, widget.composer)) {
      _unlisten(oldWidget.composer);
      _listen(widget.composer);
    }
  }

  void _scheduleSync() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (widget.composer.focus.hasPrimaryFocus) {
        // Run after EditableText's own focus/undo observers.
        UndoManager.client = this;
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          UndoManager.setUndoState(canUndo: canUndo, canRedo: canRedo);
        }
      } else if (identical(UndoManager.client, this)) {
        UndoManager.client = null;
      }
    });
  }

  @override
  bool get canUndo =>
      widget.composer.isEditing && widget.composer.history.canUndo;
  @override
  bool get canRedo =>
      widget.composer.isEditing && widget.composer.history.canRedo;
  @override
  void undo() {
    if (canUndo) widget.composer.history.undo();
  }

  @override
  void redo() {
    if (canRedo) widget.composer.history.redo();
  }

  @override
  void handlePlatformUndo(UndoDirection direction) {
    direction == UndoDirection.undo ? undo() : redo();
  }

  @override
  void dispose() {
    _unlisten(widget.composer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      UndoTextIntent: CallbackAction<UndoTextIntent>(
        onInvoke: (_) {
          undo();
          return null;
        },
      ),
      RedoTextIntent: CallbackAction<RedoTextIntent>(
        onInvoke: (_) {
          redo();
          return null;
        },
      ),
    },
    child: widget.child,
  );
}
