import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'control_style.dart';

/// A fingertip: on a phone, a control drawn smaller than this is pressed
/// across an invisible area at least this wide and tall, centred on it.
const double kDTouchTargetExtent = 44;

/// Where phone presses may reach past a control's drawn bounds.
///
/// A press that lands on no control goes to a [DTouchTarget] whose invisible
/// area holds it, as the mockup's `::after` layer would take it: the area sits
/// at the control's place in paint order, inside its ancestors' clips. Layout
/// and painting are untouched. Install one above the navigator so routes and
/// overlays are inside it. It only acts on touch platforms.
class DTouchTargets extends StatelessWidget {
  const DTouchTargets({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _TouchTargetScope(enabled: DControlStyle.isTouch(context), child: child);
}

/// Gives [child], one control, the phone's invisible [kDTouchTargetExtent]
/// area inside the nearest [DTouchTargets]. A target holding another target
/// has none, so it never takes presses meant for the one inside it.
class DTouchTarget extends SingleChildRenderObjectWidget {
  const DTouchTarget({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTouchTarget();
}

class _TouchTargetScope extends SingleChildRenderObjectWidget {
  const _TouchTargetScope({required this.enabled, required super.child});

  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTouchTargetScope(enabled: enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTouchTargetScope renderObject,
  ) => renderObject.enabled = enabled;
}

class _RenderTouchTargetScope extends RenderProxyBox {
  _RenderTouchTargetScope({required this.enabled});

  bool enabled;
  int _targets = 0;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final target = enabled && _targets > 0 ? _targetAt(position) : null;
    // The control goes first in the path so its recognizers join the arena
    // ahead of any row or page recognizer under the same press.
    if (target != null) {
      result.addWithPaintTransform(
        transform: target.getTransformTo(this),
        position: position,
        hitTest: (result, _) =>
            target.hitTest(result, position: target.size.center(Offset.zero)),
      );
    }
    return super.hitTest(result, position: position) || target != null;
  }

  _RenderTouchTarget? _targetAt(Offset position) {
    final candidates = <_RenderTouchTarget>[];
    visitChildren((child) => _collect(this, child, position, candidates));
    if (candidates.isEmpty) return null;
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: position);
    _RenderTouchTarget? best;
    for (final target in candidates) {
      if (!_uncovered(target, probe) || !_pressable(target)) continue;
      if (best == null || _paintsAbove(target, best)) best = target;
    }
    return best;
  }

  /// Gathers the targets under [child] whose area holds [point], given in
  /// [parent]'s coordinates. A box the point lies more than half a fingertip
  /// outside holds no such target, and neither does what a clip hides, as an
  /// overflow clip hides an element's `::after`.
  static void _collect(
    RenderObject parent,
    RenderObject child,
    Offset point,
    List<_RenderTouchTarget> found,
  ) {
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null && !clip.contains(point)) return;
    final transform = Matrix4.identity();
    parent.applyPaintTransform(child, transform);
    final inverse = Matrix4.tryInvert(transform);
    if (inverse == null) return;
    final local = MatrixUtils.transformPoint(inverse, point);
    if (child is RenderBox) {
      if (!child.hasSize) return;
      final reach = (Offset.zero & child.size).inflate(kDTouchTargetExtent / 2);
      if (!reach.contains(local)) return;
      if (child is _RenderTouchTarget && child._reaches(local)) {
        found.add(child);
      }
    }
    child.visitChildren((next) => _collect(child, next, local, found));
  }

  /// Whether nothing drawn over [target]'s area holds the press: no other
  /// control is under it, and what is under it paints below the target.
  bool _uncovered(_RenderTouchTarget target, BoxHitTestResult probe) {
    final ancestors = _ancestors(target);
    RenderObject? deepest;
    for (final entry in probe.path) {
      final hit = entry.target;
      if (hit is TextSpan && hit.recognizer != null) return false;
      if (hit is! RenderObject) continue;
      if (ancestors.contains(hit)) break;
      if (_isControl(hit)) return false;
      deepest ??= hit;
    }
    return deepest == null || _paintsAbove(target, deepest);
  }

  /// Whether a press at [target]'s own centre reaches it, so nothing such as
  /// a barrier, an offstage subtree or an ignored subtree stands in its way.
  bool _pressable(_RenderTouchTarget target) {
    final centre = MatrixUtils.transformPoint(
      target.getTransformTo(this),
      target.size.center(Offset.zero),
    );
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: centre);
    return probe.path.any((entry) => entry.target == target);
  }

  static bool _isControl(RenderObject hit) => switch (hit) {
    _RenderTouchTarget() || RenderEditable() => true,
    RenderSemanticsGestureHandler(:final onTap, :final onLongPress) =>
      onTap != null || onLongPress != null,
    RenderSemanticsAnnotations(:final properties) =>
      properties.button == true ||
          properties.link == true ||
          properties.textField == true ||
          properties.slider == true ||
          properties.toggled != null ||
          properties.checked != null ||
          properties.onTap != null,
    _ => false,
  };

  static List<RenderObject> _ancestors(RenderObject node) => [
    for (var a = node.parent; a != null; a = a.parent) a,
  ];

  /// Whether [a] paints over [b]: a descendant over its ancestor, otherwise
  /// the later of their branches under the nearest common ancestor.
  static bool _paintsAbove(RenderObject a, RenderObject b) {
    final aChain = [a, ..._ancestors(a)];
    final bChain = [b, ..._ancestors(b)];
    final bSet = bChain.toSet();
    final common = aChain.indexWhere(bSet.contains);
    if (common < 0) return false;
    if (common == 0) return false;
    final ancestor = aChain[common];
    final bIndex = bChain.indexOf(ancestor);
    if (bIndex == 0) return true;
    final aBranch = aChain[common - 1];
    final bBranch = bChain[bIndex - 1];
    // A viewport visits its slivers in layout order but paints them in its
    // own order, which is the order it visits them in for semantics.
    final order = <RenderObject>[];
    if (ancestor is RenderViewportBase) {
      ancestor.visitChildrenForSemantics(order.add);
    } else {
      ancestor.visitChildren(order.add);
    }
    return order.indexOf(aBranch) > order.indexOf(bBranch);
  }
}

class _RenderTouchTarget extends RenderProxyBox {
  _RenderTouchTargetScope? _scope;
  final List<_RenderTouchTarget> _holders = [];
  int _held = 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (var node = parent; node != null; node = node.parent) {
      if (node is _RenderTouchTarget) {
        node._held++;
        _holders.add(node);
      } else if (node is _RenderTouchTargetScope) {
        _scope = node;
        node._targets++;
        break;
      }
    }
  }

  @override
  void detach() {
    if (_scope case final scope?) scope._targets--;
    _scope = null;
    for (final holder in _holders) {
      holder._held--;
    }
    _holders.clear();
    super.detach();
  }

  /// Whether [local], in this control's coordinates, falls in its invisible
  /// area and outside what it draws.
  bool _reaches(Offset local) {
    if (_held > 0 || size.contains(local)) return false;
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: math.max(size.width, kDTouchTargetExtent),
      height: math.max(size.height, kDTouchTargetExtent),
    ).contains(local);
  }
}
