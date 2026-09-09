import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// The visual treatment of a [DTabList].
enum DTabListVariant { defaultStyle, line }

/// Why a tabs root changed its active value.
enum DTabChangeReason { user, initial, disabled, missing, controller }

@immutable
class DTabChange<T> {
  const DTabChange({required this.value, required this.reason});

  final T? value;
  final DTabChangeReason reason;

  @override
  bool operator ==(Object other) =>
      other is DTabChange<T> && value == other.value && reason == other.reason;

  @override
  int get hashCode => Object.hash(value, reason);
}

/// Optional imperative selection owner for [DTabs].
///
/// The widget never disposes a borrowed controller. Set [value] to select a
/// tab from application routing, or call [clear] to leave every panel hidden.
class DTabController<T> extends ChangeNotifier {
  DTabController([T? value]) : _value = value;

  T? _value;
  T? get value => _value;

  set value(T? next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }

  void clear() => value = null;
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
    this.initialValue,
    this.controller,
    this.onChanged,
    this.onSelectionChanged,
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
    this.onSelectionChanged,
    this.orientation = Axis.horizontal,
    this.enabled = true,
  }) : initialValue = null,
       controller = null,
       selectFirstOnMount = false,
       _controlled = true;

  final List<Widget> children;
  final T? initialValue;
  final T? value;
  final DTabController<T>? controller;
  final ValueChanged<T?>? onChanged;
  final ValueChanged<DTabChange<T>>? onSelectionChanged;
  final Axis orientation;
  final bool enabled;
  final bool selectFirstOnMount;
  final bool _controlled;

  @override
  State<DTabs<T>> createState() => _DTabsState<T>();
}

class _DTabsState<T> extends State<DTabs<T>> {
  final List<_DTabTriggerState<T>> _triggers = [];
  late T? _value = widget.initialValue;
  _DTabTriggerState<T>? _highlightedTrigger;
  T? _highlightedForValue;
  bool _reconcileScheduled = false;
  bool _updatingController = false;

  T? get value =>
      widget._controlled ? widget.value : widget.controller?.value ?? _value;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(DTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?.removeListener(_controllerChanged);
      widget.controller?.addListener(_controllerChanged);
    }
    _scheduleReconcile();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleReconcile();
    if (!_updatingController) {
      widget.onSelectionChanged?.call(
        DTabChange(value: value, reason: DTabChangeReason.controller),
      );
    }
  }

  void register(_DTabTriggerState<T> trigger) {
    if (_triggers.contains(trigger)) return;
    assert(
      !_triggers.any((item) => item.widget.value == trigger.widget.value),
      'DTabTrigger values must be unique within a DTabs root.',
    );
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
    final enabled = _orderedTriggers().where((item) => item.isEnabled).toList();
    final selected = _triggers.where((item) => item.widget.value == value);
    final selectedTrigger = selected.firstOrNull;
    _reconcileHighlight(enabled, selectedTrigger);
    if (widget._controlled) return;
    if (selectedTrigger != null && selectedTrigger.isEnabled) return;

    if (value == null && !widget.selectFirstOnMount) return;
    final reason = selectedTrigger == null
        ? value == null
              ? DTabChangeReason.initial
              : DTabChangeReason.missing
        : DTabChangeReason.disabled;
    _setValue(enabled.firstOrNull?.widget.value, reason: reason);
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
    if (identical(next, _highlightedTrigger)) return;
    setState(() => _highlightedTrigger = next);
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
    setState(() {
      _highlightedTrigger = trigger;
      _highlightedForValue = value;
    });
  }

  void select(T value) {
    final trigger = _triggers
        .where((candidate) => candidate.widget.value == value)
        .firstOrNull;
    if (!widget.enabled || trigger == null || !trigger.isEnabled) return;
    _setValue(value, reason: DTabChangeReason.user);
  }

  void _setValue(T? next, {required DTabChangeReason reason}) {
    if (value == next) return;
    if (!widget._controlled) {
      if (widget.controller case final controller?) {
        _updatingController = true;
        controller.value = next;
        _updatingController = false;
      } else {
        setState(() => _value = next);
      }
    }
    widget.onChanged?.call(next);
    widget.onSelectionChanged?.call(DTabChange(value: next, reason: reason));
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
    this.variant = DTabListVariant.defaultStyle,
    this.activateOnFocus = false,
    this.loopFocus = true,
    this.scrollController,
  });

  final List<Widget> children;
  final DTabListVariant variant;
  final bool activateOnFocus;
  final bool loopFocus;

  /// An optional borrowed controller for horizontal overflow.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final root = _DTabScope.require<T>(context);
    final tokens = DTokens.of(context);
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final decoration = BoxDecoration(
      color: variant == DTabListVariant.defaultStyle
          ? tokens.muted
          : Colors.transparent,
      borderRadius: variant == DTabListVariant.defaultStyle
          ? BorderRadius.circular(tokens.radius)
          : BorderRadius.zero,
    );
    final scope = _DTabListScope<T>(
      variant: variant,
      activateOnFocus: activateOnFocus,
      loopFocus: loopFocus,
      child: Flex(
        direction: root.orientation,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: root.orientation == Axis.horizontal
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && variant == DTabListVariant.line)
              SizedBox(
                width: root.orientation == Axis.horizontal ? 4 : 0,
                height: root.orientation == Axis.vertical ? 4 : 0,
              ),
            children[i],
          ],
        ],
      ),
    );

    Widget visual = Container(
      constraints: BoxConstraints(
        minHeight: root.orientation == Axis.horizontal ? 32 : 0,
      ),
      padding: const EdgeInsets.all(3),
      decoration: decoration,
      child: scope,
    );
    if (root.orientation == Axis.horizontal) {
      visual = Container(
        constraints: BoxConstraints(
          minHeight: touch ? DSpacing.touchTarget : 32,
        ),
        alignment: Alignment.center,
        child: visual,
      );
      visual = SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        child: visual,
      );
    } else {
      visual = IntrinsicWidth(child: visual);
    }
    return Semantics(container: true, explicitChildNodes: true, child: visual);
  }
}

