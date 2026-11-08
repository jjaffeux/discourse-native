import 'package:flutter/foundation.dart'
    show listEquals, precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/app_text_scaler.dart';
import '../foundation/control_motion.dart';
import '../foundation/control_style.dart';
import '../foundation/tokens.dart';
import 'd_control_wrap.dart';

/// The presentation a [DFitRow] requests from its controls.
enum DFitRowStep { full, tight, wrapped, wrappedTight, isolated }

/// Fits controls at their own widths, shortening before wrapping. If full
/// labels take more than two rows, it shortens again, then puts the item marked
/// [DFitRowItem.last] on the final row. Controls keep their elements and menus
/// throughout these layout changes. Overflowing popup content needs no room.
/// A change in the row's room or in any control's width fits it again from
/// the first step within the same layout, so no intermediate step is painted;
/// so does a rebuild, unless its [watch] is unchanged.
class DFitRow extends AbstractLayoutBuilder<DFitRowLayout> {
  const DFitRow({
    super.key,
    required this.children,
    this.spacing = DSpacing.sm,
    this.runSpacing = DSpacing.sm,
    this.compact = false,
    this.closeUp = false,
    this.watch,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  /// Requests meaningful glyphs while retaining state, counts and semantics.
  /// The owning page supplies this from its shared header state.
  final bool compact;

  /// Lets a [compact] touch row stand closer: a 6-point gap, and quiet filter
  /// pills 10 points in from their sides. Set it only while the row holds
  /// something that room keeps to one line, such as a category path with
  /// levels, so a row with nothing to shorten does not shift as it compacts.
  /// The leading [DFitRowItem], the view switch, keeps its own insets.
  final bool closeUp;

  /// What the controls say at the steps before the one the row settles on,
  /// as one value compared with `==`. A rebuild with an equal value keeps
  /// that step, since a change in the row's room or in a control's width at
  /// that step still fits it again from the first. Without it every rebuild
  /// fits it again: a shorter step can hide a label whose change would let
  /// an earlier step fit, and only the owner knows its controls' labels.
  final Object? watch;

  static bool tightOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DFitRowScope>();
    return scope?.compact == true ||
        switch (scope?.step) {
          DFitRowStep.tight ||
          DFitRowStep.wrappedTight ||
          DFitRowStep.isolated => true,
          _ => false,
        };
  }

  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DFitRowScope>()?.compact ??
      false;

  /// Whether the row is [compact] and [closeUp], outside its leading item.
  static bool closedUpOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DFitRowScope>()?.closedUp ??
      false;

  /// Measured room beside the other controls in this item's run. Use it to
  /// choose content, while retaining real minimum control bounds for layout.
  static double? availableWidthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DFitRowWidth>()?.width;

  @override
  Widget Function(BuildContext context, DFitRowLayout info) get builder =>
      (context, info) => _DFitRowScope(
        step: info.step,
        compact: compact,
        closedUp: compact && closeUp,
        child: DControlMotionScope(
          child: DReferenceTextScale(
            child: Builder(
              builder: (context) => DControlWrap(
                wrap: info.step.index >= DFitRowStep.wrapped.index,
                spacing: DControlStyle.isTouch(context) && compact && closeUp
                    ? 6
                    : spacing,
                runSpacing: runSpacing,
                children: [
                  for (final child in children)
                    DControlWrapItem(
                      remaining: child is DFitRowItem && child.leading,
                      breakAfter:
                          child is DFitRowItem &&
                          child.leading &&
                          info.step.index >= DFitRowStep.wrapped.index &&
                          info.step != DFitRowStep.isolated,
                      breakBefore:
                          child is DFitRowItem &&
                          child.last &&
                          info.step == DFitRowStep.isolated,
                      order:
                          child is DFitRowItem &&
                              child.last &&
                              info.step == DFitRowStep.isolated
                          ? 1
                          : 0,
                      child: child is DFitRowItem && child.leading
                          ? _DFitRowScope(
                              step: info.step,
                              compact: compact,
                              closedUp: false,
                              child: child,
                            )
                          : child,
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  RenderAbstractLayoutBuilderMixin<DFitRowLayout, RenderObject>
  createRenderObject(BuildContext context) => _RenderDFitRow(compact, watch);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderDFitRow).update(
        compact,
        TickerMode.valuesOf(context).enabled &&
            !(MediaQuery.maybeOf(context)?.disableAnimations ?? false),
        watch,
      );
}

/// Marks a view switch that gets its own row when wrapping, or the long control
/// that moves to the last row only after shortening is insufficient.
class DFitRowItem extends AbstractLayoutBuilder<double?> {
  const DFitRowItem({
    super.key,
    required this.child,
    this.leading = false,
    this.last = false,
  }) : assert(!leading || !last);

  final Widget child;
  final bool leading;
  final bool last;

  @override
  Widget Function(BuildContext, double?) get builder =>
      (context, width) => _DFitRowWidth(
        width: width,
        child: Semantics(
          sortKey: OrdinalSortKey(
            last &&
                    context
                            .dependOnInheritedWidgetOfExactType<_DFitRowScope>()
                            ?.step ==
                        DFitRowStep.isolated
                ? 1
                : 0,
          ),
          child: child,
        ),
      );

  @override
  RenderAbstractLayoutBuilderMixin<double?, RenderObject> createRenderObject(
    BuildContext context,
  ) => _RenderDFitRowItem();
}

class _DFitRowWidth extends InheritedWidget {
  const _DFitRowWidth({required this.width, required super.child});
  final double? width;
  @override
  bool updateShouldNotify(_DFitRowWidth oldWidget) => width != oldWidget.width;
}

class _RenderDFitRowItem extends RenderProxyBox
    with
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<double?, RenderBox> {
  @override
  double? get layoutInfo => switch (constraints) {
    DControlWrapConstraints(:final availableMain) => availableMain,
    _ => null,
  };
  @override
  void performLayout() {
    runLayoutCallback();
    super.performLayout();
  }
}

typedef DFitRowLayout = ({BoxConstraints constraints, DFitRowStep step});

class _DFitRowScope extends InheritedWidget {
  const _DFitRowScope({
    required this.step,
    required this.compact,
    required this.closedUp,
    required super.child,
  });
  final DFitRowStep step;
  final bool compact;
  final bool closedUp;

  @override
  bool updateShouldNotify(_DFitRowScope oldWidget) =>
      step != oldWidget.step ||
      compact != oldWidget.compact ||
      closedUp != oldWidget.closedUp;
}

class _RenderDFitRow extends RenderProxyBox
    with
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<DFitRowLayout, RenderBox> {
  _RenderDFitRow(this._compact, this._watch);
  bool _compact;
  Object? _watch;
  Map<RenderBox, Rect>? _fromRects;
  Map<RenderBox, Map<RenderDControlMotion, Rect>>? _fromControls;
  Size? _fromSize;
  RenderDControlWrap? _controls;
  double _elapsed = 0;
  double? _width;
  late final Ticker _ticker = Ticker((elapsed) {
    _elapsed =
        (elapsed.inMicroseconds /
                const Duration(milliseconds: 260).inMicroseconds)
            .clamp(0, 1);
    if (_elapsed == 1) {
      _ticker.stop();
      _fromRects = null;
      _fromControls = null;
      _fromSize = null;
    }
    markNeedsLayout();
  });

  void update(bool compact, bool animate, Object? watch) {
    final refit = _compact != compact || watch == null || watch != _watch;
    _watch = watch;
    if (_compact != compact && animate && hasSize) {
      _fromRects = _controls?.paintedRects;
      _fromControls = _controls?.controlRects;
      _fromSize = _controls?.size;
      _elapsed = 0;
      _ticker.stop();
      _ticker.start();
    } else if (!animate) {
      _fromRects = null;
      _fromControls = null;
      _fromSize = null;
      _ticker.stop();
    }
    _compact = compact;
    if (refit) reset();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  var _step = DFitRowStep.full;

  // The row's width and each control's width at the step the row settled on.
  // Any difference at that same step means the room or a control's content
  // changed, which says nothing about which step fits now.
  List<double>? _settled;

  void reset() {
    _step = DFitRowStep.full;
    markNeedsLayout();
  }

  static List<double> _widthsOf(double width, RenderDControlWrap controls) => [
    width,
    ...controls.childExtents,
  ];

  @override
  DFitRowLayout get layoutInfo => (constraints: constraints, step: _step);

  @override
  void performLayout() {
    if (_width != constraints.maxWidth) {
      _fromRects = null;
      _fromControls = null;
      _fromSize = null;
      _ticker.stop();
    }
    _width = constraints.maxWidth;
    _layoutControls();
  }

  void _layoutControls() {
    final width = constraints.maxWidth;
    // A new room restarts the fit whatever the settled step measures at it, so
    // laying out and building that step first would only be discarded.
    if (_step != DFitRowStep.full && _settled?.first != width) {
      _step = DFitRowStep.full;
    }
    for (var pass = 0; pass < DFitRowStep.values.length + 1; pass++) {
      runLayoutCallback();
      final line = child;
      if (line == null) {
        size = constraints.smallest;
        return;
      }
      final wrap = line is RenderDControlWrap ? line : null;
      _controls = wrap;
      final remaining = 1 - _elapsed;
      invokeLayoutCallback<BoxConstraints>(
        (_) => wrap?.transitionFrom(
          _fromRects,
          _fromSize,
          _fromRects == null ? 1 : 1 - remaining * remaining * remaining,
          controls: _fromControls,
          controlProgress: const Cubic(.2, .8, .2, 1).transform(_elapsed),
          fadeProgress: Curves.ease.transform(_elapsed),
        ),
      );
      line.layout(
        width.isFinite ? constraints.tighten(width: width) : constraints,
        parentUsesSize: true,
      );
      size = line.size;
      if (wrap == null || !width.isFinite) return;
      final controls = wrap;
      // Only the first pass can see a change from outside: later passes
      // differ by the step this layout just took.
      if (pass == 0 &&
          _step != DFitRowStep.full &&
          !listEquals(_widthsOf(width, controls), _settled)) {
        _step = DFitRowStep.full;
        continue;
      }
      final index = _step.index;
      if (index < DFitRowStep.wrapped.index &&
          controls.naturalMain > width + precisionErrorTolerance) {
        _step = DFitRowStep.values[index + 1];
      } else if ((_step == DFitRowStep.wrapped ||
              _step == DFitRowStep.wrappedTight) &&
          controls.runCount > 2) {
        _step = DFitRowStep.values[index + 1];
      } else {
        _settled = _widthsOf(width, controls);
        return;
      }
    }
  }
}
