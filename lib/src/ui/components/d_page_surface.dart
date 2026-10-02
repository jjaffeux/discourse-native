import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import 'd_card.dart';
import 'd_page_reading_lane.dart';
import 'd_scroll_behavior.dart';

/// A bounded page with a shared border, fixed tabs and footer, and a retracting
/// header. The width policy aligns the header, body content, and footer while
/// leaving the scrolling viewport at the pane edge. DPageReadingLane constrains
/// content inside that viewport. Only deliberate
/// scrolling in the body retracts the header; restoration and nested scrolls
/// leave it alone. A few pixels trigger a short reveal or retraction animation;
/// retraction also requires enough scroll speed to avoid hiding during slow reads.
class DPageSurface extends StatefulWidget {
  const DPageSurface({
    super.key,
    this.header,
    this.headerControls,
    this.tabs,
    this.footer,
    this.framed = true,
    this.border = true,
    this.backgroundColor,
    this.borderRadius,
    this.hideHeaderOnScroll = false,
    this.scrollBody = false,
    this.limitContentSize,
    required this.child,
    this.identity,
  });

  /// Optional header, fixed unless [hideHeaderOnScroll] is enabled.
  final Widget? header;

  /// A control bar below the title that remains visible when [header] retracts.
  /// The title's original space remains reserved above the scrolling body, so
  /// retraction moves the bar without moving the content or its scroll anchor.
  final Widget? headerControls;

  /// Owns a vertical scroll view for [child]. The header floats above it and
  /// reserves its full natural height inside the scroll content. Rows can
  /// scroll into the space released by the retracting title without jumping.
  /// Use non-scrolling content as [child] when enabled.
  final bool scrollBody;

  /// Animate after a small vertical movement, requiring speed to retract, or
  /// reveal completely when scrolling reaches the top.
  final bool hideHeaderOnScroll;

  /// Persistent tabs above the retracting header.
  final Widget? tabs;

  /// Persistent actions below the viewport.
  final Widget? footer;

  /// Disable when composed inside an already framed page or a touch shell.
  final bool framed;

  /// Paints the outer Card outline when framed; retains clipping when false.
  final bool border;

  /// Optional fill for the enclosing Card. Ignored when [framed] is false.
  final Color? backgroundColor;

  /// Optional outline and clip for the enclosing Card; ignored when unframed.
  final BorderRadiusGeometry? borderRadius;

  /// Centers the header, scrolling content, and footer in an 825px-wide lane.
  /// Tabs, the outer surface, and the scroll viewport remain full width. Null
  /// inherits the enclosing page policy; the default is full width.
  final bool? limitContentSize;
  final Widget child;
  final Object? identity;

  @override
  State<DPageSurface> createState() => _DPageSurfaceState();
}

