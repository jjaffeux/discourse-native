part of 'd_sheet.dart';

// iOS reports the end of its keyboard transition explicitly. Other hosts use
// settled viewport metrics; a focus change alone never starts the inset.
abstract final class _DSheetKeyboardTransitions {
  static const _channel = MethodChannel('org.discourse.native/keyboard');
  static final ready = ValueNotifier<bool?>(null);
  static bool _installed = false;
  static int _revision = 0;

  static Future<void> refresh() async {
    if (!_installed) {
      _installed = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'keyboardReady' && call.arguments is bool) {
          _revision++;
          ready.value = call.arguments as bool;
        }
      });
    }
    final revision = _revision;
    bool? value;
    try {
      value = await _channel.invokeMethod<bool>('keyboardReady');
    } on MissingPluginException {
      value = null;
    } on PlatformException {
      value = null;
    }
    if (revision == _revision) ready.value = value;
  }
}

class _DSheetAdaptiveMenuScope extends InheritedWidget {
  const _DSheetAdaptiveMenuScope({
    required this.menu,
    required this.expanded,
    required this.canCollapse,
    required super.child,
  });

  final _DSheetAdaptiveMenuState menu;
  final bool expanded;
  final bool canCollapse;

  @override
  bool updateShouldNotify(_DSheetAdaptiveMenuScope oldWidget) =>
      menu != oldWidget.menu ||
      expanded != oldWidget.expanded ||
      canCollapse != oldWidget.canCollapse;
}

// Consume only the part of a finger movement needed to raise the sheet. The
// remainder scrolls the original viewport in the same gesture, with its native
// physics. A downward pull transfers back at the top of that viewport.
// SingleChildScrollView can retain its old metrics after a layout correction.
// Each physics chain keeps the actual previous extent independently.
class _DSheetMenuDimensions {
  double? maximum;
}

class _DSheetMenuPhysics extends ScrollPhysics {
  _DSheetMenuPhysics({
    required this.consume,
    required this.resizingInsets,
    _DSheetMenuDimensions? dimensions,
    super.parent,
  }) : _dimensions = dimensions ?? _DSheetMenuDimensions();

  final double Function(ScrollMetrics, double) consume;
  final bool Function() resizingInsets;
  final _DSheetMenuDimensions _dimensions;

