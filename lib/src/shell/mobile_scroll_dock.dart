import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Gives the page the dock's space while reading down, and returns it on an
/// upward scroll. The Native collapsible owns animation and hidden controls.
class MobileScrollDock extends StatefulWidget {
  const MobileScrollDock({
    super.key,
    required this.body,
    required this.dockBuilder,
    required this.identity,
    this.visible = true,
    this.keepActionVisible = false,
  });

  final Widget body;

  /// The argument lets a composer hide destinations while keeping its action row.
  final Widget Function(bool hidden) dockBuilder;
  final Object identity;
  final bool visible;

  /// An active composer must keep its Send/Save action reachable.
  final bool keepActionVisible;

  @override
  State<MobileScrollDock> createState() => _MobileScrollDockState();
}

class _MobileScrollDockState extends State<MobileScrollDock> {
  static const _hideDistance = 16.0;
  static const _showDistance = 10.0;
  static const _topFloor = 48.0;
  static const _minimumTravel = 120.0;

  Expando<_ScrollIntent> _intents = Expando();
  bool _hidden = false;

  @override
  void didUpdateWidget(MobileScrollDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.visible != widget.visible ||
        oldWidget.keepActionVisible != widget.keepActionVisible) {
      _hidden = false;
      _intents = Expando();
    }
  }

  bool _isPageScroll(ScrollNotification notification, ScrollableState source) {
    var nested = false;
    notification.context!.visitAncestorElements((element) {
      if (identical(element.widget, widget)) return false;
      if (element case StatefulElement(
        state: final ScrollableState scrollable,
      )) {
        if (!identical(scrollable, source) &&
            scrollable.widget.axis == Axis.vertical &&
            scrollable.position.hasContentDimensions &&
            scrollable.position.maxScrollExtent >
                scrollable.position.minScrollExtent) {
          nested = true;
          return false;
        }
      }
      return true;
    });
    return !nested;
  }

  void _setHidden(bool hidden) {
    if (_hidden != hidden) setState(() => _hidden = hidden);
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.visible) return false;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical || notification.context == null) {
      return false;
    }
    final source = Scrollable.maybeOf(notification.context!);
    if (source == null || !_isPageScroll(notification, source)) return false;
    final intent = _intents[source] ??= _ScrollIntent();
    if (notification is ScrollStartNotification &&
        notification.dragDetails == null &&
        !intent.userScrolling) {
      intent.distance = 0;
      intent.holdAtEnd = false;
    }
    if (notification is UserScrollNotification) {
      intent.userScrolling = notification.direction != ScrollDirection.idle;
      if (intent.userScrolling && intent.direction != notification.direction) {
        intent.distance = 0;
        intent.direction = notification.direction;
      }
    }
    if (notification is! ScrollUpdateNotification || !intent.userScrolling) {
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    // Extent corrections and elastic rebounds can move against the gesture.
    // They must not count as a reader reversing direction.
    if ((intent.direction == ScrollDirection.reverse && delta <= 0) ||
        (intent.direction == ScrollDirection.forward && delta >= 0)) {
      return false;
    }
    final travel = metrics.maxScrollExtent - metrics.minScrollExtent;
    final reversed = metrics.axisDirection == AxisDirection.up;
    final top = reversed
        ? metrics.maxScrollExtent - metrics.pixels
        : metrics.pixels - metrics.minScrollExtent;
    final down = reversed ? delta < 0 : delta > 0;
    intent.distance += delta.abs();
    if (top <= _topFloor) {
      intent.distance = 0;
      intent.holdAtEnd = false;
      _setHidden(false);
    } else if (travel - top <= 4 && !widget.keepActionVisible) {
      intent.holdAtEnd = true;
      _setHidden(false);
    } else if (metrics.outOfRange) {
      return false;
    } else if (!down && intent.distance > _showDistance) {
      intent.holdAtEnd = false;
      _setHidden(false);
    } else if (down &&
        // Hiding enlarges the viewport and can take a short page below the
        // threshold. Only gate hiding: its top, end and upward gestures must
        // still be able to restore the dock with that smaller scroll range.
        travel >= _minimumTravel &&
        !intent.holdAtEnd &&
        (top - delta.abs() <= _topFloor || intent.distance > _hideDistance)) {
      _setHidden(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.body,
        ),
      ),
      DCollapsible(
        open: widget.visible && (widget.keepActionVisible || !_hidden),
        child: DCollapsibleContent(
          duration: DMotion.change,
          curve: Curves.easeInOutCubic,
          keepMounted: true,
          child: widget.dockBuilder(_hidden && widget.keepActionVisible),
        ),
      ),
    ],
  );
}

class _ScrollIntent {
  bool userScrolling = false;
  ScrollDirection direction = ScrollDirection.idle;
  double distance = 0;
  bool holdAtEnd = false;
}
