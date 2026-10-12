import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/focus_highlight.dart';
import '../foundation/tokens.dart';
import 'd_direction.dart';

/// Explicit v4 sizing units. Pixels are Flutter logical pixels; percentages
/// refer to the group's panel space (excluding its one-pixel dividers).
@immutable
class DResizableSize {
  const DResizableSize.pixels(this.value)
    : percentage = false,
      assert(value >= 0 && value < double.infinity);
  const DResizableSize.percent(this.value)
    : percentage = true,
      assert(value >= 0 && value <= 100);
  final double value;
  final bool percentage;
  double resolve(double extent) => percentage ? extent * value / 100 : value;
}

/// Immutable sizes keyed by stable panel ID, in logical pixels.
typedef DResizableLayout = Map<String, double>;

/// Direct children alternate panels and handles. IDs preserve widget state and
/// size through reorder; removed IDs are forgotten, inserted IDs use defaults.
class DResizablePanel extends StatelessWidget {
  const DResizablePanel({
    super.key,
    required this.id,
    required this.child,

    this.minSize = const DResizableSize.pixels(0),
  });
  final String id;
  final Widget child;

  final DResizableSize minSize;

  @override
  Widget build(BuildContext context) => child;
}

/// Bounded horizontal/vertical layout. Constraints that cannot fit are retained:
/// excess minimum space is clipped; excess maximum space is left empty. Hosts
/// should switch responsive modes before reaching infeasible constraints.
/// [layout] is controlled: callbacks propose pixels, the parent supplies sizes.
/// Without it, the group owns sizes. Persistence belongs in the caller.
class DResizablePanelGroup extends StatefulWidget {
  const DResizablePanelGroup({
    super.key,
    required this.children,
    this.orientation = Axis.horizontal,

    this.layout,
    this.onLayoutChange,
    this.onLayoutChanged,
  });
  final List<Widget> children;
  final Axis orientation;

  final Map<String, DResizableSize>? layout;
  final ValueChanged<DResizableLayout>? onLayoutChange, onLayoutChanged;

  @override
  State<DResizablePanelGroup> createState() => _DResizablePanelGroupState();
}

class _DResizablePanelGroupState extends State<DResizablePanelGroup> {
  Map<String, double> _sizes = {};

