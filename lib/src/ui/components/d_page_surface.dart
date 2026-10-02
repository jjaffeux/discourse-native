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
    this.revealHeaderAtEnd = false,
    this.scrollBody = false,
    this.limitContentSize,
    required this.child,
    this.identity,
  }) : assert(child != null),
       bodyBuilder = null;

  /// Floats the header over an existing scrollable. Insert [DPageHeaderGeometry.spacer]
  /// at the start of its scroll content, or wrap it in a SliverToBoxAdapter.
  /// The viewport and spacer keep their sizes throughout header animations.
  const DPageSurface.scrollable({
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
    this.revealHeaderAtEnd = false,
    this.limitContentSize,
    this.identity,
    required this.bodyBuilder,
  }) : assert(bodyBuilder != null),
       child = null,
       scrollBody = false;

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
  /// reveal completely when scrolling reaches the top. Content shorter than
  /// twice the viewport height keeps the header visible.
  final bool hideHeaderOnScroll;

  /// Whether reaching the physical bottom also reveals the retracting header.
  ///
  /// Requires [hideHeaderOnScroll]. The header stays visible through viewport
  /// changes at the bottom until the reader scrolls back toward the top.
  final bool revealHeaderAtEnd;

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
  final Widget? child;
  final Widget Function(BuildContext context, DPageHeaderGeometry header)?
  bodyBuilder;
  final Object? identity;

  /// Reads the overlay geometry without rebuilding when the header moves.
  /// Geometry listeners run during layout and must not rebuild widgets.
  /// Set [insideViewport] when reading from a scrolling row. Nested viewports
  /// have their own edges and do not inherit the page header's obstruction.
  static DPageHeaderGeometry? headerGeometryOf(
    BuildContext context, {
    bool insideViewport = false,
  }) {
    final scope = context.getInheritedWidgetOfExactType<_PageHeaderScope>();
    if (scope == null) return null;
    var parent = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (insideViewport && parent != null) {
      parent = Scrollable.maybeOf(parent.context, axis: Axis.vertical);
    }
    if (parent != null &&
        identical(
          parent.context.getInheritedWidgetOfExactType<_PageHeaderScope>(),
          scope,
        )) {
      return null;
    }
    return scope.geometry;
  }

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
  final _headerGeometry = DPageHeaderGeometry._();
  Widget? _builtBody;
  late final AnimationController _headerAnimation;
  bool _headerHidden = false;
  bool _headerHeldAtEnd = false;
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
    _builtBody = null;
    if (widget.header == null) _headerGeometry._update(0, 0);
    if (oldWidget.identity != widget.identity ||
        oldWidget.hideHeaderOnScroll != widget.hideHeaderOnScroll ||
        oldWidget.revealHeaderAtEnd != widget.revealHeaderAtEnd ||
        (oldWidget.header != null && widget.header == null)) {
      _headerHidden = false;
      _headerHeldAtEnd = false;
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

  bool _isPageScroll(int depth, BuildContext? context) {
    if (depth == 0) return true;
    // A table may put its main vertical list inside a horizontal viewport.
    // Ignore that horizontal boundary, but never react to an embedded vertical
    // scroller (for example a code block inside a post).
    var nestedVertical = false;
    context?.visitAncestorElements((element) {
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

  bool _keepHeaderVisibleForShortContent(ScrollMetrics metrics) {
    var viewport = metrics.viewportDimension;
    if (!widget.scrollBody && widget.bodyBuilder == null) {
      final header =
          _headerKey.currentContext?.findRenderObject()
              as _RenderScrollHeaderExtent?;
      // Column pages grow their viewport as the header retracts. Compare with
      // its fully shown size so the animation cannot cross its own cutoff.
      if (header != null) {
        viewport -= header.naturalHeight - header.size.height;
      }
    }
    final contentHeight =
        metrics.maxScrollExtent -
        metrics.minScrollExtent +
        metrics.viewportDimension;
    if (viewport > 0 && contentHeight >= 2 * viewport) return false;
    _headerHeldAtEnd = false;
    _directionDistance = 0;
    _lastScrollTime = null;
    _animateHeader(hidden: false);
    return true;
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (widget.header != null &&
        widget.hideHeaderOnScroll &&
        notification.metrics.axis == Axis.vertical &&
        _isPageScroll(notification.depth, notification.context)) {
      _keepHeaderVisibleForShortContent(notification.metrics);
    }
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (widget.header == null || !widget.hideHeaderOnScroll) return false;
    if (!_isPageScroll(notification.depth, notification.context) ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails == null &&
        !_userScrolling) {
      _headerHeldAtEnd = false;
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
    if (_keepHeaderVisibleForShortContent(notification.metrics)) return false;
    if (notification is ScrollUpdateNotification && _userScrolling) {
      final metrics = notification.metrics;
      final reversed = metrics.axisDirection == AxisDirection.up;
      final atTop = reversed
          ? metrics.pixels >= metrics.maxScrollExtent
          : metrics.pixels <= metrics.minScrollExtent;
      final atEnd =
          widget.revealHeaderAtEnd &&
          (reversed
              ? metrics.pixels <= metrics.minScrollExtent + 4
              : metrics.pixels >= metrics.maxScrollExtent - 4);
      if (atTop) {
        _headerHeldAtEnd = false;
        _directionDistance = 0;
        _animateHeader(hidden: false);
      } else if (atEnd) {
        // Returning a mobile dock can reduce the viewport while a fling is
        // still moving. Keep the header revealed through that extra travel.
        _headerHeldAtEnd = true;
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
          if (_headerHeldAtEnd && !revealing) return false;
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
                if (revealing) _headerHeldAtEnd = false;
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
    _headerGeometry.dispose();
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
    final floating = widget.scrollBody || widget.bodyBuilder != null;
    Widget scrollableBody() => _builtBody ??= Builder(
      builder: (context) => widget.bodyBuilder!(context, _headerGeometry),
    );
    final body = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetrics,
      child: NotificationListener<ScrollNotification>(
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
          child: floating
              ? DScrollFadeScope(
                  topInset: _headerGeometry._readVisibleExtent,
                  repaint: _headerGeometry,
                  child: ScrollConfiguration(
                    behavior: DScrollBehavior(
                      delegate: ScrollConfiguration.of(context),
                    ),
                    child: widget.bodyBuilder != null
                        ? scrollableBody()
                        : SingleChildScrollView(
                            // A page owns this viewport. Sharing the shell's primary
                            // controller with another page disables its edge fade.
                            primary: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (widget.header != null)
                                  _headerGeometry.spacer,
                                widget.child!,
                              ],
                            ),
                          ),
                  ),
                )
              : widget.child!,
        ),
      ),
    );
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.tabs,
        if (!floating || widget.header == null) ?header,
        Expanded(
          child: floating && widget.header != null
              ? ClipRect(
                  child: _PageOverlay(
                    geometry: _headerGeometry,
                    extents: () => (
                      headerBox()?.naturalHeight ?? 0,
                      headerBox()?.visibleHeight ?? 0,
                    ),
                    header: header!,
                    body: ClipRect(
                      clipper: _HeaderBodyClipper(_headerGeometry),
                      child: _PageHeaderScope(
                        geometry: _headerGeometry,
                        child: body,
                      ),
                    ),
                  ),
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

/// Measured header space for a page with an overlaid header.
/// Extents update during layout, before the body is laid out. Listeners may
/// invalidate render geometry or schedule work after the frame, but must not
/// rebuild widgets synchronously.
class DPageHeaderGeometry extends ChangeNotifier {
  DPageHeaderGeometry._();

  double _naturalExtent = 0;
  double _visibleExtent = 0;
  double get naturalExtent => _naturalExtent;
  double get visibleExtent => _visibleExtent;
  double _readVisibleExtent() => _visibleExtent;

  void _update(double natural, double visible) {
    if (natural == _naturalExtent && visible == _visibleExtent) return;
    _naturalExtent = natural;
    _visibleExtent = visible;
    notifyListeners();
  }

  /// Stable leading space inside the scroll content.
  Widget get spacer => inset(const SizedBox.shrink(), fullExtent: true);

  /// Places an overlay below the visible header, or reserves the full header
  /// for a loading body. This changes layout without rebuilding [child].
  Widget inset(Widget child, {bool fullExtent = false}) =>
      _HeaderInset(geometry: this, fullExtent: fullExtent, child: child);
}

class _PageHeaderScope extends InheritedWidget {
  const _PageHeaderScope({required this.geometry, required super.child});
  final DPageHeaderGeometry geometry;

  @override
  bool updateShouldNotify(_PageHeaderScope oldWidget) =>
      geometry != oldWidget.geometry;
}

class _HeaderInset extends SingleChildRenderObjectWidget {
  const _HeaderInset({
    required this.geometry,
    required this.fullExtent,
    required super.child,
  });
  final DPageHeaderGeometry geometry;
  final bool fullExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeaderInset(geometry, fullExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeaderInset renderObject,
  ) {
    renderObject.update(geometry, fullExtent);
  }
}

class _RenderHeaderInset extends RenderShiftedBox {
  _RenderHeaderInset(this._geometry, this._fullExtent) : super(null);

  DPageHeaderGeometry _geometry;
  bool _fullExtent;
  double _laidOutExtent = 0;

  double get _extent =>
      _fullExtent ? _geometry.naturalExtent : _geometry.visibleExtent;

  void _headerChanged() {
    if (_laidOutExtent != _extent) markNeedsLayout();
  }

  void update(DPageHeaderGeometry geometry, bool fullExtent) {
    if (_geometry != geometry) {
      if (attached) _geometry.removeListener(_headerChanged);
      _geometry = geometry;
      if (attached) _geometry.addListener(_headerChanged);
    }
    _fullExtent = fullExtent;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _geometry.addListener(_headerChanged);
  }

  @override
  void detach() {
    _geometry.removeListener(_headerChanged);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child!.getDryLayout(
      constraints.deflate(EdgeInsets.only(top: _extent)),
    );
    return constraints.constrain(
      Size(childSize.width, childSize.height + _extent),
    );
  }

  @override
  void performLayout() {
    _laidOutExtent = _extent;
    child!.layout(
      constraints.deflate(EdgeInsets.only(top: _laidOutExtent)),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height + _laidOutExtent),
    );
    (child!.parentData! as BoxParentData).offset = Offset(0, _laidOutExtent);
  }
}

// Measure the header before updating any body geometry. The layout callback
// permits the dependent spacer and overlays to invalidate inside this subtree,
// so both are correct in the same frame, including the very first layout.
class _PageOverlay extends MultiChildRenderObjectWidget {
  _PageOverlay({
    required this.geometry,
    required this.extents,
    required Widget header,
    required Widget body,
  }) : super(children: [body, header]);

  final DPageHeaderGeometry geometry;
  final ValueGetter<(double, double)> extents;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPageOverlay(geometry, extents);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPageOverlay renderObject,
  ) {
    renderObject.extents = extents;
    renderObject.markNeedsLayout();
  }
}

class _RenderPageOverlay extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  _RenderPageOverlay(this.geometry, this.extents);
  final DPageHeaderGeometry geometry;
  ValueGetter<(double, double)> extents;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderParentData) {
      child.parentData = _HeaderParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    lastChild!.layout(
      BoxConstraints.tightFor(width: size.width),
      parentUsesSize: true,
    );
    invokeLayoutCallback<BoxConstraints>((_) {
      final (natural, visible) = extents();
      geometry._update(natural, visible);
    });
    firstChild!.layout(BoxConstraints.tight(size));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _HeaderBodyClipper extends CustomClipper<Rect> {
  _HeaderBodyClipper(this.geometry) : super(reclip: geometry);
  final DPageHeaderGeometry geometry;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, geometry.visibleExtent, size.width, size.height);

  @override
  bool shouldReclip(_HeaderBodyClipper oldClipper) =>
      oldClipper.geometry != geometry;
}
