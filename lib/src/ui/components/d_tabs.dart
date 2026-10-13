import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/material_surface.dart';
import '../foundation/material_theme.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_kbd.dart';
import 'd_tooltip.dart';

/// The visual treatment of a [DTabList].
enum DTabListVariant {
  defaultStyle,

  /// Content-width underline tabs with a shared divider and spaced labels.
  line,

  /// A transparent list with a rounded neutral fill on the selected trigger.
  pill,

  /// Outlined capsule tabs with an accent-filled selected state. Uses the
  /// shared control sizes and retains horizontal scrolling and touch targets.
  outlinePill,

  /// Text-only selection without a background, border, shadow or indicator.
  plain,
}

/// A compositional shadcn-style tabs root.
///
/// Use the default constructor for locally owned selection, [DTabs.controlled]
/// for parent-owned selection, or provide a borrowed [controller]. When no
/// initial value is supplied, the first enabled trigger is selected after it
/// mounts. Set [selectFirstOnMount] to false to intentionally start empty.
/// Dynamic uncontrolled lists fall back to the first enabled trigger when the
/// active trigger is removed or disabled. Controlled roots never rewrite the
/// parent's value.
class DTabs<T> extends StatefulWidget {
  const DTabs({
    super.key,
    required this.children,

    this.onChanged,
    this.onActivated,

    this.orientation = Axis.horizontal,
    this.enabled = true,
    this.selectFirstOnMount = true,
  }) : value = null,
       _controlled = false;

  const DTabs.controlled({
    super.key,
    required this.children,
    required this.value,
    this.onChanged,
    this.onActivated,

    this.orientation = Axis.horizontal,
    this.enabled = true,
  }) : selectFirstOnMount = false,
       _controlled = true;

  final List<Widget> children;

  final T? value;

  final ValueChanged<T?>? onChanged;

  /// Called for every user activation, including the already-selected tab.
  final ValueChanged<T>? onActivated;

  final Axis orientation;
  final bool enabled;
  final bool selectFirstOnMount;
  final bool _controlled;

  @override
  State<DTabs<T>> createState() => _DTabsState<T>();
}

class _DTabsState<T> extends State<DTabs<T>> {
  final List<_DTabTriggerState<T>> _triggers = [];
  T? _value;
  _DTabTriggerState<T>? _highlightedTrigger;
  T? _highlightedForValue;
  bool _reconcileScheduled = false;

