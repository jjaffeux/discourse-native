import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../ui/components/d_slider.dart';

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

  bool ownsKeyboard(Widget widget) =>
      widget is EditableText ||
      widget is MenuItemButton ||
      widget is SubmenuButton ||
      widget is FormField<Object?> ||
      widget is DropdownButton<Object?> ||
      widget is DropdownMenu<Object?> ||
      widget is Checkbox ||
      widget is CheckboxListTile ||
      widget is Radio<Object?> ||
      widget is RadioListTile<Object?> ||
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
  });

  final Map<ReadingCommand, bool Function()> commands;
  final Widget child;

  @override
  State<ReadingShortcuts> createState() => _ReadingShortcutsState();
}

class _ReadingShortcutsState extends State<ReadingShortcuts> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    super.dispose();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    for (final entry in widget.commands.entries) {
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
  Widget build(BuildContext context) => widget.child;
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