  double _extent = 0;
  Map<String, double>? _reported;
  double _reportedExtent = 0;
  bool _reportScheduled = false;
  Map<String, double>? _dragOrigin;
  double _dragTotal = 0;
  List<DResizablePanel> get _panels =>
      widget.children.whereType<DResizablePanel>().toList();
  @override
  void didUpdateWidget(DResizablePanelGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orientation != widget.orientation ||
        !listEquals(
          oldWidget.children
              .whereType<DResizablePanel>()
              .map((p) => p.id)
              .toList(),
          _panels.map((p) => p.id).toList(),
        )) {
      _dragOrigin = null;
      _dragTotal = 0;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  DResizablePanel _panel(String id) => _panels.firstWhere(
    (p) => p.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown panel'),
  );
  double _min(DResizablePanel p) => p.minSize.resolve(_extent);
  double _max(DResizablePanel p) =>
      math.max(_min(p), const DResizableSize.percent(100).resolve(_extent));

  double _clamp(DResizablePanel p, double value) {
    return value.clamp(_min(p), _max(p)).toDouble();
  }

  Map<String, double> _fit(Map<String, double> requested) {
    final ps = _panels;
    final result = {
      for (final p in ps)
        p.id: _clamp(p, requested[p.id] ?? _extent / ps.length),
    };
    for (var pass = 0; pass < ps.length * 2 + 1; pass++) {
      final remainder = _extent - result.values.fold(0.0, (a, b) => a + b);
      if (remainder.abs() < .001) break;
      var eligible = ps
          .where(
            (p) => ((remainder > 0
                ? (result[p.id]! < _max(p))
                : result[p.id]! > _min(p))),
          )
          .toList();
      final relative = eligible.where((p) => !false).toList();
      if (relative.isNotEmpty) eligible = relative;
      if (eligible.isEmpty) break;
      for (final p in eligible) {
        result[p.id] = (result[p.id]! + remainder / eligible.length)
            .clamp(_min(p), _max(p))
            .toDouble();
      }
    }
    return result;
  }

  void _publish(Map<String, double> next, {bool commit = true}) {
    if (mapEquals(next, _sizes)) return;

    final snapshot = Map<String, double>.unmodifiable(next);
    if (widget.layout != null) {
      widget.onLayoutChange?.call(snapshot);
      if (commit && mounted) widget.onLayoutChanged?.call(snapshot);
      return;
    }
    setState(() => _sizes = next);
    _report(snapshot, commit: commit);
  }

  void _report(Map<String, double> snapshot, {bool commit = true}) {
    final previous = _reported;
    final previousExtent = _reportedExtent;
    _reported = Map.of(snapshot);
    _reportedExtent = _extent;
    for (final p in _panels) {
      if (!mounted) return;
      if (previous?[p.id] == snapshot[p.id] && previousExtent == _extent) {
        continue;
      }
    }
    if (!mounted) return;
    widget.onLayoutChange?.call(Map.unmodifiable(snapshot));
    if (commit && mounted) {
      widget.onLayoutChanged?.call(Map.unmodifiable(snapshot));
    }
  }

  void _scheduleReport() {
    if (_reportScheduled ||
        (mapEquals(_reported, _sizes) && _reportedExtent == _extent)) {
      return;
    }
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted ||
          (mapEquals(_reported, _sizes) && _reportedExtent == _extent)) {
        return;
      }
      _report(Map.of(_sizes));
    });
  }

  void _resizePanel(String id, DResizableSize size) {
    final ps = _panels;
    final index = ps.indexWhere((p) => p.id == id);
    final p = _panel(id);

    final others = [...ps.skip(index + 1), ...ps.take(index).toList().reversed];
    _publish(
      _transfer([p], others, _clamp(p, size.resolve(_extent)) - _sizes[id]!),
    );
  }

  // Nearest panels absorb movement first; saturated/disabled panels pass the
  // remainder to more distant panels on the same side of the separator.
  Map<String, double> _transfer(
    List<DResizablePanel> before,
    List<DResizablePanel> after,
    double delta,
  ) {
    if (delta == 0) return Map.of(_sizes);
    final grow = delta > 0 ? before : after;
    final shrink = delta > 0 ? after : before;
    double capacity(List<DResizablePanel> ps, bool growing) => ps.fold(
      0.0,
      (sum, p) =>
          sum +
          ((growing ? _max(p) - _sizes[p.id]! : _sizes[p.id]! - ((_min(p))))),
    );
    final growCapacity = capacity(grow, true);
    final shrinkCapacity = capacity(shrink, false);
    var requested = delta.abs();

    final amount = math.min(requested, math.min(growCapacity, shrinkCapacity));
    Map<String, double> apply(
      List<DResizablePanel> ps,
      bool growing,
      double requested,
      double available,
    ) {
      final out = <String, double>{};
      var usedTotal = 0.0;
      for (final p in ps) {
        if ((usedTotal >= requested)) continue;
        final old = _sizes[p.id]!;
        final target = _clamp(
          p,
          old + (growing ? 1 : -1) * (requested - usedTotal),
        );
        final used = (target - old).abs();
        // A discrete snap may exceed pointer distance, but never the capacity
        // of the other side. Distance and capacity are deliberately separate.
        if (usedTotal + used > available + .001) continue;
        out[p.id] = target;
        usedTotal += used;
      }
      return out;
    }

    final shrinking = apply(shrink, false, amount, growCapacity);
    final shrunk = shrinking.entries.fold(
      0.0,
      (sum, e) => sum + _sizes[e.key]! - e.value,
    );
    final growing = apply(grow, true, shrunk, shrunk);
    final grown = growing.entries.fold(
      0.0,
      (sum, e) => sum + e.value - _sizes[e.key]!,
    );
    if ((grown - shrunk).abs() < .001) {
      return {..._sizes, ...shrinking, ...growing};
    }
    return Map.of(_sizes);
  }

  void _drag(int index, double delta, {bool keyboard = false}) {
    final ps = _panels;
    final current = _sizes;
    if (keyboard) {
      _dragOrigin = Map.of(_sizes);
      _dragTotal = 0;
    }
    _dragOrigin ??= Map.of(_sizes);
    _dragTotal += delta;
    _sizes = _dragOrigin!;
    final next = _transfer(
      ps.take(index + 1).toList().reversed.toList(),
      ps.skip(index + 1).toList(),
      _dragTotal,
    );
    _sizes = current;
    _publish(next, commit: false);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
        throw FlutterError(
          'DResizablePanelGroup requires bounded width and height.',
        );
      }
      if (widget.children.isEmpty ||
          widget.children.length.isEven ||
          !widget.children.asMap().entries.every(
            (e) => e.key.isEven
                ? e.value is DResizablePanel
                : e.value is DResizableHandle,
          )) {
        throw FlutterError(
          'Alternate DResizablePanel and DResizableHandle children, starting and ending with a panel.',
        );
      }
      final ps = _panels;
      if (ps.map((p) => p.id).toSet().length != ps.length) {
        throw FlutterError('Panel IDs must be unique.');
      }
      final horizontal = widget.orientation == Axis.horizontal;
      final oldExtent = _extent;
      _extent = math.max(
        0,
        (horizontal ? constraints.maxWidth : constraints.maxHeight) -
            ps.length +
            1,
      );
      if (oldExtent != _extent) {
        _dragOrigin = null;
        _dragTotal = 0;
      }
      final requested = <String, double>{};
      for (final p in ps) {
        final previous = _sizes[p.id];
        requested[p.id] =
            widget.layout?[p.id]?.resolve(_extent) ??
            (previous == null
                ? (_extent / ps.length)
                : (oldExtent > 0)
                ? previous * _extent / oldExtent
                : previous);
      }
      final automatic = ps
          .where(
            (p) => (!_sizes.containsKey(p.id)) && widget.layout?[p.id] == null,
          )
          .toList();
      if (automatic.isNotEmpty) {
        final explicit = requested.entries
            .where((e) => !automatic.any((p) => p.id == e.key))
            .fold(0.0, (sum, e) => sum + e.value);
        for (final p in automatic) {
          requested[p.id] = math.max(
            0,
            (_extent - explicit) / automatic.length,
          );
        }
      }
      _sizes = _fit(requested);
      _scheduleReport();

      final children = <Widget>[];
      var position = 0.0;
      final rtl = horizontal && DDirection.of(context) == TextDirection.rtl;
      Widget positioned(Widget child, double start, double extent) => horizontal
          ? Positioned(
              key: child.key,
              left: rtl ? null : start,
              right: rtl ? start : null,
              top: 0,
              bottom: 0,
              width: extent,
              child: child,
            )
          : Positioned(
              key: child.key,
              top: start,
              left: 0,
              right: 0,
              height: extent,
              child: child,
            );
      final handles = <Widget>[];
      for (var i = 0; i < ps.length; i++) {
        final p = ps[i], size = _sizes[ps[i].id]!;
        children.add(
          positioned(
            KeyedSubtree(
              key: ValueKey(p.id),
              child: ClipRect(
                child: ExcludeFocus(
                  excluding: size == 0,
                  child: ExcludeSemantics(excluding: size == 0, child: p),
                ),
              ),
            ),
            position,
            size,
          ),
        );
        position += size;
        if (i == ps.length - 1) continue;
        final h = widget.children[i * 2 + 1] as DResizableHandle;
        if (h.onChanged != null) {
          throw FlutterError(
            'Use the group DResizableHandle constructor inside a group.',
          );
        }
        final handleIndex = i;
        final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final hit = math.min(
          total,
          DResizableHandle.visualExtent(
            withHandle: h.withHandle,
            dividerThickness: h.dividerThickness,
          ),
        );
        final handleStart = (position + .5 - hit / 2)
            .clamp(0.0, math.max(0.0, total - hit))
            .toDouble();
        final logicalOffset = position + .5 - handleStart;
        final paintOffset = rtl ? hit - logicalOffset : logicalOffset;
        final before = ps.take(i + 1).toList().reversed.toList();
        final after = ps.skip(i + 1).toList();
        double positionIn(Map<String, double> sizes) =>
            before.fold(0.0, (sum, p) => sum + sizes[p.id]!);
        final handleValue = positionIn(_sizes);
        final handleMin = positionIn(_transfer(before, after, -_extent));
        final handleMax = positionIn(_transfer(before, after, _extent));
        handles.add(
          positioned(
            _HandleBinding(
              paintOffset: paintOffset,
              orientation: widget.orientation,
              value: handleValue,
              min: handleMin,
              max: handleMax,
              increase: positionIn(_transfer(before, after, h.keyboardStep)),
              decrease: positionIn(_transfer(before, after, -h.keyboardStep)),
              disabled: (handleMax - handleMin < .001),
              onDelta: (d) => _drag(handleIndex, d),
              onKeyboardDelta: (d) => _drag(handleIndex, d, keyboard: true),
              onCommit: () {
                _dragOrigin = null;
                _dragTotal = 0;
                widget.onLayoutChanged?.call(Map.unmodifiable(_sizes));
              },

              onReset: () =>
                  _resizePanel(p.id, (DResizableSize.percent(100 / ps.length))),
              child: h,
            ),
            handleStart,
            hit,
          ),
        );
        position += 1;
      }
      return ClipRect(child: Stack(children: [...children, ...handles]));
    },
  );
}

