import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// App-wide focus outlines: Tab enables them; pointer presses hide them.
///
/// Mount once above the Navigator so routes and overlays share the policy.
/// Focus, text carets, selection and keyboard shortcuts remain unaffected.
class DFocusHighlight extends StatefulWidget {
  const DFocusHighlight({super.key, required this.child});

  final Widget child;

  /// Standalone components retain their default focus styling outside the app.
  static bool visibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_FocusHighlightScope>()
          ?.visible ??
      true;

  @override
  State<DFocusHighlight> createState() => _DFocusHighlightState();
}

class _DFocusHighlightState extends State<DFocusHighlight> {
  late final FocusHighlightStrategy _previousStrategy;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
  }

  void _setVisible(bool visible) {
    if (_visible == visible) return;
    FocusManager.instance.highlightStrategy = visible
        ? FocusHighlightStrategy.alwaysTraditional
        : FocusHighlightStrategy.alwaysTouch;
    setState(() => _visible = visible);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      _setVisible(true);
    }
    return KeyEventResult.ignored;
  }

  void _handlePointer(PointerEvent event) {
    if (event is PointerDownEvent) _setVisible(false);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
    FocusManager.instance.highlightStrategy = _previousStrategy;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _FocusHighlightScope(visible: _visible, child: widget.child);
}

class _FocusHighlightScope extends InheritedWidget {
  const _FocusHighlightScope({required this.visible, required super.child});

  final bool visible;

  @override
  bool updateShouldNotify(_FocusHighlightScope oldWidget) =>
      visible != oldWidget.visible;
}