  T? get value => widget._controlled ? widget.value : (_value);

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(DTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    _scheduleReconcile();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void register(_DTabTriggerState<T> trigger) {
    if (_triggers.contains(trigger)) return;
    _triggers.add(trigger);
    _scheduleReconcile();
  }

  void unregister(_DTabTriggerState<T> trigger) {
    _triggers.remove(trigger);
    if (identical(_highlightedTrigger, trigger)) _highlightedTrigger = null;
    _scheduleReconcile();
  }

  void _scheduleReconcile() {
    if (_reconcileScheduled) return;
    _reconcileScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconcileScheduled = false;
      if (mounted) _reconcile();
    });
  }

  void _reconcile() {
    assert(() {
      for (var index = 0; index < _triggers.length; index++) {
        final value = _triggers[index].widget.value;
        assert(
          !_triggers.skip(index + 1).any((item) => item.widget.value == value),
          'DTabTrigger values must be unique within a DTabs root.',
        );
      }
      return true;
    }());
    final enabled = _orderedTriggers().where((item) => item.isEnabled).toList();
    final selected = _triggers.where((item) => item.widget.value == value);
    final selectedTrigger = selected.firstOrNull;
    _reconcileHighlight(enabled, selectedTrigger);
    if (widget._controlled) return;
    if (selectedTrigger != null && selectedTrigger.isEnabled) return;

    if (value == null && !widget.selectFirstOnMount) {
      return;
    }
    _setValue(enabled.firstOrNull?.widget.value);
  }

  void _reconcileHighlight(
    List<_DTabTriggerState<T>> enabled,
    _DTabTriggerState<T>? selected,
  ) {
    final focused = enabled
        .where((item) => item.focusNode.hasFocus)
        .firstOrNull;
    final selectionChanged = _highlightedForValue != value;
    final next =
        focused ??
        (!selectionChanged &&
                _highlightedTrigger != null &&
                enabled.contains(_highlightedTrigger)
            ? _highlightedTrigger
            : null) ??
        (selected?.isEnabled ?? false ? selected : null) ??
        enabled.firstOrNull;
    _highlightedForValue = value;
    _highlightedTrigger = next;
    // Stops computed while building can predate this highlight: a trigger's
    // first build runs before the triggers after it register, and a selection
    // change rebuilds the triggers before this reconcile moves the highlight.
    _syncTabStops();
  }

  /// [_DTabScope] carries the selection but not the highlight, so a highlight
  /// change rebuilds only the triggers the single Tab stop moved between.
  void _syncTabStops() {
    for (final trigger in _triggers) {
      trigger.updateTabStop();
    }
  }

  bool isTabStop(_DTabTriggerState<T> trigger) {
    final highlighted = _highlightedTrigger;
    if (highlighted != null && highlighted.isEnabled) {
      return identical(trigger, highlighted);
    }
    final enabled = _orderedTriggers().where((item) => item.isEnabled);
    final selected = enabled
        .where((item) => item.widget.value == value)
        .firstOrNull;
    return identical(trigger, selected ?? enabled.firstOrNull);
  }

  void highlight(_DTabTriggerState<T> trigger) {
    if (!trigger.isEnabled || identical(_highlightedTrigger, trigger)) return;
    _highlightedTrigger = trigger;
    _highlightedForValue = value;
    _syncTabStops();
  }

  void select(T value) {
    final trigger = _triggers
        .where((candidate) => candidate.widget.value == value)
        .firstOrNull;
    if (!widget.enabled || trigger == null || !trigger.isEnabled) return;
    _setValue(value);
    widget.onActivated?.call(value);
  }

  void _setValue(T? next) {
    if (value == next) return;
    if (!widget._controlled) {
      {
        setState(() => _value = next);
      }
    }
    widget.onChanged?.call(next);
  }

  void moveFocus(
    _DTabTriggerState<T> current,
    LogicalKeyboardKey key,
    bool loop,
    bool activate,
  ) {
    final enabled = _orderedTriggers().where((item) => item.isEnabled).toList();
    if (enabled.isEmpty) return;
    var nextIndex = enabled.indexOf(current);
    if (key == LogicalKeyboardKey.home) {
      nextIndex = 0;
    } else if (key == LogicalKeyboardKey.end) {
      nextIndex = enabled.length - 1;
    } else {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final delta = switch ((widget.orientation, key)) {
        (Axis.horizontal, LogicalKeyboardKey.arrowRight) => rtl ? -1 : 1,
        (Axis.horizontal, LogicalKeyboardKey.arrowLeft) => rtl ? 1 : -1,
        (Axis.vertical, LogicalKeyboardKey.arrowDown) => 1,
        (Axis.vertical, LogicalKeyboardKey.arrowUp) => -1,
        _ => 0,
      };
      if (delta == 0) return;
      nextIndex += delta;
      if (loop) {
        nextIndex %= enabled.length;
      } else {
        nextIndex = nextIndex.clamp(0, enabled.length - 1);
      }
    }
    final next = enabled[nextIndex];
    highlight(next);
    next.focusNode.requestFocus();
    next.ensureVisible();
    if (activate) select(next.widget.value);
  }

  void restoreTriggerFocus(T value) {
    final trigger = _triggers
        .where((candidate) => candidate.widget.value == value)
        .firstOrNull;
    if (trigger == null || !trigger.isEnabled) return;
    trigger.focusNode.requestFocus();
    trigger.ensureVisible();
  }

  List<_DTabTriggerState<T>> _orderedTriggers() {
    final ordered = [..._triggers];
    ordered.sort((left, right) {
      final leftBox = left.context.findRenderObject() as RenderBox?;
      final rightBox = right.context.findRenderObject() as RenderBox?;
      if (leftBox == null ||
          rightBox == null ||
          !leftBox.hasSize ||
          !rightBox.hasSize) {
        return _triggers.indexOf(left).compareTo(_triggers.indexOf(right));
      }
      final a = leftBox.localToGlobal(Offset.zero);
      final b = rightBox.localToGlobal(Offset.zero);
      if (widget.orientation == Axis.vertical) return a.dy.compareTo(b.dy);
      final comparison = a.dx.compareTo(b.dx);
      return Directionality.of(context) == TextDirection.rtl
          ? -comparison
          : comparison;
    });
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.children
        .where((child) => child is! DTabPanel<T>)
        .toList(growable: true);
    final panels = widget.children.whereType<DTabPanel<T>>().toList();
    if (panels.isNotEmpty) {
      parts.add(
        Stack(alignment: AlignmentDirectional.topStart, children: panels),
      );
    }
    final content = _DTabScope<T>(
      state: this,
      value: value,
      enabled: widget.enabled,
      orientation: widget.orientation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackedVertical =
              widget.orientation == Axis.vertical &&
              (constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21);
          final direction =
              widget.orientation == Axis.horizontal || stackedVertical
              ? Axis.vertical
              : Axis.horizontal;
          return Flex(
            direction: direction,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: direction == Axis.vertical
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0)
                  SizedBox(
                    width: direction == Axis.horizontal ? DSpacing.sm : 0,
                    height: direction == Axis.vertical ? DSpacing.sm : 0,
                  ),
                if (direction == Axis.horizontal &&
                    i == parts.length - 1 &&
                    panels.isNotEmpty &&
                    constraints.hasBoundedWidth)
                  Flexible(fit: FlexFit.loose, child: parts[i])
                else
                  parts[i],
              ],
            ],
          );
        },
      ),
    );
    return Semantics(container: true, explicitChildNodes: true, child: content);
  }
}

class _DTabScope<T> extends InheritedWidget {
  const _DTabScope({
    required this.state,
    required this.value,
    required this.enabled,
    required this.orientation,
    required super.child,
  });

  final _DTabsState<T> state;
  final T? value;
  final bool enabled;
  final Axis orientation;

