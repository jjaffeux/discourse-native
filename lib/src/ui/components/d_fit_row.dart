import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../foundation/app_text_scaler.dart';
import '../foundation/control_style.dart';
import '../foundation/tokens.dart';
import 'd_control_wrap.dart';

/// The presentation a [DFitRow] requests from its controls.
enum DFitRowStep { full, tight, wrapped, wrappedTight, isolated }

/// Fits controls at their own widths, shortening before wrapping. If full
/// labels take more than two rows, it shortens again, then puts the item marked
/// [DFitRowItem.last] on the final row. Controls keep their elements and menus
/// throughout these layout changes. Overflowing popup content needs no room.
class DFitRow extends AbstractLayoutBuilder<DFitRowLayout> {
  const DFitRow({
    super.key,
    required this.children,
    this.spacing = DSpacing.sm,
    this.runSpacing = DSpacing.sm,
    this.compact = false,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  /// Requests meaningful glyphs while retaining state, counts and semantics.
  /// The owning page supplies this from its shared header state.
  final bool compact;

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

  /// Measured room beside the other controls in this item's run. Use it to
  /// choose content, while retaining real minimum control bounds for layout.
  static double? availableWidthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DFitRowWidth>()?.width;

  @override
  Widget Function(BuildContext context, DFitRowLayout info) get builder =>
      (context, info) => _DFitRowScope(
        step: info.step,
        compact: compact,
        child: DReferenceTextScale(
          child: Builder(
            builder: (context) => DControlWrap(
              wrap: info.step.index >= DFitRowStep.wrapped.index,
              spacing: DControlStyle.isTouch(context) && tightOf(context)
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
                    child: child,
                  ),
              ],
            ),
          ),
        ),
      );

  @override
  RenderAbstractLayoutBuilderMixin<DFitRowLayout, RenderObject>
  createRenderObject(BuildContext context) => _RenderDFitRow();

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderDFitRow).reset();
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
    required super.child,
  });
  final DFitRowStep step;
  final bool compact;

  @override
  bool updateShouldNotify(_DFitRowScope oldWidget) =>
      step != oldWidget.step || compact != oldWidget.compact;
}

class _RenderDFitRow extends RenderProxyBox
    with
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<DFitRowLayout, RenderBox> {
  var _step = DFitRowStep.full;
  final _need = List.filled(DFitRowStep.values.length - 1, 0.0);

  void reset() {
    _step = DFitRowStep.full;
    _need.fillRange(0, _need.length, 0);
    markNeedsLayout();
  }

  @override
  DFitRowLayout get layoutInfo => (constraints: constraints, step: _step);

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    for (var pass = 0; pass < DFitRowStep.values.length + 1; pass++) {
      runLayoutCallback();
      final line = child;
      if (line == null) {
        size = constraints.smallest;
        return;
      }
      line.layout(constraints, parentUsesSize: true);
      size = line.size;
      if (line is! RenderDControlWrap || !width.isFinite) return;
      final index = _step.index;
      if (index > 0 && width >= _need[index - 1]) {
        _step = DFitRowStep.values[index - 1];
      } else if (index < DFitRowStep.wrapped.index &&
          line.naturalMain > width + precisionErrorTolerance) {
        _need[index] = line.naturalMain;
        _step = DFitRowStep.values[index + 1];
      } else if ((_step == DFitRowStep.wrapped ||
              _step == DFitRowStep.wrappedTight) &&
          line.runCount > 2) {
        _need[index] = width + 1;
        _step = DFitRowStep.values[index + 1];
      } else {
        return;
      }
    }
  }
}
