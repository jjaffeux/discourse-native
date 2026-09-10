import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';
import 'd_toggle.dart';
import 'd_tooltip.dart';

/// Parent-owned mutable selection for [DToggleGroup].
///
/// A controller passed to a group is borrowed and never disposed by the
/// widget. Call [dispose] in the same owner that created it.
class DToggleGroupController<T extends Object> extends ChangeNotifier {
  DToggleGroupController({Iterable<T> values = const []})
    : _values = List.unmodifiable(values);

  List<T> _values;

  List<T> get values => _values;

  void setValues(Iterable<T> values) {
    final next = List<T>.unmodifiable(values);
    if (listEquals(_values, next)) return;
    _values = next;
    notifyListeners();
  }

  void clear() => setValues(const []);
}

/// Presentation and behavior for one [DToggleGroup] item.
@immutable
class DToggleGroupItem<T extends Object> {
  const DToggleGroupItem({
    required this.value,
    required this.child,
    this.semanticLabel,
    this.semanticHint,
    this.tooltip,
    this.icon,
    this.selectedIcon,
    this.iconPosition = DToggleIconPosition.start,
    this.enabled = true,
    this.invalid = false,
    this.variant,
    this.size,
    this.focusNode,
    this.autofocus = false,
    this.visualStyle,
  }) : _iconOnly = false;

  const DToggleGroupItem.iconOnly({
    required this.value,
    required this.icon,
    required this.semanticLabel,
    this.semanticHint,
    this.tooltip,
    this.selectedIcon,
    this.enabled = true,
    this.invalid = false,
    this.variant,
    this.size,
    this.focusNode,
    this.autofocus = false,
    this.visualStyle,
  }) : child = const SizedBox.shrink(),
       iconPosition = DToggleIconPosition.start,
       _iconOnly = true;

  final T value;
  final Widget child;
  final String? semanticLabel;
  final String? semanticHint;
  final String? tooltip;
  final Widget? icon;
  final Widget? selectedIcon;
  final DToggleIconPosition iconPosition;
  final bool enabled;
  final bool invalid;
  final DToggleVariant? variant;
  final DToggleSize? size;

  /// Borrowed from the caller and never disposed by the group.
  final FocusNode? focusNode;
  final bool autofocus;
  final DToggleVisualStyle? visualStyle;
  final bool _iconOnly;
}

/// A shadcn/Base UI selection group composed from real [DToggle] controls.
///
/// Supply [values] for controlled state, [controller] for externally mutable
/// state, or neither for state initialized by [initialValues]. Controlled state
/// requires [onChanged] to be interactive. A borrowed controller and borrowed
/// item focus nodes are never disposed. Arrow keys follow [orientation],
/// Home/End jump to an edge, and [loopFocus] controls wrapping.
class DToggleGroup<T extends Object> extends StatefulWidget {
  const DToggleGroup({
    super.key,
    required this.items,
    this.values,
    this.initialValues = const [],
    this.controller,
    this.onChanged,
    this.multiple = false,
    this.allowEmptySelection = true,
    this.enabled = true,
    this.orientation = Axis.horizontal,
    this.loopFocus = true,
    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.spacing = 2,
    this.semanticLabel,
    this.scrollable = true,
  }) : assert(values == null || controller == null),
       assert(spacing >= 0);

  final List<DToggleGroupItem<T>> items;

  /// Parent-owned controlled selection. Values preserve item declaration order.
  final List<T>? values;

  /// Initial selection for internally owned state.
  final List<T> initialValues;

  /// Borrowed mutable selection; cannot be combined with [values].
  final DToggleGroupController<T>? controller;
  final ValueChanged<List<T>>? onChanged;
  final bool multiple;

  /// Base UI permits deselecting the last item. Set false for required choices.
  final bool allowEmptySelection;
  final bool enabled;
  final Axis orientation;
  final bool loopFocus;
  final DToggleVariant variant;
  final DToggleSize size;