  static _DTabScope<T> require<T>(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DTabScope<T>>();
    assert(scope != null, 'Tabs parts must be descendants of DTabs<$T>.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DTabScope<T> oldWidget) =>
      value != oldWidget.value ||
      enabled != oldWidget.enabled ||
      orientation != oldWidget.orientation;
}

/// Groups tab triggers and owns roving-focus behavior.
class DTabList<T> extends StatelessWidget {
  const DTabList({
    super.key,
    required this.children,
    this.size = DControlSize.regular,
    this.variant = DTabListVariant.defaultStyle,
    this.activateOnFocus = false,

    this.expandSelected = false,
  });

  final List<Widget> children;
  final DTabListVariant variant;

  final DControlSize size;
  final bool activateOnFocus;

  /// Icon tabs share the strip with the selected label taking the spare width.
  final bool expandSelected;

  @override
  Widget build(BuildContext context) {
    final root = _DTabScope.require<T>(context);
    final tokens = DTokens.of(context);
    final horizontalLine =
        variant == DTabListVariant.line && root.orientation == Axis.horizontal;

    if (expandSelected) {
      assert(root.orientation == Axis.horizontal);
      final tabs = children.cast<DTabTrigger<T>>();
      return LayoutBuilder(
        builder: (context, constraints) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final well = Colors.black.withValues(alpha: dark ? .16 : .045);
          return Semantics(
            container: true,
            explicitChildNodes: true,
            child: ClipRect(
              clipper: const _SidebarTabShadowClipper(),
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                child: DMaterialBatch(
                  child: DMaterialSurface(
                    depth: DSurfaceDepth.recessed,
                    preserveColor: true,
                    insetEdges: true,
                    color: well,
                    radius: BorderRadius.circular(DRadius.pill),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: DMaterialSurface.fill(context, well),
                        borderRadius: BorderRadius.circular(DRadius.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _DTabListScope<T>(
                          variant: variant,
                          size: size,
                          activateOnFocus: activateOnFocus,
                          expandSelected: true,
                          child: _ExpandingTabStrip(
                            availableWidth: constraints.hasBoundedWidth
                                ? math.max(0, constraints.maxWidth - 6)
                                : 0,
                            textDirection: Directionality.of(context),
                            children: [
                              for (final tab in tabs)
                                TweenAnimationBuilder<double>(
                                  key: ValueKey(('expanding-tab', tab.value)),
                                  tween: Tween(
                                    end: root.value == tab.value ? 1 : 0,
                                  ),
                                  duration: DMotion.duration(
                                    context,
                                    const Duration(milliseconds: 300),
                                  ),
                                  curve: Curves.ease,
                                  child: tab,
                                  builder: (_, weight, child) =>
                                      _ExpandingTabWeight(
                                        weight: weight,
                                        child: child!,
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    final decoration = BoxDecoration(
      color: variant == DTabListVariant.defaultStyle
          ? tokens.muted
          : Colors.transparent,
      borderRadius: variant == DTabListVariant.defaultStyle
          ? BorderRadius.circular(DRadius.panel)
          : BorderRadius.zero,
    );
    final scope = _DTabListScope<T>(
      variant: variant,
      size: size,
      activateOnFocus: activateOnFocus,

      child: Flex(
        direction: root.orientation,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: root.orientation == Axis.horizontal
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && variant != DTabListVariant.defaultStyle)
              SizedBox(
                width: root.orientation == Axis.horizontal
                    ? (horizontalLine
                          ? 20
                          : variant == DTabListVariant.outlinePill
                          ? DSpacing.controlGap
                          : 4)
                    : 0,
                height: root.orientation == Axis.vertical ? 4 : 0,
              ),
            children[i],
          ],
        ],
      ),
    );

    if (horizontalLine) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: SingleChildScrollView(
            controller: null,
            scrollDirection: Axis.horizontal,
            child: scope,
          ),
        ),
      );
    }

    Widget visual = Container(
      constraints: BoxConstraints(
        minHeight: root.orientation == Axis.horizontal
            ? DControlStyle.scaledHeight(
                size,
                MediaQuery.textScalerOf(context),
                context: context,
              )
            : 0,
      ),
      padding: const EdgeInsets.all(3),
      decoration: decoration,
      child: scope,
    );
    if (root.orientation == Axis.horizontal) {
      visual = SingleChildScrollView(
        controller: null,
        scrollDirection: Axis.horizontal,
        child: visual,
      );
    } else {
      visual = IntrinsicWidth(child: visual);
    }
    return Semantics(container: true, explicitChildNodes: true, child: visual);
  }
}

// The reference distributes spare width by animated flex-grow, after measuring
// each glyph/label/badge. Layout and hit testing use the same painted bounds.
/// Keep horizontally scrolled choices inside the track while allowing the
/// selected capsule's 4px/14px shadow to paint above and below its artwork.
class _SidebarTabShadowClipper extends CustomClipper<Rect> {
  const _SidebarTabShadowClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -30, size.width, size.height + 30);

  @override
  bool shouldReclip(_SidebarTabShadowClipper oldClipper) => false;
}

class _ExpandingTabData extends ContainerBoxParentData<RenderBox> {
  double weight = 0;
}

class _ExpandingTabWeight extends ParentDataWidget<_ExpandingTabData> {
  const _ExpandingTabWeight({required this.weight, required super.child});
  final double weight;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _ExpandingTabData;
    if (data.weight == weight) return;
    data.weight = weight;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _ExpandingTabStrip;
}

class _ExpandingTabStrip extends MultiChildRenderObjectWidget {
  const _ExpandingTabStrip({
    required this.availableWidth,
    required this.textDirection,
    required super.children,
  });
  final double availableWidth;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderExpandingTabs(
    availableWidth: availableWidth,
    textDirection: textDirection,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExpandingTabs renderObject,
  ) {
    renderObject
      ..availableWidth = availableWidth
      ..textDirection = textDirection
      ..markNeedsLayout();
  }
}

class _RenderExpandingTabs extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ExpandingTabData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ExpandingTabData> {
  _RenderExpandingTabs({
    required this.availableWidth,
    required this.textDirection,
  });
  double availableWidth;
  TextDirection textDirection;
  static const gap = 3.0;
  static const minimumWidth = 38.0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ExpandingTabData) {
      child.parentData = _ExpandingTabData();
    }
  }

  List<RenderBox> get _children => getChildrenAsList();

  @override
  void performLayout() {
    final children = _children;
    final widths = <double>[];
    var naturalWidth = math.max(0, children.length - 1) * gap;
    var height = 0.0;
    var totalWeight = 0.0;
    for (final child in children) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      final width = math.max(minimumWidth, child.size.width);
      widths.add(width);
      naturalWidth += width;
      height = math.max(height, child.size.height);
      totalWeight += (child.parentData! as _ExpandingTabData).weight;
    }
    final spare = totalWeight > 0
        ? math.max(0, availableWidth - naturalWidth)
        : 0.0;
    size = constraints.constrain(Size(naturalWidth + spare, height));
    var x = 0.0;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final data = child.parentData! as _ExpandingTabData;
      final width =
          widths[i] + (totalWeight > 0 ? spare * data.weight / totalWeight : 0);
      child.layout(
        BoxConstraints.tight(Size(width, height)),
        parentUsesSize: true,
      );
      data.offset = Offset(
        textDirection == TextDirection.ltr ? x : size.width - x - width,
        0,
      );
      x += width + gap;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    var width = 0.0;
    var height = 0.0;
    for (final child in _children) {
      final childSize = child.getDryLayout(const BoxConstraints());
      width += math.max(minimumWidth, childSize.width);
      height = math.max(height, childSize.height);
    }
    width += math.max(0, childCount - 1) * gap;
    return constraints.constrain(Size(math.max(width, availableWidth), height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _DTabListScope<T> extends InheritedWidget {
  const _DTabListScope({
    required this.variant,
    required this.size,
    required this.activateOnFocus,
    this.expandSelected = false,
    required super.child,
  });

  final DTabListVariant variant;
  final DControlSize size;

  final bool activateOnFocus;
  final bool expandSelected;

  static _DTabListScope<T> require<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DTabListScope<T>>();
    assert(scope != null, 'DTabTrigger<$T> must be inside DTabList<$T>.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DTabListScope<T> oldWidget) =>
      ((variant != oldWidget.variant || size != oldWidget.size) ||
      activateOnFocus != oldWidget.activateOnFocus ||
      expandSelected != oldWidget.expandSelected);
}

/// An individual tab button.
///
/// [child] can compose text and a 16px icon. Keep independently interactive
/// controls outside a trigger. Pointer activation retains focus without its
/// outline; keyboard navigation and activation show the focus outline.
/// Borrowed [focusNode] is never disposed.
class DTabTrigger<T> extends StatefulWidget {
  const DTabTrigger({
    super.key,
    required this.value,
    required this.child,

    this.semanticLabel,
    this.icon,
    this.trailing,
    this.selectedLabelOnly = false,
  });

  final T value;
  final Widget child;

  final String? semanticLabel;
  final Widget? icon;
  final Widget? trailing;
  final bool selectedLabelOnly;

  @override
  State<DTabTrigger<T>> createState() => _DTabTriggerState<T>();
}

class _DTabTriggerState<T> extends State<DTabTrigger<T>> {
  final FocusNode _ownedFocusNode = FocusNode();
  _DTabsState<T>? _root;

  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  bool _focusFromPointer = false;

  FocusNode get focusNode => (_ownedFocusNode);
  bool get isEnabled => ((_root?.widget.enabled ?? true));

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final root = _DTabScope.require<T>(context).state;
    if (!identical(root, _root)) {
      _root?.unregister(this);
      _root = root..register(this);
    }
  }

  @override
  void didUpdateWidget(DTabTrigger<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if ((oldWidget.value != widget.value)) {
      _root?._scheduleReconcile();
    }
  }

  @override
  void dispose() {
    _root?.unregister(this);

    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _setFocusFromPointer(bool value) {
    if (_focusFromPointer == value) return;
    setState(() => _focusFromPointer = value);
  }

  bool get _skipsTraversal {
    return (!isEnabled) || !(_root?.isTabStop(this) ?? false);
  }

  /// The flag is written only during build: the root moves the Tab stop from
  /// focus notifications, while the focus manager is still iterating the
  /// nodes it notifies.
  void updateTabStop() {
    if (focusNode.skipTraversal != _skipsTraversal) setState(() {});
  }

  void ensureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          duration: DMotion.duration(context, DMotion.change),
          alignment: .5,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final root = _DTabScope.require<T>(context);
    final list = _DTabListScope.require<T>(context);
    final size = list.size;
    final tokens = DTokens.of(context);
    final selected = root.value == widget.value;
    final enabled = root.enabled;
    focusNode.skipTraversal = _skipsTraversal;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = list.variant == DTabListVariant.line;
    final horizontalLine = line && root.orientation == Axis.horizontal;
    final pill = list.variant == DTabListVariant.pill;
    final outlinePill = list.variant == DTabListVariant.outlinePill;
    final plain = list.variant == DTabListVariant.plain;
    final expanding = list.expandSelected;
    const navigation = false;
    final flat = (pill || outlinePill || plain);
    final radius = expanding || outlinePill || !selected
        ? DRadius.pill
        : DRadius.panel;
    final accent = tokens.buttonTheme.primary;
    final outline = tokens.buttonTheme.outline;
    final selectedBackground = expanding
        ? Color.lerp(tokens.background, tokens.foreground, .03)!
        : outlinePill
        ? (_hovered ? accent.hover : accent.background)
        : pill
        ? tokens.foreground.withValues(alpha: .08)
        : dark
        ? tokens.colors.outlineVariant.withValues(
            alpha: tokens.colors.outlineVariant.a * .3,
          )
        : tokens.background;
    final foreground = outlinePill && selected
        ? accent.foreground
        : selected || (_hovered && !expanding)
        ? tokens.foreground
        : expanding || flat || horizontalLine
        ? tokens.mutedForeground
        : tokens.foreground.withValues(alpha: .6);

    final label = widget.selectedLabelOnly
        ? TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1 : 0),
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 300),
            ),
            curve: Curves.ease,
            child: ExcludeSemantics(
              excluding: widget.semanticLabel != null || !selected,
              child: widget.child,
            ),
            builder: (_, progress, child) => ClipRect(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: progress,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: DControlStyle.gap,
                  ),
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: DMotion.duration(
                      context,
                      const Duration(milliseconds: 200),
                    ),
                    curve: Curves.ease,
                    child: child,
                  ),
                ),
              ),
            ),
          )
        : widget.child;
    final content = widget.icon == null
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.icon!,
              if (!widget.selectedLabelOnly) const SizedBox(width: DSpacing.xs),
              Flexible(child: label),
              if (widget.trailing case final trailing?) ...[
                const SizedBox(width: DControlStyle.gap),
                trailing,
              ],
            ],
          );
    final expandingFill = selected
        ? selectedBackground
        : _hovered
        ? tokens.foreground.withValues(alpha: dark ? .05 : .07)
        : Colors.transparent;
    final surface = AnimatedContainer(
      duration: expanding
          ? DMotion.duration(context, const Duration(milliseconds: 200))
          : flat || horizontalLine
          ? Duration.zero
          : DMotion.duration(context, DMotion.change),
      curve: Curves.easeOut,
      constraints: BoxConstraints(
        minHeight: (expanding
            ? MediaQuery.textScalerOf(context).scale(12.5) * 1.5 + 10
            : horizontalLine
            ? 0
            : DControlStyle.scaledHeight(
                    size,
                    MediaQuery.textScalerOf(context),
                    context: context,
                  ) -
                  (flat ? 0 : 7)),
      ),
      padding: (expanding
          ? const EdgeInsets.symmetric(horizontal: 8)
          : horizontalLine
          ? const EdgeInsets.symmetric(vertical: 11)
          : flat
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5)),
      decoration: BoxDecoration(
        color: expanding
            ? DMaterialSurface.fill(context, expandingFill)
            : (selected && !line && !plain)
            ? selectedBackground
            : outlinePill && _hovered
            ? outline.hover
            : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: horizontalLine || expanding
            ? null
            : Border.all(
                color: outlinePill
                    ? (selected
                          ? Colors.transparent
                          : _hovered
                          ? outline.hoverBorder
                          : outline.border)
                    : selected && !line && !flat && dark
                    ? tokens.colors.outlineVariant
                    : Colors.transparent,
              ),
        boxShadow: selected && !line && !flat && !expanding
            ? const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: AnimatedDefaultTextStyle(
        duration: expanding
            ? DMotion.duration(context, const Duration(milliseconds: 200))
            : Duration.zero,
        curve: Curves.ease,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DefaultTextStyle.of(context).style.merge(
          TextStyle(
            color: foreground,
            fontSize: expanding
                ? 12.5
                : DControlStyle.fontSize(size, context: context),
            height: expanding
                ? 1.5
                : DControlStyle.lineHeight(size, context: context) /
                      DControlStyle.fontSize(size, context: context),
            fontWeight: expanding
                ? (selected ? FontWeight.w600 : FontWeight.w400)
                : horizontalLine
                ? (selected ? FontWeight.w600 : FontWeight.w400)
                : pill
                ? FontWeight.w600
                : FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: foreground),
          duration: expanding
              ? DMotion.duration(context, const Duration(milliseconds: 200))
              : Duration.zero,
          curve: Curves.ease,
          child: Align(
            alignment: root.orientation == Axis.horizontal
                ? Alignment.center
                : AlignmentDirectional.centerStart,
            widthFactor: 1,
            heightFactor: 1,
            child: content,
          ),
          builder: (_, color, child) => IconTheme.merge(
            data: IconThemeData(color: color, size: expanding ? 12.5 : 16),
            child: child!,
          ),
        ),
      ),
    );

    Widget artwork = CustomPaint(
      foregroundPainter: _DTabIndicatorPainter(
        color: tokens.foreground,
        orientation: root.orientation,
        visible: ((line)) && selected,
        topMarker: navigation,
        direction: Directionality.of(context),
      ),
      child: expanding
          ? TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: expandingFill),
              duration: DMotion.duration(
                context,
                const Duration(milliseconds: 200),
              ),
              curve: Curves.ease,
              child: surface,
              builder: (_, color, child) => DMaterialTheme.glassOf(context)
                  ? _DocumentTabMaterial(
                      sidebar: true,
                      selected: selected,
                      hovered: _hovered,
                      radius: BorderRadius.circular(radius),
                      color: Color.lerp(
                        tokens.background,
                        tokens.foreground,
                        .1,
                      )!,
                      child: child!,
                    )
                  : DMaterialSurface(
                      color: color!,
                      radius: BorderRadius.circular(radius),
                      child: child!,
                    ),
            )
          : surface,
    );
    if (_focused && !_focusFromPointer) {
      artwork = CustomPaint(
        foregroundPainter: _DTabFocusPainter(
          color: tokens.focusRing,
          radius: radius,
        ),
        child: artwork,
      );
    }
    if (!enabled) artwork = Opacity(opacity: .5, child: artwork);
    if (widget.selectedLabelOnly && !selected && widget.semanticLabel != null) {
      artwork = DTooltip(
        message: widget.semanticLabel!,
        excludeFromSemantics: true,
        child: artwork,
      );
    }
    final trigger = Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? () => root.state.select(widget.value) : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: focusNode,
        autofocus: false,
        descendantsAreFocusable: false,
        mouseCursor: enabled
            ? expanding && selected
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowHoverHighlight: expanding
            ? null
            : (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onFocusChange: (focused) {
          if (!focused) _setFocusFromPointer(false);
          if (focused) root.state.highlight(this);
          if (focused && list.activateOnFocus) root.state.select(widget.value);
        },
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.space):
              const ActivateIntent(),
          if (root.orientation == Axis.horizontal) ...{
            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                const _MoveTabFocusIntent(LogicalKeyboardKey.arrowLeft),
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                const _MoveTabFocusIntent(LogicalKeyboardKey.arrowRight),
          } else ...{
            const SingleActivator(LogicalKeyboardKey.arrowUp):
                const _MoveTabFocusIntent(LogicalKeyboardKey.arrowUp),
            const SingleActivator(LogicalKeyboardKey.arrowDown):
                const _MoveTabFocusIntent(LogicalKeyboardKey.arrowDown),
          },
          const SingleActivator(LogicalKeyboardKey.home):
              const _MoveTabFocusIntent(LogicalKeyboardKey.home),
          const SingleActivator(LogicalKeyboardKey.end):
              const _MoveTabFocusIntent(LogicalKeyboardKey.end),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _setFocusFromPointer(false);
              root.state.select(widget.value);
              return null;
            },
          ),
          _MoveTabFocusIntent: CallbackAction<_MoveTabFocusIntent>(
            onInvoke: (intent) {
              _setFocusFromPointer(false);
              root.state.moveFocus(
                this,
                intent.key,
                true,
                list.activateOnFocus,
              );
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: expanding && enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: expanding && enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          onTapCancel: expanding && enabled
              ? () => setState(() => _pressed = false)
              : null,
          onTap: enabled
              ? () {
                  // Desktop highlight mode includes mouse focus. Keep the
                  // ring reserved for keyboard use without clearing focus.
                  _setFocusFromPointer(true);
                  focusNode.requestFocus();
                  root.state.select(widget.value);
                }
              : null,
          child: artwork,
        ),
      ),
    );
    return expanding
        ? AnimatedScale(
            scale: _pressed ? (selected ? .95 : .92) : 1,
            duration: DMotion.duration(
              context,
              Duration(milliseconds: _pressed ? 80 : 400),
            ),
            curve: _pressed ? Curves.ease : const Cubic(.34, 1.56, .64, 1),
            child: MouseRegion(
              onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
              onExit: enabled ? (_) => setState(() => _hovered = false) : null,
              child: trigger,
            ),
          )
        : trigger;
  }
}

