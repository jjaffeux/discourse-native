import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../foundation/material_surface.dart';
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
}

/// Presentation and behavior for one [DToggleGroup] item.
@immutable
class DToggleGroupItem<T extends Object> {
  const DToggleGroupItem({
    required this.value,
    required this.child,
    this.semanticLabel,

    this.tooltip,
    this.icon,
    this.selectedIcon,

    this.visualStyle,
  }) : _iconOnly = false;

  const DToggleGroupItem.iconOnly({
    required this.value,
    required this.icon,
    required this.semanticLabel,

    this.tooltip,
    this.selectedIcon,

    this.visualStyle,
  }) : child = const SizedBox.shrink(),

       _iconOnly = true;

  final T value;
  final Widget child;
  final String? semanticLabel;

  final String? tooltip;
  final Widget? icon;
  final Widget? selectedIcon;

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

    this.controller,
    this.onChanged,
    this.onItemActivated,
    this.multiple = false,
    this.allowEmptySelection = true,

    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.density = DToggleDensity.standard,
    this.expanded = false,
    this.spacing = 2,
    this.inset = false,
    this.slidingIndicator = false,
    this.semanticLabel,
    this.scrollable = true,
  }) : assert(values == null || controller == null),
       assert(spacing >= 0),
       assert(
         density != DToggleDensity.compactInset || ((inset) && !expanded),
         'Compact inset groups require two horizontal icon choices.',
       );

  /// Draw a shared recessed frame around the choices. Standard density uses
  /// segmented colors, weight and full-width selection inside this frame.
  final bool inset;

  /// A shared moving selection surface for horizontal inset icon choices.
  /// Native owns its measured geometry, colors and reduced-motion behavior.
  final bool slidingIndicator;
  final List<DToggleGroupItem<T>> items;

  /// Parent-owned controlled selection. Values preserve item declaration order.
  final List<T>? values;

  /// Borrowed mutable selection; cannot be combined with [values].
  final DToggleGroupController<T>? controller;
  final ValueChanged<List<T>>? onChanged;

  /// Called for every user activation, including the already selected item.
  /// Useful when a choice also opens options without clearing its selection.
  final ValueChanged<T>? onItemActivated;
  final bool multiple;

  /// Base UI permits deselecting the last item. Set false for required choices.
  final bool allowEmptySelection;

  final DToggleVariant variant;
  final DToggleSize size;
  final DToggleDensity density;

  /// Equal-width choices filling the available horizontal space. Disables
  /// scrolling; callers must provide bounded width (or height when vertical).
  final bool expanded;

  /// Number of 4px spacing units. The frozen default is 2 (8px).
  final double spacing;
  final String? semanticLabel;

  /// Scroll along the group axis instead of overflowing a narrow viewport.
  final bool scrollable;

  @override
  State<DToggleGroup<T>> createState() => _DToggleGroupState<T>();
}

class _DToggleGroupState<T extends Object> extends State<DToggleGroup<T>> {
  late List<T> _localValues = List.unmodifiable(const <Never>[]);
  final Map<T, FocusNode> _ownedFocusNodes = {};
  final Map<FocusNode, bool> _borrowedSkipTraversal = {};
  int _rovingIndex = 0;
  final _indicatorBounds = GlobalKey();
  final Map<T, GlobalKey> _indicatorKeys = {};
  Rect? _indicatorRect;

