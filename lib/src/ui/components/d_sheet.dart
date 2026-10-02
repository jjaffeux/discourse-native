import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/d_overlay_route.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_dialog.dart';

/// Physical edges, direction-aware conveniences, and a centered reading panel.
enum DSheetSide { top, right, bottom, left, start, end, center }

extension on DSheetSide {
  DSheetSide resolve(TextDirection direction) => switch (this) {
    DSheetSide.start =>
      direction == TextDirection.ltr ? DSheetSide.left : DSheetSide.right,
    DSheetSide.end =>
      direction == TextDirection.ltr ? DSheetSide.right : DSheetSide.left,
    _ => this,
  };

  bool get isHorizontal =>
      this == DSheetSide.left ||
      this == DSheetSide.right ||
      this == DSheetSide.center;
}

typedef DSheetController<T> = DDialogController<T>;

typedef DSheetChangeDetails<T> = DDialogChangeDetails<T>;
typedef DSheetChangeReason = DDialogChangeReason;
typedef DSheetTriggerBuilder =
    Widget Function(BuildContext context, VoidCallback open);

class DSheetTrigger extends StatelessWidget {
  const DSheetTrigger({super.key, required this.builder});

  final DSheetTriggerBuilder builder;

  @override
  Widget build(BuildContext context) => DDialogTrigger(builder: builder);
}

/// Declarative Sheet root using Dialog's route and controller ownership.
class DSheet<T> extends StatelessWidget {
  const DSheet({
    super.key,
    required this.trigger,
    required this.content,
    this.controller,
    this.open,
    this.initiallyOpen = false,
    this.onOpenChanged,
    this.onOpenChangeComplete,
    this.useRootNavigator = false,
    this.modal = true,
    this.dismissOnBarrier = true,
    this.dismissOnEscape = true,
    this.dismissOnSwipe = true,
    this._barrierLabel,
    this.routeSettings,
    this.initialFocusNode,
    this.finalFocusNode,
    this.restoreFocus = true,
  }) : assert(open == null || !initiallyOpen);

  final DSheetTrigger trigger;
  final DSheetContent content;
  final DSheetController<T>? controller;
  final bool? open;
  final bool initiallyOpen;
  final ValueChanged<DSheetChangeDetails<T>>? onOpenChanged;

  /// Called when the opening or closing transition finishes.
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool useRootNavigator;

  /// Allows interaction with the exposed background without dismissing the
  /// sheet when false. Modal sheets retain their dimmed, blurred backdrop.
  final bool modal;
  final bool dismissOnBarrier;
  final bool dismissOnEscape;

  /// Allows mobile touch drags down from a bottom sheet's header and continued
  /// scrolling beyond the top content edge to pull the sheet down. Uses the
  /// same close request as [DSheetClose].
  /// Releasing before 30% of the distance to the viewport bottom restores it.
  final bool dismissOnSwipe;
  final String? _barrierLabel;
  String get barrierLabel => _barrierLabel ?? appL10n.dismissSheet;
  final RouteSettings? routeSettings;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  /// Restores focus to the trigger or previous control after dismissal.
  final bool restoreFocus;

  @override
  Widget build(BuildContext context) => DDialog<T>(
    controller: controller,
    open: open,
    initiallyOpen: initiallyOpen,
    onOpenChanged: onOpenChanged,
    onOpenChangeComplete: onOpenChangeComplete,
    useRootNavigator: useRootNavigator,
    modal: modal,
    dismissOnBarrier: dismissOnBarrier,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    routeSettings: routeSettings,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    restoreFocus: restoreFocus,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    presentationBuilder: (context, presentation) => _sheetPresentation(
      context,
      presentation,
      content.side,
      content.sidePanelMaxWidth,
      content.sidePanelWidth,
      content.inset,
      content.animateSize,
      content.fillAvailableHeight,
      content.extendBehindKeyboard,
      dismissOnSwipe,
    ),
    trigger: DDialogTrigger(builder: trigger.builder),
    content: content,
  );
}

/// Sheet presentation for a retained surface whose host owns its visibility.
///
/// Mount in a full viewport outside a resizing [Scaffold]. The host owns back
/// handling and excludes the covered content from focus and semantics. Hide
/// [DSheetContent.showCloseButton] or supply [DSheetContent.closeButton] with
/// the host's close action; route-owned [DSheetClose] is unavailable here.
class DSheetViewport extends StatelessWidget {
  const DSheetViewport({super.key, required this.content, this.onDismiss});

  final DSheetContent content;

  /// Enables mobile bottom-sheet swipes and requests removal after the exit
  /// animation. If the host keeps the sheet mounted, it returns to its position.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    assert(!content.showCloseButton || content.closeButton != null);
    return FocusScope(
      child: _sheetPresentation(
        context,
        DDialogPresentation(
          content: content,
          animation: const AlwaysStoppedAnimation(1),
          barrierLabel: context.l10n.sheetBackground,
          dismissOnBarrier: false,
          onBarrierDismiss: () {},
        ),
        content.side,
        content.sidePanelMaxWidth,
        content.sidePanelWidth,
        content.inset,
        content.animateSize,
        content.fillAvailableHeight,
        content.extendBehindKeyboard,
        onDismiss != null,
        retainKeyboardInsets: true,
        onRetainedDismiss: onDismiss,
      ),
    );
  }
}