class _DTabListScope<T> extends InheritedWidget {
  const _DTabListScope({
    required this.variant,
    required this.activateOnFocus,
    required this.loopFocus,
    required super.child,
  });

  final DTabListVariant variant;
  final bool activateOnFocus;
  final bool loopFocus;

  static _DTabListScope<T> require<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DTabListScope<T>>();
    assert(scope != null, 'DTabTrigger<$T> must be inside DTabList<$T>.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DTabListScope<T> oldWidget) =>
      variant != oldWidget.variant ||
      activateOnFocus != oldWidget.activateOnFocus ||
      loopFocus != oldWidget.loopFocus;
}

/// An individual tab button.
///
/// [child] can compose text and a 16px icon. Keep independently interactive
/// controls outside a trigger. Borrowed [focusNode] is never disposed.
class DTabTrigger<T> extends StatefulWidget {
  const DTabTrigger({
    super.key,
    required this.value,
    required this.child,
    this.enabled = true,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
  });

  final T value;
  final Widget child;
  final bool enabled;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<DTabTrigger<T>> createState() => _DTabTriggerState<T>();
}

class _DTabTriggerState<T> extends State<DTabTrigger<T>> {
  final FocusNode _ownedFocusNode = FocusNode();
  _DTabsState<T>? _root;
  bool? _borrowedSkipTraversal;
  bool _hovered = false;
  bool _focused = false;

  FocusNode get focusNode => widget.focusNode ?? _ownedFocusNode;
  bool get isEnabled => widget.enabled && (_root?.widget.enabled ?? true);

  @override
  void initState() {
    super.initState();
    _borrowedSkipTraversal = widget.focusNode?.skipTraversal;
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
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      if (oldWidget.focusNode case final old?) {
        old.skipTraversal = _borrowedSkipTraversal ?? false;
      }
      _borrowedSkipTraversal = widget.focusNode?.skipTraversal;
    }
    if (oldWidget.value != widget.value ||
        oldWidget.enabled != widget.enabled) {
      _root?._scheduleReconcile();
    }
  }