  void _measureIndicator() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.slidingIndicator) return;
      final value = _currentValues.singleOrNull;
      final bounds = _indicatorBounds.currentContext?.findRenderObject();
      final item = _indicatorKeys[value]?.currentContext?.findRenderObject();
      final rect =
          bounds is RenderBox &&
              item is RenderBox &&
              bounds.hasSize &&
              item.hasSize
          ? bounds.globalToLocal(item.localToGlobal(Offset.zero)) & item.size
          : null;
      if (rect != _indicatorRect) setState(() => _indicatorRect = rect);
    });
  }

  List<T> get _currentValues =>
      widget.values ?? widget.controller?.values ?? _localValues;

  bool get _groupInteractive =>
      ((widget.values == null || widget.onChanged != null));

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
    final values = widget.items.map((item) => item.value).toSet();
    final removed = _ownedFocusNodes.keys
        .where((value) => !values.contains(value))
        .toList();
    for (final value in removed) {
      _ownedFocusNodes.remove(value)?.dispose();
    }
    for (final item in widget.items) {
      {
        _ownedFocusNodes.putIfAbsent(
          item.value,
          () => FocusNode(debugLabel: 'Toggle Group ${item.value}'),
        );
      }
    }
  }

  FocusNode _focusFor(DToggleGroupItem<T> item) =>
      (_ownedFocusNodes[item.value]!);

  bool _isFocusableIndex(int index) =>
      (index >= 0 && index < widget.items.length && _groupInteractive);

  int _preferredRovingIndex() {
    final selected = _currentValues.toSet();
    final selectedIndex = widget.items.indexWhere(
      (item) => (selected.contains(item.value)),
    );
    if (selectedIndex >= 0) return selectedIndex;
    final enabledIndex = widget.items.indexWhere((item) => true);
    return enabledIndex < 0 ? 0 : enabledIndex;
  }

  void _toggleItem(T value) {
    if (!_groupInteractive) return;
    widget.onItemActivated?.call(value);
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
    // A held arrow key repeats. An ignored repeat reaches the default
    // directional traversal, which skips the non-roving items and leaves the
    // group, so repeats rove exactly like the initial press.
    if (event is KeyUpEvent || !_groupInteractive) {
      return KeyEventResult.ignored;
    }
    final direction = Directionality.of(context);
    final forwardKey = switch (Axis.horizontal) {
      Axis.vertical => LogicalKeyboardKey.arrowDown,
      Axis.horizontal when direction == TextDirection.rtl =>
        LogicalKeyboardKey.arrowLeft,
      Axis.horizontal => LogicalKeyboardKey.arrowRight,
    };
    final backwardKey = switch (Axis.horizontal) {
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
          : Scrollable.maybeOf(itemContext, axis: Axis.horizontal);
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
      if (widget.density == DToggleDensity.menuFilter) {
        // Keep a keyboard-selected pill clear of the menu's overflow fade.
        scrollable.position.ensureVisible(renderObject, alignment: .5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.density != DToggleDensity.compactInset || widget.items.length == 2,
      'Compact inset groups require exactly two choices.',
    );
    assert(
      widget.items.map((item) => item.value).toSet().length ==
          widget.items.length,
      'DToggleGroup item values must be unique.',
    );
    assert(
      !widget.slidingIndicator ||
          ((widget.inset && !widget.multiple) &&
              widget.items.every((item) => item._iconOnly)),
      'Sliding indicators require single-selection horizontal inset icon choices.',
    );
    if (widget.slidingIndicator) _measureIndicator();
    final selected = _currentValues.toSet();
    final compactInset = widget.density == DToggleDensity.compactInset;
    final gap = compactInset
        ? 2.0
        : widget.inset
        ? 2.0
        : widget.spacing * 4;
    final connected = gap == 0;
    final children = <Widget>[];
    for (var index = 0; index < widget.items.length; index++) {
      final item = widget.items[index];
      final variant =
          (widget.slidingIndicator ? DToggleVariant.inline : null) ??
          (widget.inset &&
                  (widget.density == DToggleDensity.standard || compactInset) &&
                  widget.variant == DToggleVariant.standard
              ? DToggleVariant.segmented
              : widget.variant);
      final size = widget.size;
      final baseStyle = item.visualStyle;
      final groupRadius = BorderRadius.circular(DRadius.control);
      final joinedRadius = !connected
          ? baseStyle?.borderRadius
          : (BorderRadiusDirectional.only(
              topStart: index == 0 ? groupRadius.topLeft : Radius.zero,
              bottomStart: index == 0 ? groupRadius.bottomLeft : Radius.zero,
              topEnd: index == widget.items.length - 1
                  ? groupRadius.topRight
                  : Radius.zero,
              bottomEnd: index == widget.items.length - 1
                  ? groupRadius.bottomRight
                  : Radius.zero,
            ));
      final edges = connected && variant == DToggleVariant.outline
          ? DToggleBorderEdges(
              top: true,
              bottom: true,
              start: (index == 0),
              end: true,
            )
          : baseStyle?.borderEdges ?? DToggleBorderEdges.all;
      final style = DToggleVisualStyle(
        borderRadius: widget.inset
            ? BorderRadius.circular(compactInset ? 7 : 8)
            : joinedRadius ?? baseStyle?.borderRadius,
        borderEdges: edges,
        expandArtwork: widget.expanded,
      );
      final itemEnabled = (_groupInteractive);
      _focusFor(item).skipTraversal = index != _rovingIndex;
      Widget toggle = item._iconOnly
          ? DToggle.iconOnly(
              key: ValueKey(('toggle-group-item', item.value)),
              icon: item.icon!,
              selectedIcon: item.selectedIcon,
              semanticLabel: item.semanticLabel!,
              semanticHint: null,
              pressed: selected.contains(item.value),
              onPressedChanged: itemEnabled
                  ? (_) => _toggleItem(item.value)
                  : null,
              enabled: itemEnabled,
              invalid: false,
              variant: variant,
              size: size,
              density: widget.density,
              focusNode: _focusFor(item),
              autofocus: false,
              onFocusChanged: (focused) =>
                  _handleItemFocusChanged(index, focused),
              visualStyle: style,
            )
          : DToggle(
              key: ValueKey(('toggle-group-item', item.value)),
              icon: item.icon,
              selectedIcon: item.selectedIcon,
              iconPosition: DToggleIconPosition.start,
              semanticLabel: item.semanticLabel,
              semanticHint: null,
              pressed: selected.contains(item.value),
              onPressedChanged: itemEnabled
                  ? (_) => _toggleItem(item.value)
                  : null,
              enabled: itemEnabled,
              invalid: false,
              variant: variant,
              size: size,
              density: widget.density,
              focusNode: _focusFor(item),
              autofocus: false,
              onFocusChanged: (focused) =>
                  _handleItemFocusChanged(index, focused),
              visualStyle: style,
              child: item.child,
            );
      if (item.tooltip case final tooltip?) {
        toggle = DTooltip(message: tooltip, child: toggle);
      }
      if (widget.slidingIndicator) {
        toggle = SizedBox(
          key: _indicatorKeys.putIfAbsent(item.value, GlobalKey.new),
          child: toggle,
        );
      }
      children.add(widget.expanded ? Expanded(child: toggle) : toggle);
      if (index != widget.items.length - 1 && gap > 0) {
        children.add(SizedBox(width: (gap), height: 0));
      }
    }

    Widget group = _FocusOrderedFlex(
      direction: Axis.horizontal,
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      focusedChildIndex: connected ? _rovingIndex : null,
      children: children,
    );
    if (widget.slidingIndicator) {
      final rect = _indicatorRect;
      group = Stack(
        key: _indicatorBounds,
        children: [
          if (rect != null)
            AnimatedPositioned(
              key: const ValueKey('toggle-group-sliding-indicator'),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubic,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: DTokens.of(context).background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DTokens.of(context).border),
                  ),
                ),
              ),
            ),
          group,
        ],
      );
    }
    if (widget.scrollable && !widget.expanded) {
      group = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // The mockup pads the scroll viewport itself. Padding outside it
        // clips the capsule's shadow at its 26px bounds, flattening corners.
        padding: widget.density == DToggleDensity.menuFilter
            ? const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 10)
            : null,
        child: group,
      );
      if (widget.density == DToggleDensity.menuFilter) {
        group = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Directionality.of(context) == TextDirection.rtl
                ? Alignment.centerRight
                : Alignment.centerLeft,
            end: Directionality.of(context) == TextDirection.rtl
                ? Alignment.centerLeft
                : Alignment.centerRight,
            colors: const [Colors.black, Colors.black, Colors.transparent],
            stops: [0, (1 - 28 / bounds.width).clamp(0, 1), 1],
          ).createShader(bounds),
          child: group,
        );
      }
    }
    if (widget.inset) {
      final tokens = DTokens.of(context);
      final decoration = BoxDecoration(
        color: DMaterialSurface.fill(
          context,
          Color.lerp(tokens.background, Colors.black, .14)!,
        ),
        border: Border.all(
          color: widget.density == DToggleDensity.tile
              ? tokens.border
              : Color.lerp(tokens.background, tokens.foreground, .12)!,
        ),
        borderRadius: BorderRadius.circular(compactInset ? 9 : 10),
      );
      group = DMaterialSurface(
        depth: DSurfaceDepth.recessed,
        radius: BorderRadius.circular(compactInset ? 9 : 10),
        color: Color.lerp(tokens.background, Colors.black, .14)!,
        child: DecoratedBox(
          key: compactInset
              ? const ValueKey('toggle-group-compact-frame')
              : null,
          decoration: decoration,
          child: Padding(padding: const EdgeInsets.all(3), child: group),
        ),
      );
      group = Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        heightFactor: 1,
        child: group,
      );
    }
    group = DMaterialBatch(child: group);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      enabled: true,
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
