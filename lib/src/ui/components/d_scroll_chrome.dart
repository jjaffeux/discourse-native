import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import 'd_scroll_behavior.dart';

/// Coordinates a page's retracting headers and navigation footer. Slow reading
/// never accumulates into hiding; a deliberate reversal restores navigation.
/// Only direct input in the primary vertical scroll view can hide the chrome.
class DScrollChrome extends StatefulWidget {
  const DScrollChrome({
    super.key,
    required this.identity,
    required this.child,
    required this.footerBuilder,
    this.visible = true,
    this.enabled = true,
    this.keepFooterVisible = false,
  });

  final Object identity;
  final Widget child;
  final Widget Function(bool hidden) footerBuilder;
  final bool visible;
  final bool enabled;

  /// Keeps contextual actions visible while the builder hides destinations.
  final bool keepFooterVisible;

  static DScrollChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChromeScope>()?.controller;

  @override
  State<DScrollChrome> createState() => _DScrollChromeState();
}

/// Shared animation and header geometry for [DScrollChrome] participants.
class DScrollChromeController extends ChangeNotifier {
  DScrollChromeController._(this._animation);

  final AnimationController _animation;
  final _headers =
      <
        Object,
        ({
          FocusNode focus,
          double Function() reduction,
          double Function() extent,
        })
      >{};

  double get hiddenFraction => _animation.value;

  /// The reduction is space released from the viewport's surrounding layout;
  /// floating headers report zero because their viewport does not change size.
  void registerHeader(
    Object owner, {
    required FocusNode focus,
    required double Function() layoutReduction,
    required double Function() layoutExtent,
  }) {
    _headers[owner] = (
      focus: focus,
      reduction: layoutReduction,
      extent: layoutExtent,
    );
  }

  void unregisterHeader(Object owner) => _headers.remove(owner);

  bool get _hasFocus => _headers.values.any((header) => header.focus.hasFocus);
  double get _layoutReduction =>
      _headers.values.fold(0.0, (sum, header) => sum + header.reduction());
  double get _layoutExtent =>
      _headers.values.fold(0.0, (sum, header) => sum + header.extent());

  void _changed() => notifyListeners();
}