class _MoveTabFocusIntent extends Intent {
  const _MoveTabFocusIntent(this.key);
  final LogicalKeyboardKey key;
}

class _DTabIndicatorPainter extends CustomPainter {
  const _DTabIndicatorPainter({
    required this.color,
    required this.orientation,
    required this.visible,
    required this.direction,
    this.topMarker = false,
  });
  final Color color;
  final Axis orientation;
  final bool visible;
  final TextDirection direction;
  final bool topMarker;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final paint = Paint()..color = color;
    if (topMarker) {
      final width = math.min(28.0, size.width);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH((size.width - width) / 2, 0, width, 4),
          bottomLeft: const Radius.circular(4),
          bottomRight: const Radius.circular(4),
        ),
        paint,
      );
      return;
    }
    if (orientation == Axis.horizontal) {
      canvas.drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), paint);
    } else {
      final x = direction == TextDirection.ltr ? size.width + 4 : -6.0;
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DTabIndicatorPainter oldDelegate) =>
      color != oldDelegate.color ||
      orientation != oldDelegate.orientation ||
      visible != oldDelegate.visible ||
      topMarker != oldDelegate.topMarker ||
      direction != oldDelegate.direction;
}

class _DTabFocusPainter extends CustomPainter {
  const _DTabFocusPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(.5), Radius.circular(radius + .5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(3), Radius.circular(radius + 3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: color.a * .5),
    );
  }

  @override
  bool shouldRepaint(_DTabFocusPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}