  @override
  _DSheetMenuPhysics applyTo(ScrollPhysics? ancestor) => _DSheetMenuPhysics(
    consume: consume,
    resizingInsets: resizingInsets,
    dimensions: _dimensions,
    parent: buildParent(ancestor),
  );

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final remaining = consume(position, offset);
    // BouncingScrollPhysics expects a nonzero offset. A drag fully consumed
    // by the sheet has nothing left to send to the content viewport.
    return remaining == 0
        ? 0
        : super.applyPhysicsToUserOffset(position, remaining);
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final previousMaximum = _dimensions.maximum ?? oldPosition.maxScrollExtent;
    _dimensions.maximum = newPosition.maxScrollExtent;
    if (resizingInsets() &&
        oldPosition.axis == Axis.vertical &&
        previousMaximum > oldPosition.minScrollExtent) {
      // Keep the same distance from the end as the floating margins resize
      // the viewport. Correcting dimensions preserves an active finger drag;
      // jumpTo would cancel it and pin small reverse drags to the last row.
      return (newPosition.maxScrollExtent -
              math.max(0, previousMaximum - newPosition.pixels))
          .clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

class _DSheetMenuScrollBehavior extends ScrollBehavior {
  const _DSheetMenuScrollBehavior(
    this.delegate,
    this.consume,
    this.resizingInsets,
  );

  final ScrollBehavior delegate;
  final double Function(ScrollMetrics, double) consume;
  final bool Function() resizingInsets;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => _DSheetMenuPhysics(
    consume: consume,
    resizingInsets: resizingInsets,
    parent: delegate.getScrollPhysics(context),
  );

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => delegate.buildScrollbar(context, child, details);

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => delegate.buildOverscrollIndicator(context, child, details);

  @override
  Set<PointerDeviceKind> get dragDevices => delegate.dragDevices;

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      delegate.getPlatform(context);

  @override
  bool shouldNotify(_DSheetMenuScrollBehavior oldDelegate) =>
      delegate != oldDelegate.delegate ||
      consume != oldDelegate.consume ||
      resizingInsets != oldDelegate.resizingInsets;
}

class _DSheetAdaptiveMenu extends StatefulWidget {
  const _DSheetAdaptiveMenu({
    required this.presentation,
    required this.onDismiss,
    required this.retained,
    this.onDismissRequested,
  });

  final DDialogPresentation presentation;
  final VoidCallback? onDismiss;
  final bool retained;
  final VoidCallback? onDismissRequested;

  @override
  State<_DSheetAdaptiveMenu> createState() => _DSheetAdaptiveMenuState();
}

class _DSheetAdaptiveMenuState extends State<_DSheetAdaptiveMenu>
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 280);
  static const _curve = Cubic(.32, .72, 0, 1);
  final _surface = GlobalKey();
  final _positions = <ScrollPosition>{};
  late final _travel = AnimationController.unbounded(vsync: this);
  late final _inset = AnimationController(vsync: this, duration: _duration);
  late final _keyboardPlacement = AnimationController(
    vsync: this,
    duration: _duration,
  );
  double _low = 0;
  double _room = 0;
  double _lift = 0;
  double _keyboard = 0;
  bool _measured = false;
  bool _interacted = false;
  bool _dragging = false;
  bool _scrollDrag = false;
  bool _scheduled = false;
  bool _floating = false;
  bool _raiseForKeyboard = false;
  bool _expanded = true;
  bool _resizingInsets = false;
  double _previousInset = 0;
  bool _keyboardSettled = false;
  bool _floatingBeforeKeyboard = false;
  bool _keyboardMinimumElapsed = false;
  bool _keyboardMetricsStable = false;
  Timer? _keyboardMinimum;
  Timer? _keyboardStability;
  int? _pointer;
  VelocityTracker? _velocity;
  double _startOffset = 0;
  double _swipeExtent = 1;
  double? _dismissOrigin;
  double _dismissCurve = 1;
  double _dismissAnimationOrigin = 1;
  double _exitVelocity = 0;
  double? _exitKeyboard;
  double? _exitSafeBottom;
  double _safeBottom = 0;
  DOverlayRoute<dynamic, Object>? _route;
  Simulation? Function()? _exitSimulation;

  bool get _animate => !MediaQuery.disableAnimationsOf(context);

  double get _offset => _dismissOrigin == null
      ? _travel.value
      : _dismissOrigin! +
            (_room - _dismissOrigin!) *
                (1 -
                        widget.presentation.animation.value /
                            _dismissAnimationOrigin)
                    .clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _travel.addListener(_travelChanged);
    _travel.addStatusListener(_travelStatus);
    _inset.addListener(_changed);
    _keyboardPlacement.addListener(_changed);
    _keyboardPlacement.addStatusListener(_travelStatus);
    _DSheetKeyboardTransitions.ready.addListener(_keyboardTransition);
    unawaited(_DSheetKeyboardTransitions.refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    if (_route?.reverseSimulationBuilder == _exitSimulation) {
      _route?.reverseSimulationBuilder = null;
    }
    _route = !widget.retained && route is DOverlayRoute<dynamic, Object>
        ? route
        : null;
    _exitSimulation = _beginExit;
    _route?.reverseSimulationBuilder = _exitSimulation;
  }

  Simulation? _beginExit() {
    if (!_animate) return null;
    _interacted = true;
    _travel.stop();
    _inset.stop();
    _keyboardPlacement.stop();
    _dismissOrigin = _travel.value;
    _dismissAnimationOrigin = math.max(
      .001,
      widget.presentation.animation.value,
    );
    _dismissCurve = _curve.transform(widget.presentation.animation.value);
    _exitKeyboard = _keyboard * _keyboardPlacement.value;
    _exitSafeBottom = _safeBottom;
    return _DSheetDismissSimulation(
      math.max(1, _room - _travel.value),
      math.max(0, _exitVelocity),
      widget.presentation.animation.value,
      duration: _exitVelocity > 0 ? .24 : .18,
    );
  }

