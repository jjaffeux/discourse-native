import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'active_use.dart';

/// Feeds [ActiveUse] the input the web client counts: touches, clicks, scrolls
/// and keys. A mouse passing over the window is not one of them.
final class ActiveUseSignals {
  ActiveUseSignals(this._activeUse);

  final ActiveUse _activeUse;

  void attach() {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void detach() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  void _onPointer(PointerEvent event) {
    if (event.down ||
        event is PointerSignalEvent ||
        event is PointerPanZoomUpdateEvent) {
      _activeUse.seen();
    }
  }

  bool _onKey(KeyEvent event) {
    _activeUse.seen();
    return false;
  }
}