// A retained sheet stays visible beneath picker routes. Its keyboard belongs
// to its own editor, so another route's focus handoff must not resize it.
class _DSheetRetainedKeyboardInsets extends StatefulWidget {
  const _DSheetRetainedKeyboardInsets({required this.child});

  final Widget child;

  @override
  State<_DSheetRetainedKeyboardInsets> createState() =>
      _DSheetRetainedKeyboardInsetsState();
}

class _DSheetRetainedKeyboardInsetsState
    extends State<_DSheetRetainedKeyboardInsets> {
  EdgeInsets? _insets;
  EdgeInsets? _padding;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: DOverlayRoute.modalCoverCountOf(context),
    builder: (context, covers, child) {
      final media = MediaQuery.of(context);
      if (covers == 0 || _insets == null) {
        _insets = media.viewInsets;
        _padding = media.padding;
      }
      return DOverlayKeyboardMetrics(
        viewInsets: media.viewInsets,
        padding: media.padding,
        child: MediaQuery(
          data: media.copyWith(viewInsets: _insets, padding: _padding),
          child: child!,
        ),
      );
    },
    child: widget.child,
  );
}

class _DSheetSideScope extends InheritedWidget {
  const _DSheetSideScope({
    required this.side,
    required this.inset,
    required this.fillAvailableHeight,
    required this.extendBehindKeyboard,
    required super.child,
  });

  final DSheetSide side;
  final bool inset;
  final bool fillAvailableHeight;
  final bool extendBehindKeyboard;

  static DSheetSide? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DSheetSideScope>()?.side;

  static bool? insetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DSheetSideScope>()?.inset;

  static bool? fillsAvailableHeightOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DSheetSideScope>()
      ?.fillAvailableHeight;

  static bool? extendsBehindKeyboardOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DSheetSideScope>()
      ?.extendBehindKeyboard;

  @override
  bool updateShouldNotify(_DSheetSideScope oldWidget) =>
      side != oldWidget.side ||
      inset != oldWidget.inset ||
      fillAvailableHeight != oldWidget.fillAvailableHeight ||
      extendBehindKeyboard != oldWidget.extendBehindKeyboard;
}

// A CurvedAnimation holds a status listener on the route animation until it
// is disposed, so the sheet's curves are owned by a State rather than rebuilt
// with every inset or configuration change of the open sheet.
class _DSheetCurves extends StatefulWidget {
  const _DSheetCurves({required this.animation, required this.builder});

  final Animation<double> animation;
  final Widget Function(
    BuildContext context,
    Animation<double> popupCurve,
    Animation<double> backdropCurve,
    ValueNotifier<double> swipeProgress,
  )
  builder;

  @override
  State<_DSheetCurves> createState() => _DSheetCurvesState();
}

class _DSheetCurvesState extends State<_DSheetCurves> {
  late CurvedAnimation _popup;
  late CurvedAnimation _backdrop;
  final _swipeProgress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    _popup = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeInOut,
    );
    _backdrop = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0, .75, curve: Curves.easeInOut),
      reverseCurve: const Interval(.25, 1, curve: Curves.easeInOut),
    );
  }

  void _dispose() {
    _popup.dispose();
    _backdrop.dispose();
  }

  @override
  void didUpdateWidget(_DSheetCurves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.animation, widget.animation)) return;
    _dispose();
    _create();
  }

  @override
  void dispose() {
    _dispose();
    _swipeProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _popup, _backdrop, _swipeProgress);
}

Widget _sheetPresentation(
  BuildContext context,
  DDialogPresentation presentation,
  DSheetSide requestedSide,
  double maxWidth,
  double? width,
  bool inset,
  bool animateSize,
  bool fillAvailableHeight,
  bool extendBehindKeyboard,
  bool dismissOnSwipe, {
  bool retainKeyboardInsets = false,
  VoidCallback? onRetainedDismiss,
}) => _DSheetCurves(
  animation: presentation.animation,
  builder: (context, popupCurve, backdropCurve, swipeProgress) => _sheetLayout(
    context,
    presentation,
    popupCurve,
    backdropCurve,
    swipeProgress,
    requestedSide,
    maxWidth,
    width,
    inset,
    animateSize,
    fillAvailableHeight,
    extendBehindKeyboard,
    dismissOnSwipe,
    retainKeyboardInsets: retainKeyboardInsets,
    onRetainedDismiss: onRetainedDismiss,
  ),
);