/// Content associated with one [DTabTrigger].
///
/// Hidden content is unmounted by default, matching Base UI. With
/// [maintainState], it remains offstage with ticking and semantics disabled.
/// If selection changes while focus is inside the old panel, focus returns to
/// that panel's trigger instead of escaping unpredictably.
class DTabPanel<T> extends StatefulWidget {
  const DTabPanel({
    super.key,
    required this.value,
    required this.child,

    this.semanticLabel,
  });

  final T value;
  final Widget child;

  final String? semanticLabel;

  @override
  State<DTabPanel<T>> createState() => _DTabPanelState<T>();
}

class _DTabPanelState<T> extends State<DTabPanel<T>> {
  final FocusScopeNode _ownedFocusNode = FocusScopeNode();
  bool _wasActive = false;
  FocusScopeNode get focusNode => (_ownedFocusNode);

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = _DTabScope.require<T>(context);
    final active = root.value == widget.value;
    if (_wasActive && !active && focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) root.state.restoreTriggerFocus(widget.value);
      });
    }
    _wasActive = active;

    Widget panel = Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: FocusScope(node: focusNode, child: widget.child),
    );
    panel = DefaultTextStyle.merge(
      style: const TextStyle(fontSize: DiscourseTypography.sm, height: 20 / 14),
      child: panel,
    );

    return active ? panel : const SizedBox.shrink();
  }
}

