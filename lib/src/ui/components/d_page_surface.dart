import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../theme/d_icon.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/header_motion.dart';
import '../foundation/tokens.dart';
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
  /// The standard page heading: a title that yields to persistent controls,
  /// with the Native scroll fade in place of a divider or an opaque fill.
  ///
  /// Use [bodyBuilder] for an existing viewport and reserve [DPageHeaderGeometry.spacer]
  /// in its scroll content. Use [child] for a bounded body such as a table or
  /// calendar. The kit owns the heading typography, spacing and scroll motion.
  /// An [icon] marks the title the way the page's navigation entry does.
  DPageSurface.headed({
    super.key,
    required Widget title,
    DIconData? icon,
    Widget? controls,
    this.bodyBuilder,
    this.adaptiveBodyBuilder,
    this.child,
    this.identity,
    this.limitContentSize,
    this.footer,
    this.foldTitleAtTop = false,
  }) : assert(
         (bodyBuilder != null ? 1 : 0) +
                 (adaptiveBodyBuilder != null ? 1 : 0) +
                 (child != null ? 1 : 0) ==
             1,
       ),
       floatingFooter = false,
       header = _PageTitle(icon: icon, child: title),
       headerControls = _PageControls(child: controls),
       compactHeader = null,
       initialCompactHeader = null,
       measureCompactHeader = false,
       tabs = null,
       framed = false,
       border = false,
       backgroundColor = null,
       borderRadius = null,
       hideHeaderOnScroll = true,
       minimumScrollExtent = 120,
       revealHeaderAtEnd = false,
       headerSuppressed = null;

  const DPageSurface({
    super.key,
    this.header,
    this.compactHeader,
    this.initialCompactHeader,
    this.measureCompactHeader = false,
    this.headerControls,
    this.tabs,
    this.footer,
    this.framed = true,
    this.border = true,
    this.backgroundColor,
    this.borderRadius,
    this.hideHeaderOnScroll = false,
    this.minimumScrollExtent,
    this.revealHeaderAtEnd = false,
    this.headerSuppressed,

    this.limitContentSize,
    required this.child,
    this.identity,
  }) : assert(child != null),
       foldTitleAtTop = false,
       floatingFooter = false,
       adaptiveBodyBuilder = null,
       bodyBuilder = null;

  /// Floats the header over an existing scrollable. Insert [DPageHeaderGeometry.spacer]
  /// at the start of its scroll content, or wrap it in a SliverToBoxAdapter.
  /// The viewport and spacer keep their sizes throughout header animations.
  const DPageSurface.scrollable({
    super.key,
    this.header,
    this.compactHeader,
    this.initialCompactHeader,
    this.measureCompactHeader = false,
    this.headerControls,
    this.tabs,
    this.footer,
    this.floatingFooter = false,
    this.framed = true,
    this.border = true,
    this.backgroundColor,
    this.borderRadius,
    this.hideHeaderOnScroll = false,
    this.minimumScrollExtent,
    this.revealHeaderAtEnd = false,
    this.headerSuppressed,
    this.limitContentSize,
    this.identity,
    required this.bodyBuilder,
  }) : assert(bodyBuilder != null),
       foldTitleAtTop = false,
       adaptiveBodyBuilder = null,
       child = null;

  /// Directory indexes keep a compact title away from the top, including
  /// programmatic jumps; ordinary pages reveal their title on upward input.
  final bool foldTitleAtTop;

  /// Optional header, fixed unless [hideHeaderOnScroll] is enabled.
  final Widget? header;

  /// Alternative reader layout after scrolling past the difference between
  /// its full and compact measured extents. The full spacer remains reserved.
  final Widget? compactHeader;

  /// Starts a reader in this layout and keeps it through restoration and
  /// loading until the user scrolls. Null follows scroll position immediately.
  /// Changes take effect when [identity] changes, not when content arrives.
  final bool? initialCompactHeader;

  /// Measures an inert, offstage copy of [compactHeader] before its first use.
  /// This makes the switch follow its actual width and text scaling instead of
  /// the initial 76px estimate. Enable for headers that can mount an independent
  /// copy; shared GlobalKeys or externally owned control state must not be used
  /// in both layouts. The visible header retains its own element and state.
  final bool measureCompactHeader;

  /// A control bar below the title that remains visible when [header] retracts.
  /// The title's original space remains reserved above the scrolling body, so
  /// retraction moves the bar without moving the content or its scroll anchor.
  final Widget? headerControls;

  /// Follow vertical scroll distance, or reveal when scrolling reaches the
  /// top. Standard headings stay visible below 120px of scroll overflow.
  /// Custom reader headers stay visible below two viewport heights.
  final bool hideHeaderOnScroll;

  /// Scroll overflow needed before the header can retract. Null preserves the
  /// reader policy of two viewport heights. Standard page headings use 120px.
  /// Zero lets short, scrollable conversations hide their header and shared dock.
  final double? minimumScrollExtent;

  /// Whether reaching the physical bottom also reveals the retracting header.
  ///
  /// Requires [hideHeaderOnScroll]. The header stays visible through viewport
  /// changes at the bottom until the reader scrolls back toward the top.
  final bool revealHeaderAtEnd;

  /// Temporarily yields the title and its controls to content that owns the
  /// viewport. The full scroll spacer remains, while the header's paint, hit
  /// targets, semantics and body obstruction leave together. Releasing this
  /// restores the ordinary scroll-driven position. The caller owns this value.
  final ValueListenable<bool>? headerSuppressed;

  /// Persistent tabs above the retracting header.
  final Widget? tabs;

  /// Persistent actions below the viewport.
  final Widget? footer;

  /// Overlays [footer] at the bottom of the full-height scrolling viewport.
  /// The measured [DPageHeaderGeometry.footerExtent] lets content reserve room
  /// for its live edge while history continues behind the footer.
  final bool floatingFooter;

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

  /// Keeps a directory lazy while the measured heading and footer fit. When
  /// they leave less than 48px for rows, false asks for a natural-height body
  /// and the whole page scrolls together. The same title and controls remain.
  final Widget Function(BuildContext context, bool bounded)?
  adaptiveBodyBuilder;

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
    with TickerProviderStateMixin {
  final _headerFocus = FocusNode(canRequestFocus: false);
  final _headerKey = GlobalKey();
  double? _measuredCompactHeight;
  final _headerGeometry = DPageHeaderGeometry._();
  Widget? _builtBody;
  ({bool bounded, Widget child})? _builtAdaptiveBody;
  late final HeaderMotion _motion = HeaderMotion(this)
    ..addListener(_updateHeader);
  late final _suppression = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(_updateHeader);
  late final _titleFold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addListener(_updateHeader);
  double _titleFoldTarget = 0;
  bool _compact = false;
  bool _compactFollowsScroll = true;
  double _compactHeight = 76;
  Timer? _compactTimer;
  Widget? get _header =>
      _compact ? widget.compactHeader ?? widget.header : widget.header;

  // Until the edge fade engages, the body is wholly below the header, so the
  // first row's lift and shadow may paint into the controls' empty padding.
  final _bodyAtTop = ValueNotifier(false);
  bool _headerHeldAtEnd = false;
  bool _userScrolling = false;
  ScrollDirection _direction = ScrollDirection.idle;
  bool _gone = false;
  bool _updateScheduled = false;
  DScrollChromeController? _scrollChrome;
  bool _chromeHeaderEnabled = true;

  double get _motionSpan {
    final header =
        _headerKey.currentContext?.findRenderObject()
            as _RenderScrollHeaderExtent?;
    if (header == null) return 64;
    return widget.header is _PageTitle
        ? header.titleHeight
        : header.naturalHeight;
  }

  ValueListenable<double> get _progress => widget.foldTitleAtTop
      ? _titleFold
      : (_chromeHeaderEnabled ? _scrollChrome : null) ?? _motion;
  double get _hiddenFraction => widget.hideHeaderOnScroll ? _progress.value : 0;

  @override
  void initState() {
    super.initState();
    _compact = widget.initialCompactHeader ?? false;
    _compactFollowsScroll = widget.initialCompactHeader == null;
    _headerFocus.addListener(_revealFocusedHeader);
    widget.headerSuppressed?.addListener(_syncSuppression);
    _suppression.value = widget.headerSuppressed?.value == true ? 1 : 0;
  }

  void _syncSuppression() {
    final target = widget.headerSuppressed?.value == true ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _suppression.value = target;
    } else {
      _suppression.animateTo(target, curve: Curves.easeOutCubic);
    }
    // Focus and semantics stop immediately; paint and obstruction ease away.
    setState(() {});
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
    final enabled = TickerMode.valuesOf(context).enabled;
    if (identical(chrome, _scrollChrome) && enabled == _chromeHeaderEnabled) {
      return;
    }
    _scrollChrome?.removeListener(_updateHeader);
    _scrollChrome?.unregisterHeader(this);
    _scrollChrome = chrome;
    _chromeHeaderEnabled = enabled;
    chrome?.addListener(_updateHeader);
    _registerHeader();
  }

  void _registerHeader() {
    // Retained navigation previews must not set the active page's scroll
    // threshold, motion distance, or focus policy.
    if (!_chromeHeaderEnabled || widget.header == null) {
      _scrollChrome?.unregisterHeader(this);
      return;
    }
    _scrollChrome?.registerHeader(
      this,
      focus: _headerFocus,
      minimumScrollExtent: widget.minimumScrollExtent,
      motionExtent: () => _motionSpan,
      layoutReduction: () {
        if ((!widget.hideHeaderOnScroll) ||
            widget.bodyBuilder != null ||
            (widget.headerControls != null && widget.header is! _PageTitle)) {
          return 0;
        }
        final header =
            _headerKey.currentContext?.findRenderObject()
                as _RenderScrollHeaderExtent?;
        return header == null ? 0 : header.naturalHeight - header.layoutHeight;
      },
      layoutExtent: () {
        if ((!widget.hideHeaderOnScroll) ||
            widget.bodyBuilder != null ||
            (widget.headerControls != null && widget.header is! _PageTitle)) {
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
    if (oldWidget.minimumScrollExtent != widget.minimumScrollExtent ||
        (oldWidget.header == null) != (widget.header == null)) {
      _registerHeader();
    }
    _builtBody = null;
    _builtAdaptiveBody = null;
    if (oldWidget.headerSuppressed != widget.headerSuppressed) {
      oldWidget.headerSuppressed?.removeListener(_syncSuppression);
      widget.headerSuppressed?.addListener(_syncSuppression);
      _syncSuppression();
    }
    if (_header == null) _headerGeometry._update(0, 0);
    if (!widget.floatingFooter || widget.footer == null) {
      _headerGeometry._updateFooter(0);
    }
    if (oldWidget.identity != widget.identity ||
        oldWidget.hideHeaderOnScroll != widget.hideHeaderOnScroll ||
        oldWidget.revealHeaderAtEnd != widget.revealHeaderAtEnd ||
        (oldWidget.header != null && _header == null)) {
      _compactTimer?.cancel();
      _compact = widget.initialCompactHeader ?? false;
      _compactFollowsScroll = widget.initialCompactHeader == null;
      _compactHeight = 76;
      _measuredCompactHeight = null;
      _headerHeldAtEnd = false;
      _userScrolling = false;
      _direction = ScrollDirection.idle;
      _headerGeometry._update(0, 0);
      _motion.reset();
      _titleFold.value = 0;
      _titleFoldTarget = 0;
    }
  }

  void _updateHeader() {
    // Only accessibility boundaries rebuild widgets. Motion goes straight to
    // the render objects, including the body mask and sticky-day geometry.
    final gone = _hiddenFraction == 1 || _suppression.value == 1;
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

  void _updateBodyAtTop(
    ScrollMetrics metrics,
    int depth,
    BuildContext? origin,
  ) {
    if (metrics.axis != Axis.vertical || !_isPageScroll(depth, origin)) return;
    // Match the edge fade's 2px tolerance, so one of the two always hides
    // content that has scrolled under the header.
    _bodyAtTop.value =
        metrics.axisDirection == AxisDirection.down &&
        metrics.pixels - metrics.minScrollExtent <= 2;
  }

  bool _keepHeaderVisibleForShortContent(ScrollMetrics metrics) {
    var viewport = metrics.viewportDimension;
    if ((widget.bodyBuilder == null)) {
      final header =
          _headerKey.currentContext?.findRenderObject()
              as _RenderScrollHeaderExtent?;
      // Column pages grow their viewport as the header retracts. Compare with
      // its fully shown size so the animation cannot cross its own cutoff.
      if (header != null) {
        viewport -= header.naturalHeight - header.layoutHeight;
      }
    }
    final contentHeight =
        metrics.maxScrollExtent -
        metrics.minScrollExtent +
        metrics.viewportDimension;
    if (widget.minimumScrollExtent != null
        ? contentHeight - viewport >= widget.minimumScrollExtent!
        : viewport > 0 && contentHeight >= 2 * viewport) {
      return false;
    }
    _headerHeldAtEnd = false;
    _motion.reveal(fresh: true);
    return true;
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    _updateBodyAtTop(
      notification.metrics,
      notification.depth,
      notification.context,
    );
    if (widget.measureCompactHeader) {
      _updateCompact(
        notification.metrics,
        notification.depth,
        notification.context,
      );
    }

    if (widget.adaptiveBodyBuilder != null &&
        notification.metrics.maxScrollExtent <=
            notification.metrics.minScrollExtent) {
      return false;
    }
    _revealStandardTitleAtTop(
      notification.metrics,
      notification.depth,
      notification.context,
    );
    _updateTitleFold(
      notification.metrics,
      notification.depth,
      notification.context,
    );
    if (widget.foldTitleAtTop) return false;
    if (_scrollChrome != null) return false;
    if (_header != null &&
        widget.hideHeaderOnScroll &&
        notification.metrics.axis == Axis.vertical &&
        _isPageScroll(notification.depth, notification.context)) {
      _keepHeaderVisibleForShortContent(notification.metrics);
    }
    return false;
  }

  void _updateTitleFold(
    ScrollMetrics metrics,
    int depth,
    BuildContext? origin,
  ) {
    if (!widget.foldTitleAtTop ||
        metrics.axis != Axis.vertical ||
        !_isPageScroll(depth, origin)) {
      return;
    }
    final target = metrics.pixels - metrics.minScrollExtent > 2 ? 1.0 : 0.0;
    if (_titleFoldTarget == target) return;
    _titleFoldTarget = target;
    void update() {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _titleFold.value = target;
      } else {
        _titleFold.animateTo(target, curve: Curves.easeOutCubic);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  void _revealStandardTitleAtTop(
    ScrollMetrics metrics,
    int depth,
    BuildContext? origin,
  ) {
    if (widget.header is! _PageTitle ||
        widget.foldTitleAtTop ||
        metrics.axis != Axis.vertical ||
        !_isPageScroll(depth, origin) ||
        metrics.pixels - metrics.minScrollExtent > 2 ||
        metrics.maxScrollExtent <= metrics.minScrollExtent) {
      return;
    }
    _motion.reveal(fresh: true);
    if (_chromeHeaderEnabled) _scrollChrome?.reveal();
  }

  void _updateCompact(
    ScrollMetrics metrics,
    int depth,
    BuildContext? scrollContext,
  ) {
    if (!_compactFollowsScroll ||
        _headerFocus.hasFocus ||
        widget.compactHeader == null ||
        metrics.axis != Axis.vertical ||
        !_isPageScroll(depth, scrollContext)) {
      return;
    }
    final box =
        _headerKey.currentContext?.findRenderObject()
            as _RenderScrollHeaderExtent?;
    if (_compact && box != null) {
      _compactHeight = box.naturalHeight;
    } else if (widget.measureCompactHeader && _measuredCompactHeight != null) {
      _compactHeight = _measuredCompactHeight! + (box?.controlsHeight ?? 0);
    }
    final floor = math.max(0.0, _headerGeometry.naturalExtent - _compactHeight);
    final top = metrics.axisDirection == AxisDirection.up
        ? metrics.maxScrollExtent - metrics.pixels
        : metrics.pixels - metrics.minScrollExtent;
    final compact = top > floor;
    if (compact == _compact) return;
    _compactTimer?.cancel();
    void change() {
      if (!mounted) return;
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _compact = compact);
        });
      } else {
        setState(() => _compact = compact);
      }
    }

    if (compact && _gone) {
      _compactTimer = Timer(const Duration(milliseconds: 240), change);
    } else {
      change();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_compactFollowsScroll &&
        notification.metrics.axis == Axis.vertical &&
        ((notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null)) &&
        _isPageScroll(notification.depth, notification.context)) {
      _compactFollowsScroll = true;
    }
    _updateBodyAtTop(
      notification.metrics,
      notification.depth,
      notification.context,
    );
    _revealStandardTitleAtTop(
      notification.metrics,
      notification.depth,
      notification.context,
    );
    _updateTitleFold(
      notification.metrics,
      notification.depth,
      notification.context,
    );
    _updateCompact(
      notification.metrics,
      notification.depth,
      notification.context,
    );
    if (widget.foldTitleAtTop ||
        _scrollChrome != null ||
        _header == null ||
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
      final span = _motionSpan;
      _motion.scroll(down > 0 && top - down < 48 ? top - 48 : down, span: span);
    }
    return false;
  }

  @override
  void dispose() {
    _scrollChrome?.removeListener(_updateHeader);
    _scrollChrome?.unregisterHeader(this);
    widget.headerSuppressed?.removeListener(_syncSuppression);
    _suppression.dispose();
    _titleFold.dispose();
    _bodyAtTop.dispose();
    _compactTimer?.cancel();
    _motion.dispose();
    _headerFocus.dispose();
    _headerGeometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.header is _PageTitle
      ? LayoutBuilder(
          builder: (context, viewport) =>
              _buildPage(context, viewportExtent: viewport.maxHeight),
        )
      : _buildPage(context);

  Widget _buildPage(BuildContext context, {double? viewportExtent}) {
    final maxHeaderExtent =
        viewportExtent != null && widget.adaptiveBodyBuilder == null
        ? math.max(0.0, viewportExtent - 48)
        : null;
    _headerGeometry._maxExtent = maxHeaderExtent ?? double.infinity;
    _headerGeometry._retainNaturalExtent = _compact;
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
    final headerContent = _header == null
        ? widget.headerControls == null
              ? null
              : fixedContent(widget.headerControls!)
        : fixedContent(
            Stack(
              fit: StackFit.passthrough,
              children: [
                if (widget.measureCompactHeader &&
                    !_compact &&
                    widget.compactHeader != null)
                  Offstage(
                    child: ExcludeSemantics(
                      child: ExcludeFocus(
                        child: IgnorePointer(
                          child: TickerMode(
                            enabled: false,
                            child: _CompactHeaderMeasure(
                              onExtent: (height) =>
                                  _measuredCompactHeight = height,
                              child: SizedBox(
                                width: double.infinity,
                                child: widget.compactHeader,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ClipRect(
                  child: _ScrollHeaderExtent(
                    key: _headerKey,
                    progress: _progress,
                    suppression: _suppression,
                    enabled: widget.hideHeaderOnScroll,
                    floating: (widget.bodyBuilder != null),
                    releaseSpace: widget.header is _PageTitle,
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
                              child: RepaintBoundary(child: _header!),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
    final suppressed = widget.headerSuppressed?.value == true;
    final header = headerContent == null
        ? null
        : IgnorePointer(
            ignoring: suppressed,
            child: ExcludeSemantics(
              excluding: suppressed,
              child: ExcludeFocus(
                excluding: suppressed,
                child: maxHeaderExtent == null
                    ? headerContent
                    : ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeaderExtent),
                        child: _HeaderOverflow(
                          maxExtent: maxHeaderExtent,
                          child: headerContent,
                        ),
                      ),
              ),
            ),
          );
    if (widget.adaptiveBodyBuilder case final builder?) {
      return DPageContentSettings(
        limitContentSize: limited,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: _onScrollMetrics,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ScrollConfiguration(
              behavior: DScrollBehavior(
                delegate: ScrollConfiguration.of(context),
              ),
              child: SingleChildScrollView(
                primary: false,
                child: _AdaptivePageLayout(
                  viewportExtent: viewportExtent!,
                  naturalHeaderExtent: () =>
                      (_headerKey.currentContext?.findRenderObject()
                              as _RenderScrollHeaderExtent?)
                          ?.naturalHeight ??
                      0,
                  children: [
                    ?header,
                    LayoutBuilder(
                      builder: (context, slot) {
                        final bounded = slot.hasBoundedHeight;
                        if (_builtAdaptiveBody?.bounded != bounded) {
                          _builtAdaptiveBody = (
                            bounded: bounded,
                            child: Builder(
                              builder: (context) => builder(context, bounded),
                            ),
                          );
                        }
                        return _builtAdaptiveBody!.child;
                      },
                    ),
                    if (widget.footer case final footer?) fixedContent(footer),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    _RenderScrollHeaderExtent? headerBox() =>
        _headerKey.currentContext?.findRenderObject()
            as _RenderScrollHeaderExtent?;
    final floating = (widget.bodyBuilder != null);
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
                              if (_header != null) _headerGeometry.spacer,
                              widget.child!,
                            ],
                          ),
                        ),
                ),
              )
            : ScrollConfiguration(
                behavior: DScrollBehavior(
                  delegate: ScrollConfiguration.of(context),
                ),
                child: widget.child!,
              ),
      ),
    );
    final overlaidFooter = widget.floatingFooter && widget.footer != null;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.tabs,
        if (!floating || _header == null) ?header,
        Expanded(
          child: floating && (_header != null || widget.floatingFooter)
              ? ClipRect(
                  child: _PageOverlay(
                    geometry: _headerGeometry,
                    extents: () => (
                      headerBox()?.naturalHeight ?? 0,
                      headerBox()?.visibleHeight ?? 0,
                    ),
                    header: header == null
                        ? null
                        : ClipRect(
                            clipper: _HeaderHitClipper(_headerGeometry),
                            child: header,
                          ),
                    footer: overlaidFooter
                        ? fixedContent(widget.footer!)
                        : null,
                    body: ClipRect(
                      clipper: _HeaderBodyClipper(
                        _headerGeometry,
                        _bodyAtTop,
                        widget.headerControls is _PageControls
                            ? _PageControls.bottomPadding
                            : 0,
                      ),
                      child: _PageHeaderScope(
                        geometry: _headerGeometry,
                        child: body,
                      ),
                    ),
                  ),
                )
              : body,
        ),
        if (!overlaidFooter)
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

// Scroll notifications can arrive during viewport layout. Cache this extent
// in the measuring box's own layout so no notification reads a sibling's size.
class _CompactHeaderMeasure extends SingleChildRenderObjectWidget {
  const _CompactHeaderMeasure({required this.onExtent, required super.child});
  final ValueChanged<double> onExtent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCompactHeaderMeasure(onExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCompactHeaderMeasure renderObject,
  ) {
    renderObject
      ..onExtent = onExtent
      ..markNeedsLayout();
  }
}

class _RenderCompactHeaderMeasure extends RenderProxyBox {
  _RenderCompactHeaderMeasure(this.onExtent);
  ValueChanged<double> onExtent;

  @override
  void performLayout() {
    super.performLayout();
    onExtent(size.height);
  }
}

class _HeaderOverflow extends StatefulWidget {
  const _HeaderOverflow({required this.maxExtent, required this.child});
  final double maxExtent;
  final Widget child;
  @override
  State<_HeaderOverflow> createState() => _HeaderOverflowState();
}

class _HeaderOverflowState extends State<_HeaderOverflow> {
  bool _overflow = false;
  bool _pending = false;
  bool _scheduled = false;
  void _measure(bool overflow) {
    _pending = overflow;
    if (overflow == _overflow || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _overflow != _pending) {
        setState(() => _overflow = _pending);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _HeaderMeasure(
      maxExtent: widget.maxExtent,
      scrolling: _overflow,
      onOverflow: _measure,
      child: widget.child,
    );
    if (!_overflow) return content;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) => true,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: SingleChildScrollView(primary: false, child: content),
      ),
    );
  }
}

class _HeaderMeasure extends SingleChildRenderObjectWidget {
  const _HeaderMeasure({
    required this.maxExtent,
    required this.scrolling,
    required this.onOverflow,
    required super.child,
  });
  final double maxExtent;
  final bool scrolling;
  final ValueChanged<bool> onOverflow;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeaderMeasure(maxExtent, scrolling, onOverflow);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeaderMeasure renderObject,
  ) {
    renderObject
      ..maxExtent = maxExtent
      ..scrolling = scrolling
      ..onOverflow = onOverflow
      ..markNeedsLayout();
  }
}

class _RenderHeaderMeasure extends RenderProxyBox {
  _RenderHeaderMeasure(this.maxExtent, this.scrolling, this.onOverflow);
  double maxExtent;
  bool scrolling;
  ValueChanged<bool> onOverflow;
  @override
  void performLayout() {
    child!.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    onOverflow(child!.size.height > maxExtent);
    size = constraints.constrain(
      Size(
        child!.size.width,
        scrolling
            ? child!.size.height
            : math.min(maxExtent, child!.size.height),
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => super.paint(context, offset),
    );
  }
}

class _HeaderHitClipper extends CustomClipper<Rect> {
  _HeaderHitClipper(this.geometry) : super(reclip: geometry);
  final DPageHeaderGeometry geometry;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    0,
    size.width,
    math.min(size.height, geometry.visibleExtent),
  );
  @override
  bool shouldReclip(_HeaderHitClipper oldClipper) =>
      oldClipper.geometry != geometry;
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({this.icon, required this.child});
  final DIconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touch =
        theme.platform == TargetPlatform.iOS ||
        theme.platform == TargetPlatform.android;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, touch ? 12 : 20, 16, 0),
      child: Semantics(
        header: true,
        headingLevel: 1,
        child: DefaultTextStyle.merge(
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: DiscourseTypography.xxl,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: icon == null
                ? child
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DIcon(
                        icon!,
                        size: 16,
                        color: DTokens.of(context).mutedForeground,
                      ),
                      const SizedBox(width: 9),
                      Flexible(child: child),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PageControls extends StatelessWidget {
  const _PageControls({this.child});
  final Widget? child;

  static const bottomPadding = 14.0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
    child: child ?? const SizedBox.shrink(),
  );
}

// Keep the header at its natural height while animating the visible fraction.
// Measuring here also handles header size changes during the transition.
class _ScrollHeaderExtent extends MultiChildRenderObjectWidget {
  _ScrollHeaderExtent({
    super.key,
    required this.progress,
    required this.suppression,
    required this.enabled,
    required this.floating,
    required this.releaseSpace,
    required this.geometry,
    required Widget child,
    Widget? controls,
  }) : super(children: [child, ?controls]);
  final ValueListenable<double> progress;
  final ValueListenable<double> suppression;
  final bool enabled;
  final bool floating;
  final bool releaseSpace;
  final DPageHeaderGeometry geometry;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollHeaderExtent(
        progress,
        suppression,
        enabled,
        floating,
        releaseSpace,
        geometry,
      );
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollHeaderExtent renderObject,
  ) => renderObject.update(
    progress,
    suppression,
    enabled,
    floating,
    releaseSpace,
  );
}

class _HeaderParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderScrollHeaderExtent extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  _RenderScrollHeaderExtent(
    this._progress,
    this._suppression,
    this._enabled,
    this._floating,
    this._releaseSpace,
    this.geometry,
  );
  ValueListenable<double> _progress;
  ValueListenable<double> _suppression;
  bool _enabled;
  bool _floating;
  bool _releaseSpace;
  final DPageHeaderGeometry geometry;
  double get _hiddenFraction => _enabled ? _progress.value : 0;
  double _hiddenHeight(double title, double total) =>
      title * _hiddenFraction +
      (total - title * _hiddenFraction) * _suppression.value;
  void update(
    ValueListenable<double> progress,
    ValueListenable<double> suppression,
    bool enabled,
    bool floating,
    bool releaseSpace,
  ) {
    if (!identical(_suppression, suppression)) {
      if (attached) _suppression.removeListener(_move);
      _suppression = suppression;
      if (attached) _suppression.addListener(_move);
    }
    if (!identical(_progress, progress)) {
      if (attached) _progress.removeListener(_move);
      _progress = progress;
      if (attached) _progress.addListener(_move);
    }
    _enabled = enabled;
    _floating = floating;
    _releaseSpace = releaseSpace;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_move);
    _suppression.addListener(_move);
  }

  @override
  void detach() {
    _progress.removeListener(_move);
    _suppression.removeListener(_move);
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
    final hidden = _hiddenHeight(firstChild!.size.height, naturalHeight);
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
  double titleHeight = 0;
  double layoutHeight = 0;
  double get controlsHeight => naturalHeight - titleHeight;

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
        childSize.height +
            (controls?.height ?? 0) -
            (_floating || (controls != null && !_releaseSpace)
                ? 0
                : _hiddenHeight(
                    childSize.height,
                    childSize.height + (controls?.height ?? 0),
                  )),
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
    titleHeight = firstChild!.size.height;
    final controls = childCount > 1 ? lastChild : null;
    controls?.layout(natural, parentUsesSize: true);
    naturalHeight = firstChild!.size.height + (controls?.size.height ?? 0);
    final hidden = _hiddenHeight(firstChild!.size.height, naturalHeight);
    visibleHeight = naturalHeight - hidden;
    size = constraints.constrain(
      Size(
        firstChild!.size.width,
        !_floating && (controls == null || _releaseSpace)
            ? visibleHeight
            : naturalHeight,
      ),
    );
    layoutHeight = size.height;
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

  double _footerExtent = 0;

  /// Bottom space occupied by a floating footer, measured before body layout.
  double get footerExtent => _footerExtent;

  void _updateFooter(double extent) {
    if (_footerExtent == extent) return;
    _footerExtent = extent;
    notifyListeners();
  }

  double _naturalExtent = 0;
  double _visibleExtent = 0;
  double _maxExtent = double.infinity;
  bool _retainNaturalExtent = false;
  double get naturalExtent => _naturalExtent;
  double get visibleExtent => _visibleExtent;
  double _readVisibleExtent() => _visibleExtent;

  void _update(double natural, double visible) {
    natural = math.min(natural, _maxExtent);
    visible = math.min(visible, _maxExtent);
    final full = _retainNaturalExtent && natural > 0
        ? math.max(natural, _naturalExtent)
        : natural;
    if (full == _naturalExtent && visible == _visibleExtent) return;
    _naturalExtent = full;
    _visibleExtent = visible;
    notifyListeners();
  }

  /// Stable leading space inside the scroll content.
  Widget get spacer => inset(const SizedBox.shrink(), fullExtent: true);

  /// Keeps an overlay above the floating footer as its height changes.
  Widget footerInset(Widget child) =>
      _FooterInset(geometry: this, child: child);

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

class _FooterInset extends SingleChildRenderObjectWidget {
  const _FooterInset({required this.geometry, required super.child});
  final DPageHeaderGeometry geometry;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFooterInset(geometry);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFooterInset renderObject,
  ) {
    renderObject.geometry = geometry;
  }
}

class _RenderFooterInset extends RenderProxyBox {
  _RenderFooterInset(this._geometry);
  DPageHeaderGeometry _geometry;
  double _laidOutExtent = 0;

  set geometry(DPageHeaderGeometry value) {
    if (identical(value, _geometry)) return;
    if (attached) _geometry.removeListener(_changed);
    _geometry = value;
    if (attached) _geometry.addListener(_changed);
    markNeedsLayout();
  }

  void _changed() {
    if (_laidOutExtent != _geometry.footerExtent) markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _geometry.addListener(_changed);
  }

  @override
  void detach() {
    _geometry.removeListener(_changed);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final extent = _geometry.footerExtent;
    final childSize = child!.getDryLayout(
      constraints.deflate(EdgeInsets.only(bottom: extent)),
    );
    return constraints.constrain(
      Size(childSize.width, childSize.height + extent),
    );
  }

  @override
  void performLayout() {
    _laidOutExtent = _geometry.footerExtent;
    child!.layout(
      constraints.deflate(EdgeInsets.only(bottom: _laidOutExtent)),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height + _laidOutExtent),
    );
  }
}

// Measure the header before updating any body geometry. The layout callback
// permits the dependent spacer and overlays to invalidate inside this subtree,
// so both are correct in the same frame, including the very first layout.
class _PageOverlay extends MultiChildRenderObjectWidget {
  _PageOverlay({
    required this.geometry,
    required this.extents,
    required Widget? header,
    required Widget? footer,
    required Widget body,
  }) : hasHeader = header != null,
       hasFooter = footer != null,
       super(children: [body, ?header, ?footer]);

  final DPageHeaderGeometry geometry;
  final ValueGetter<(double, double)> extents;
  final bool hasHeader;
  final bool hasFooter;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPageOverlay(geometry, extents, hasHeader, hasFooter);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPageOverlay renderObject,
  ) {
    renderObject
      ..hasHeader = hasHeader
      ..hasFooter = hasFooter
      ..extents = extents;
    renderObject.markNeedsLayout();
  }
}

class _RenderPageOverlay extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderParentData> {
  _RenderPageOverlay(
    this.geometry,
    this.extents,
    this.hasHeader,
    this.hasFooter,
  );
  final DPageHeaderGeometry geometry;
  ValueGetter<(double, double)> extents;
  bool hasHeader;
  bool hasFooter;

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
    final header = hasHeader ? childAfter(firstChild!) : null;
    final footer = hasFooter ? lastChild : null;
    final natural = BoxConstraints.tightFor(width: size.width);
    header?.layout(natural, parentUsesSize: true);
    footer?.layout(natural, parentUsesSize: true);
    if (footer != null) {
      (footer.parentData! as BoxParentData).offset = Offset(
        0,
        size.height - footer.size.height,
      );
    }
    invokeLayoutCallback<BoxConstraints>((_) {
      final (natural, visible) = hasHeader ? extents() : (0.0, 0.0);
      geometry._update(natural, visible);
      geometry._updateFooter(footer?.size.height ?? 0);
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
  _HeaderBodyClipper(this.geometry, this.atTop, this.emptyBand)
    : super(reclip: Listenable.merge([geometry, atTop]));
  final DPageHeaderGeometry geometry;
  final ValueListenable<bool> atTop;

  /// Height of the header's lowest band, which holds nothing of its own.
  final double emptyBand;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    geometry.visibleExtent - (atTop.value ? emptyBand : 0),
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_HeaderBodyClipper oldClipper) =>
      oldClipper.geometry != geometry ||
      oldClipper.atTop != atTop ||
      oldClipper.emptyBand != emptyBand;
}

/// Leading space for a lazy viewport beneath a floating page header. Only
/// natural extent changes rebuild the viewport; scrolling changes paint alone.
class DPageScrollInsets extends StatefulWidget {
  const DPageScrollInsets({super.key, required this.builder});
  final Widget Function(BuildContext context, EdgeInsets insets) builder;
  @override
  State<DPageScrollInsets> createState() => _DPageScrollInsetsState();
}

class _DPageScrollInsetsState extends State<DPageScrollInsets> {
  DPageHeaderGeometry? _geometry;
  double _top = 0;
  bool _scheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DPageSurface.headerGeometryOf(context);
    if (identical(next, _geometry)) return;
    _geometry?.removeListener(_changed);
    _geometry = next;
    next?.addListener(_changed);
    _top = next?.naturalExtent ?? 0;
  }

  void _changed() {
    if (_top == _geometry?.naturalExtent || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() => _top = _geometry?.naturalExtent ?? 0);
    });
  }

  @override
  void dispose() {
    _geometry?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    EdgeInsets.only(top: _top, bottom: DScrollChrome.bottomInsetOf(context)),
  );
}

/// Lays out the header, the list and an optional footer. The list reads the
/// outcome from its constraints: a bounded height is a lazy list's own
/// viewport, an unbounded one asks for every row.
class _AdaptivePageLayout extends MultiChildRenderObjectWidget {
  const _AdaptivePageLayout({
    required this.viewportExtent,
    required this.naturalHeaderExtent,
    required super.children,
  });

  final double viewportExtent;
  final ValueGetter<double> naturalHeaderExtent;

  @override
  _RenderAdaptivePageLayout createRenderObject(BuildContext context) =>
      _RenderAdaptivePageLayout(viewportExtent, naturalHeaderExtent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAdaptivePageLayout renderObject,
  ) {
    renderObject
      ..viewportExtent = viewportExtent
      ..naturalHeaderExtent = naturalHeaderExtent
      ..markNeedsLayout();
  }
}

class _AdaptivePageParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAdaptivePageLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AdaptivePageParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AdaptivePageParentData> {
  _RenderAdaptivePageLayout(this._viewportExtent, this.naturalHeaderExtent);

  ValueGetter<double> naturalHeaderExtent;
  double _viewportExtent;
  set viewportExtent(double value) {
    if (value == _viewportExtent) return;
    _viewportExtent = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AdaptivePageParentData) {
      child.parentData = _AdaptivePageParentData();
    }
  }

  @override
  void performLayout() {
    final header = firstChild!;
    final list = childAfter(header)!;
    final footer = childAfter(list);
    final width = constraints.maxWidth;
    final natural = BoxConstraints.tightFor(width: width);
    header.layout(natural, parentUsesSize: true);
    footer?.layout(natural, parentUsesSize: true);
    final headerExtent = header.size.height;
    final footerExtent = footer?.size.height ?? 0;
    final room = _viewportExtent - headerExtent - footerExtent;
    final double listExtent;
    // Title motion must not switch the list between bounded and natural
    // height, which would reset the outer scroll position during the gesture.
    final fits = _viewportExtent - naturalHeaderExtent() - footerExtent >= 48;
    if (fits) {
      list.layout(BoxConstraints.tightFor(width: width, height: room));
      listExtent = room;
    } else {
      list.layout(natural, parentUsesSize: true);
      listExtent = math.max(room, list.size.height);
    }
    final height = headerExtent + listExtent + footerExtent;
    (header.parentData! as _AdaptivePageParentData).offset = Offset.zero;
    (list.parentData! as _AdaptivePageParentData).offset = Offset(
      0,
      headerExtent,
    );
    if (footer != null) {
      (footer.parentData! as _AdaptivePageParentData).offset = Offset(
        0,
        height - footerExtent,
      );
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