  /// Number of 4px spacing units. The frozen default is 2 (8px).
  final double spacing;
  final String? semanticLabel;

  /// Scroll along the group axis instead of overflowing a narrow viewport.
  final bool scrollable;

  @override
  State<DToggleGroup<T>> createState() => _DToggleGroupState<T>();
}

class _DToggleGroupState<T extends Object> extends State<DToggleGroup<T>> {
  late List<T> _localValues = List.unmodifiable(widget.initialValues);
  final Map<T, FocusNode> _ownedFocusNodes = {};
  final Map<FocusNode, bool> _borrowedSkipTraversal = {};
  int _rovingIndex = 0;

  List<T> get _currentValues =>
      widget.values ?? widget.controller?.values ?? _localValues;

  bool get _groupInteractive =>
      widget.enabled && (widget.values == null || widget.onChanged != null);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_controllerChanged);
    _reconcileFocusNodes();
    _rovingIndex = _preferredRovingIndex();
  }

  @override
  void didUpdateWidget(DToggleGroup<T> oldWidget) {
    final previousRovingValue =
        _rovingIndex >= 0 && _rovingIndex < oldWidget.items.length
        ? oldWidget.items[_rovingIndex].value
        : null;
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_controllerChanged);
      if (widget.controller == null && widget.values == null) {
        _localValues = List.unmodifiable(
          oldWidget.controller?.values ?? oldWidget.values ?? _localValues,
        );
      }
      widget.controller?.addListener(_controllerChanged);
    } else if (oldWidget.values != null && widget.values == null) {
      _localValues = List.unmodifiable(oldWidget.values!);
    }
    _reconcileFocusNodes();
    final previousRovingIndex = widget.items.indexWhere(
      (item) => item.value == previousRovingValue,
    );
    if (_isFocusableIndex(previousRovingIndex)) {
      _rovingIndex = previousRovingIndex;
    } else {
      _rovingIndex = _preferredRovingIndex();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_controllerChanged);
    for (final node in _ownedFocusNodes.values) {
      node.dispose();
    }
    for (final entry in _borrowedSkipTraversal.entries) {
      entry.key.skipTraversal = entry.value;
    }
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  void _reconcileFocusNodes() {
    final currentBorrowed = {
      for (final item in widget.items)
        if (item.focusNode != null) item.focusNode!,
    };
    final removedBorrowed = _borrowedSkipTraversal.keys
        .where((node) => !currentBorrowed.contains(node))
        .toList();
    for (final node in removedBorrowed) {
      node.skipTraversal = _borrowedSkipTraversal.remove(node)!;
    }
    final borrowed = {
      for (final item in widget.items)
        if (item.focusNode != null) item.value,
    };
    final values = widget.items.map((item) => item.value).toSet();
    final removed = _ownedFocusNodes.keys
        .where((value) => !values.contains(value) || borrowed.contains(value))
        .toList();
    for (final value in removed) {
      _ownedFocusNodes.remove(value)?.dispose();
    }
    for (final item in widget.items) {
      if (item.focusNode case final borrowed?) {
        _borrowedSkipTraversal.putIfAbsent(
          borrowed,
          () => borrowed.skipTraversal,
        );
      }
      if (item.focusNode == null) {
        _ownedFocusNodes.putIfAbsent(
          item.value,
          () => FocusNode(debugLabel: 'Toggle Group ${item.value}'),
        );
      }
    }
  }

  FocusNode _focusFor(DToggleGroupItem<T> item) =>
      item.focusNode ?? _ownedFocusNodes[item.value]!;

  bool _isFocusableIndex(int index) =>
      index >= 0 &&
      index < widget.items.length &&
      _groupInteractive &&
      widget.items[index].enabled;

  int _preferredRovingIndex() {
    final selected = _currentValues.toSet();
    final selectedIndex = widget.items.indexWhere(
      (item) => item.enabled && selected.contains(item.value),
    );
    if (selectedIndex >= 0) return selectedIndex;
    final enabledIndex = widget.items.indexWhere((item) => item.enabled);
    return enabledIndex < 0 ? 0 : enabledIndex;
  }

  void _toggleItem(T value) {
    if (!_groupInteractive) return;
    // The child reflects the last build and can still report its previous
    // pressed value when another input arrives before the scheduled rebuild.
    // Derive the transition from the group's already-updated selection.
    final selected = _currentValues.toSet();
    final pressed = !selected.contains(value);
    final next = <T>[];
    if (widget.multiple) {
      if (pressed) {
        selected.add(value);
      } else if (widget.allowEmptySelection || selected.length > 1) {
        selected.remove(value);
      }
      for (final item in widget.items) {
        if (selected.contains(item.value)) next.add(item.value);
      }
    } else if (pressed) {
      next.add(value);
    } else if (!widget.allowEmptySelection) {
      next.add(value);
    }

    final immutable = List<T>.unmodifiable(next);
    if (listEquals(immutable, _currentValues)) return;
    if (widget.values == null) {
      if (widget.controller case final controller?) {
        controller.setValues(immutable);
      } else {
        setState(() => _localValues = immutable);
      }
    }
    widget.onChanged?.call(immutable);
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_groupInteractive) {
      return KeyEventResult.ignored;
    }
    final direction = Directionality.of(context);
    final forwardKey = switch (widget.orientation) {
      Axis.vertical => LogicalKeyboardKey.arrowDown,
      Axis.horizontal when direction == TextDirection.rtl =>
        LogicalKeyboardKey.arrowLeft,
      Axis.horizontal => LogicalKeyboardKey.arrowRight,
    };
    final backwardKey = switch (widget.orientation) {
      Axis.vertical => LogicalKeyboardKey.arrowUp,
      Axis.horizontal when direction == TextDirection.rtl =>
        LogicalKeyboardKey.arrowRight,
      Axis.horizontal => LogicalKeyboardKey.arrowLeft,
    };
    if (event.logicalKey == LogicalKeyboardKey.home) {
      return _moveToEdge(first: true);
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      return _moveToEdge(first: false);
    }
    if (event.logicalKey == forwardKey) return _moveFocus(1);
    if (event.logicalKey == backwardKey) return _moveFocus(-1);
    return KeyEventResult.ignored;
  }

  KeyEventResult _moveToEdge({required bool first}) {
    final indices = Iterable<int>.generate(widget.items.length);
    final ordered = first ? indices : indices.toList().reversed;
    final target = ordered.cast<int?>().firstWhere(
      (index) => _isFocusableIndex(index!),
      orElse: () => null,
    );
    if (target == null) return KeyEventResult.ignored;
    _focusIndex(target);
    return KeyEventResult.handled;
  }

  KeyEventResult _moveFocus(int delta) {
    if (widget.items.isEmpty) return KeyEventResult.ignored;
    final focused = widget.items.indexWhere((item) => _focusFor(item).hasFocus);
    var index = focused >= 0 ? focused : _rovingIndex;
    for (var count = 0; count < widget.items.length; count++) {
      final next = index + delta;
      if (!widget.loopFocus && (next < 0 || next >= widget.items.length)) {
        return KeyEventResult.handled;
      }
      index = next % widget.items.length;
      if (index < 0) index += widget.items.length;
      if (_isFocusableIndex(index)) {
        _focusIndex(index);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.handled;
  }

  void _focusIndex(int index) {
    final previousIndex = _rovingIndex;
    if (previousIndex != index) {
      setState(() => _rovingIndex = index);
    }
    final item = widget.items[index];
    final node = _focusFor(item);
    node.requestFocus();
    _revealAfterLayout(item.value);
  }

  void _handleItemFocusChanged(int index, bool focused) {
    if (!focused) return;
    final previousIndex = _rovingIndex;
    if (previousIndex != index) {
      setState(() => _rovingIndex = index);
      _revealAfterLayout(widget.items[index].value);
    }
  }

  void _revealAfterLayout(T value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.items.indexWhere((item) => item.value == value);
      if (index < 0) return;
      final node = _focusFor(widget.items[index]);
      if (!node.hasFocus) return;
      final itemContext = node.context;
      final renderObject = itemContext?.findRenderObject();
      final scrollable = itemContext == null
          ? null
          : Scrollable.maybeOf(itemContext, axis: widget.orientation);
      if (renderObject == null ||
          !renderObject.attached ||
          scrollable == null) {
        return;
      }
      // Apply both policies so the nearest hidden edge is revealed. Flutter
      // flips them for left/up axis directions, which also covers horizontal
      // RTL without deriving direction from declaration order.
      scrollable.position.ensureVisible(
        renderObject,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      scrollable.position.ensureVisible(
        renderObject,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.items.map((item) => item.value).toSet().length ==
          widget.items.length,
      'DToggleGroup item values must be unique.',
    );
    final selected = _currentValues.toSet();
    final gap = widget.spacing * 4;
    final connected = gap == 0;
    final children = <Widget>[];
    for (var index = 0; index < widget.items.length; index++) {
      final item = widget.items[index];
      final variant = item.variant ?? widget.variant;
      final size = item.size ?? widget.size;
      final baseStyle = item.visualStyle;
      final groupRadius = BorderRadius.circular(
        _toggleGroupRadius(context, size),
      );
      final joinedRadius = !connected
          ? baseStyle?.borderRadius
          : widget.orientation == Axis.horizontal
          ? BorderRadiusDirectional.only(
              topStart: index == 0 ? groupRadius.topLeft : Radius.zero,
              bottomStart: index == 0 ? groupRadius.bottomLeft : Radius.zero,
              topEnd: index == widget.items.length - 1
                  ? groupRadius.topRight
                  : Radius.zero,
              bottomEnd: index == widget.items.length - 1
                  ? groupRadius.bottomRight
                  : Radius.zero,
            )
          : BorderRadius.vertical(
              top: index == 0 ? groupRadius.topLeft : Radius.zero,
              bottom: index == widget.items.length - 1
                  ? groupRadius.bottomLeft
                  : Radius.zero,
            );
      final edges = connected && variant == DToggleVariant.outline
          ? DToggleBorderEdges(
              top: widget.orientation == Axis.horizontal || index == 0,
              bottom: true,
              start: widget.orientation == Axis.vertical || index == 0,
              end: true,
            )
          : baseStyle?.borderEdges ?? DToggleBorderEdges.all;
      final style = DToggleVisualStyle(
        constraints: baseStyle?.constraints,
        padding:
            baseStyle?.padding ??
            (connected && !item._iconOnly
                ? item.icon == null
                      ? const EdgeInsets.symmetric(horizontal: 8)
                      : item.iconPosition == DToggleIconPosition.start
                      ? const EdgeInsetsDirectional.only(start: 6, end: 8)
                      : const EdgeInsetsDirectional.only(start: 8, end: 6)
                : null),
        borderRadius: joinedRadius ?? baseStyle?.borderRadius,
        borderEdges: edges,
      );
      final itemEnabled = _groupInteractive && item.enabled;
      _focusFor(item).skipTraversal = index != _rovingIndex;
      Widget toggle = item._iconOnly
          ? DToggle.iconOnly(
              key: ValueKey(('toggle-group-item', item.value)),
              icon: item.icon!,
              selectedIcon: item.selectedIcon,
              semanticLabel: item.semanticLabel!,
              semanticHint: item.semanticHint,
              pressed: selected.contains(item.value),
              onPressedChanged: itemEnabled
                  ? (_) => _toggleItem(item.value)
                  : null,
              enabled: itemEnabled,
              invalid: item.invalid,
              variant: variant,
              size: size,
              focusNode: _focusFor(item),
              autofocus: item.autofocus,
              onFocusChanged: (focused) =>
                  _handleItemFocusChanged(index, focused),
              visualStyle: style,
            )
          : DToggle(
              key: ValueKey(('toggle-group-item', item.value)),
              icon: item.icon,
              selectedIcon: item.selectedIcon,
              iconPosition: item.iconPosition,
              semanticLabel: item.semanticLabel,
              semanticHint: item.semanticHint,
              pressed: selected.contains(item.value),
              onPressedChanged: itemEnabled
                  ? (_) => _toggleItem(item.value)
                  : null,
              enabled: itemEnabled,
              invalid: item.invalid,
              variant: variant,
              size: size,
              focusNode: _focusFor(item),
              autofocus: item.autofocus,
              onFocusChanged: (focused) =>
                  _handleItemFocusChanged(index, focused),
              visualStyle: style,
              child: item.child,
            );
      if (item.tooltip case final tooltip?) {
        toggle = DTooltip(message: tooltip, child: toggle);
      }
      children.add(toggle);
      if (index != widget.items.length - 1 && gap > 0) {
        children.add(
          SizedBox(
            width: widget.orientation == Axis.horizontal ? gap : 0,
            height: widget.orientation == Axis.vertical ? gap : 0,
          ),
        );
      }
    }

    Widget group = _FocusOrderedFlex(
      direction: widget.orientation,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.orientation == Axis.vertical
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      focusedChildIndex: connected ? _rovingIndex : null,
      children: children,
    );
    if (widget.scrollable) {
      group = SingleChildScrollView(
        scrollDirection: widget.orientation,
        child: group,
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handleKey,
        child: group,
      ),
    );
  }
}

/// Keeps Flex layout/hit testing while matching the reference's focus z-index.
///
/// [DToggle] still paints the ring. Repainting the focused connected item after
/// the ordinary Flex pass only ensures that later siblings cannot cover it.
class _FocusOrderedFlex extends Flex {
  const _FocusOrderedFlex({
    required super.direction,
    required super.mainAxisSize,
    required super.crossAxisAlignment,
    required super.children,
    required this.focusedChildIndex,
  });

  final int? focusedChildIndex;

  @override
  RenderFlex createRenderObject(BuildContext context) =>
      _RenderFocusOrderedFlex(
        focusedChildIndex: focusedChildIndex,
        direction: direction,
        mainAxisAlignment: mainAxisAlignment,
        mainAxisSize: mainAxisSize,
        crossAxisAlignment: crossAxisAlignment,
        textDirection: getEffectiveTextDirection(context),
        verticalDirection: verticalDirection,
        textBaseline: textBaseline,
        clipBehavior: clipBehavior,
        spacing: spacing,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFocusOrderedFlex renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.focusedChildIndex = focusedChildIndex;
  }
}

class _RenderFocusOrderedFlex extends RenderFlex {
  _RenderFocusOrderedFlex({
    required this._focusedChildIndex,
    required super.direction,
    required super.mainAxisAlignment,
    required super.mainAxisSize,
    required super.crossAxisAlignment,
    required super.textDirection,
    required super.verticalDirection,
    required super.textBaseline,
    required super.clipBehavior,
    required super.spacing,
  });

  int? _focusedChildIndex;

  set focusedChildIndex(int? value) {
    if (_focusedChildIndex == value) return;
    _focusedChildIndex = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final index = _focusedChildIndex;
    if (index == null || index < 0) return;
    var child = firstChild;
    for (var current = 0; child != null && current < index; current++) {
      child = childAfter(child);
    }
    if (child == null) return;
    final parentData = child.parentData! as FlexParentData;
    context.paintChild(child, offset + parentData.offset);
  }
}

double _toggleGroupRadius(BuildContext context, DToggleSize size) {
  // Connected items use the group's rounded-lg outer corners at every size;
  // the small group's own wrapper is rounded min(radius-md, 10px).
  final radius = DTokens.of(context).radius;
  return size == DToggleSize.small ? (radius * .8).clamp(0, 10) : radius;
}
