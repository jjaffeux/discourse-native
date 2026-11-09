import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Takes one two-finger sideways trackpad run as one history step.
///
/// The macOS and Linux engines deliver a run as one pan-zoom start, its
/// updates and one end, with no momentum events, so each start opens a run
/// without a timer. The region only listens: it never joins the gesture arena,
/// so vertical scrolling and inner horizontal scrollers behave as without it.
class TrackpadHistoryRegion extends StatefulWidget {
  const TrackpadHistoryRegion({
    super.key,
    required this.onBack,
    required this.onForward,
    required this.child,
  });

  /// Sideways travel, in logical pixels, that commits a run.
  static const distance = 80.0;

  final VoidCallback onBack;
  final VoidCallback onForward;
  final Widget child;

  @override
  State<TrackpadHistoryRegion> createState() => _TrackpadHistoryRegionState();
}

final class _Run {
  double travel = 0;
  bool stepped = false;
  List<ScrollableState>? scrollers;
}

class _TrackpadHistoryRegionState extends State<TrackpadHistoryRegion> {
  var _run = _Run();

  void _update(PointerPanZoomUpdateEvent event) {
    final run = _run;
    // The hit path outlives this state when a run ends the page it began on.
    if (run.stepped || !mounted) return;
    final delta = event.panDelta;
    if (delta.dx.abs() <= delta.dy.abs()) return;
    final scrollers = run.scrollers ??= _horizontalScrollersAt(
      event.localPosition,
    );
    if (scrollers.any((s) => s.mounted && _canTake(s, delta.dx))) return;
    run.travel += delta.dx;
    // A slow vertical scroll reports many updates that are sideways by a
    // pixel, so the whole run has to be sideways as well as each update.
    if (run.travel.abs() < TrackpadHistoryRegion.distance ||
        event.pan.dx.abs() <= event.pan.dy.abs()) {
      return;
    }
    run.stepped = true;
    if (run.travel > 0) {
      widget.onBack();
    } else {
      widget.onForward();
    }
  }

  /// Runs once per sideways run. Scrollers carry no render-tree back link, so
  /// the elements are walked, and the hit path rules out those hidden or
  /// covered at the pointer.
  List<ScrollableState> _horizontalScrollersAt(Offset position) {
    final hit = BoxHitTestResult();
    (context.findRenderObject()! as RenderBox).hitTest(hit, position: position);
    final underPointer = {for (final entry in hit.path) entry.target};
    final scrollers = <ScrollableState>[];
    void visit(Element element) {
      if (element case StatefulElement(state: final ScrollableState scroller)
          when scroller.widget.axis == Axis.horizontal &&
              underPointer.contains(
                scroller.position.context.notificationContext
                    ?.findRenderObject(),
              )) {
        scrollers.add(scroller);
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return scrollers;
  }

  bool _canTake(ScrollableState scroller, double panX) {
    final position = scroller.position;
    if (!position.hasPixels ||
        !position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return false;
    }
    // Content follows the fingers, so moving them left advances an axis that
    // lays out rightwards.
    final advancing =
        (panX < 0) == (scroller.axisDirection == AxisDirection.right);
    return (advancing ? position.extentAfter : position.extentBefore) > 1;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerPanZoomStart: (_) => _run = _Run(),
    onPointerPanZoomUpdate: _update,
    child: widget.child,
  );
}
