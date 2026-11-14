part of 'd_sheet.dart';

class _DSheetKeyboardFrame {
  _DSheetKeyboardFrame(this.inset, this.duration, this.elapsed, this.curve);

  final double inset;
  final Duration duration;
  final Duration elapsed;
  final Curve curve;

  static _DSheetKeyboardFrame? parse(Object? value) {
    if (value is! Map) return null;
    double? number(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    final inset = number(value['bottomInset']);
    final seconds = number(value['duration']);
    if (inset == null || inset < 0 || seconds == null || seconds < 0) {
      return null;
    }
    final duration = Duration(microseconds: (seconds * 1000000).round());
    final elapsed = Duration(
      microseconds:
          ((number(value['elapsed']) ?? 0).clamp(0, seconds) * 1000000).round(),
    );
    Curve curve = switch (value['curve']) {
      1 => Curves.easeIn,
      2 => Curves.easeOut,
      3 => Curves.linear,
      _ => Curves.easeInOut,
    };
    final points = value['controlPoints'];
    if (points is List &&
        points.length == 4 &&
        points.every((p) => number(p) != null)) {
      curve = Cubic(
        number(points[0])!,
        number(points[1])!,
        number(points[2])!,
        number(points[3])!,
      );
    }
    final spring = value['spring'];
    if (spring is Map) {
      final mass = number(spring['mass']);
      final stiffness = number(spring['stiffness']);
      final damping = number(spring['damping']);
      final velocity = number(spring['velocity']);
      if (mass != null &&
          mass > 0 &&
          stiffness != null &&
          stiffness > 0 &&
          damping != null &&
          damping >= 0 &&
          velocity != null &&
          seconds > 0) {
        curve = _DSheetKeyboardSpring(
          SpringSimulation(
            SpringDescription(
              mass: mass,
              stiffness: stiffness,
              damping: damping,
            ),
            0,
            1,
            velocity,
          ),
          seconds,
        );
      }
    }
    return _DSheetKeyboardFrame(inset, duration, elapsed, curve);
  }

  Duration get remaining => duration - elapsed;
  Curve get remainingCurve =>
      elapsed == Duration.zero || duration == Duration.zero
      ? curve
      : _DSheetKeyboardRemainingCurve(
          curve,
          elapsed.inMicroseconds / duration.inMicroseconds,
        );
}

class _DSheetKeyboardRemainingCurve extends Curve {
  const _DSheetKeyboardRemainingCurve(this.curve, this.start);
  final Curve curve;
  final double start;

  @override
  double transformInternal(double t) {
    final from = curve.transform(start);
    return from >= 1
        ? 1
        : ((curve.transform(start + (1 - start) * t) - from) / (1 - from))
              .clamp(0.0, 1.0);
  }
}

class _DSheetKeyboardSpring extends Curve {
  const _DSheetKeyboardSpring(this.simulation, this.seconds);
  final SpringSimulation simulation;
  final double seconds;

  @override
  double transformInternal(double t) =>
      simulation.x(t * seconds).clamp(0.0, 1.0);
}

// iOS supplies its target frame and timing before the keyboard moves. Older
// bridges and other hosts retain the settled-metrics fallback.
abstract final class _DSheetKeyboardTransitions {
  static const _channel = MethodChannel('org.discourse.native/keyboard');
  static final ready = ValueNotifier<bool?>(null);
  static final frame = ValueNotifier<_DSheetKeyboardFrame?>(null);
  static bool _installed = false;
  static int _revision = 0;
  static int _queryRevision = 0;

  static Future<void> refresh() async {
    if (!_installed) {
      _installed = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'keyboardReady' && call.arguments is bool) {
          _revision++;
          ready.value = call.arguments as bool;
        } else if (call.method == 'keyboardTransition') {
          final transition = _DSheetKeyboardFrame.parse(call.arguments);
          if (transition != null) {
            _revision++;
            frame.value = transition;
          }
        }
      });
    }
    final revision = _revision;
    final queryRevision = ++_queryRevision;
    bool? value;
    _DSheetKeyboardFrame? transition;
    try {
      transition = _DSheetKeyboardFrame.parse(
        await _channel.invokeMethod<Object?>('keyboardTransition'),
      );
    } on MissingPluginException {
      transition = null;
    } on PlatformException {
      transition = null;
    }
    try {
      value = await _channel.invokeMethod<bool>('keyboardReady');
    } on MissingPluginException {
      value = null;
    } on PlatformException {
      value = null;
    }
    if (revision == _revision && queryRevision == _queryRevision) {
      frame.value = transition;
      ready.value = value;
    }
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