class _DPageSurfaceState extends State<DPageSurface>
    with SingleTickerProviderStateMixin {
  static const _triggerDistance = 6.0;
  static const _hideVelocity = 180.0;
  static const _sampleInterval = Duration(microseconds: 16667);
  static const _scrollPause = Duration(milliseconds: 200);

  final _headerFocus = FocusNode(canRequestFocus: false);
  final _headerKey = GlobalKey();
  late final AnimationController _headerAnimation;
  bool _headerHidden = false;
  bool _userScrolling = false;
  ScrollDirection _direction = ScrollDirection.idle;
  double _directionDistance = 0;
  Duration? _lastScrollTime;
  Duration? _pointerScrollTime;
  Duration? _gestureStartTime;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    _headerAnimation = AnimationController(vsync: this)
      ..addListener(_updateHeader);
  }

  @override
  void didUpdateWidget(DPageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.hideHeaderOnScroll != widget.hideHeaderOnScroll ||
        (oldWidget.header != null && widget.header == null)) {
      _headerHidden = false;
      _headerAnimation.value = 0;
      _userScrolling = false;
      _direction = ScrollDirection.idle;
      _directionDistance = 0;
      _lastScrollTime = null;
      _pointerScrollTime = null;
      _gestureStartTime = null;
    }
  }

  void _animateHeader({required bool hidden}) {
    if (_headerHidden == hidden || (hidden && _headerFocus.hasFocus)) return;
    _headerHidden = hidden;
    final duration = DMotion.duration(
      context,
      hidden ? DMotion.exit : DMotion.enter,
    );
    if (duration == Duration.zero) {
      _headerAnimation.value = hidden ? 1 : 0;
    } else {
      _headerAnimation.animateTo(
        hidden ? 1 : 0,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _updateHeader() {
    // Reduced-motion changes can be raised during layout; animation ticks and
    // ordinary pointer input can update immediately.
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
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _directionDistance = 0;
      _lastScrollTime =
          _gestureStartTime ?? notification.dragDetails?.sourceTimeStamp;
      _gestureStartTime = null;
    }
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      if (_userScrolling && _direction != notification.direction) {
        _direction = notification.direction;
        _directionDistance = 0;
      }
    }
    if (notification is ScrollUpdateNotification && _userScrolling) {
      final metrics = notification.metrics;
      final reversed = metrics.axisDirection == AxisDirection.up;
      final atTop = reversed
          ? metrics.pixels >= metrics.maxScrollExtent
          : metrics.pixels <= metrics.minScrollExtent;
      if (atTop) {
        _directionDistance = 0;
        _animateHeader(hidden: false);
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
              _headerHidden ||
              metrics.maxScrollExtent - metrics.minScrollExtent > headerHeight;
          if (revealing || canRetract) {
            final time =
                notification.dragDetails?.sourceTimeStamp ??
                _pointerScrollTime ??
                SchedulerBinding.instance.currentSystemFrameTimeStamp;
            var elapsed = _lastScrollTime == null
                ? _sampleInterval
                : time - _lastScrollTime!;
            _lastScrollTime = time;
            _pointerScrollTime = null;
            // A wheel packet after a pause starts a fresh burst. The idle gap
            // is not its velocity; touch drags retain their actual event timing.
            if (notification.dragDetails == null && elapsed > _scrollPause) {
              _directionDistance = 0;
              elapsed = _sampleInterval;
            }
            // Wheel packets and synthetic input can share a timestamp. Treat
            // them as one frame rather than dividing by zero.
            final micros = elapsed.inMicroseconds > 0
                ? elapsed.inMicroseconds
                : _sampleInterval.inMicroseconds;
            final velocity =
                delta.abs() * Duration.microsecondsPerSecond / micros;
            if (!revealing && velocity < _hideVelocity) {
              _directionDistance = 0;
            } else {
              _directionDistance += delta.abs();
              if (_directionDistance >= _triggerDistance) {
                _animateHeader(hidden: !revealing);
              }
            }
          }
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    _headerAnimation.dispose();
    _headerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final limited =
        widget.limitContentSize ?? DPageContentSettings.limitOf(context);
    Widget fixedContent(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: limited ? DPageReadingLane.maxWidth : double.infinity,
        ),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
    final header = widget.header == null
        ? widget.headerControls == null
              ? null
              : fixedContent(widget.headerControls!)
        : fixedContent(
            ClipRect(
              child: _ScrollHeaderExtent(
                key: _headerKey,
                hiddenFraction: widget.hideHeaderOnScroll
                    ? _headerAnimation.value
                    : 0,
                controls: widget.headerControls,
                child: ExcludeSemantics(
                  excluding: _headerAnimation.value > 0,
                  child: ExcludeFocus(
                    excluding: _headerAnimation.value > 0,
                    // The extent and clip restrict hits to the visible slice.
                    child: TickerMode(
                      enabled: _headerAnimation.value == 0,
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
          );
    _RenderScrollHeaderExtent? headerBox() =>
        _headerKey.currentContext?.findRenderObject()
            as _RenderScrollHeaderExtent?;
    final body = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Listener(
        onPointerDown: (event) => _gestureStartTime = event.timeStamp,
        onPointerPanZoomStart: (event) => _gestureStartTime = event.timeStamp,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _pointerScrollTime = event.timeStamp == Duration.zero
                ? null
                : event.timeStamp;
          }
        },
        child: widget.scrollBody
            ? DScrollFadeScope(
                topInset: () => headerBox()?.visibleHeight ?? 0,
                child: ScrollConfiguration(
                  behavior: DScrollBehavior(
                    delegate: ScrollConfiguration.of(context),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.header != null)
                          _HeaderGap(
                            extent: () => headerBox()?.naturalHeight ?? 0,
                          ),
                        widget.child,
                      ],
                    ),
                  ),
                ),
              )
            : widget.child,
      ),
    );
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.tabs,
        if (!widget.scrollBody || widget.header == null) ?header,
        Expanded(
          child: widget.scrollBody && widget.header != null
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRect(
                        clipper: _HeaderBodyClipper(
                          () => headerBox()?.visibleHeight ?? 0,
                        ),
                        child: body,
                      ),
                    ),
                    header!,
                  ],
                )
              : body,
        ),
        if (widget.footer case final footer?) fixedContent(footer),
      ],
    );
    return DPageContentSettings(
      limitContentSize: limited,
      child: widget.framed
          ? DCard(
              border: widget.border,
              spacing: 0,
              backgroundColor: widget.backgroundColor,
              borderRadius: widget.borderRadius,
              child: Expanded(child: page),
            )
          : page,
    );
  }
}

