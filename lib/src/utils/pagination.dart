import 'dart:math' as math;

import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollDirection;
import 'package:flutter/widgets.dart';

/// Exposes ballistic speed for fetching ahead without polling during scrolling.
class PaginationScrollController extends ScrollController {
  double get velocity =>
      hasClients ? (position as PaginationScrollPosition).velocity : 0;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => PaginationScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class PaginationScrollPosition extends ScrollPositionWithSingleContext {
  PaginationScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  double get velocity => activity?.velocity ?? 0;
}

/// Decides whether scroll-driven paging may ask a feed for its next page.
///
/// A page is requested only when there is more to load, none is in flight, and
/// no failed page still stands: every scroll update near an edge would
/// otherwise resend it as soon as it fails. A feed with a Try again row ends a
/// failure through that row. A feed without one ends it at the next
/// [UserScrollGestures] start, so one failure cannot strand the feed.
@immutable
final class ScrollPagingGate {
  const ScrollPagingGate({
    required this.hasMore,
    required this.busy,
    required this.lastPageFailed,
  });

  final bool hasMore;
  final bool busy;
  final bool lastPageFailed;

  bool get admits => hasMore && !busy && !lastPageFailed;
}

/// Recognises the moment a person starts a new scroll.
///
/// A drag starts once however often it changes direction. A mouse wheel has no
/// drag, so each notch reports its direction instead. Programmatic scrolling
/// and layout corrections carry neither signal.
final class UserScrollGestures {
  bool _dragging = false;

  bool starts(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
      return true;
    }
    if (notification is ScrollEndNotification) _dragging = false;
    return !_dragging &&
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
  }
}

/// Starts fetching with two screens left to read, including on small windows.
///
/// Fling headroom targets 750ms for the request and layout, capped at six
/// screens. Negative [velocity] moves away from the edge and retains the
/// ordinary reading window.
/// Whether to request at all is the feed's [ScrollPagingGate].
double paginationPrefetchDistance(
  ScrollMetrics metrics, {
  double velocity = 0,
}) {
  final readingDistance = math.max(1600.0, metrics.viewportDimension * 2);
  final flingDistance = velocity.isFinite
      ? (velocity * .75).clamp(0.0, metrics.viewportDimension * 6)
      : 0.0;
  return math.max(readingDistance, flingDistance);
}

/// Requests a page when its list boundary reaches the viewport.
class ScrollPageTrigger extends StatefulWidget {
  const ScrollPageTrigger({
    super.key,
    required this.enabled,
    required this.onLoad,
    required this.child,
    this.leading = false,
  });

  final bool enabled;
  final VoidCallback onLoad;
  final Widget child;
  final bool leading;

  @override
  State<ScrollPageTrigger> createState() => _ScrollPageTriggerState();
}

class _ScrollPageTriggerState extends State<ScrollPageTrigger> {
  ScrollPosition? _position;
  bool _scheduled = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position == _position) return;
    _position?.removeListener(_scheduleCheck);
    _position = position;
    position?.addListener(_scheduleCheck);
  }

  @override
  void didUpdateWidget(ScrollPageTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    _requested = false;
  }

  void _scheduleCheck() {
    if (!widget.enabled || _scheduled || _requested) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !widget.enabled) return;
      final position = _position;
      final target = context.findRenderObject();
      if (position == null ||
          !position.hasContentDimensions ||
          target == null ||
          !target.attached) {
        return;
      }
      final viewport = RenderAbstractViewport.maybeOf(target);
      if (viewport == null) return;
      final bottom = viewport.getOffsetToReveal(target, 1).offset;
      final top = widget.leading
          ? viewport.getOffsetToReveal(target, 0).offset
          : null;
      if (bottom <= position.pixels + 0.5 &&
          (top == null || top >= position.pixels - 0.5)) {
        _requested = true;
        widget.onLoad();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleCheck);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    MediaQuery.maybeSizeOf(context);
    _scheduleCheck();
    return widget.child;
  }
}