// An expansion gesture belongs to the sheet until release. The next gesture
// scrolls with native physics; downward pulls transfer back at the list's top.
class _DSheetMenuPhysics extends ScrollPhysics {
  const _DSheetMenuPhysics({
    required this.consume,
    required this.stopMomentum,
    required this.contentScale,
    super.parent,
  });

  final double Function(ScrollMetrics, double) consume;
  final bool Function() stopMomentum;
  final double contentScale;

  @override
  _DSheetMenuPhysics applyTo(ScrollPhysics? ancestor) => _DSheetMenuPhysics(
    consume: consume,
    stopMomentum: stopMomentum,
    contentScale: contentScale,
    parent: buildParent(ancestor),
  );

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final remaining = consume(position, offset * contentScale) / contentScale;
    // BouncingScrollPhysics expects a nonzero offset. A drag fully consumed
    // by the sheet has nothing left to send to the content viewport.
    return remaining == 0
        ? 0
        : super.applyPhysicsToUserOffset(position, remaining);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(
    position,
    position.axis == Axis.vertical && stopMomentum() ? 0 : velocity,
  );
}

class _DSheetMenuScrollBehavior extends ScrollBehavior {
  const _DSheetMenuScrollBehavior(
    this.delegate,
    this.consume,
    this.stopMomentum,
  );

  final ScrollBehavior delegate;
  final double Function(ScrollMetrics, double) consume;
  final bool Function() stopMomentum;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => _DSheetMenuPhysics(
    consume: consume,
    stopMomentum: stopMomentum,
    contentScale: DMenuContentScale.isActiveOf(context)
        ? DMenuContentScale.factor
        : 1,
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
      stopMomentum != oldDelegate.stopMomentum;
}

class _DSheetAdaptiveMenu extends StatefulWidget {
  const _DSheetAdaptiveMenu({
    required this.presentation,
    required this.onDismiss,
    required this.retained,
    required this.sizeToContent,
    required this.keepFootInView,
    required this.initiallyExpanded,
    required this.contentLoading,
    this.restAt,
    this.onDismissRequested,
  });

  final DDialogPresentation presentation;
  final VoidCallback? onDismiss;
  final bool retained;
  final bool sizeToContent;
  final bool keepFootInView;
  final bool initiallyExpanded;
  final bool contentLoading;
  final GlobalKey? restAt;
  final VoidCallback? onDismissRequested;