class _HandleBinding extends InheritedWidget {
  const _HandleBinding({
    required this.orientation,
    required this.value,
    required this.min,
    required this.max,
    required this.disabled,
    required this.onDelta,
    required this.onKeyboardDelta,
    required this.paintOffset,
    required this.increase,
    required this.decrease,
    required this.onCommit,

    this.onReset,
    required super.child,
  });
  final Axis orientation;
  final double value, min, max, increase, decrease;
  final bool disabled;
  final ValueChanged<double> onDelta, onKeyboardDelta;
  final double paintOffset;
  final VoidCallback onCommit;
  final VoidCallback? onReset;
  @override
  bool updateShouldNotify(_HandleBinding oldWidget) => true;
}

/// Group separator, or standalone handle for app-owned pixel geometry. The
/// standalone mode shares all interaction/painting with grouped panels.
/// [reverse] grows a trailing pane when moving toward the logical start.
class DResizableHandle extends StatefulWidget {
  /// Layout space reserved around a divider-free workspace grip.
  static const double workspaceGutterExtent = 12;
  static const double gripThickness = 4;
  static const double gripLength = 36;

  /// Width of the divider or workspace gutter, perpendicular to the resize axis.
  static double visualExtent({
    bool withHandle = false,
    double dividerThickness = 1,
  }) => math.max(
    withHandle
        ? (dividerThickness == 0 ? workspaceGutterExtent : gripThickness)
        : 0,
    dividerThickness,
  );

