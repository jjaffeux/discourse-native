import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/header_motion.dart';
import 'd_scroll_behavior.dart';

/// Coordinates a page's retracting headers and navigation footer. Slow reading
/// moves a continuous target; reversal slack and holds prevent accidental flips.
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
    this.floatingFooter = false,
  });

  final Object identity;
  final Widget child;
  final Widget Function(bool hidden) footerBuilder;
  final bool visible;
  final bool enabled;

  /// Keeps contextual actions visible while the builder hides destinations.
  final bool keepFooterVisible;

  /// Overlays the footer without resizing the page viewport. The builder owns
  /// its compact state; [bottomInsetOf] keeps the last row clear of the open dock.
  final bool floatingFooter;

  static double bottomInsetOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_DockRoom>()
          ?.notifier
          ?.value ??
      0;

  static DScrollChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChromeScope>()?.controller;

  @override
  State<DScrollChrome> createState() => _DScrollChromeState();
}

/// Shared animation and header geometry for [DScrollChrome] participants.
class DScrollChromeController extends ChangeNotifier
    implements ValueListenable<double> {
  DScrollChromeController._(this._animation);

  final HeaderMotion _animation;
  final _headers =
      <
        Object,
        ({
          FocusNode focus,
          double Function() reduction,
          double Function() extent,
          double Function() motionExtent,
        })
      >{};

  double get hiddenFraction => _animation.value;
  @override
  double get value => hiddenFraction;

  /// Opens coupled page headers and the dock without changing the destination.
  void reveal() => _animation.reveal(fresh: true);

  /// The reduction is space released from the viewport's surrounding layout;
  /// floating headers report zero because their viewport does not change size.
  void registerHeader(
    Object owner, {
    required FocusNode focus,
    required double Function() layoutReduction,
    required double Function() layoutExtent,
    required double Function() motionExtent,
  }) {
    unregisterHeader(owner);
    focus.addListener(_focusChanged);
    _headers[owner] = (
      focus: focus,
      reduction: layoutReduction,
      extent: layoutExtent,
      motionExtent: motionExtent,
    );
  }

  void unregisterHeader(Object owner) {
    _headers.remove(owner)?.focus.removeListener(_focusChanged);
  }

  void _focusChanged() {
    if (_hasFocus) {
      _animation.reveal(fresh: true);
    }
  }

  bool get _hasFocus => _headers.values.any((header) => header.focus.hasFocus);
  double get _layoutReduction =>
      _headers.values.fold(0.0, (sum, header) => sum + header.reduction());
  double get _layoutExtent =>
      _headers.values.fold(0.0, (sum, header) => sum + header.extent());

  double get _motionExtent {
    final span = _headers.values.fold(
      0.0,
      (span, header) => math.max(span, header.motionExtent()),
    );
    return span > 0 ? span : 64;
  }

  void _changed() => notifyListeners();
  @override
  void dispose() {
    for (final header in _headers.values) {
      header.focus.removeListener(_focusChanged);
    }
    _headers.clear();
    super.dispose();
  }
}

class _DScrollChromeState extends State<DScrollChrome>
    with SingleTickerProviderStateMixin {
  late final _animation = HeaderMotion(this)..addListener(_update);
  late final _controller = DScrollChromeController._(_animation);
  final _footerFocus = FocusNode(canRequestFocus: false);
  final _footerKey = GlobalKey();
  final _footerContentKey = GlobalKey();
  Expando<_ScrollIntent> _intents = Expando();
  final _anchors = Expando<_ChromeAnchor>();
  ScrollableState? _activeSource;
  bool _hidden = false;
  bool _updateScheduled = false;
  double _shownFooterHeight = 0;
  Widget? _footerContent;
  final _dockRoom = ValueNotifier<double>(0);

  void _measureDock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.floatingFooter) return;
      final height = _footerContentKey.currentContext?.size?.height ?? 0;
      if (widget.visible &&
          (!_hidden || height > _dockRoom.value) &&
          height > 0 &&
          (_dockRoom.value - height).abs() > .5) {
        _dockRoom.value = height;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _footerFocus.addListener(_revealFocusedFooter);
  }

  void _revealFocusedFooter() {
    if (_footerFocus.hasFocus) {
      _animation.reveal(fresh: true);
    }
  }

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
      _shownFooterHeight = 0;
      _animation.reset();
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
    final footer = widget.keepFooterVisible || widget.floatingFooter
        ? 0.0
        : _shownFooterHeight;
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
    _animation.configure(
      DHeaderMotionSettings.of(context),
      disableAnimations: MediaQuery.disableAnimationsOf(context),
    );
  }

  void _update() {
    _controller._changed();
    final hidden = _animation.value >= .5;
    final gone = _animation.value == 1;
    if (_hidden == hidden && _gone == gone) return;
    _hidden = hidden;
    _gone = gone;
    _footerContent = null;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_updateScheduled) return;
      _updateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  bool _gone = false;

  void _setHidden(bool hidden) {
    if (hidden && (_footerFocus.hasFocus || _controller._hasFocus)) return;
    if (!hidden) _animation.reveal(fresh: true);
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
        (widget.floatingFooter
            ? 0.0
            : math.max(0.0, _shownFooterHeight - footerHeight)) +
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
      return false;
    }
    final intent = _intents[source] ??= _ScrollIntent();
    if (notification is ScrollStartNotification &&
        notification.dragDetails == null &&
        !intent.userScrolling) {
      intent.holdAtEnd = false;
    }
    if (notification is UserScrollNotification) {
      intent.userScrolling = notification.direction != ScrollDirection.idle;
      if (intent.userScrolling && intent.direction != notification.direction) {
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

    if (_shortContent(metrics) || top <= 48) {
      intent.holdAtEnd = false;
      _setHidden(false);
    } else if (travel - top <= 4) {
      intent.holdAtEnd = true;
      _setHidden(false);
    } else if (!metrics.outOfRange) {
      if (_footerFocus.hasFocus || _controller._hasFocus) {
        _animation.reveal(fresh: true);
      } else if (!down || !intent.holdAtEnd) {
        if (!down) intent.holdAtEnd = false;
        _animation.scroll(
          down && top - delta.abs() < 48
              ? top - 48
              : (reversed ? -delta : delta),
          span: _controller._motionExtent,
        );
      }
    }
    return false;
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    _footerFocus.dispose();
    _dockRoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.floatingFooter) {
      _measureDock();
      return _ChromeScope(
        controller: _controller,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _DockRoom(
              notifier: _dockRoom,
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _onMetrics,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
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
            if (widget.visible)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (_) {
                    _measureDock();
                    return false;
                  },
                  child: SizeChangedLayoutNotifier(
                    child: Focus(
                      focusNode: _footerFocus,
                      child: SizedBox(
                        key: _footerContentKey,
                        child: _footerContent ??= widget.footerBuilder(_hidden),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return _ChromeScope(
      controller: _controller,
      child: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: _onMetrics,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
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
          AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              final fraction = widget.keepFooterVisible
                  ? 0.0
                  : _animation.value;
              final gone = !widget.visible || fraction == 1;
              return SizedBox(
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
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DockRoom extends InheritedNotifier<ValueNotifier<double>> {
  const _DockRoom({required super.notifier, required super.child});
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
  bool userScrolling = false;
  ScrollDirection direction = ScrollDirection.idle;
  bool holdAtEnd = false;
}