  @override
  void didUpdateWidget(_DSheetAdaptiveMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dismissOrigin == null &&
        !_interacted &&
        // The overlay can rebuild its content before build observes the first
        // keyboard inset. Keep the measured detent: remeasuring as an initial
        // layout would reset travel to zero and skip the keyboard animation.
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        !identical(
          oldWidget.presentation.content,
          widget.presentation.content,
        )) {
      _measured = false;
    }
  }

  void _keyboardTransition() {
    if (_keyboard <= 0 || _keyboardSettled) return;
    final native = _DSheetKeyboardTransitions.ready.value;
    if (native == true ||
        (native == null && _keyboardMinimumElapsed && _keyboardMetricsStable)) {
      _keyboardSettled = true;
      _raiseForKeyboard = true;
      _scheduleMeasure();
      if (mounted) setState(() {});
    }
  }

  void _keyboardChanged(double keyboard) {
    final opening = _keyboard == 0 && keyboard > 0;
    _keyboard = keyboard;
    _keyboardStability?.cancel();
    if (keyboard == 0) {
      _keyboardMinimum?.cancel();
      _keyboardSettled = false;
      _raiseForKeyboard = false;
      _keyboardPlacement.value = 0;
      _keyboardMinimumElapsed = false;
      _keyboardMetricsStable = false;
    } else {
      if (opening) {
        _floatingBeforeKeyboard = _floating;
        _keyboardSettled = _DSheetKeyboardTransitions.ready.value == true;
        _raiseForKeyboard = _keyboardSettled;
        _keyboardMinimumElapsed = false;
        _keyboardMinimum = Timer(const Duration(milliseconds: 300), () {
          _keyboardMinimumElapsed = true;
          _keyboardTransition();
        });
      }
      _keyboardMetricsStable = false;
      _keyboardStability = Timer(const Duration(milliseconds: 80), () {
        _keyboardMetricsStable = true;
        _keyboardTransition();
      });
      _interacted = true;
    }
    _scheduleMeasure();
  }

  void _travelChanged() {
    // Translation and backdrop dimming listen directly to travel. Rebuild the
    // content's inherited state only when the handle changes Expand/Collapse.
    final expanded = _travel.value <= 1;
    if (expanded == _expanded || !mounted) return;
    _expanded = expanded;
    setState(() {});
    _scheduleMeasure();
  }

  void _travelStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _scheduleMeasure();
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _measure();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _measure() {
    if (_dismissOrigin != null) return;
    final box = _surface.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _positions.removeWhere((p) {
      final origin = p.context.notificationContext;
      return origin == null ||
          !origin.mounted ||
          Scrollable.maybeOf(origin)?.position != p;
    });
    final tall = box.size.height + _lift;
    final half = _room * .55;
    final low = _keyboard == 0 && tall > half + 60 ? tall - half : 0.0;
    final wasLow = _low;
    _low = low;
    if (!_measured || (!_interacted && (wasLow - low).abs() > 1)) {
      _measured = true;
      _travel.value = low;
      setState(() {});
    }
    if (_raiseForKeyboard) {
      _raiseForKeyboard = false;
      _settle(0);
      if (_animate) {
        unawaited(_keyboardPlacement.animateTo(1, curve: _curve));
      } else {
        _keyboardPlacement.value = 1;
      }
    }
    _resizingInsets = false;
    final more =
        _travel.value > 1 ||
        _positions.any((p) => p.hasContentDimensions && p.extentAfter > 1);
    // Once the keyboard is ready, margins animate alongside its placement and
    // the sheet's rise. Direct drags retain their existing width and corners.
    final floating = _keyboard > 0 && _keyboardSettled
        ? true
        : _dragging || _travel.isAnimating
        ? _floating
        : _keyboard > 0
        ? _floatingBeforeKeyboard
        : !more;
    if (floating != _floating) {
      _floating = floating;
      if (_animate) {
        unawaited(_inset.animateTo(floating ? 1 : 0, curve: _curve));
      } else {
        _inset.value = floating ? 1 : 0;
      }
    }
  }

  // End anchoring belongs to scroll-triggered margins. A keyboard resize
  // keeps the current rows in place as its viewport shrinks.
  bool _isResizingInsets() => _resizingInsets && _keyboard == 0;

  bool _metrics(ScrollMetricsNotification notification) {
    _remember(notification.context, notification.metrics);
    return false;
  }

  bool _scroll(ScrollNotification notification) {
    _remember(notification.context, notification.metrics);
    return false;
  }

  void _remember(BuildContext? origin, ScrollMetrics metrics) {
    if (origin == null || metrics.axis != Axis.vertical) return;
    final position = Scrollable.maybeOf(origin)?.position;
    if (position != null) _positions.add(position);
    _scheduleMeasure();
  }

  void _start() {
    if (_dismissOrigin != null) return;
    _interacted = true;
    _dragging = true;
    _startOffset = _travel.value;
    final box = _surface.currentContext?.findRenderObject();
    _swipeExtent = math.max(
      1,
      MediaQuery.sizeOf(context).height -
          (box is RenderBox ? box.localToGlobal(Offset.zero).dy : 0),
    );
    _travel.stop();
  }

  void _update(double delta) {
    if (_dismissOrigin != null) return;
    _travel.value = math.max(0, _travel.value + delta);
  }

  double _consume(ScrollMetrics metrics, double delta) {
    if (_pointer == null ||
        metrics.axis != Axis.vertical ||
        _dismissOrigin != null) {
      return delta;
    }
    if (_travel.value <= 0 &&
        !(delta > 0 && metrics.pixels <= metrics.minScrollExtent)) {
      return delta;
    }
    if (!_dragging) _start();
    _scrollDrag = true;
    final before = _travel.value;
    _update(delta);
    return delta - (_travel.value - before);
  }

  void _settle(double to) {
    if (_animate) {
      unawaited(_travel.animateTo(to, duration: _duration, curve: _curve));
    } else {
      _travel.value = to;
    }
  }

  void _toggle() {
    _interacted = true;
    _settle(_travel.value > 1 ? 0 : _low);
  }

  void _finish(double velocity, {bool cancelled = false}) {
    if (!_dragging || _dismissOrigin != null) return;
    _dragging = false;
    _scrollDrag = false;
    if (cancelled) {
      _settle(_startOffset > _low / 2 ? _low : 0);
      return;
    }
    final pulled = _travel.value - _startOffset;
    if (pulled >= 0) {
      // Match standard sheets: velocity shapes an accepted exit, but never
      // turns a short pull into a dismissal. A deliberate expanded pull can
      // return to the lower detent before another pull dismisses it.
      final threshold = _swipeExtent * _sheetDismissFraction;
      if (pulled < threshold) {
        _settle(_startOffset > _low / 2 ? _low : 0);
      } else if (_travel.value >= _low + threshold) {
        _dismiss(velocity);
      } else {
        _settle(_low);
      }
    } else {
      final ahead = _travel.value + velocity * .18;
      final to = velocity < -500
          ? 0.0
          : velocity > 500 && _low > 0
          ? _low
          : ahead > _low / 2
          ? _low
          : 0.0;
      _settle(to);
    }
  }

  void _dismiss(double velocity) {
    _travel.stop();
    if (widget.onDismissRequested != null) {
      _settle(_low);
      widget.onDismissRequested!();
      return;
    }
    final dismiss = widget.onDismiss;
    if (dismiss == null) {
      _settle(_low);
      return;
    }
    if (widget.retained) {
      if (!_animate) {
        dismiss();
        return;
      }
      final destination = MediaQuery.sizeOf(context).height + _lift;
      unawaited(
        _travel
            .animateWith(
              _DSheetDismissSimulation(
                math.max(1, destination - _travel.value),
                math.max(0, velocity),
                _travel.value,
                endValue: destination,
              ),
            )
            .then<void>((_) {
              if (!mounted) return;
              dismiss();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _settle(_low);
              });
            }),
      );
      return;
    }
    _exitVelocity = velocity;
    dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.presentation.animation.status == AnimationStatus.completed) {
        _dismissOrigin = null;
        _exitKeyboard = null;
        _exitSafeBottom = null;
        _exitVelocity = 0;
        _settle(_low);
      }
    });
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null || event.kind != PointerDeviceKind.touch) return;
    _pointer = event.pointer;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _move(PointerMoveEvent event) {
    if (_pointer == event.pointer) {
      _velocity?.addPosition(event.timeStamp, event.position);
    }
  }

  void _up(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    if (_scrollDrag) _finish(_velocity?.getVelocity().pixelsPerSecond.dy ?? 0);
    _pointer = null;
    _velocity = null;
  }

  void _cancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    _finish(0, cancelled: true);
    _pointer = null;
    _velocity = null;
  }

  @override
  void dispose() {
    if (_route?.reverseSimulationBuilder == _exitSimulation) {
      _route?.reverseSimulationBuilder = null;
    }
    _travel.dispose();
    _inset.dispose();
    _keyboardPlacement.dispose();
    _keyboardMinimum?.cancel();
    _keyboardStability?.cancel();
    _DSheetKeyboardTransitions.ready.removeListener(_keyboardTransition);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final view = View.of(context);
    final systemKeyboard = media.viewInsets.bottom;
    if (_dismissOrigin == null && _keyboard != systemKeyboard) {
      _keyboardChanged(systemKeyboard);
    }
    final keyboard = _exitKeyboard ?? _keyboard * _keyboardPlacement.value;
    final safeTop = math.max(
      media.padding.top,
      view.viewPadding.top / view.devicePixelRatio,
    );
    final safeBottom =
        _exitSafeBottom ??
        math.max(
              media.viewPadding.bottom,
              view.viewPadding.bottom / view.devicePixelRatio,
            ) *
            (1 - _keyboardPlacement.value);
    _safeBottom = safeBottom;
    final side = 6 * _inset.value;
    if (_previousInset != _inset.value) {
      _resizingInsets = true;
      _previousInset = _inset.value;
    }
    _lift = (6 + safeBottom) * _inset.value;
    _scheduleMeasure();
    final content = _DSheetAdaptiveMenuScope(
      menu: this,
      expanded: _expanded,
      canCollapse: _low > 0,
      child: _DSheetSideScope(
        side: DSheetSide.bottom,
        inset: _inset.value > 0,
        menuInsetProgress: _inset.value,
        fillAvailableHeight: false,
        extendBehindKeyboard: false,
        child: MediaQuery(
          data: media.copyWith(
            padding: EdgeInsets.only(bottom: safeBottom * (1 - _inset.value)),
            viewInsets: EdgeInsets.zero,
          ),
          child: widget.presentation.content,
        ),
      ),
    );
    final backdrop = widget.presentation.buildBackdrop(blurSigma: 2);
    return LayoutBuilder(
      builder: (context, bounds) {
        _room = math.max(0, bounds.maxHeight - keyboard);
        final maximum = math.max(0.0, _room - safeTop - 8 - _lift);
        return AnimatedBuilder(
          animation: Listenable.merge([widget.presentation.animation, _travel]),
          builder: (context, child) {
            final curve = _animate
                ? _curve.transform(widget.presentation.animation.value)
                : 1.0;
            final dim =
                (1 - math.max(0, _offset - _low) / math.max(1, _room - _low))
                    .clamp(0.0, 1.0);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Opacity(opacity: curve * dim, child: backdrop),
                Positioned(
                  left: side,
                  right: side,
                  bottom: keyboard + _lift,
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      _offset +
                          40 *
                              (1 -
                                  (_dismissOrigin == null
                                      ? curve
                                      : _dismissCurve)),
                    ),
                    child: Offstage(
                      offstage: !_measured,
                      child: ConstrainedBox(
                        key: _surface,
                        constraints: BoxConstraints(maxHeight: maximum),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: GestureDetector(
              supportedDevices: const {PointerDeviceKind.touch},
              onVerticalDragStart: (_) => _start(),
              onVerticalDragUpdate: (details) => _update(details.delta.dy),
              onVerticalDragEnd: (details) =>
                  _finish(details.primaryVelocity ?? 0),
              onVerticalDragCancel: () => _finish(0, cancelled: true),
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _metrics,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _scroll,
                  child: ScrollConfiguration(
                    behavior: _DSheetMenuScrollBehavior(
                      ScrollConfiguration.of(context),
                      _consume,
                      _isResizingInsets,
                    ),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