Widget _sheetLayout(
  BuildContext context,
  DDialogPresentation presentation,
  Animation<double> popupCurve,
  Animation<double> backdropCurve,
  ValueNotifier<double> swipeProgress,
  DSheetSide requestedSide,
  double maxWidth,
  double? width,
  bool inset,
  bool animateSize,
  bool fillAvailableHeight,
  bool extendBehindKeyboard,
  bool dismissOnSwipe, {
  bool retainKeyboardInsets = false,
  VoidCallback? onRetainedDismiss,
}) {
  final animate = !MediaQuery.disableAnimationsOf(context);
  final side = requestedSide.resolve(Directionality.of(context));
  final background = DTokens.of(context).background.withValues(alpha: 1);
  // Full-height sheets start with an opaque canvas. A swipe reveals the
  // underlying application as the sheet moves out of the viewport.
  final backdropColor = Color.lerp(
    background,
    Colors.black,
    Theme.of(context).brightness == Brightness.dark ? .32 : .12,
  )!;
  Widget backdrop = fillAvailableHeight
      ? presentation.buildBackdrop(color: backdropColor, blurSigma: 0)
      : presentation.buildBackdrop(blurSigma: 2);
  if (animate && !fillAvailableHeight) {
    backdrop = FadeTransition(opacity: backdropCurve, child: backdrop);
  }
  backdrop = ValueListenableBuilder<double>(
    valueListenable: swipeProgress,
    builder: (context, progress, child) =>
        Opacity(opacity: 1 - progress, child: child),
    child: backdrop,
  );

  final beginOffset = switch (side) {
    DSheetSide.center => const Offset(0, 40),
    DSheetSide.top => const Offset(0, -40),
    DSheetSide.right => const Offset(40, 0),
    DSheetSide.bottom => const Offset(0, 40),
    DSheetSide.left => const Offset(-40, 0),
    _ => throw StateError('Sheet side was not resolved.'),
  };
  final content = inset && !extendBehindKeyboard
      ? Builder(
          builder: (context) => MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: presentation.content,
          ),
        )
      : presentation.content;
  Widget popup = _DSheetSideScope(
    side: side,
    inset: inset,
    fillAvailableHeight: fillAvailableHeight,
    extendBehindKeyboard: extendBehindKeyboard,
    child: extendBehindKeyboard
        ? Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: content,
            ),
          )
        : fillAvailableHeight
        ? MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Builder(
              builder: (context) => MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: content,
              ),
            ),
          )
        : content,
  );
  final mobile = switch (Theme.of(context).platform) {
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => true,
    _ => false,
  };
  if (dismissOnSwipe && mobile && side == DSheetSide.bottom) {
    final content = popup;
    Widget swipe(VoidCallback close, {bool retained = false}) =>
        _DSheetSwipeDismiss(
          onDismiss: close,
          retained: retained,
          routeAnimation: presentation.animation,
          popupCurve: popupCurve,
          scale: fillAvailableHeight,
          swipeProgress: swipeProgress,
          child: content,
        );
    popup = onRetainedDismiss != null
        ? swipe(onRetainedDismiss, retained: true)
        : DSheetClose<void>(builder: (context, close) => swipe(close));
  } else {
    popup = _DSheetMotion(
      curve: popupCurve,
      beginOffset: beginOffset,
      scale: fillAvailableHeight,
      child: popup,
    );
  }

  final layout = LayoutBuilder(
    builder: (context, bounds) {
      final margin = inset ? DSpacing.md : 0.0;
      // A trigger inside SafeArea can capture a MediaQuery with its top padding
      // consumed, even though the overlay route covers the whole screen.
      final view = View.of(context);
      final safeTop = math.max(
        MediaQuery.paddingOf(context).top,
        view.viewPadding.top / view.devicePixelRatio,
      );
      // Inset surfaces float above the device's bottom corners. The opening
      // control may already have consumed this padding inside a SafeArea.
      final safeBottom = inset && !extendBehindKeyboard
          ? math.max(
              MediaQuery.viewPaddingOf(context).bottom,
              view.viewPadding.bottom / view.devicePixelRatio,
            )
          : 0.0;
      final pickerTop = math.max(safeTop + DSpacing.xl, bounds.maxHeight * .11);
      final availableWidth = (bounds.maxWidth - margin * 2).clamp(
        0.0,
        double.infinity,
      );
      final panelWidth = width == null
          ? availableWidth < 640
                ? availableWidth * .75
                : (availableWidth * .75).clamp(0, maxWidth).toDouble()
          : width.clamp(0, maxWidth).clamp(0, availableWidth).toDouble();
      final horizontal = side.isHorizontal;
      final positioned = AnimatedPositioned(
        duration: animateSize
            ? DMotion.duration(context, DMotion.change)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        left: side == DSheetSide.center
            ? (bounds.maxWidth - panelWidth) / 2
            : side == DSheetSide.right
            ? null
            : margin,
        right: side == DSheetSide.left || side == DSheetSide.center
            ? null
            : margin,
        top: extendBehindKeyboard
            ? safeTop + DSpacing.sm
            : fillAvailableHeight
            ? pickerTop
            : side == DSheetSide.bottom
            ? null
            : margin,
        bottom: fillAvailableHeight
            ? (extendBehindKeyboard
                      ? 0.0
                      : math.max(
                          MediaQuery.viewInsetsOf(context).bottom,
                          safeBottom,
                        )) +
                  margin
            : side == DSheetSide.top
            ? null
            : margin + safeBottom,
        width: horizontal ? panelWidth : null,
        child: popup,
      );
      return Stack(
        children: [
          Positioned.fill(child: backdrop),
          positioned,
        ],
      );
    },
  );
  return fillAvailableHeight
      ? _DSheetKeyboardInsets(
          child: retainKeyboardInsets
              ? _DSheetRetainedKeyboardInsets(child: layout)
              : layout,
        )
      : layout;
}

