import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'd_card.dart';
import 'd_collapsible.dart';
import 'd_page_reading_lane.dart';

/// A bounded page with a shared border, fixed tabs and footer, and a retracting
/// header. Compose content with DPageReadingLane from the Native kit to keep
/// scroll viewports full width while limiting their contents. Only deliberate
/// scrolling in the body retracts the header; restoration and nested scrolls
/// leave it alone. Collapsible owns animation, reduced motion and hidden focus.
class DPageSurface extends StatefulWidget {
  const DPageSurface({
    super.key,
    this.header,
    this.tabs,
    this.footer,
    this.framed = true,
    this.hideHeaderOnScroll = false,
    this.limitContentSize,
    required this.child,
    this.identity,
  });

  /// Optional header, fixed unless [hideHeaderOnScroll] is enabled.
  final Widget? header;

  /// Hide on downward scrolling; reveal after 100 logical pixels upward
  /// or immediately when scrolling reaches the top.
  final bool hideHeaderOnScroll;

  /// Persistent tabs above the retracting header.
  final Widget? tabs;

  /// Persistent actions below the viewport.
  final Widget? footer;

  /// Disable when composed inside an already framed page or a touch shell.
  final bool framed;

  /// Constrains reading-lane content to 825px without narrowing its viewport.
  /// Null inherits the enclosing page policy; the default is full width.
  final bool? limitContentSize;
  final Widget child;
  final Object? identity;

  @override
  State<DPageSurface> createState() => _DPageSurfaceState();
}

class _DPageSurfaceState extends State<DPageSurface> {
  final _headerFocus = FocusNode(canRequestFocus: false);
  bool _visible = true;
  bool _userScrolling = false;
  ScrollDirection _direction = ScrollDirection.idle;
  double _distance = 0;
  bool _updateScheduled = false;

  @override
  void didUpdateWidget(DPageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.hideHeaderOnScroll != widget.hideHeaderOnScroll) {
      _visible = true;
      _userScrolling = false;
      _direction = ScrollDirection.idle;
      _distance = 0;
    }
  }

  void _show(bool visible) {
    if (_visible == visible || (!visible && _headerFocus.hasFocus)) return;
    _visible = visible;
    // Scroll notifications can arrive during layout. Coalesce direction
    // changes without rebuilding the expensive body on each scroll tick.
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _isPageScroll(ScrollNotification notification) {
    if (notification.depth == 0) return true;
    // A table may put its main vertical list inside a horizontal viewport.
    // Ignore that horizontal boundary, but never react to an embedded vertical
    // scroller (for example a code block inside a post).
    var nestedVertical = false;
    notification.context?.visitAncestorElements((element) {
      if (identical(element.widget, widget)) return false;
      final axis = switch (element.widget) {
        Viewport(:final axisDirection) => axisDirectionToAxis(axisDirection),
        ShrinkWrappingViewport(:final axisDirection) => axisDirectionToAxis(
          axisDirection,
        ),
        _ => null,
      };
      if (axis == Axis.vertical) {
        nestedVertical = true;
        return false;
      }
      return true;
    });
    return !nestedVertical;
  }

  bool _onScroll(ScrollNotification notification) {
    if (widget.header == null || !widget.hideHeaderOnScroll) return false;
    if (!_isPageScroll(notification) ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      if (_userScrolling && _direction != notification.direction) {
        _direction = notification.direction;
        _distance = 0;
      }
    }
    if (notification is ScrollUpdateNotification && _userScrolling) {
      final metrics = notification.metrics;
      final reversed = metrics.axisDirection == AxisDirection.up;
      final atTop = reversed
          ? metrics.pixels >= metrics.maxScrollExtent
          : metrics.pixels <= metrics.minScrollExtent;
      if (atTop) {
        _distance = 0;
        _show(true);
      } else if (!metrics.outOfRange) {
        final delta = notification.scrollDelta ?? 0;
        // Ignore extent corrections and elastic rebound against the user's
        // direction, including when the header changes the viewport height.
        if ((_direction == ScrollDirection.reverse && delta > 0) ||
            (_direction == ScrollDirection.forward && delta < 0)) {
          _distance += delta.abs();
          final revealing = reversed
              ? _direction == ScrollDirection.reverse
              : _direction == ScrollDirection.forward;
          final headerHeight = _headerFocus.context?.size?.height ?? 0;
          final canRetract =
              !_visible ||
              metrics.maxScrollExtent - metrics.minScrollExtent > headerHeight;
          if (_distance >= (revealing ? 100 : 12) &&
              (revealing || canRetract)) {
            _show(revealing);
          }
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    _headerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.tabs,
        if (widget.header != null)
          DCollapsible(
            open: !widget.hideHeaderOnScroll || _visible,
            child: DCollapsibleContent(
              keepMounted: true,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOutCubic,
              child: SizedBox(
                width: double.infinity,
                child: Focus(focusNode: _headerFocus, child: widget.header!),
              ),
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
        ?widget.footer,
      ],
    );
    return DPageContentSettings(
      limitContentSize:
          widget.limitContentSize ?? DPageContentSettings.limitOf(context),
      child: widget.framed
          ? DCard(spacing: 0, child: Expanded(child: page))
          : page,
    );
  }
}