  @override
  void dispose() {
    _root?.unregister(this);
    if (widget.focusNode case final borrowed?) {
      borrowed.skipTraversal = _borrowedSkipTraversal ?? false;
    }
    _ownedFocusNode.dispose();
    super.dispose();
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
    final tokens = DTokens.of(context);
    final selected = root.value == widget.value;
    final enabled = widget.enabled && root.enabled;
    final originalSkip = widget.focusNode == null
        ? false
        : _borrowedSkipTraversal ?? false;
    focusNode.skipTraversal =
        originalSkip || !root.state.isTabStop(this) || !enabled;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = list.variant == DTabListVariant.line;
    final radius = tokens.radius * .8;
    final selectedBackground = dark
        ? tokens.colors.outlineVariant.withValues(
            alpha: tokens.colors.outlineVariant.a * .3,
          )
        : tokens.background;
    final foreground = enabled
        ? selected || _hovered
              ? tokens.foreground
              : tokens.foreground.withValues(alpha: .6)
        : tokens.foreground.withValues(alpha: .3);

    final surface = AnimatedContainer(
      duration: DMotion.duration(context, DMotion.change),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minHeight: 25),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: selected && !line ? selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected && !line && dark
              ? tokens.colors.outlineVariant
              : Colors.transparent,
        ),
        boxShadow: selected && !line
            ? [
                BoxShadow(
                  color: tokens.foreground.withValues(alpha: .08),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: DefaultTextStyle.merge(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: DiscourseTypography.sm,
          height: 20 / 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground, size: 16),
          child: widget.child,
        ),
      ),
    );

    Widget artwork = CustomPaint(
      foregroundPainter: _DTabIndicatorPainter(
        color: tokens.foreground,
        orientation: root.orientation,
        visible: line && selected,
        direction: Directionality.of(context),
      ),
      child: surface,
    );
    if (_focused) {
      artwork = CustomPaint(
        foregroundPainter: _DTabFocusPainter(
          color: tokens.focusRing,
          radius: radius,
        ),
        child: artwork,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? () => root.state.select(widget.value) : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: focusNode,
        autofocus: widget.autofocus,
        descendantsAreFocusable: false,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onFocusChange: (focused) {
          if (focused) root.state.highlight(this);
          if (focused && list.activateOnFocus) root.state.select(widget.value);
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveTabFocusIntent(
            LogicalKeyboardKey.arrowLeft,
          ),
          SingleActivator(LogicalKeyboardKey.arrowRight): _MoveTabFocusIntent(
            LogicalKeyboardKey.arrowRight,
          ),
          SingleActivator(LogicalKeyboardKey.arrowUp): _MoveTabFocusIntent(
            LogicalKeyboardKey.arrowUp,
          ),
          SingleActivator(LogicalKeyboardKey.arrowDown): _MoveTabFocusIntent(
            LogicalKeyboardKey.arrowDown,
          ),
          SingleActivator(LogicalKeyboardKey.home): _MoveTabFocusIntent(
            LogicalKeyboardKey.home,
          ),
          SingleActivator(LogicalKeyboardKey.end): _MoveTabFocusIntent(
            LogicalKeyboardKey.end,
          ),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              root.state.select(widget.value);
              return null;
            },
          ),
          _MoveTabFocusIntent: CallbackAction<_MoveTabFocusIntent>(
            onInvoke: (intent) {
              root.state.moveFocus(
                this,
                intent.key,
                list.loopFocus,
                list.activateOnFocus,
              );
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: enabled
              ? () {
                  focusNode.requestFocus();
                  root.state.select(widget.value);
                }
              : null,
          child: artwork,
        ),
      ),
    );
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
  });
  final Color color;
  final Axis orientation;
  final bool visible;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final paint = Paint()..color = color;
    if (orientation == Axis.horizontal) {
      canvas.drawRect(Rect.fromLTWH(0, size.height + 4, size.width, 2), paint);
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
    this.maintainState = false,
    this.focusNode,
    this.semanticLabel,
  });

  final T value;
  final Widget child;
  final bool maintainState;
  final FocusScopeNode? focusNode;
  final String? semanticLabel;

  @override
  State<DTabPanel<T>> createState() => _DTabPanelState<T>();
}

class _DTabPanelState<T> extends State<DTabPanel<T>> {
  final FocusScopeNode _ownedFocusNode = FocusScopeNode();
  bool _wasActive = false;
  FocusScopeNode get focusNode => widget.focusNode ?? _ownedFocusNode;

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
    if (widget.maintainState) {
      return Offstage(
        offstage: !active,
        child: TickerMode(enabled: active, child: panel),
      );
    }
    return active ? panel : const SizedBox.shrink();
  }
}