class _DSheetMotion extends StatelessWidget {
  const _DSheetMotion({
    required this.curve,
    required this.beginOffset,
    required this.scale,
    required this.child,
  });

  final Animation<double> curve;
  final Offset beginOffset;
  final bool scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return FadeTransition(
      opacity: curve,
      child: AnimatedBuilder(
        animation: curve,
        child: scale
            ? ScaleTransition(
                scale: Tween<double>(begin: .97, end: 1).animate(curve),
                child: child,
              )
            : child,
        builder: (context, child) => Transform.translate(
          offset: Offset.lerp(beginOffset, Offset.zero, curve.value)!,
          child: child,
        ),
      ),
    );
  }
}

// Start the exit at the swipe's release velocity. Slow swipes accelerate to
// finish within 320ms; a faster swipe coasts without losing any of its speed.
class _DSheetDismissSimulation extends Simulation {
  _DSheetDismissSimulation(
    this.distance,
    this.velocity,
    this.initialValue, {
    this.endValue = 0,
  }) : acceleration = math.max(
         0,
         2 * (distance - velocity * .32) / (.32 * .32),
       );

  final double distance;
  final double velocity;
  final double initialValue;
  final double endValue;
  final double acceleration;

  double _progress(double time) =>
      (velocity * time + acceleration * time * time / 2) / distance;

  @override
  double x(double time) =>
      initialValue + (endValue - initialValue) * _progress(time).clamp(0, 1);

  @override
  double dx(double time) =>
      (endValue - initialValue) * (velocity + acceleration * time) / distance;

  @override
  bool isDone(double time) => _progress(time) >= 1;
}

/// A visible sheet region that drags the sheet independently of body scrolling.
///
/// Wrap a pinned header to allow dismissal even when its scrollable ancestor
/// is away from the top. In sheets without swipe dismissal this is inert.
class DSheetDragRegion extends StatelessWidget {
  const DSheetDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final swipe = context
        .dependOnInheritedWidgetOfExactType<_DSheetSwipeScope>()
        ?.swipe;
    if (swipe == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: const {PointerDeviceKind.touch},
      onVerticalDragStart: (_) => swipe._start(),
      onVerticalDragUpdate: (details) => swipe._update(details.delta.dy),
      onVerticalDragEnd: (details) =>
          swipe._finish(details.primaryVelocity ?? 0),
      onVerticalDragCancel: () => swipe._finish(0, cancelled: true),
      child: child,
    );
  }
}

class _DSheetSwipeScope extends InheritedWidget {
  const _DSheetSwipeScope({required this.swipe, required super.child});

  final _DSheetSwipeDismissState swipe;

  @override
  bool updateShouldNotify(_DSheetSwipeScope oldWidget) =>
      swipe != oldWidget.swipe;
}

class _DSheetSwipeDismiss extends StatefulWidget {
  const _DSheetSwipeDismiss({
    required this.onDismiss,
    required this.retained,
    required this.routeAnimation,
    required this.popupCurve,
    required this.scale,
    required this.swipeProgress,
    required this.child,
  });

  final VoidCallback onDismiss;
  final bool retained;
  final Animation<double> routeAnimation;
  final Animation<double> popupCurve;
  final bool scale;
  final ValueNotifier<double> swipeProgress;
  final Widget child;

  @override
  State<_DSheetSwipeDismiss> createState() => _DSheetSwipeDismissState();
}

