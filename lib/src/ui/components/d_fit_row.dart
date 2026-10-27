import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import 'd_control_wrap.dart';

/// How much a [DFitRow] is saying to keep to one line.
enum DFitRowStep {
  /// Every child at its full length on one line.
  full,

  /// On one line with what can drop its words, read by [DFitRow.tightOf],
  /// saying less.
  tight,

  /// Wrapped, everything at its full length again.
  wrapped,
}

/// A row of controls that says less before it takes a second line. Laid out
/// at the children's own widths, it is first [DFitRowStep.tight] and only if
/// that is still too wide does it wrap. A line is measured as each child's
/// own width and the gaps between them, so what hangs past a child, such as
/// its open menu, needs no room in it. Each step back is taken once the row
/// is as wide as that step needed.
class DFitRow extends AbstractLayoutBuilder<DFitRowLayout> {
  const DFitRow({
    super.key,
    required this.children,
    this.spacing = DSpacing.sm,
    this.runSpacing = DSpacing.sm,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  /// Whether the nearest [DFitRow] asks its children to say less.
  static bool tightOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DFitRowScope>()?.tight ??
      false;

  @override
  Widget Function(BuildContext context, DFitRowLayout info) get builder =>
      (context, info) => _DFitRowScope(
        tight: info.step == DFitRowStep.tight,
        child: DControlWrap(
          wrap: info.step == DFitRowStep.wrapped,
          spacing: spacing,
          runSpacing: runSpacing,
          children: children,
        ),
      );

  @override
  RenderAbstractLayoutBuilderMixin<DFitRowLayout, RenderObject>
  createRenderObject(BuildContext context) => _RenderDFitRow();

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderDFitRow).reset();
}

/// What a [DFitRow] builds its line from: the room it has and its step.
typedef DFitRowLayout = ({BoxConstraints constraints, DFitRowStep step});

class _DFitRowScope extends InheritedWidget {
  const _DFitRowScope({required this.tight, required super.child});

  final bool tight;

  @override
  bool updateShouldNotify(_DFitRowScope oldWidget) => tight != oldWidget.tight;
}

class _RenderDFitRow extends RenderProxyBox
    with
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<DFitRowLayout, RenderBox> {
  var _step = DFitRowStep.full;

  /// How wide the line was at each step it left.
  final _need = [0.0, 0.0];

  /// Rebuilt children are measured afresh from their full length.
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
    // Each pass either settles or moves one step, and a step is left only
    // for one whose need is met, so three passes reach any of the three.
    for (var pass = 0; pass < 4; pass++) {
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
      } else if (_step != DFitRowStep.wrapped &&
          line.naturalMain > width + precisionErrorTolerance) {
        _need[index] = line.naturalMain;
        _step = DFitRowStep.values[index + 1];
      } else {
        return;
      }
    }
  }
}
