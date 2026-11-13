import 'dart:math' as math;

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

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