  @override
  State<_DSheetAdaptiveMenu> createState() => _DSheetAdaptiveMenuState();
}

class _DSheetAdaptiveMenuState extends State<_DSheetAdaptiveMenu>
    with
        TickerProviderStateMixin,
        _DSheetKeyboardCoverRefresh<_DSheetAdaptiveMenu> {
  static const _duration = Duration(milliseconds: 280);
  static const _curve = Cubic(.32, .72, 0, 1);
  final _surface = GlobalKey();
  late final _travel = AnimationController.unbounded(vsync: this);
  late final _keyboardPlacement = AnimationController(
    vsync: this,
    duration: _duration,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final _keyboardInsetAnimation = AnimationController.unbounded(
    vsync: this,
  );
  _DSheetKeyboardFrame? _nativeKeyboardFrame;
  late final _peekClock = AnimationController(
    vsync: this,
    duration: DSwipeHint.hold,
  );
  Timer? _peekNext;
  bool _peekTaken = false;
  bool _peeking = false;

  void _cancelPeek() {
    _peekTaken = true;
    _peekNext?.cancel();
    if (_peeking) {
      _peeking = false;
      _travel.stop();
      _peekClock.stop();
    }
  }

  void _schedulePeek() {
    if (widget.restAt == null ||
        _peekTaken ||
        widget.contentLoading ||
        _low <= 0) {
      return;
    }
    _peekTaken = true;
    _peekNext = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _interacted || (_travel.value - _low).abs() > 1) return;
      _peeking = true;
      final target = math.max(0.0, _low - 40);
      if (_animate) {
        unawaited(
          _travel.animateTo(
            target,
            duration: const Duration(milliseconds: 460),
            curve: const Cubic(.3, 1.36, .5, 1),
          ),
        );
        _peekClock.forward(from: 0);
      } else {
        _travel.value = target;
      }
      _peekNext = Timer(DSwipeHint.hold, () {
        if (!mounted || !_peeking) return;
        _peeking = false;
        if (_animate) {
          unawaited(
            _travel.animateTo(
              _low,
              duration: const Duration(milliseconds: 460),
              curve: const Cubic(.3, 1.36, .5, 1),
            ),
          );
        } else {
          _travel.value = _low;
        }
      });
    });
  }

  double _low = 0;
  double _fixedLow = 0;

  // A sheet that keeps its foot in view is laid out no taller than what is in
  // view. Its full height is read whenever a layout was not cut short of it.
  double _fullHeight = 0;
  double _laidHeightOffset = 0;
  double _laidCap = double.infinity;
  double _room = 0;
  double _keyboard = 0;
  bool _measured = false;
  bool _interacted = false;
  bool _dragging = false;
  bool _scrollDrag = false;
  bool _expansionGesture = false;
  bool _scheduled = false;
  bool _contentLayoutPending = false;
  bool _raiseForKeyboard = false;
  bool _expanded = true;
  bool _fullyExpanded = false;
  bool _keyboardSettled = false;
  bool _keyboardMinimumElapsed = false;
  bool _keyboardMetricsStable = false;
  Timer? _keyboardMinimum;
  Timer? _keyboardStability;
  Timer? _wheelEnd;

  late final _restScroll = _DSheetRestScrollController(this);

  double _wheelDelta(double delta) {
    if (widget.restAt == null || _exit.geometry != null) return delta;
    _cancelPeek();
    _interacted = true;
    if (_travel.value <= 0 && (delta >= 0 || _restScroll.position.pixels > 0)) {
      return delta;
    }
    if (!_dragging) _start();
    final before = _travel.value;
    _update(-delta);
    _wheelEnd?.cancel();
    _wheelEnd = Timer(const Duration(milliseconds: 140), () {
      if (delta > 0 && _travel.value <= _low) {
        _dragging = false;
        _settle(0);
      } else {
        _finish(0);
      }
    });
    return delta + _travel.value - before;
  }

  int? _pointer;
  VelocityTracker? _velocity;
  double _startOffset = 0;
  double _swipeExtent = 1;
  final _exit = _DSheetExitLifecycle<_DSheetMenuExitGeometry>();
  double _exitVelocity = 0;
  double? _retainedExitHeightOffset;
  double _safeBottom = 0;

  bool get _animate => !MediaQuery.disableAnimationsOf(context);
  double get _keyboardInset => _keyboardInsetAnimation.value;

  double get _offset => _exit.geometry == null
      ? _travel.value
      : _exit.geometry!.origin +
            (_room - _exit.geometry!.origin) *
                (1 -
                        widget.presentation.animation.value /
                            _exit.geometry!.animationOrigin)
                    .clamp(0.0, 1.0);

  double get _heightOffset => _heightOffsetAt(_offset);

  double _heightOffsetAt(double offset) => _fullyExpanded
      ? 0
      : math.min(offset, widget.keepFootInView ? _low : _fixedLow);

  @override
  void initState() {
    super.initState();
    _fullyExpanded = widget.initiallyExpanded;
    _travel.addListener(_travelChanged);
    _travel.addStatusListener(_travelStatus);
    _keyboardPlacement.addListener(_changed);
    _keyboardPlacement.addStatusListener(_travelStatus);
    _keyboardInsetAnimation.addListener(_changed);
    _DSheetKeyboardTransitions.ready.addListener(_keyboardTransition);
    _DSheetKeyboardTransitions.frame.addListener(_keyboardFrameChanged);
    unawaited(_DSheetKeyboardTransitions.refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _exit.route)) return;
    _exit.attach(
      !widget.retained && route is DOverlayRoute<dynamic, Object>
          ? route
          : null,
      _beginExit,
    );
  }

  Simulation? _beginExit() {
    if (!_animate) return null;
    _interacted = true;
    _travel.stop();
    _keyboardPlacement.stop();
    _keyboardInsetAnimation.stop();
    _exit.geometry = (
      origin: _travel.value,
      animationOrigin: math.max(.001, widget.presentation.animation.value),
      curve: _curve.transform(widget.presentation.animation.value),
      keyboard: _keyboardInset,
      safeBottom: _safeBottom,
      heightOffset: _heightOffsetAt(_travel.value),
    );
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
    if (!oldWidget.initiallyExpanded && widget.initiallyExpanded) {
      _interacted = true;
      _settle(0);
    }
    if (oldWidget.contentLoading && !widget.contentLoading) {
      _contentLayoutPending = true;
    }
  }

  void _keyboardTransition() {
    if (_nativeKeyboardFrame != null) return;
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

  void _keyboardFrameChanged() {
    final frame = _DSheetKeyboardTransitions.frame.value;
    if (!mounted ||
        frame == null ||
        _exit.geometry != null ||
        ModalRoute.of(context)?.isCurrent == false ||
        DOverlayRoute.modalCoverCountOf(context).value > 0) {
      return;
    }
    final current = _keyboardInset;
    if (current == 0 && frame.inset == 0 && _nativeKeyboardFrame == null) {
      return;
    }
    _nativeKeyboardFrame = frame;
    _keyboardMinimum?.cancel();
    _keyboardStability?.cancel();
    _raiseForKeyboard = false;
    _keyboardSettled = frame.inset > 0;
    _keyboard = math.max(current, frame.inset);
    _interacted = true;
    _keyboardInsetAnimation.value = current;
    if (frame.inset == 0) _travel.stop();
    final duration = frame.remaining;
    final curve = frame.remainingCurve;
    if (_animate && duration > Duration.zero) {
      unawaited(
        _keyboardInsetAnimation
            .animateTo(frame.inset, duration: duration, curve: curve)
            .then((_) {
              if (!mounted || !identical(_nativeKeyboardFrame, frame)) return;
              _keyboard = frame.inset;
              _changed();
            }),
      );
      unawaited(
        _keyboardPlacement.animateTo(
          frame.inset > 0 ? 1 : 0,
          duration: duration,
          curve: curve,
        ),
      );
      if (frame.inset > 0) {
        unawaited(_travel.animateTo(0, duration: duration, curve: curve));
      }
    } else {
      _keyboard = frame.inset;
      _keyboardInsetAnimation.value = frame.inset;
      _keyboardPlacement.value = frame.inset > 0 ? 1 : 0;
      if (frame.inset > 0) _travel.value = 0;
    }
    _changed();
  }

  void _keyboardChanged(double keyboard) {
    final opening = _keyboard == 0 && keyboard > 0;
    _keyboard = keyboard;
    _keyboardStability?.cancel();
    if (keyboard == 0) {
      _keyboardMinimum?.cancel();
      _keyboardSettled = false;
      _raiseForKeyboard = false;
      if (_animate) {
        unawaited(
          _keyboardInsetAnimation.animateTo(
            0,
            duration: _duration,
            curve: _curve,
          ),
        );
        unawaited(_keyboardPlacement.animateTo(0, curve: _curve));
      } else {
        _keyboardInsetAnimation.value = 0;
        _keyboardPlacement.value = 0;
      }
      _keyboardMinimumElapsed = false;
      _keyboardMetricsStable = false;
    } else {
      if (!opening && _keyboardSettled) {
        if (_animate) {
          unawaited(
            _keyboardInsetAnimation.animateTo(
              keyboard,
              duration: _duration,
              curve: _curve,
            ),
          );
        } else {
          _keyboardInsetAnimation.value = keyboard;
        }
      }
      if (opening) {
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
      if (_travel.value == 0 && _interacted) _completeExpansion();
      _scheduleMeasure();
    }
  }

  void _completeExpansion() {
    if (_fullyExpanded || widget.restAt != null) return;
    setState(() {
      _fullyExpanded = true;
      _low = 0;
    });
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
    if (_exit.geometry != null) return;
    final box = _surface.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final tall = box.size.height;
    if (_laidHeightOffset <= 0 || tall < _laidCap - .5) _fullHeight = tall;
    final full = widget.keepFootInView ? _fullHeight : tall;
    final half = _room * .55;
    var low = _fullyExpanded || _keyboard > 0
        ? 0.0
        : !widget.sizeToContent
        ? _fixedLow
        : full > half + 60
        ? full - half
        : 0.0;
    final rest = widget.restAt?.currentContext;
    final restBox = rest?.findRenderObject();
    if (restBox is RenderBox &&
        restBox.hasSize &&
        _keyboard == 0 &&
        !_fullyExpanded) {
      final bottom = restBox
          .localToGlobal(Offset(0, restBox.size.height), ancestor: box)
          .dy;
      final scrolled = Scrollable.maybeOf(rest!)?.position.pixels ?? 0;
      low = math.max(
        0.0,
        (tall - bottom - scrolled - _safeBottom - 6).floorToDouble(),
      );
    }
    final wasLow = _low;
    _low = low;
    if (!_measured || (!_interacted && !_peeking && (wasLow - low).abs() > 1)) {
      _measured = true;
      _travel.value = low;
      if (restBox is RenderBox) _schedulePeek();
      setState(() {});
      // The first offstage layout establishes the detent. Let the visible
      // viewport and its scroll metrics settle before deciding it is short.
      return;
    }
    if (_raiseForKeyboard) {
      _raiseForKeyboard = false;
      _settle(0);
      if (_animate) {
        unawaited(
          _keyboardInsetAnimation.animateTo(
            _keyboard,
            duration: _duration,
            curve: _curve,
          ),
        );
        unawaited(_keyboardPlacement.animateTo(1, curve: _curve));
      } else {
        _keyboardInsetAnimation.value = _keyboard;
        _keyboardPlacement.value = 1;
      }
    }
    // Native timing already owns all geometry until hiding completes. Metrics
    // notifications must not restart those animations with the menu duration.
    if (_nativeKeyboardFrame != null &&
        (_nativeKeyboardFrame!.inset > 0 ||
            _keyboardInsetAnimation.isAnimating)) {
      return;
    }
    if (_contentLayoutPending) {
      // Descendants may publish their loaded rows after this frame. Measure
      // those rows on the next layout instead of retaining the placeholder height.
      _contentLayoutPending = false;
      _scheduleMeasure();
      return;
    }
  }

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
    _scheduleMeasure();
  }

  void _start() {
    if (_exit.geometry != null) return;
    _cancelPeek();
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

  void _update(double delta, {bool allowExpand = true}) {
    if (_exit.geometry != null) return;
    _travel.value = math.max(
      allowExpand ? 0 : _startOffset,
      _travel.value + delta,
    );
  }

  double _consume(ScrollMetrics metrics, double delta) {
    if (_pointer == null ||
        metrics.axis != Axis.vertical ||
        _exit.geometry != null) {
      return delta;
    }
    if (_expansionGesture) {
      final before = _travel.value;
      _update(delta);
      return widget.restAt == null ? 0 : delta - (_travel.value - before);
    }
    if (_travel.value <= 0 &&
        !(delta > 0 && metrics.pixels <= metrics.minScrollExtent)) {
      return delta;
    }
    if (!_dragging) _start();
    _scrollDrag = true;
    _expansionGesture = delta < 0 && _startOffset > 1;
    final before = _travel.value;
    _update(delta);
    return _expansionGesture && widget.restAt == null
        ? 0
        : delta - (_travel.value - before);
  }

  bool _stopScrollMomentum() => _expansionGesture && widget.restAt == null;

  void _settle(double to) {
    if (_animate) {
      unawaited(_travel.animateTo(to, duration: _duration, curve: _curve));
    } else {
      _travel.value = to;
      if (to == 0) _completeExpansion();
    }
  }

  void _toggle() {
    _cancelPeek();
    _interacted = true;
    _settle(_travel.value > 1 ? 0 : _low);
  }

  void _finish(double velocity, {bool cancelled = false}) {
    if (!_dragging || _exit.geometry != null) return;
    _dragging = false;
    _scrollDrag = false;
    if (cancelled) {
      _settle(_startOffset > _low / 2 ? _low : 0);
      return;
    }
    final pulled = _travel.value - _startOffset;
    if (widget.restAt != null) {
      final ahead = _travel.value + velocity * .18;
      final fromLow = _low <= 0 || _startOffset > _low / 2;
      if (fromLow && pulled > 60 && (velocity > 500 || ahead > _low + 60)) {
        _dismiss(velocity);
      } else if (fromLow) {
        _settle(pulled < -60 || velocity < -500 ? 0 : _low);
      } else {
        _settle(pulled > 60 || velocity > 500 ? _low : 0);
      }
      return;
    }
    if (_expansionGesture && pulled < 0) {
      _settle(0);
      return;
    }
    if (pulled >= 0) {
      // Match standard sheets: velocity shapes an accepted exit, but never
      // turns a short pull into a dismissal.
      final threshold = _swipeExtent * _sheetDismissFraction;
      if (pulled < threshold) {
        _settle(_startOffset > _low / 2 ? _low : 0);
      } else {
        _dismiss(velocity);
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
      final destination = MediaQuery.sizeOf(context).height;
      _retainedExitHeightOffset = _heightOffset;
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
                if (mounted) {
                  _retainedExitHeightOffset = null;
                  _settle(_low);
                }
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
        _exit.geometry = null;
        _retainedExitHeightOffset = null;
        _exitVelocity = 0;
        _settle(_low);
      }
    });
  }

  void _down(PointerDownEvent event) {
    _cancelPeek();
    _interacted = true;
    if (_pointer != null || event.kind != PointerDeviceKind.touch) return;
    _pointer = event.pointer;
    // A gesture that raises the sheet owns all of its motion, including the
    // release velocity. Only a new touch may start scrolling the content.
    _expansionGesture = false;
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
    _wheelEnd?.cancel();
    _restScroll.dispose();
    _peekNext?.cancel();
    _peekClock.dispose();
    _exit.detach();
    _travel.dispose();
    _keyboardPlacement.dispose();
    _keyboardInsetAnimation.dispose();
    _keyboardMinimum?.cancel();
    _keyboardStability?.cancel();
    _DSheetKeyboardTransitions.ready.removeListener(_keyboardTransition);
    _DSheetKeyboardTransitions.frame.removeListener(_keyboardFrameChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final view = View.of(context);
    final systemKeyboard = media.viewInsets.bottom;
    if (_exit.geometry == null &&
        _nativeKeyboardFrame == null &&
        _keyboard != systemKeyboard) {
      _keyboardChanged(systemKeyboard);
    }
    final keyboard = _exit.geometry?.keyboard ?? _keyboardInset;

    final safeTop = widget.retained
        ? media.padding.top
        : math.max(
            media.padding.top,
            view.viewPadding.top / view.devicePixelRatio,
          );
    final screenFoot = math.max(
      media.viewPadding.bottom,
      view.viewPadding.bottom / view.devicePixelRatio,
    );
    final safeBottom =
        _exit.geometry?.safeBottom ??
        screenFoot * (1 - _keyboardPlacement.value);
    _safeBottom = safeBottom;
    _scheduleMeasure();
    final content = _DSheetAdaptiveMenuScope(
      menu: this,
      expanded: _expanded,
      canCollapse: _low > 0,
      child: _DSheetSideScope(
        side: DSheetSide.bottom,
        inset: false,
        menuFootCorners: _sheetBottomCorners(context),
        fillAvailableHeight: false,
        extendBehindKeyboard: false,
        child: MediaQuery(
          data: media.copyWith(
            padding: EdgeInsets.only(bottom: safeBottom),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: widget.presentation.content,
        ),
      ),
    );
    Widget backdrop(double progress) {
      const color = Color(0x1A000000);
      Widget result = widget.presentation.buildBackdrop(
        color: color.withValues(alpha: color.a * progress),
      );
      if (widget.presentation.modal &&
          (widget.onDismiss != null || widget.onDismissRequested != null)) {
        result = Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          child: GestureDetector(
            excludeFromSemantics: true,
            supportedDevices: const {PointerDeviceKind.touch},
            onVerticalDragStart: (_) => _start(),
            onVerticalDragUpdate: (details) =>
                _update(details.delta.dy, allowExpand: false),
            onVerticalDragEnd: (details) =>
                _finish(details.primaryVelocity ?? 0),
            onVerticalDragCancel: () => _finish(0, cancelled: true),
            child: result,
          ),
        );
      }
      return result;
    }

    return LayoutBuilder(
      builder: (context, bounds) {
        _room = math.max(0, bounds.maxHeight - keyboard);
        final maximum = math.max(0.0, _room - safeTop - 8);
        final restHeight = widget.retained
            ? media.size.height
            : bounds.maxHeight;
        _fixedLow = math.max(
          0,
          bounds.maxHeight - safeTop - 8 - restHeight * .55,
        );
        return AnimatedBuilder(
          animation: Listenable.merge([widget.presentation.animation, _travel]),
          builder: (context, child) {
            final curve = _animate
                ? _curve.transform(widget.presentation.animation.value)
                : 1.0;
            final dim =
                (1 - math.max(0, _offset - _low) / math.max(1, _room - _low))
                    .clamp(0.0, 1.0);
            // Fixed menus lay out their actual visible viewport, so arriving
            // results cannot resize the surface, and a sheet that keeps its foot
            // in view lays out no more than is in view. Below the lower detent,
            // keep that height and translate the whole sheet with the finger.
            final heightOffset = widget.sizeToContent && !widget.keepFootInView
                ? 0.0
                : _exit.geometry?.heightOffset ??
                      _retainedExitHeightOffset ??
                      _heightOffset;
            _laidHeightOffset = heightOffset;
            _laidCap =
                (heightOffset > 0 && widget.keepFootInView
                    ? math.max(0.0, _fullHeight - heightOffset)
                    : maximum) +
                keyboard;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                backdrop(curve * dim),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      _offset -
                          heightOffset +
                          40 *
                              (1 -
                                  (_exit.geometry == null
                                      ? curve
                                      : _exit.geometry!.curve)),
                    ),
                    child: Offstage(
                      offstage: !_measured,
                      child:
                          NotificationListener<SizeChangedLayoutNotification>(
                            onNotification: (_) {
                              _scheduleMeasure();
                              return false;
                            },
                            child: SizeChangedLayoutNotifier(
                              child: ConstrainedBox(
                                key: _surface,
                                constraints: widget.sizeToContent
                                    ? BoxConstraints(maxHeight: _laidCap)
                                    : BoxConstraints.tightFor(
                                        height:
                                            math.max(
                                              0,
                                              maximum - heightOffset,
                                            ) +
                                            keyboard,
                                      ),
                                child: child,
                              ),
                            ),
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
                      _stopScrollMomentum,
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

class _DSheetRestScrollController extends ScrollController {
  _DSheetRestScrollController(this.menu);
  final _DSheetAdaptiveMenuState menu;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _DSheetRestScrollPosition(
    menu,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _DSheetRestScrollPosition extends ScrollPositionWithSingleContext {
  _DSheetRestScrollPosition(
    this.menu, {
    required super.physics,
    required super.context,
    super.oldPosition,
  });
  final _DSheetAdaptiveMenuState menu;

  @override
  void pointerScroll(double delta) =>
      super.pointerScroll(menu._wheelDelta(delta));
}
