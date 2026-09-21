import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'd_card.dart';
import 'd_page_reading_lane.dart';

/// A bounded page with a shared border, fixed tabs and footer, and a retracting
/// header. Compose content with DPageReadingLane from the Native kit to keep
/// scroll viewports full width while limiting their contents. Only deliberate
/// scrolling in the body retracts the header; restoration and nested scrolls
/// leave it alone. The header follows scroll distance without a timed animation.
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

  /// Retract and reveal pixel-for-pixel with vertical scrolling, or reveal
  /// completely when scrolling reaches the top.
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
  double _hiddenExtent = 0;
  bool _userScrolling = false;
  ScrollDirection _direction = ScrollDirection.idle;
  bool _updateScheduled = false;

  @override
  void didUpdateWidget(DPageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.hideHeaderOnScroll != widget.hideHeaderOnScroll) {
      _hiddenExtent = 0;
      _userScrolling = false;
      _direction = ScrollDirection.idle;
    }
  }

  void _setHiddenExtent(double extent) {
    if (_hiddenExtent == extent ||
        (extent > _hiddenExtent && _headerFocus.hasFocus)) {
      return;
    }
    _hiddenExtent = extent;
    // Pointer input and ballistic ticks arrive before build. Update in that
    // frame so the header stays in step with the content, including reversals.
    // Only notifications raised during build/layout need to wait for a frame.
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
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
      }
    }
    if (notification is ScrollUpdateNotification && _userScrolling) {
      final metrics = notification.metrics;
      final reversed = metrics.axisDirection == AxisDirection.up;
      final atTop = reversed
          ? metrics.pixels >= metrics.maxScrollExtent
          : metrics.pixels <= metrics.minScrollExtent;
      if (atTop) {
        _setHiddenExtent(0);
      } else if (!metrics.outOfRange) {
        final delta = notification.scrollDelta ?? 0;
        // Ignore extent corrections and elastic rebound against the user's
        // direction, including when the header changes the viewport height.
        if ((_direction == ScrollDirection.reverse && delta > 0) ||
            (_direction == ScrollDirection.forward && delta < 0)) {
          final revealing = reversed
              ? _direction == ScrollDirection.reverse
              : _direction == ScrollDirection.forward;
          final headerHeight = _headerFocus.context?.size?.height ?? 0;
          final canRetract =
              _hiddenExtent > 0 ||
              metrics.maxScrollExtent - metrics.minScrollExtent > headerHeight;
          if (revealing || canRetract) {
            _setHiddenExtent(
              (_hiddenExtent + (revealing ? -delta.abs() : delta.abs())).clamp(
                0.0,
                headerHeight,
              ),
            );
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
          ClipRect(
            child: _ScrollHeaderExtent(
              hiddenExtent: widget.hideHeaderOnScroll ? _hiddenExtent : 0,
              child: ExcludeSemantics(
                excluding: _hiddenExtent > 0,
                child: ExcludeFocus(
                  excluding: _hiddenExtent > 0,
                  child: IgnorePointer(
                    ignoring: _hiddenExtent > 0,
                    child: TickerMode(
                      enabled: _hiddenExtent == 0,
                      child: SizedBox(
                        width: double.infinity,
                        child: Focus(
                          focusNode: _headerFocus,
                          child: widget.header!,
                        ),
                      ),
                    ),
                  ),
                ),
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

// Keep the header at its natural height while removing exactly the scrolled
// distance from the page layout. Measuring here also handles header size changes.
class _ScrollHeaderExtent extends SingleChildRenderObjectWidget {
  const _ScrollHeaderExtent({required this.hiddenExtent, required super.child});

  final double hiddenExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollHeaderExtent(hiddenExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollHeaderExtent renderObject,
  ) {
    renderObject.hiddenExtent = hiddenExtent;
  }
}

class _RenderScrollHeaderExtent extends RenderShiftedBox {
  _RenderScrollHeaderExtent(this._hiddenExtent) : super(null);

  double _hiddenExtent;

  set hiddenExtent(double value) {
    if (_hiddenExtent == value) return;
    _hiddenExtent = value;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child!.getDryLayout(constraints);
    return constraints.constrain(
      Size(
        childSize.width,
        (childSize.height - _hiddenExtent).clamp(0.0, childSize.height),
      ),
    );
  }

  @override
  void performLayout() {
    child!.layout(constraints, parentUsesSize: true);
    final hidden = _hiddenExtent.clamp(0.0, child!.size.height);
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height - hidden),
    );
    (child!.parentData! as BoxParentData).offset = Offset(0, -hidden);
  }
}