class _DSheetSwipeDismissState extends State<_DSheetSwipeDismiss>
    with SingleTickerProviderStateMixin {
  late final _travel = AnimationController.unbounded(vsync: this);
  int? _pointer;
  VelocityTracker? _velocity;
  BuildContext? _scrollOrigin;
  bool _dragging = false;
  bool _exiting = false;
  DOverlayRoute<dynamic, Object>? _route;
  Simulation? Function()? _pendingSimulation;
  _DSheetDismissSimulation? _dismissal;
  double _dismissOrigin = 0;
  double _dismissCurve = 1;
  double _swipeExtent = 1;

  double get _offset {
    final dismissal = _dismissal;
    return dismissal == null
        ? _travel.value
        : _dismissOrigin +
              dismissal.distance *
                  (1 - widget.routeAnimation.value / dismissal.initialValue);
  }

  void _syncBackdrop() {
    widget.swipeProgress.value = (_offset / _swipeExtent).clamp(0, 1);
  }

  Simulation _beginDismissal(double velocity) {
    _travel.stop();
    _dismissOrigin = _travel.value;
    _dismissCurve = widget.popupCurve.value;
    final box = context.findRenderObject()! as RenderBox;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy + _dismissOrigin;
    _swipeExtent = math.max(1, viewportHeight - top + _dismissOrigin);
    return _dismissal = _DSheetDismissSimulation(
      math.max(1, viewportHeight - top),
      math.max(0, velocity),
      widget.routeAnimation.value,
    );
  }

  void _clearPendingSimulation() {
    if (_route?.reverseSimulationBuilder == _pendingSimulation) {
      _route?.reverseSimulationBuilder = null;
    }
    _pendingSimulation = null;
  }

  @override
  void initState() {
    super.initState();
    _travel.addListener(_syncBackdrop);
    widget.routeAnimation.addListener(_syncBackdrop);
    widget.routeAnimation.addStatusListener(_onRouteStatus);
  }

  @override
  void didUpdateWidget(_DSheetSwipeDismiss oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeAnimation == widget.routeAnimation) return;
    oldWidget.routeAnimation.removeListener(_syncBackdrop);
    oldWidget.routeAnimation.removeStatusListener(_onRouteStatus);
    widget.routeAnimation.addListener(_syncBackdrop);
    widget.routeAnimation.addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      // Controlled picker owners can forward a close over several frames.
      // Keep the drag offset when their route starts closing, even if the
      // fallback return animation has already been scheduled.
      _travel.stop();
    }
  }

  void _start() {
    if (_exiting) return;
    final box = context.findRenderObject()! as RenderBox;
    _swipeExtent = math.max(
      1,
      MediaQuery.sizeOf(context).height - box.localToGlobal(Offset.zero).dy,
    );
    _clearPendingSimulation();
    _travel.stop();
    _dragging = true;
  }

  void _update(double delta) {
    if (_exiting) return;
    _travel.value = math.max(0, _travel.value + delta);
  }

  void _restore() {
    if (!mounted) return;
    final pending = _pendingSimulation;
    _travel
        .animateTo(
          0,
          duration: DMotion.duration(context, DMotion.change),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          if (mounted && _dismissal == null && _pendingSimulation == pending) {
            _clearPendingSimulation();
          }
        });
  }

  void _dismissRetained(double velocity) {
    _exiting = true;
    void complete() {
      if (!mounted) return;
      widget.onDismiss();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _exiting = false;
        _restore();
      });
    }

    if (MediaQuery.disableAnimationsOf(context)) {
      complete();
      return;
    }
    final box = context.findRenderObject()! as RenderBox;
    final distance = math.max(
      1.0,
      MediaQuery.sizeOf(context).height -
          box.localToGlobal(Offset.zero).dy -
          _travel.value,
    );
    unawaited(
      _travel
          .animateWith(
            _DSheetDismissSimulation(
              distance,
              math.max(0, velocity),
              _travel.value,
              endValue: _travel.value + distance,
            ),
          )
          .then<void>((_) => complete()),
    );
  }

  void _finish(double velocity, {bool cancelled = false}) {
    if (!_dragging) return;
    _dragging = false;
    _scrollOrigin = null;
    // Require a deliberate pull regardless of release speed. Measure against
    // the distance off-screen so opening the keyboard does not make the sheet
    // easier to dismiss; velocity only determines how an accepted exit moves.
    if (!cancelled && _travel.value >= _swipeExtent * .3) {
      if (widget.retained) {
        _dismissRetained(velocity);
        return;
      }
      final route = ModalRoute.of(context);
      if (!MediaQuery.disableAnimationsOf(context) &&
          route is DOverlayRoute<dynamic, Object>) {
        _route = route;
        _pendingSimulation = () => _beginDismissal(velocity);
        route.reverseSimulationBuilder = _pendingSimulation;
      }
      widget.onDismiss();
      // Controlled owners can decline the close request. Let their route
      // update before deciding whether the sheet needs to settle back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.routeAnimation.status != AnimationStatus.reverse &&
            widget.routeAnimation.status != AnimationStatus.dismissed) {
          _restore();
        }
      });
    } else {
      _restore();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (_exiting ||
        _pointer == null ||
        notification.metrics.axisDirection != AxisDirection.down ||
        (_scrollOrigin != null && _scrollOrigin != notification.context)) {
      return false;
    }
    final details = switch (notification) {
      OverscrollNotification(:final dragDetails) => dragDetails,
      ScrollUpdateNotification(:final dragDetails) => dragDetails,
      _ => null,
    };
    if (details == null) return false;
    if (_scrollOrigin != null) {
      // Once scrolling reaches an edge, track the finger like a header drag.
      // Applying bouncing-scroll resistance here would swallow the handoff.
      _update(details.delta.dy);
      return false;
    }

    double delta = 0;
    if (notification is OverscrollNotification) {
      delta = notification.overscroll;
    } else if (notification is ScrollUpdateNotification) {
      // Bouncing physics move outside the range instead of reporting an
      // OverscrollNotification. Transfer only movement beyond the edge.
      final pixels = notification.metrics.pixels;
      final minimum = notification.metrics.minScrollExtent;
      final previous = pixels - (notification.scrollDelta ?? 0);
      delta = math.max(0, minimum - previous) - math.max(0, minimum - pixels);
    }
    final atTop =
        notification.metrics.pixels <= notification.metrics.minScrollExtent;
    if (atTop && delta < 0 && details.delta.dy > 0) {
      if (!_dragging) _start();
      _scrollOrigin = notification.context;
      _update(delta.abs());
    }
    return false;
  }

  @override
  void dispose() {
    _clearPendingSimulation();
    widget.routeAnimation.removeListener(_syncBackdrop);
    widget.routeAnimation.removeStatusListener(_onRouteStatus);
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_travel, widget.routeAnimation]),
    builder: (context, child) {
      final dismissal = _dismissal;
      return Transform.translate(
        offset: Offset(0, _offset),
        child: _DSheetMotion(
          curve: dismissal == null
              ? widget.popupCurve
              : AlwaysStoppedAnimation(_dismissCurve),
          beginOffset: const Offset(0, 40),
          scale: widget.scale,
          child: child!,
        ),
      );
    },
    child: Listener(
      onPointerDown: (event) {
        if (_exiting ||
            _pointer != null ||
            event.kind != PointerDeviceKind.touch) {
          return;
        }
        _pointer = event.pointer;
        _velocity = VelocityTracker.withKind(event.kind)
          ..addPosition(event.timeStamp, event.position);
      },
      onPointerMove: (event) {
        if (event.pointer == _pointer) {
          _velocity?.addPosition(event.timeStamp, event.position);
        }
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        if (_scrollOrigin != null) {
          _finish(_velocity?.getVelocity().pixelsPerSecond.dy ?? 0);
        }
        _pointer = null;
        _velocity = null;
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointer) return;
        _finish(0, cancelled: true);
        _pointer = null;
        _velocity = null;
      },
      child: GestureDetector(
        supportedDevices: const {PointerDeviceKind.touch},
        onVerticalDragStart: (_) => _start(),
        onVerticalDragUpdate: (details) => _update(details.delta.dy),
        onVerticalDragEnd: (details) => _finish(details.primaryVelocity ?? 0),
        onVerticalDragCancel: () => _finish(0, cancelled: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: _DSheetSwipeScope(swipe: this, child: widget.child),
        ),
      ),
    ),
  );
}

