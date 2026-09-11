import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';

/// A pane focus target whose nested controls retain their own focus handling.
class ReadingFocusNode extends FocusNode {
  ReadingFocusNode({super.debugLabel}) : super(skipTraversal: true);
}

bool navigationShortcutsAllowed(
  BuildContext context, {
  bool activation = false,
}) {
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return false;
  if (!TickerMode.valuesOf(context).enabled ||
      ModalRoute.of(context)?.isCurrent == false ||
      Navigator.maybeOf(context)?.canPop() == true) {
    return false;
  }
  final focus = FocusManager.instance.primaryFocus;
  final focusContext = focus?.context;
  if (focusContext == null) return true;
  final focusRoute = ModalRoute.of(focusContext);
  if (focusRoute != null && !identical(focusRoute, ModalRoute.of(context))) {
    return false;
  }

  bool ownsKeyboard(Widget widget) {
    // A closed combobox trigger is a button; its FormField wrapper should
    // not block reading keys. Focused editors still keep their own keys.
    if (widget is DCombobox<Object?>) {
      return widget.open ?? widget.controller?.isOpen ?? true;
    }
    return widget is EditableText ||
        widget is MenuItemButton ||
        widget is SubmenuButton ||
        widget is FormField<Object?> ||
        widget is DropdownButton<Object?> ||
        widget is DropdownMenu<Object?> ||
        widget is DTabTrigger<Object?> ||
        widget is DCheckbox ||
        widget is Checkbox ||
        widget is CheckboxListTile ||
        widget is RawRadio<Object?> ||
        widget is Radio<Object?> ||
        widget is RadioListTile<Object?> ||
        widget is DSwitch ||
        widget is DSwitchTile ||
        widget is Switch ||
        widget is SwitchListTile ||
        widget is DMultiSlider ||
        widget is Slider ||
        widget is RangeSlider ||
        widget is SegmentedButton<Object?> ||
        widget is ToggleButtons ||
        (activation &&
            (widget is ButtonStyleButton ||
                widget is CupertinoButton ||
                widget is InkResponse));
  }

  if (ownsKeyboard(focusContext.widget)) return false;
  var blocked = false;
  focusContext.visitAncestorElements((element) {
    blocked = ownsKeyboard(element.widget);
    return !blocked;
  });
  if (blocked || focus is FocusScopeNode || focus is ReadingFocusNode) {
    return !blocked;
  }

  // A control may attach its focus node above its actual widget. Do not
  // descend into independent focus targets inside a focused reading pane.
  void visit(Element element) {
    if (blocked || element.widget is Focus) return;
    blocked = ownsKeyboard(element.widget);
    if (!blocked) element.visitChildElements(visit);
  }

  if (focusContext is Element) focusContext.visitChildElements(visit);
  return !blocked;
}

/// Dispatches commands to their content pane, independently of pane focus.
class ReadingShortcuts extends StatefulWidget {
  const ReadingShortcuts({
    super.key,
    required this.commands,
    required this.child,
    this.sequenceContext,
  });

  final Map<ReadingCommand, bool Function()> commands;
  final Widget child;
  final Object? sequenceContext;

  @override
  State<ReadingShortcuts> createState() => _ReadingShortcutsState();
}

class _ReadingShortcutsState extends State<ReadingShortcuts> {
  static final _scopes = <_ReadingShortcutsState>[];

  // Flutter calls every early handler even when one returns handled. Dispatch
  // reading commands together so a sequence cannot also move the post cursor.
  static KeyEventResult _dispatchKey(KeyEvent event) {
    final scopes = List.of(_scopes);
    for (final sequences in [true, false]) {
      for (final scope in scopes) {
        if (!scope.mounted ||
            scope.widget.commands.keys.any(
                  (command) => command.prefix != null,
                ) !=
                sequences) {
          continue;
        }
        final result = scope._handleKey(event);
        if (result != KeyEventResult.ignored) return result;
      }
    }
    return KeyEventResult.ignored;
  }

  List<ReadingCommand> _pendingSequence = const [];
  Timer? _sequenceTimer;
  LogicalKeyboardKey? _heldSequenceKey;

  @override
  void initState() {
    super.initState();
    if (_scopes.isEmpty) {
      FocusManager.instance.addEarlyKeyEventHandler(_dispatchKey);
    }
    _scopes.add(this);
    FocusManager.instance.addListener(_resetSequence);
  }

  @override
  void didUpdateWidget(ReadingShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sequenceContext != widget.sequenceContext) _resetSequence();
  }

  void _resetSequence() {
    _sequenceTimer?.cancel();
    _sequenceTimer = null;
    _pendingSequence = const [];
  }

  @override
  void dispose() {
    _resetSequence();
    FocusManager.instance.removeListener(_resetSequence);
    _scopes.remove(this);
    if (_scopes.isEmpty) {
      FocusManager.instance.removeEarlyKeyEventHandler(_dispatchKey);
    }
    super.dispose();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event.logicalKey == _heldSequenceKey) {
      if (event is KeyUpEvent) _heldSequenceKey = null;
      return KeyEventResult.handled;
    }
    if (_pendingSequence.isNotEmpty && event is KeyDownEvent) {
      final pending = _pendingSequence;
      _resetSequence();
      if (!navigationShortcutsAllowed(context)) return KeyEventResult.ignored;
      for (final command in pending) {
        if (!command.accepts(event)) continue;
        _heldSequenceKey = event.logicalKey;
        widget.commands[command]?.call();
        // A completed sequence must not fall through to the single-key post
        // command when there is no adjacent topic to open.
        return KeyEventResult.handled;
      }
    }
    final sequences = [
      for (final command in widget.commands.keys)
        if (command.prefix?.accepts(event, HardwareKeyboard.instance) == true)
          command,
    ];
    if (sequences.isNotEmpty && navigationShortcutsAllowed(context)) {
      _resetSequence();
      _pendingSequence = sequences;
      _sequenceTimer = Timer(const Duration(seconds: 1), _resetSequence);
      return KeyEventResult.handled;
    }
    for (final entry in widget.commands.entries) {
      if (entry.key.prefix != null) continue;
      if (!entry.key.accepts(event)) continue;
      if (!navigationShortcutsAllowed(
        context,
        activation: entry.key == ReadingCommand.openTopic,
      )) {
        return KeyEventResult.ignored;
      }
      return entry.value() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerDown: (_) => _resetSequence(), child: widget.child);
}

class KeyboardSelection extends StatelessWidget {
  const KeyboardSelection({
    super.key,
    required this.selected,
    required this.child,
  }) : _drawBorder = true;

  /// Lets row surfaces combine the cursor with their own focus and selection.
  const KeyboardSelection.scope({
    super.key,
    required this.selected,
    required this.child,
  }) : _drawBorder = false;

  final bool selected;
  final Widget child;
  final bool _drawBorder;

  static bool isSelectedOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_KeyboardSelectionScope>()
          ?.selected ??
      false;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected ? true : null,
    child: _drawBorder
        ? DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: child,
          )
        : _KeyboardSelectionScope(selected: selected, child: child),
  );
}

class _KeyboardSelectionScope extends InheritedWidget {
  const _KeyboardSelectionScope({required this.selected, required super.child});

  final bool selected;

  @override
  bool updateShouldNotify(_KeyboardSelectionScope oldWidget) =>
      selected != oldWidget.selected;
}
