import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/header_motion.dart';
import 'd_card.dart';
import 'd_page_reading_lane.dart';
import 'd_scroll_behavior.dart';
import 'd_scroll_chrome.dart';

/// A bounded page with a shared border, fixed tabs and footer, and a retracting
/// header. The width policy aligns the header, body content, and footer while
/// leaving the scrolling viewport at the pane edge. DPageReadingLane constrains
/// content inside that viewport. Only deliberate
/// scrolling in the body retracts the header; restoration and nested scrolls
/// leave it alone. Scroll distance moves a continuous target; one frame loop
/// smooths all coupled chrome toward it, with reversal slack and endpoint holds.
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

  /// Follow vertical scroll distance, or reveal when scrolling reaches the
  /// top. Content shorter than
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
  final _headerFocus = FocusNode(canRequestFocus: false);
  final _headerKey = GlobalKey();
  final _headerGeometry = DPageHeaderGeometry._();
  Widget? _builtBody;
  late final HeaderMotion _motion = HeaderMotion(this)
    ..addListener(_updateHeader);
  bool _headerHeldAtEnd = false;
  bool _userScrolling = false;
  ScrollDirection _direction = ScrollDirection.idle;
  bool _gone = false;
  bool _updateScheduled = false;
  DScrollChromeController? _scrollChrome;

  ValueListenable<double> get _progress => _scrollChrome ?? _motion;
  double get _hiddenFraction => widget.hideHeaderOnScroll ? _progress.value : 0;

  @override
  void initState() {
    super.initState();
    _headerFocus.addListener(_revealFocusedHeader);
  }

  void _revealFocusedHeader() {
    if (_headerFocus.hasFocus &&
        _scrollChrome == null &&
        widget.hideHeaderOnScroll) {
      _motion.reveal(fresh: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.configure(
      DHeaderMotionSettings.of(context),
      disableAnimations: MediaQuery.disableAnimationsOf(context),
    );
    final chrome = DScrollChrome.maybeOf(context);
    if (identical(chrome, _scrollChrome)) return;
    _scrollChrome?.removeListener(_updateHeader);
    _scrollChrome?.unregisterHeader(this);
    _scrollChrome = chrome;
    chrome?.addListener(_updateHeader);
    chrome?.registerHeader(
      this,
      focus: _headerFocus,
      motionExtent: () =>
          (_headerKey.currentContext?.findRenderObject()
                  as _RenderScrollHeaderExtent?)
              ?.naturalHeight ??
          64,
      layoutReduction: () {
        if (!widget.hideHeaderOnScroll ||
            widget.scrollBody ||
            widget.bodyBuilder != null ||
            widget.headerControls != null) {
          return 0;
        }
        final header =
            _headerKey.currentContext?.findRenderObject()
                as _RenderScrollHeaderExtent?;
        return header == null ? 0 : header.naturalHeight - header.size.height;
      },
      layoutExtent: () {
        if (!widget.hideHeaderOnScroll ||
            widget.scrollBody ||
            widget.bodyBuilder != null ||
            widget.headerControls != null) {
          return 0;
        }
        return (_headerKey.currentContext?.findRenderObject()
                    as _RenderScrollHeaderExtent?)
                ?.naturalHeight ??
            0;
      },
    );
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
      _headerHeldAtEnd = false;
      _userScrolling = false;
      _direction = ScrollDirection.idle;
      _headerGeometry._update(0, 0);
      _motion.reset();
    }
  }

  void _updateHeader() {
    // Only accessibility boundaries rebuild widgets. Motion goes straight to
    // the render objects, including the body mask and sticky-day geometry.
    final gone = _hiddenFraction == 1;
    if (_gone == gone) return;
    _gone = gone;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
    } else if (!_updateScheduled) {
      _updateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScheduled = false;
        if (mounted) setState(() {});
      });
    }
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
    _motion.reveal(fresh: true);
    return true;
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (_scrollChrome != null) return false;
    if (widget.header != null &&
        widget.hideHeaderOnScroll &&
        notification.metrics.axis == Axis.vertical &&
        _isPageScroll(notification.depth, notification.context)) {
      _keepHeaderVisibleForShortContent(notification.metrics);
    }
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (_scrollChrome != null ||
        widget.header == null ||
        !widget.hideHeaderOnScroll) {
      return false;
    }
    if (!_isPageScroll(notification.depth, notification.context) ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails == null &&
        !_userScrolling) {
      _headerHeldAtEnd = false;
    }
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      if (_userScrolling) _direction = notification.direction;
    }
    if (_keepHeaderVisibleForShortContent(notification.metrics)) return false;
    if (notification is! ScrollUpdateNotification || !_userScrolling) {
      return false;
    }
    final metrics = notification.metrics;
    final reversed = metrics.axisDirection == AxisDirection.up;
    final top = reversed
        ? metrics.maxScrollExtent - metrics.pixels
        : metrics.pixels - metrics.minScrollExtent;
    final atEnd =
        widget.revealHeaderAtEnd &&
        metrics.maxScrollExtent - metrics.minScrollExtent - top <= 4;
    if (top <= 48 || _headerFocus.hasFocus) {
      _headerHeldAtEnd = false;
      _motion.reveal(fresh: true);
    } else if (atEnd) {
      _headerHeldAtEnd = true;
      _motion.reveal();
    } else if (!metrics.outOfRange) {
      final delta = notification.scrollDelta ?? 0;
      // Layout corrections against user intent must not reveal a paged reader.
      if ((_direction == ScrollDirection.reverse && delta <= 0) ||
          (_direction == ScrollDirection.forward && delta >= 0)) {
        return false;
      }
      final down = reversed ? -delta : delta;
      if (_headerHeldAtEnd && down > 0) return false;
      if (down < 0) _headerHeldAtEnd = false;
      final span =
          (_headerKey.currentContext?.findRenderObject()
                  as _RenderScrollHeaderExtent?)
              ?.naturalHeight ??
          64;
      _motion.scroll(down > 0 && top - down < 48 ? top - 48 : down, span: span);
    }
    return false;
  }

  @override
  void dispose() {
    _scrollChrome?.removeListener(_updateHeader);
    _scrollChrome?.unregisterHeader(this);
    _motion.dispose();
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
                progress: _progress,
                enabled: widget.hideHeaderOnScroll,
                floating: widget.scrollBody || widget.bodyBuilder != null,
                geometry: _headerGeometry,
                controls: widget.headerControls,
                child: ExcludeSemantics(
                  excluding: _gone,
                  child: ExcludeFocus(
                    excluding: _gone,
                    // The extent and clip restrict hits to the visible slice.
                    child: TickerMode(
                      enabled: !_gone,
                      child: SizedBox(
                        width: double.infinity,
                        child: Focus(
                          focusNode: _headerFocus,
                          child: RepaintBoundary(child: widget.header!),
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
                              if (widget.header != null) _headerGeometry.spacer,
                              widget.child!,
                            ],
                          ),
                        ),
                ),
              )
            : widget.child!,
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
    required this.progress,
    required this.enabled,
    required this.floating,
    required this.geometry,
    required Widget child,
    Widget? controls,
  }) : super(children: [child, ?controls]);
  final ValueListenable<double> progress;
  final bool enabled;
  final bool floating;
  final DPageHeaderGeometry geometry;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollHeaderExtent(progress, enabled, floating, geometry);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollHeaderExtent renderObject,
  ) => renderObject.update(progress, enabled, floating);
}