// Scaffold can consume the opening control's keyboard inset. Observe the view
// so a full-height sheet still resizes as the keyboard opens and closes, while
// preserving the caller's other MediaQuery overrides.
class _DSheetKeyboardInsets extends StatelessWidget {
  const _DSheetKeyboardInsets({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery.fromView(
      view: View.of(context),
      child: Builder(
        builder: (viewContext) => MediaQuery(
          data: media.copyWith(
            viewInsets: media.viewInsets.copyWith(
              bottom: math.max(
                media.viewInsets.bottom,
                MediaQuery.viewInsetsOf(viewContext).bottom,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The base-nova fixed-edge sheet surface.
class DSheetContent extends StatelessWidget {
  const DSheetContent({
    super.key,
    required this.children,
    this.side = DSheetSide.right,
    this.showCloseButton = true,
    this.closeButton,
    this._closeSemanticLabel,
    this.semanticLabel,
    this.backgroundColor,
    this.sidePanelMaxWidth = 384,
    this.sidePanelWidth,
    this.inset = false,
    this.animateSize = false,
    this.sideAccessory,
    this.sideAccessoryWidth = 52,
    this.scrollWholeSheet,
    this.topBottomMaxHeightFactor,
    this.fillAvailableHeight = false,
    this.extendBehindKeyboard = false,
  }) : assert(sideAccessoryWidth > 0),
       assert(!extendBehindKeyboard || fillAvailableHeight),
       assert(
         sideAccessory == null ||
             (side != DSheetSide.top && side != DSheetSide.bottom),
       ),
       assert(sidePanelMaxWidth > 0),
       assert(sidePanelWidth == null || sidePanelWidth > 0),
       assert(
         topBottomMaxHeightFactor == null ||
             (topBottomMaxHeightFactor > 0 && topBottomMaxHeightFactor <= 1),
       );

  final List<Widget> children;
  final DSheetSide side;
  final bool showCloseButton;
  final Widget? closeButton;
  final String? _closeSemanticLabel;
  String get closeSemanticLabel => _closeSemanticLabel ?? appL10n.close;
  final String? semanticLabel;

  /// The surface fill override.
  ///
  /// Defaults to opaque [DTokens.background] for full-height sheets and
  /// [DTokens.surface] otherwise.
  final Color? backgroundColor;

  final double sidePanelMaxWidth;

  /// An exact side-panel width, clamped to [sidePanelMaxWidth] and the viewport.
  ///
  /// Null preserves Sheet's responsive 75% width and 384px desktop cap.
  final double? sidePanelWidth;

  /// Floats the surface inside the viewport with shared spacing and rounded
  /// corners, above the bottom safe area. The safe inset is consumed outside
  /// the surface so its content does not repeat that padding. The default
  /// retains the reference's fixed-edge presentation.
  final bool inset;

  /// Animates changes to the sheet's bounds without replacing its contents.
  /// Reduced-motion preferences always make these changes immediate.
  final bool animateSize;

  /// Optional controls beside the surface, on the inward-facing edge.
  ///
  /// Supported on side sheets only. The gutter is inside the panel width and
  /// shares its route, focus scope and motion, but stays outside its decoration.
  final Widget? sideAccessory;

  /// Space reserved for [sideAccessory], including its horizontal breathing room.
  /// Both this gutter and the surface must fit inside [sidePanelWidth].
  final double sideAccessoryWidth;

  /// Overrides automatic whole-surface scrolling at large text sizes.
  ///
  /// Null preserves the default. Set false only when a composed child owns a
  /// bounded scroll region while its surrounding header and footer stay fixed.
  final bool? scrollWholeSheet;

  /// Optional cap used by long top and bottom compositions.
  final double? topBottomMaxHeightFactor;

  /// Whether the sheet fills the viewport above the keyboard.
  ///
  /// The top gap is at least 11% of the viewport and 24px below the safe area.
  /// [extendBehindKeyboard] instead fills to the bottom of the viewport with
  /// an 8px gap below the top safe area.
  final bool fillAvailableHeight;

  /// Whether a full-height sheet paints behind the keyboard.
  ///
  /// The live bottom view inset remains available to the content, which must
  /// keep controls and scroll reveal bounds above it. Bottom safe-area padding
  /// is also content-owned. An edge-to-edge sheet has rounded top corners.
  final bool extendBehindKeyboard;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final inset = _DSheetSideScope.insetOf(context) ?? this.inset;
    final fillAvailableHeight =
        _DSheetSideScope.fillsAvailableHeightOf(context) ??
        this.fillAvailableHeight;
    final extendBehindKeyboard =
        _DSheetSideScope.extendsBehindKeyboardOf(context) ??
        this.extendBehindKeyboard;
    final resolved =
        _DSheetSideScope.maybeOf(context) ??
        side.resolve(Directionality.of(context));
    final fillsHeight = resolved.isHorizontal;
    final hasBody = children.any((child) => child is DSheetBody);
    final scrollWholeSheet =
        this.scrollWholeSheet ??
        ((fillsHeight || topBottomMaxHeightFactor != null) &&
            (MediaQuery.textScalerOf(context).scale(1) > 1.5 ||
                (topBottomMaxHeightFactor != null && !hasBody)));
    final parts = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      final child = children[index];
      if (index > 0) parts.add(const SizedBox(height: DSpacing.lg));
      if (child is DSheetBody && fillsHeight && !scrollWholeSheet) {
        parts.add(Expanded(child: child));
      } else if (child is DSheetBody &&
          topBottomMaxHeightFactor != null &&
          !scrollWholeSheet) {
        parts.add(Flexible(child: child));
      } else if (fillsHeight && child is DSheetFooter) {
        if (!hasBody && !scrollWholeSheet) parts.add(const Spacer());
        parts.add(child);
      } else {
        parts.add(child);
      }
    }

    final edgeBorder = BorderSide(color: tokens.border);
    final border = inset
        ? Border.all(color: tokens.border)
        : switch (resolved) {
            DSheetSide.center => Border.all(color: tokens.border),
            DSheetSide.top => Border(bottom: edgeBorder),
            DSheetSide.right => Border(left: edgeBorder),
            DSheetSide.bottom => Border(top: edgeBorder),
            DSheetSide.left => Border(right: edgeBorder),
            _ => throw StateError('Sheet side was not resolved.'),
          };
    final radius = inset
        ? BorderRadius.circular(DRadius.panel)
        : extendBehindKeyboard
        ? const BorderRadius.vertical(top: Radius.circular(DRadius.panel * 2))
        : BorderRadius.zero;
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .1),
            blurRadius: 15,
            offset: const Offset(0, 10),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .1),
            blurRadius: 6,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: border, borderRadius: radius),
        child: Material(
          animationDuration: Duration.zero,
          borderRadius: radius,
          clipBehavior: inset || extendBehindKeyboard
              ? Clip.antiAlias
              : Clip.none,
          color:
              backgroundColor ??
              (fillAvailableHeight
                  ? tokens.background.withValues(alpha: 1)
                  : tokens.surface),
          textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: DiscourseTypography.sm,
            height: 20 / 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: tokens.foreground,
          ),
          child: SafeArea(
            bottom: !extendBehindKeyboard,
            minimum: EdgeInsets.only(
              bottom: extendBehindKeyboard
                  ? 0
                  : MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Stack(
              children: [
                if (scrollWholeSheet)
                  SingleChildScrollView(
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: parts,
                    ),
                  )
                else
                  Column(
                    mainAxisSize: fillsHeight
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: parts,
                  ),
                if (showCloseButton)
                  Positioned(
                    top: DSpacing.md,
                    right: DSpacing.md,
                    child:
                        closeButton ??
                        DSheetClose<void>(
                          builder: (context, close) => DButton.iconOnly(
                            onPressed: close,
                            size: DButtonSize.small,
                            variant: DButtonVariant.ghost,
                            icon: const _DSheetCloseIcon(),
                            tooltip: closeSemanticLabel,
                            semanticLabel: closeSemanticLabel,
                          ),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final maxHeightFactor = topBottomMaxHeightFactor;
    if (!fillsHeight && maxHeightFactor != null) {
      surface = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
        ),
        child: surface,
      );
    }
    if (sideAccessory case final accessory?) {
      final gutter = SizedBox(
        width: sideAccessoryWidth,
        child: Center(child: accessory),
      );
      surface = Row(
        textDirection: TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resolved == DSheetSide.right || resolved == DSheetSide.center)
            gutter,
          Expanded(key: const ValueKey('sheet-surface'), child: surface),
          if (resolved == DSheetSide.left) gutter,
        ],
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      label: semanticLabel,
      child: surface,
    );
  }
}

class DSheetHeader extends StatelessWidget {
  const DSheetHeader({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(DSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 2),
          children[index],
        ],
      ],
    ),
  );
}

class DSheetTitle extends StatelessWidget {
  const DSheetTitle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      header: true,
      namesRoute: true,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
          fontSize: DiscourseTypography.base,
          height: 24 / 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: tokens.foreground,
        ),
        child: child,
      ),
    );
  }
}