// Keep the header at its natural height while animating the visible fraction.
// Measuring here also handles header size changes during the transition.
class _ScrollHeaderExtent extends MultiChildRenderObjectWidget {
  _ScrollHeaderExtent({
    super.key,
    required this.hiddenFraction,
    required Widget child,
    Widget? controls,
  }) : super(children: [child, ?controls]);

  final double hiddenFraction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollHeaderExtent(hiddenFraction);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollHeaderExtent renderObject,
  ) {
    renderObject.hiddenFraction = hiddenFraction;
  }
}

class _HeaderParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderScrollHeaderExtent extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  _RenderScrollHeaderExtent(this._hiddenFraction);

  double naturalHeight = 0;
  double visibleHeight = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderParentData) {
      child.parentData = _HeaderParentData();
    }
  }

  double _hiddenFraction;

  set hiddenFraction(double value) {
    if (_hiddenFraction == value) return;
    _hiddenFraction = value;
    markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final natural = constraints.copyWith(
      minHeight: 0,
      maxHeight: double.infinity,
    );
    final childSize = firstChild!.getDryLayout(natural);
    final controls = childCount > 1 ? lastChild!.getDryLayout(natural) : null;
    return constraints.constrain(
      Size(
        childSize.width,
        controls == null
            ? childSize.height * (1 - _hiddenFraction)
            : childSize.height + controls.height,
      ),
    );
  }

  @override
  void performLayout() {
    final natural = constraints.copyWith(
      minHeight: 0,
      maxHeight: double.infinity,
    );
    firstChild!.layout(natural, parentUsesSize: true);
    final controls = childCount > 1 ? lastChild : null;
    controls?.layout(natural, parentUsesSize: true);
    final hidden = _hiddenFraction * firstChild!.size.height;
    naturalHeight = firstChild!.size.height + (controls?.size.height ?? 0);
    visibleHeight = naturalHeight - hidden;
    size = constraints.constrain(
      Size(
        firstChild!.size.width,
        controls == null
            ? firstChild!.size.height - hidden
            : firstChild!.size.height + controls.size.height,
      ),
    );
    (firstChild!.parentData! as BoxParentData).offset = Offset(0, -hidden);
    if (controls != null) {
      (controls.parentData! as BoxParentData).offset = Offset(
        0,
        firstChild!.size.height - hidden,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _HeaderGap extends LeafRenderObjectWidget {
  const _HeaderGap({required this.extent});
  final ValueGetter<double> extent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeaderGap(extent);

  @override
  void updateRenderObject(BuildContext context, _RenderHeaderGap renderObject) {
    renderObject.extent = extent;
    renderObject.markNeedsLayout();
  }
}

class _RenderHeaderGap extends RenderBox {
  _RenderHeaderGap(this.extent);
  ValueGetter<double> extent;

  @override
  void performLayout() => size = constraints.constrain(Size(0, extent()));
}

class _HeaderBodyClipper extends CustomClipper<Rect> {
  _HeaderBodyClipper(this.extent);
  final ValueGetter<double> extent;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, extent(), size.width, size.height);

  @override
  bool shouldReclip(_HeaderBodyClipper oldClipper) => true;
}