  const DResizableHandle({
    super.key,
    this.withHandle = false,

    this._semanticLabel,

    this.keyboardStep = 10,

    this.dividerThickness = 1,
    this.focusedDividerThickness,
    this.focusKey,
    this.semanticsKey,
    this.gestureKey,
    this.dividerKey,
    this.valueFormatter,
  }) : dividerAlignment = Alignment.center,

       value = 0,
       min = 0,
       max = double.infinity,
       onChanged = null,
       onChangeStart = null,
       onChangeEnd = null,
       reverse = false,
       trackUnrenderedChanges = true,

       assert(keyboardStep > 0);

  const DResizableHandle.standalone({
    super.key,
    this.withHandle = false,

    this._semanticLabel,

    required this.value,
    this.min = 0,
    this.max = double.infinity,
    required this.onChanged,
    this.onChangeEnd,
    this.onChangeStart,
    this.reverse = false,
    this.trackUnrenderedChanges = true,
    this.keyboardStep = 10,

    this.dividerThickness = 1,
    this.focusedDividerThickness,
    this.dividerAlignment = Alignment.center,
    this.focusKey,
    this.semanticsKey,
    this.gestureKey,
    this.dividerKey,
    this.valueFormatter,
  }) : assert(keyboardStep > 0),
       assert(min <= max);
  final bool withHandle, reverse;

  /// Accumulates pointer updates that arrive before the next frame. App adapters
  /// can disable this when saved widths must follow only rendered geometry.
  final bool trackUnrenderedChanges;
  final double value, min, max, keyboardStep, dividerThickness;
  final double? focusedDividerThickness;

  final String? _semanticLabel;
  String get semanticLabel => _semanticLabel ?? appL10n.resizePanel;

  final ValueChanged<double>? onChanged;
  final VoidCallback? onChangeEnd, onChangeStart;
  final AlignmentGeometry dividerAlignment;
  final Key? focusKey, semanticsKey, gestureKey, dividerKey;
  final String Function(double)? valueFormatter;
  @override
  State<DResizableHandle> createState() => _DResizableHandleState();
}