class DSheetDescription extends StatelessWidget {
  const DSheetDescription({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: DTokens.of(context).mutedForeground,
    ),
    child: child,
  );
}

/// Scrollable body with the reference's 16px horizontal inset.
class DSheetBody extends StatelessWidget {
  const DSheetBody({
    super.key,
    required this.child,
    this.controller,
    this.padding = const EdgeInsets.symmetric(horizontal: DSpacing.lg),
  });

  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    primary: false,
    padding: padding,
    child: child,
  );
}

class DSheetFooter extends StatelessWidget {
  const DSheetFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(DSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: DSpacing.sm),
          children[index],
        ],
      ],
    ),
  );
}

typedef DSheetCloseBuilder =
    Widget Function(BuildContext context, VoidCallback close);

class DSheetClose<T> extends StatelessWidget {
  const DSheetClose({super.key, required this.builder, this.result});

  final DSheetCloseBuilder builder;
  final T? result;

  @override
  Widget build(BuildContext context) =>
      DDialogClose<T>(result: result, builder: builder);
}

class _DSheetCloseIcon extends StatelessWidget {
  const _DSheetCloseIcon();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CustomPaint(
      painter: _DSheetCloseIconPainter(
        IconTheme.of(context).color ?? DTokens.of(context).foreground,
      ),
    ),
  );
}