class _DScrollChromeState extends State<DScrollChrome>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this)
    ..addListener(_update);
  late final _controller = DScrollChromeController._(_animation);
  final _footerFocus = FocusNode(canRequestFocus: false);
  final _footerKey = GlobalKey();
  final _footerContentKey = GlobalKey();
  Expando<_ScrollIntent> _intents = Expando();
  final _anchors = Expando<_ChromeAnchor>();
  ScrollableState? _activeSource;
  bool _hidden = false;
  bool _updateScheduled = false;
  bool _panZoomActive = false;
  Duration? _gestureStart;
  Duration? _wheelTime;
  double _shownFooterHeight = 0;
  Widget? _footerContent;

  @override
  void didUpdateWidget(DScrollChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _footerContent = null;
    if (oldWidget.identity != widget.identity ||
        oldWidget.visible != widget.visible ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.keepFooterVisible != widget.keepFooterVisible) {
      _hidden = false;
      _intents = Expando();
      _activeSource = null;
      _gestureStart = null;
      _wheelTime = null;
      _panZoomActive = false;
      _shownFooterHeight = 0;
      _animation.value = 0;
    }
  }

  _ChromeAnchor _anchorFor(
    ScrollableState source,
  ) => _anchors[source] ??= _ChromeAnchor(_animation.value, (
    previous,
    old,
    next,
  ) {
    final fraction = _animation.value;
    if (!identical(source, _activeSource) ||
        old.axis != Axis.vertical ||
        old.atEdge ||
        old.outOfRange) {
      return (fraction, 0.0);
    }
    final header = _controller._layoutExtent;
    final footer = widget.keepFooterVisible ? 0.0 : _shownFooterHeight;
    final change = fraction - previous;
    // Only compensate layout released by our own bars. Keyboard, window,
    // content and unrelated viewport changes retain their platform behavior.
    final growth = next.viewportDimension - old.viewportDimension;
    if ((growth - change * (header + footer)).abs() > .5) {
      return (fraction, 0.0);
    }
    final extent = old.axisDirection == AxisDirection.up ? footer : header;
    return (fraction, -change * extent);
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _animation.isAnimating) {
      _animation.value = _hidden ? 1 : 0;
    }
  }

  void _update() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_updateScheduled) return;
      _updateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScheduled = false;
        if (mounted) _update();
      });
      return;
    }
    setState(() {});
    _controller._changed();
  }

  void _setHidden(bool hidden) {
    if (_hidden == hidden ||
        (hidden && (_footerFocus.hasFocus || _controller._hasFocus))) {
      return;
    }
    _hidden = hidden;
    _footerContent = null;
    final duration = DMotion.duration(
      context,
      hidden ? DMotion.exit : DMotion.enter,
    );
    if (duration == Duration.zero) {
      _animation.value = hidden ? 1 : 0;
    } else {
      _animation.animateTo(
        hidden ? 1 : 0,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
    _update();
  }

  ScrollableState? _pageScroll(BuildContext? context, Axis axis) {
    if (axis != Axis.vertical || context == null) return null;
    final source = Scrollable.maybeOf(context);
    if (source == null) return null;
    var nested = false;
    context.visitAncestorElements((element) {
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
    return nested ? null : source;
  }

  bool _shortContent(ScrollMetrics metrics) {
    final natural = _footerContentKey.currentContext?.size?.height ?? 0;
    if (!_hidden && _animation.value == 0) _shownFooterHeight = natural;
    final footerHeight = _footerKey.currentContext?.size?.height ?? 0;
    final reduction =
        math.max(0.0, _shownFooterHeight - footerHeight) +
        _controller._layoutReduction;
    final shownViewport = metrics.viewportDimension - reduction;
    final content =
        metrics.maxScrollExtent -
        metrics.minScrollExtent +
        metrics.viewportDimension;
    return shownViewport > 0 && content < 2 * shownViewport;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    final source = _pageScroll(notification.context, notification.metrics.axis);
    if (source != null &&
        identical(source, _activeSource) &&
        _shortContent(notification.metrics)) {
      _setHidden(false);
    }
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.visible || !widget.enabled) return false;
    final metrics = notification.metrics;
    final source = _pageScroll(notification.context, metrics.axis);
    if (source == null) {
      if (notification is ScrollUpdateNotification) _wheelTime = null;
      return false;
    }
    final intent = _intents[source] ??= _ScrollIntent();
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        intent.reset(
          _gestureStart ?? notification.dragDetails?.sourceTimeStamp,
        );
        _gestureStart = null;
      } else if (!intent.userScrolling) {
        intent.holdAtEnd = false;
      }
    }
    if (notification is UserScrollNotification) {
      intent.userScrolling = notification.direction != ScrollDirection.idle;
      if (intent.userScrolling && intent.direction != notification.direction) {
        intent.clearDistance();
        intent.direction = notification.direction;
      }
    }
    if (notification is! ScrollUpdateNotification || !intent.userScrolling) {
      return false;
    }
    _activeSource = source;
    final delta = notification.scrollDelta ?? 0;
    // Layout corrections and elastic rebound are not a change of intent.
    if ((intent.direction == ScrollDirection.reverse && delta <= 0) ||
        (intent.direction == ScrollDirection.forward && delta >= 0)) {
      return false;
    }
    final reversed = metrics.axisDirection == AxisDirection.up;
    final top = reversed
        ? metrics.maxScrollExtent - metrics.pixels
        : metrics.pixels - metrics.minScrollExtent;
    final travel = metrics.maxScrollExtent - metrics.minScrollExtent;
    final down = reversed ? delta < 0 : delta > 0;
    final wheelTime = _wheelTime;
    _wheelTime = null;
    final direct =
        notification.dragDetails != null || wheelTime != null || _panZoomActive;
    final time =
        notification.dragDetails?.sourceTimeStamp ??
        wheelTime ??
        SchedulerBinding.instance.currentSystemFrameTimeStamp;

    if (_shortContent(metrics) || top <= 48) {
      intent.reset(time);
      intent.holdAtEnd = false;
      _setHidden(false);
    } else if (travel - top <= 4) {
      intent.reset(time);
      intent.holdAtEnd = true;
      _setHidden(false);
    } else if (!metrics.outOfRange && direct) {
      final distance = intent.add(
        delta.abs(),
        time,
        wheel: wheelTime != null,
        hiding: down,
      );
      if (!down && distance >= 10) {
        intent.holdAtEnd = false;
        _setHidden(false);
      } else if (down && !intent.holdAtEnd && distance >= 16) {
        // Retraction must leave enough scroll range to preserve the reading
        // anchor. In a column page the disappearing title releases top space;
        // a reversed list instead releases space beneath its content.
        final extent = reversed
            ? (widget.keepFooterVisible ? 0.0 : _shownFooterHeight)
            : _controller._layoutExtent;
        final remaining = extent * (1 - _animation.value);
        if (metrics.pixels - metrics.minScrollExtent - remaining <
            (reversed ? 4 : 48)) {
          return false;
        }
        _setHidden(true);
      }
    }
    return false;
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    _footerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = widget.keepFooterVisible ? 0.0 : _animation.value;
    final gone = !widget.visible || fraction == 1;
    return _ChromeScope(
      controller: _controller,
      child: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: _onMetrics,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: Listener(
                  onPointerDown: (event) => _gestureStart = event.timeStamp,
                  onPointerPanZoomStart: (event) {
                    _panZoomActive = true;
                    _gestureStart = event.timeStamp;
                  },
                  onPointerPanZoomEnd: (_) => _panZoomActive = false,
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      _wheelTime = event.timeStamp == Duration.zero
                          ? SchedulerBinding
                                .instance
                                .currentSystemFrameTimeStamp
                          : event.timeStamp;
                      // Resolution of a wheel event is synchronous. An event
                      // that hit an edge must not authorize a later animation.
                      scheduleMicrotask(() => _wheelTime = null);
                    }
                  },
                  child: ScrollConfiguration(
                    behavior: _ChromeScrollBehavior(
                      delegate: ScrollConfiguration.of(context),
                      anchorFor: _anchorFor,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            key: _footerKey,
            child: Offstage(
              offstage: gone,
              child: ExcludeSemantics(
                excluding: gone,
                child: ExcludeFocus(
                  excluding: gone,
                  child: TickerMode(
                    enabled: !gone,
                    child: ClipRect(
                      child: Align(
                        heightFactor: 1 - fraction,
                        alignment: Alignment.topCenter,
                        child: Focus(
                          focusNode: _footerFocus,
                          child: SizedBox(
                            key: _footerContentKey,
                            child: _footerContent ??= widget.footerBuilder(
                              _hidden,
                            ),
                          ),
                        ),
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
  }
}

// Correct inside viewport layout, before paint, so retracting a column header
// or expanding a reversed list does not move the content under the reader.
class _ChromeAnchor {
  _ChromeAnchor(this.fraction, this.adjust);
  double fraction;
  final (double, double) Function(double, ScrollMetrics, ScrollMetrics) adjust;
}

class _ChromeScrollBehavior extends DScrollBehavior {
  const _ChromeScrollBehavior({
    required super.delegate,
    required this.anchorFor,
  });
  final _ChromeAnchor Function(ScrollableState) anchorFor;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final parent = super.getScrollPhysics(context);
    if (context case StatefulElement(state: final ScrollableState source)) {
      return _ChromeScrollPhysics(anchorFor(source), parent: parent);
    }
    return parent;
  }
}

class _ChromeScrollPhysics extends ScrollPhysics {
  const _ChromeScrollPhysics(this.anchor, {super.parent});
  final _ChromeAnchor anchor;

  @override
  _ChromeScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ChromeScrollPhysics(anchor, parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final (fraction, correction) = anchor.adjust(
      anchor.fraction,
      oldPosition,
      newPosition,
    );
    anchor.fraction = fraction;
    if (correction != 0) {
      return (newPosition.pixels + correction).clamp(
        newPosition.minScrollExtent,
        newPosition.maxScrollExtent,
      );
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

class _ChromeScope extends InheritedWidget {
  const _ChromeScope({required this.controller, required super.child});
  final DScrollChromeController controller;

  @override
  bool updateShouldNotify(_ChromeScope oldWidget) =>
      controller != oldWidget.controller;
}

class _ScrollIntent {
  static const _window = Duration(milliseconds: 80);
  static const _pause = Duration(milliseconds: 200);
  static const _frame = Duration(microseconds: 16667);
  final _samples = <({Duration start, Duration end, double distance})>[];
  bool userScrolling = false;
  ScrollDirection direction = ScrollDirection.idle;
  bool holdAtEnd = false;
  double distance = 0;
  Duration? _time;

  void clearDistance() {
    distance = 0;
    _samples.clear();
  }

  void reset(Duration? time) {
    clearDistance();
    _time = time;
  }

  double add(
    double delta,
    Duration time, {
    required bool wheel,
    required bool hiding,
  }) {
    var elapsed = _time == null ? _frame : time - _time!;
    if (elapsed >= _pause) {
      clearDistance();
      // A wheel packet has no gesture start time; an idle gap isn't its speed.
      if (wheel) elapsed = _frame;
    }
    if (elapsed < Duration.zero) clearDistance();
    if (elapsed <= Duration.zero) elapsed = _frame;
    _time = time;
    _samples.add((start: time - elapsed, end: time, distance: delta));
    final cutoff = time - _window;
    _samples.removeWhere((sample) => sample.end <= cutoff);
    final start = _samples.first.start > cutoff ? _samples.first.start : cutoff;
    final duration = (time - start).inMicroseconds;
    final travel = _samples.fold(0.0, (sum, sample) {
      final overlap =
          sample.end - (sample.start > cutoff ? sample.start : cutoff);
      return sum +
          sample.distance *
              overlap.inMicroseconds /
              (sample.end - sample.start).inMicroseconds;
    });
    final velocity = travel * Duration.microsecondsPerSecond / duration;
    if (hiding && velocity < 180) {
      distance = 0;
    } else {
      distance += delta;
    }
    return distance;
  }
}