class _DResizableHandleState extends State<DResizableHandle> {
  late final FocusNode _focus = (FocusNode());
  bool _focused = false, _pending = false, _hovered = false;
  double? _pendingValue;
  _HandleBinding? get _binding =>
      context.getInheritedWidgetOfExactType<_HandleBinding>();
  Axis get _axis => _binding?.orientation ?? Axis.horizontal;
  double get _value => _binding?.value ?? widget.value;
  double get _increase =>
      _binding?.increase ?? math.min(_max, _value + widget.keyboardStep);
  double get _decrease =>
      _binding?.decrease ?? math.max(_min, _value - widget.keyboardStep);
  double get _min => _binding?.min ?? widget.min;
  double get _max => _binding?.max ?? widget.max;
  bool get _disabled => ((_binding?.disabled ?? widget.onChanged == null));
  double get _sign =>
      (widget.reverse ? -1 : 1) *
      (_axis == Axis.horizontal && DDirection.of(context) == TextDirection.rtl
          ? -1
          : 1);
  String _format(double v) =>
      widget.valueFormatter?.call(v) ?? appL10n.pixels((v.round()).toString());
  @override
  void didUpdateWidget(DResizableHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  void _begin() {
    if (_pending) return;
    _pending = true;
    widget.onChangeStart?.call();
  }

  void _commit() {
    if (!_pending) return;
    _pending = false;
    _pendingValue = null;
    (_binding?.onCommit ?? widget.onChangeEnd)?.call();
  }

  void _delta(double d, {bool keyboard = false}) {
    if (_disabled) return;
    _begin();
    if (_binding case final b?) {
      (keyboard ? b.onKeyboardDelta : b.onDelta)(d);
    } else {
      final next =
          ((widget.trackUnrenderedChanges ? _pendingValue ?? _value : _value) +
                  d)
              .clamp(_min, _max)
              .toDouble();
      _pendingValue = next;
      widget.onChanged?.call(next);
    }
  }

  @override
  void dispose() {
    // Persistence adapters also flush on removal; do not invoke app callbacks
    // from tree teardown or dereference inherited state after deactivation.
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_disabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final k = HardwareKeyboard.instance;
    if (k.isAltPressed || k.isMetaPressed || k.isControlPressed) {
      _commit();
      _focus.unfocus();
      return KeyEventResult.ignored;
    }
    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft when _axis == Axis.horizontal =>
        -widget.keyboardStep * _sign,
      LogicalKeyboardKey.arrowRight when _axis == Axis.horizontal =>
        widget.keyboardStep * _sign,
      LogicalKeyboardKey.arrowUp when _axis == Axis.vertical =>
        -widget.keyboardStep * _sign,
      LogicalKeyboardKey.arrowDown when _axis == Axis.vertical =>
        widget.keyboardStep * _sign,
      LogicalKeyboardKey.home => _min - _value,
      LogicalKeyboardKey.end => _max.isFinite ? _max - _value : 0.0,
      _ => null,
    };
    if (delta == null && key != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      _commit();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (delta != null) {
        _delta(
          delta *
              (k.isShiftPressed && delta.abs() == widget.keyboardStep ? 10 : 1),
          keyboard: true,
        );
      } else {}
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<_HandleBinding>();
    final t = DTokens.of(context), horizontal = _axis == Axis.horizontal;
    final enabled = !_disabled;
    void start(DragStartDetails _) {
      _focus.requestFocus();
      _begin();
    }

    void update(DragUpdateDetails d) =>
        _delta((horizontal ? d.delta.dx : d.delta.dy) * _sign);
    void end() {
      _commit();
      _focus.unfocus();
    }

    Widget place(double thickness, Widget child) {
      final offset = _binding?.paintOffset;
      if (offset == null) {
        return Align(
          alignment: widget.dividerAlignment,
          child: OverflowBox(
            minWidth: horizontal ? thickness : null,
            maxWidth: horizontal ? thickness : null,
            minHeight: horizontal ? null : thickness,
            maxHeight: horizontal ? null : thickness,
            child: child,
          ),
        );
      }
      return horizontal
          ? Positioned(
              left: offset - thickness / 2,
              width: thickness,
              top: 0,
              bottom: 0,
              child: child,
            )
          : Positioned(
              top: offset - thickness / 2,
              height: thickness,
              left: 0,
              right: 0,
              child: child,
            );
    }

    final focusVisible = _focused && DFocusHighlight.visibleOf(context);
    final thickness = focusVisible
        ? widget.focusedDividerThickness ?? widget.dividerThickness
        : widget.dividerThickness;
    final line = place(
      thickness,
      Container(
        key: widget.dividerKey,
        width: horizontal ? thickness : double.infinity,
        height: horizontal ? double.infinity : thickness,
        color: focusVisible && widget.focusedDividerThickness != null
            ? t.focusRing
            : t.border,
      ),
    );
    final extent = DResizableHandle.visualExtent(
      withHandle: widget.withHandle,
      dividerThickness: widget.dividerThickness,
    );
    final gripOnly = widget.withHandle && widget.dividerThickness == 0;
    return Align(
      alignment: widget.dividerAlignment,
      child: SizedBox(
        // A divider-free workspace handle is only the painted grip. The
        // surrounding gutter remains layout space, without pointer targets.
        width: horizontal
            ? (gripOnly ? DResizableHandle.gripThickness : extent)
            : (gripOnly ? DResizableHandle.gripLength : null),
        height: horizontal
            ? (gripOnly ? DResizableHandle.gripLength : null)
            : (gripOnly ? DResizableHandle.gripThickness : extent),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: !enabled
              ? SystemMouseCursors.basic
              : horizontal
              ? SystemMouseCursors.resizeLeftRight
              : SystemMouseCursors.resizeUpDown,
          child: Focus(
            key: widget.focusKey,
            focusNode: _focus,
            canRequestFocus: enabled,
            onKeyEvent: _key,
            onFocusChange: (v) {
              if (!v) _commit();
              if (mounted) setState(() => _focused = v);
            },
            child: Semantics(
              key: widget.semanticsKey,
              container: true,
              slider: true,
              enabled: enabled,
              focusable: enabled,
              focused: _focused,
              label: widget.semanticLabel,
              value: _format(_value),
              increasedValue: enabled && _increase != _value
                  ? _format(_increase)
                  : null,
              decreasedValue: enabled && _decrease != _value
                  ? _format(_decrease)
                  : null,
              onIncrease: enabled && _increase != _value
                  ? () {
                      _delta(widget.keyboardStep, keyboard: true);
                      _commit();
                    }
                  : null,
              onDecrease: enabled && _decrease != _value
                  ? () {
                      _delta(-widget.keyboardStep, keyboard: true);
                      _commit();
                    }
                  : null,
              child: GestureDetector(
                key: widget.gestureKey,
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: enabled && horizontal ? start : null,
                onHorizontalDragUpdate: enabled && horizontal ? update : null,
                onHorizontalDragEnd: enabled && horizontal
                    ? (_) => end()
                    : null,
                onHorizontalDragCancel: enabled && horizontal ? end : null,
                onVerticalDragStart: enabled && !horizontal ? start : null,
                onVerticalDragUpdate: enabled && !horizontal ? update : null,
                onVerticalDragEnd: enabled && !horizontal ? (_) => end() : null,
                onVerticalDragCancel: enabled && !horizontal ? end : null,
                onDoubleTap: (enabled) ? (_binding?.onReset) : null,
                // The focus ring and focused divider are wider than the hit
                // strip; they paint past it while hit testing stays within it.
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    line,
                    if (widget.withHandle)
                      place(
                        DResizableHandle.gripThickness,
                        Center(
                          child: Container(
                            width: horizontal
                                ? DResizableHandle.gripThickness
                                : DResizableHandle.gripLength,
                            height: horizontal
                                ? DResizableHandle.gripLength
                                : DResizableHandle.gripThickness,
                            decoration: BoxDecoration(
                              color:
                                  enabled &&
                                      (_hovered || _pending || focusVisible)
                                  ? t.primary
                                  : t.border,
                              borderRadius: BorderRadius.circular(t.radius),
                            ),
                          ),
                        ),
                      ),
                    if (focusVisible)
                      place(
                        3,
                        Container(
                          width: horizontal ? 3 : double.infinity,
                          height: horizontal ? double.infinity : 3,
                          decoration: BoxDecoration(
                            border: Border.all(color: t.focusRing),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
