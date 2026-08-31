import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gives a scrollable browser-style shortcuts for its logical boundaries.
///
/// Only the active wrapper reacts, so side-by-side scrollables do not both
/// move. Initial ownership does not take primary focus, pointer interaction
/// transfers ownership, and the focus tree gets first chance to handle keys so
/// editable controls keep their native shortcuts.
class ListBoundaryShortcuts extends StatefulWidget {
  const ListBoundaryShortcuts({
    super.key,
    required this.onStart,
    required this.onEnd,
    required this.child,
    this.initiallyActive = false,
    this.debugLabel,
  });

  final VoidCallback onStart;
  final VoidCallback onEnd;
  final Widget child;

  /// Makes this wrapper the fallback owner without stealing primary focus.
  final bool initiallyActive;
  final String? debugLabel;

  @override
  State<ListBoundaryShortcuts> createState() => _ListBoundaryShortcutsState();
}

class _ListBoundaryShortcutsState extends State<ListBoundaryShortcuts> {
  static _ListBoundaryShortcutsState? _active;

  static const _startShortcuts = <SingleActivator>[
    SingleActivator(LogicalKeyboardKey.home, includeRepeats: false),
    SingleActivator(
      LogicalKeyboardKey.arrowUp,
      meta: true,
      includeRepeats: false,
    ),
  ];
  static const _endShortcuts = <SingleActivator>[
    SingleActivator(LogicalKeyboardKey.end, includeRepeats: false),
    SingleActivator(
      LogicalKeyboardKey.arrowDown,
      meta: true,
      includeRepeats: false,
    ),
  ];

  late final FocusNode _focusNode = FocusNode(
    debugLabel: widget.debugLabel,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addLateKeyEventHandler(_handleUnclaimedKeyEvent);
    if (widget.initiallyActive) _active = this;
  }

  @override
  void didUpdateWidget(ListBoundaryShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyActive && !oldWidget.initiallyActive) _active = this;
    if (!widget.initiallyActive &&
        oldWidget.initiallyActive &&
        identical(_active, this)) {
      _active = null;
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeLateKeyEventHandler(_handleUnclaimedKeyEvent);
    if (identical(_active, this)) _active = null;
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleBoundaryKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (_startShortcuts.any((shortcut) => shortcut.accepts(event, keyboard))) {
      widget.onStart();
      return KeyEventResult.handled;
    }
    if (_endShortcuts.any((shortcut) => shortcut.accepts(event, keyboard))) {
      widget.onEnd();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    _active = this;
    return _handleBoundaryKey(event);
  }

  KeyEventResult _handleUnclaimedKeyEvent(KeyEvent event) {
    if (!identical(_active, this) || !_fallbackCanHandle) {
      return KeyEventResult.ignored;
    }
    return _handleBoundaryKey(event);
  }

  bool get _fallbackCanHandle {
    final focusManager = FocusManager.instance;
    final primaryFocus = focusManager.primaryFocus;
    if (primaryFocus == null ||
        identical(primaryFocus, focusManager.rootScope)) {
      return true;
    }

    final focusContext = primaryFocus.context;
    if (focusContext == null) return false;
    final ownerRoute = ModalRoute.of(context);
    final focusRoute = ModalRoute.of(focusContext);
    if (focusRoute != null && !identical(focusRoute, ownerRoute)) return false;

    bool isFormControl(Widget widget) =>
        widget is EditableText ||
        widget is FormField<Object?> ||
        widget is DropdownButton<Object?> ||
        widget is DropdownMenu<Object?> ||
        widget is Checkbox ||
        widget is CheckboxListTile ||
        widget is Radio<Object?> ||
        widget is RadioListTile<Object?> ||
        widget is Switch ||
        widget is SwitchListTile ||
        widget is Slider ||
        widget is RangeSlider ||
        widget is SegmentedButton<Object?> ||
        widget is ToggleButtons;

    if (isFormControl(focusContext.widget)) return false;
    var found = false;
    focusContext.visitAncestorElements((element) {
      found = isFormControl(element.widget);
      return !found;
    });
    return !found;
  }

  void _claimFocus(PointerEvent _) {
    _active = this;
    _focusNode.requestFocus();
  }

  void _activate(PointerEvent _) => _active = this;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    includeSemantics: false,
    onKeyEvent: _handleKeyEvent,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _claimFocus,
      onPointerSignal: _activate,
      child: widget.child,
    ),
  );
}