/// A controlled, closable document tab for application workspace strips.
///
/// Unlike content tabs, document tabs may be reordered or renamed by their host.
/// The host owns routing and drag handling; this control owns the raised,
/// outlined selected surface, selection and separately focusable close action. Supply an
/// [editor] while renaming to keep its field outside the selection gesture.
class DDocumentTab extends StatefulWidget {
  const DDocumentTab({
    super.key,
    required this.selected,
    required this.child,
    required this.onSelect,
    required this.onClose,
    required this.closeLabel,
    this.closeShortcut,

    this.onDoubleTap,
    this.onTapDown,
    this.onTapCancel,
    this.editor,

    this.excludeSelectionSemantics = false,
    this.surfaceKey,
    this.pointerKey,
    this.closeKey,
    this.size = DControlSize.regular,
  }) : assert(size == DControlSize.regular || size == DControlSize.documentTab);

  final bool selected;
  final Widget child;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final String closeLabel;

  final DShortcut? closeShortcut;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapCancelCallback? onTapCancel;
  final Widget? editor;

  /// Whether the host already supplies the tab selection semantics.
  /// The close action always retains its own semantics.
  final bool excludeSelectionSemantics;
  final Key? surfaceKey;
  final Key? pointerKey;
  final Key? closeKey;

  /// Use [DControlSize.documentTab] for the mockup workspace strip.
  final DControlSize size;