class _HeaderParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderScrollHeaderExtent extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  _RenderScrollHeaderExtent(
    this._progress,
    this._enabled,
    this._floating,
    this.geometry,
  );
  ValueListenable<double> _progress;
  bool _enabled;
  bool _floating;
  final DPageHeaderGeometry geometry;
  double get _hiddenFraction => _enabled ? _progress.value : 0;
  void update(ValueListenable<double> progress, bool enabled, bool floating) {
    if (!identical(_progress, progress)) {
      if (attached) _progress.removeListener(_move);
      _progress = progress;
      if (attached) _progress.addListener(_move);
    }
    _enabled = enabled;
    _floating = floating;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_move);
  }

  @override
  void detach() {
    _progress.removeListener(_move);
    super.detach();
  }

  void _move() {
    if (!_floating || !hasSize || !firstChild!.hasSize) {
      markNeedsLayout();
      return;
    }
    _position();
    geometry._update(naturalHeight, visibleHeight);
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void _position() {
    final hidden = _hiddenFraction * firstChild!.size.height;
    visibleHeight = naturalHeight - hidden;
    (firstChild!.parentData! as BoxParentData).offset = Offset(0, -hidden);
    if (childCount > 1) {
      (lastChild!.parentData! as BoxParentData).offset = Offset(
        0,
        firstChild!.size.height - hidden,
      );
    }
  }

  double naturalHeight = 0;
  double visibleHeight = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderParentData) {
      child.parentData = _HeaderParentData();
    }
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
        controls == null && !_floating
            ? childSize.height * (1 - _hiddenFraction)
            : childSize.height + (controls?.height ?? 0),
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
        controls == null && !_floating
            ? firstChild!.size.height - hidden
            : firstChild!.size.height + (controls?.size.height ?? 0),
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
    final full = natural == 0
        ? 0.0
        : (natural > _naturalExtent ? natural : _naturalExtent);
    if (full == _naturalExtent && visible == _visibleExtent) return;
    _naturalExtent = full;
    _visibleExtent = visible;
    notifyListeners();
  }

  /// Stable leading space inside the scroll content.
  Widget get spacer => inset(const SizedBox.shrink(), fullExtent: true);

  /// Places an overlay below the visible header, or reserves the full header
  /// for a loading body. Floating insets move during paint; full insets reserve
  /// stable layout space without rebuilding [child].
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
    if (_fullExtent) {
      if (_laidOutExtent != _extent) markNeedsLayout();
    } else if (_laidOutExtent != _geometry.naturalExtent) {
      markNeedsLayout();
    } else if (child != null &&
        (child!.parentData! as BoxParentData).offset.dy != _extent) {
      (child!.parentData! as BoxParentData).offset = Offset(0, _extent);
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
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
    _laidOutExtent = _fullExtent ? _extent : _geometry.naturalExtent;
    child!.layout(
      constraints.deflate(EdgeInsets.only(top: _laidOutExtent)),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height + _laidOutExtent),
    );
    (child!.parentData! as BoxParentData).offset = Offset(0, _extent);
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