class _DSheetCloseIconPainter extends CustomPainter {
  const _DSheetCloseIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4 / 3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(4, 4), const Offset(12, 12), paint)
      ..drawLine(const Offset(12, 4), const Offset(4, 12), paint);
  }

  @override
  bool shouldRepaint(_DSheetCloseIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

typedef DSheetContentBuilder<T> =
    DSheetContent Function(
      BuildContext context,
      DSheetController<T> controller,
    );

/// Opens a route-owned Sheet and returns its typed result.
Future<T?> showDSheet<T>({
  required BuildContext context,
  required DSheetContentBuilder<T> builder,
  DSheetSide side = DSheetSide.right,
  double sidePanelMaxWidth = 384,
  double? sidePanelWidth,
  bool inset = false,
  bool animateSize = false,
  bool fillAvailableHeight = false,
  bool extendBehindKeyboard = false,
  bool useRootNavigator = false,
  bool modal = true,
  bool dismissOnBarrier = true,
  bool dismissOnEscape = true,
  bool dismissOnSwipe = true,
  String? barrierLabel,
  RouteSettings? routeSettings,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
}) {
  assert(sidePanelMaxWidth > 0);
  assert(sidePanelWidth == null || sidePanelWidth > 0);
  assert(!extendBehindKeyboard || fillAvailableHeight);
  return showDDialog<T>(
    context: context,
    builder: builder,
    useRootNavigator: useRootNavigator,
    modal: modal,
    dismissOnBarrier: dismissOnBarrier,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel ?? appL10n.dismissSheet,
    routeSettings: routeSettings,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    presentationBuilder: (context, presentation) => _sheetPresentation(
      context,
      presentation,
      side,
      sidePanelMaxWidth,
      sidePanelWidth,
      inset,
      animateSize,
      fillAvailableHeight,
      extendBehindKeyboard,
      dismissOnSwipe,
    ),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
  );
}