  @override
  State<DDocumentTab> createState() => _DDocumentTabState();
}

class _DDocumentTabState extends State<DDocumentTab> {
  bool _hovered = false;
  late final _selectionFocus = FocusNode(
    onKeyEvent: (_, event) {
      // A drag or double click can consume the button's pointer activation.
      // Keyboard activation must not inherit the host's pointer-down selection.
      if (event is KeyDownEvent) widget.onTapCancel?.call();
      return KeyEventResult.ignored;
    },
  );
  final _closeFocus = FocusNode();

  @override
  void dispose() {
    _selectionFocus.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    Color mix(double amount) =>
        Color.lerp(tokens.background, tokens.foreground, amount)!;
    final foreground = widget.selected ? mix(.9) : mix(.5);
    final glass = DMaterialTheme.glassOf(context);
    final radius = BorderRadius.circular(
      widget.selected && widget.size != DControlSize.documentTab
          ? DRadius.panel
          : DRadius.pill,
    );
    final fontSize = DControlStyle.fontSize(
      DControlSize.regular,
      context: context,
    );
    // Tab labels use the regular control role even though the select target
    // is a small button, whose own text style would otherwise win.
    final labelStyle = TextStyle(
      fontSize: fontSize,
      height:
          DControlStyle.lineHeight(DControlSize.regular, context: context) /
          fontSize,
      fontWeight: FontWeight.w400,
    );
    return MouseRegion(
      key: widget.pointerKey,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _DocumentTabMaterial(
        selected: widget.selected,
        hovered: _hovered,
        radius: radius,
        color: mix(.10),
        child: Container(
          key: widget.surfaceKey,
          height: DControlStyle.scaledHeight(
            widget.size,
            MediaQuery.textScalerOf(context),
            context: context,
          ),
          // The outline supplies the other pixel of the compact outer inset.
          padding: const EdgeInsetsDirectional.only(start: 1, end: 10),
          decoration: ShapeDecoration(
            color: widget.selected && !glass ? mix(.10) : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: (BorderSide(
                color: widget.selected && !glass
                    ? mix(.22)
                    : Colors.transparent,
                strokeAlign: BorderSide.strokeAlignInside,
              )),
            ),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: DefaultTextStyle.merge(
              style: labelStyle.copyWith(color: foreground),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child:
                        widget.editor ??
                        ExcludeSemantics(
                          excluding: widget.excludeSelectionSemantics,
                          child: MergeSemantics(
                            child: Semantics(
                              selected: widget.selected,
                              child: GestureDetector(
                                onDoubleTap: widget.onDoubleTap,
                                excludeFromSemantics: true,
                                child: Listener(
                                  onPointerDown: (event) {
                                    if (event.buttons != kPrimaryButton) return;
                                    widget.onTapDown?.call(
                                      TapDownDetails(
                                        globalPosition: event.position,
                                        localPosition: event.localPosition,
                                        kind: event.kind,
                                      ),
                                    );
                                  },
                                  onPointerCancel: (_) =>
                                      widget.onTapCancel?.call(),
                                  child: DButton(
                                    onPressed: widget.onSelect,
                                    size:
                                        widget.size == DControlSize.documentTab
                                        ? DControlSize.documentTab
                                        : DButtonSize.small,
                                    focusNode: _selectionFocus,
                                    variant: DButtonVariant.ghost,
                                    alignment: AlignmentDirectional.centerStart,
                                    backgroundColor: Colors.transparent,
                                    interactiveBackgroundColor:
                                        Colors.transparent,
                                    foregroundColor: foreground,
                                    label: DefaultTextStyle.merge(
                                      style: labelStyle,
                                      child: widget.child,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                  ListenableBuilder(
                    listenable: _closeFocus,
                    builder: (context, _) => AnimatedOpacity(
                      opacity:
                          widget.selected ||
                              _hovered ||
                              _closeFocus.hasFocus ||
                              DControlStyle.isTouch(context)
                          ? 1
                          : 0,
                      alwaysIncludeSemantics: true,
                      duration: DMotion.duration(context, DMotion.change),
                      child: Center(
                        widthFactor: 1,
                        child: DButton.iconOnly(
                          key: widget.closeKey,
                          tooltip: widget.closeLabel,
                          shortcut: widget.closeShortcut,
                          focusNode: _closeFocus,
                          size: widget.size == DControlSize.documentTab
                              ? DControlSize.tabClose
                              : DButtonSize.small,
                          variant: DButtonVariant.inline,
                          backgroundColor: Colors.transparent,
                          interactiveBackgroundColor: Colors.transparent,
                          foregroundColor: mix(.5),
                          icon: const DIcon(DIcons.xmark),
                          onPressed: widget.onClose,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mockup's tab-specific glass: thinner than ordinary raised controls.
/// Paint stays behind the stable controls, so material changes retain focus.
class _DocumentTabMaterial extends StatelessWidget {
  const _DocumentTabMaterial({
    required this.selected,
    required this.hovered,
    required this.radius,
    required this.color,
    required this.child,
    this.sidebar = false,
  });

  final bool selected;
  final bool hovered;
  final BorderRadius radius;
  final Color color;
  final Widget child;
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final glass = DMaterialTheme.glassOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final visible = glass && (selected || hovered);
    // app.css: selected .42/.50 tint, inactive document hover .22 and
    // sidebar bare hover .28. Only selection samples the softened backdrop.
    final highlight = sidebar && hovered
        ? (selected ? (dark ? .22 : .75) : (dark ? .12 : .55))
        : hovered
        ? .22
        : (dark ? .12 : .55);
    return CustomPaint(
      painter: glass && selected ? _DocumentTabShadow(radius, dark) : null,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: radius,
                  child: BackdropFilter(
                    enabled: glass && selected,
                    filter: ui.ImageFilter.compose(
                      outer:
                          // CSS saturation matrix, using sRGB luminance.
                          const ColorFilter.matrix([
                            1.66895,
                            -.60775,
                            -.0612,
                            0,
                            0,
                            -.18105,
                            1.24225,
                            -.0612,
                            0,
                            0,
                            -.18105,
                            -.60775,
                            1.7888,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ]),
                      inner: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    ),
                    child: sidebar
                        ? TweenAnimationBuilder<Color?>(
                            tween: ColorTween(
                              end: color.withValues(
                                alpha: !visible
                                    ? 0
                                    : selected
                                    ? (dark ? .42 : .5)
                                    : .28,
                              ),
                            ),
                            duration: DMotion.duration(
                              context,
                              const Duration(milliseconds: 200),
                            ),
                            curve: Curves.ease,
                            builder: (_, tint, _) {
                              final strength =
                                  (tint!.a /
                                          (selected ? (dark ? .42 : .5) : .28))
                                      .clamp(0.0, 1.0);
                              return CustomPaint(
                                painter: _DocumentTabGlassPaint(
                                  radius: radius,
                                  tint: tint,
                                  rim: Colors.white.withValues(
                                    alpha: (dark ? .14 : .75) * strength,
                                  ),
                                  highlight: highlight * strength,
                                  bare: !selected,
                                ),
                              );
                            },
                          )
                        : CustomPaint(
                            painter: visible
                                ? _DocumentTabGlassPaint(
                                    radius: radius,
                                    tint: color.withValues(
                                      alpha:
                                          color.a *
                                          (selected ? (dark ? .42 : .5) : .22),
                                    ),
                                    rim: Colors.white.withValues(
                                      alpha: dark ? .14 : .75,
                                    ),
                                    highlight: selected ? highlight : 0,
                                  )
                                : null,
                          ),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _DocumentTabShadow extends CustomPainter {
  const _DocumentTabShadow(this.radius, this.dark);
  final BorderRadius radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    // CSS outer shadows leave the border box clear. A normal BoxShadow
    // would show through the translucent tab and pollute its own backdrop.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(30))
      ..addRRect(shape);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(
      shape.shift(const Offset(0, 4)),
      const BoxShadow(blurRadius: 14)
          .copyWith(color: Colors.black.withValues(alpha: dark ? .2 : .08))
          .toPaint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DocumentTabShadow old) =>
      radius != old.radius || dark != old.dark;
}

class _DocumentTabGlassPaint extends CustomPainter {
  const _DocumentTabGlassPaint({
    required this.radius,
    required this.tint,
    required this.rim,
    required this.highlight,
    this.bare = false,
  });

  final BorderRadius radius;
  final Color tint;
  final Color rim;
  final double highlight;
  final bool bare;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    canvas.drawRRect(shape, Paint()..color = tint);
    if (highlight > 0) {
      canvas.save();
      canvas.clipRRect(shape);
      // CSS's explicit elliptical radial gradient, fading at 62%.
      canvas.translate(
        size.width * (bare ? .5 : .35),
        size.height * (bare ? 0 : -.25),
      );
      canvas.scale(size.width * 1.2, size.height * 1.1);
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            1,
            [Colors.white.withValues(alpha: highlight), Colors.transparent],
            [0, .62],
          ),
      );
      canvas.restore();
      // Inset catches along the upper and lower edge, clipped to the capsule.
      canvas.save();
      canvas.clipRRect(shape);
      for (final (offset, blur, color) in [
        (
          const Offset(0, 1),
          1.0,
          Colors.white.withValues(alpha: highlight * (bare ? 1.4 : 1.8)),
        ),
        if (!bare)
          (const Offset(0, -1), 2.0, Colors.black.withValues(alpha: .1)),
      ]) {
        final outside = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(20))
          ..addRRect(shape.shift(offset));
        canvas.drawPath(
          outside,
          Paint()
            ..color = color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
        );
      }
      canvas.restore();
    }
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DocumentTabGlassPaint old) =>
      radius != old.radius ||
      tint != old.tint ||
      rim != old.rim ||
      highlight != old.highlight ||
      bare != old.bare;
}
