import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/d_overlay_route.dart';
import '../foundation/tokens.dart';

enum DDrawerSwipeDirection { up, right, down, left, start, end }

enum DDrawerModalMode { modal, nonModal, trapFocus }

enum DDrawerChangeReason {
  trigger,
  outsidePress,
  escape,
  back,
  close,
  focusOut,
  programmatic,
  swipe,
  routeRemoved,
}

enum DDrawerSnapChangeReason { initial, controlled, programmatic, swipe }

@immutable
class DDrawerSnapPoint {
  const DDrawerSnapPoint.fraction(double value)
    : value = value,
      unit = DDrawerSnapPointUnit.fraction,
      assert(value > 0 && value <= 1);

  const DDrawerSnapPoint.pixels(double value)
    : value = value,
      unit = DDrawerSnapPointUnit.pixels,
      assert(value > 0);

  const DDrawerSnapPoint.rem(double value)
    : value = value,
      unit = DDrawerSnapPointUnit.rem,
      assert(value > 0);

  final double value;
  final DDrawerSnapPointUnit unit;

  double resolve(double viewportExtent) => switch (unit) {
    DDrawerSnapPointUnit.fraction => viewportExtent * value,
    DDrawerSnapPointUnit.pixels => value,
    DDrawerSnapPointUnit.rem => value * 16,
  };

  @override
  bool operator ==(Object other) =>
      other is DDrawerSnapPoint && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => 'DDrawerSnapPoint.${unit.name}($value)';
}

enum DDrawerSnapPointUnit { fraction, pixels, rem }

class DDrawerChangeDetails<T> {
  DDrawerChangeDetails({required this.open, required this.reason, this.result});

  final bool open;
  final DDrawerChangeReason reason;
  final T? result;
  bool _canceled = false;

  bool get isCanceled => _canceled;
  void cancel() => _canceled = true;
}

class DDrawerSnapChangeDetails {
  DDrawerSnapChangeDetails({required this.point, required this.reason});

  final DDrawerSnapPoint? point;
  final DDrawerSnapChangeReason reason;
  bool _canceled = false;

  bool get isCanceled => _canceled;
  void cancel() => _canceled = true;
}

/// Imperative state and detached-trigger handle for a mounted [DDrawer].
///
/// Calls while no drawer is attached are intentionally ignored. A borrowed
/// controller is never disposed by the drawer.
class DDrawerController<T> extends ChangeNotifier {
  DDrawerController({
    bool initiallyOpen = false,
    DDrawerSnapPoint? initialSnapPoint,
  }) : _open = initiallyOpen,
       _snapPoint = initialSnapPoint;

  bool _open;
  bool _busy = false;
  bool _disposed = false;
  DDrawerSnapPoint? _snapPoint;
  Object? _attachment;
  void Function(DDrawerChangeReason)? _requestOpen;
  void Function(T?, DDrawerChangeReason)? _requestClose;
  void Function(DDrawerSnapPoint?, DDrawerSnapChangeReason)? _requestSnap;
  DDrawerSwipeDirection? _dismissDirection;
  Future<T?>? _submission;
  int _openSession = 0;

  bool get isOpen => _open;
  bool get isBusy => _busy;
  DDrawerSnapPoint? get snapPoint => _snapPoint;
  bool get isAttached => _attachment != null;

  void open() => _requestOpen?.call(DDrawerChangeReason.programmatic);
  void close([T? result]) =>
      _requestClose?.call(result, DDrawerChangeReason.programmatic);
  void snapTo(DDrawerSnapPoint point) =>
      _requestSnap?.call(point, DDrawerSnapChangeReason.programmatic);

  Future<T?> submit(Future<T> Function() operation) {
    final current = _submission;
    if (current != null) return current;
    final attachment = _attachment;
    final session = _openSession;
    final completer = Completer<T?>();
    _submission = completer.future;
    _busy = true;
    notifyListeners();
    Future<T>.sync(operation)
        .then(
          (result) {
            if (!_disposed &&
                _attachment == attachment &&
                _open &&
                _openSession == session) {
              close(result);
            }
            completer.complete(result);
          },
          onError: (Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          },
        )
        .whenComplete(() {
          if (_submission == completer.future) {
            _submission = null;
            _busy = false;
            if (!_disposed) notifyListeners();
          }
        })
        .ignore();
    return completer.future;
  }

  void _attach(
    Object attachment,
    void Function(DDrawerChangeReason) requestOpen,
    void Function(T?, DDrawerChangeReason) requestClose,
    void Function(DDrawerSnapPoint?, DDrawerSnapChangeReason) requestSnap,
    DDrawerSwipeDirection dismissDirection,
  ) {
    _attachment = attachment;
    _requestOpen = requestOpen;
    _requestClose = requestClose;
    _requestSnap = requestSnap;
    _dismissDirection = dismissDirection;
  }

  void _detach(Object attachment) {
    if (_attachment != attachment) return;
    _attachment = null;
    _requestOpen = null;
    _requestClose = null;
    _requestSnap = null;
    _dismissDirection = null;
  }

  void _setOpen(bool value) {
    if (_open == value) return;
    _open = value;
    if (value) _openSession++;
    if (!_disposed) notifyListeners();
  }

  void _setSnapPoint(DDrawerSnapPoint? value) {
    if (_snapPoint == value) return;
    _snapPoint = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _attachment = null;
    _requestOpen = null;
    _requestClose = null;
    _requestSnap = null;
    _dismissDirection = null;
    super.dispose();
  }
}

typedef DDrawerTriggerBuilder =
    Widget Function(BuildContext context, VoidCallback open);

class DDrawerTrigger extends StatelessWidget {
  const DDrawerTrigger({super.key, required this.builder, this.controller});

  final DDrawerTriggerBuilder builder;
  final DDrawerController<dynamic>? controller;

  @override
  Widget build(BuildContext context) {
    final root = _DDrawerRootScope.maybeOf(context);
    assert(
      root != null || controller != null,
      'DDrawerTrigger must be below DDrawer or receive a controller.',
    );
    return builder(context, root?.open ?? controller!.open);
  }
}

class DDrawer<T> extends StatefulWidget {
  const DDrawer({
    super.key,
    required this.trigger,
    required this.content,
    this.controller,
    this.open,
    this.initiallyOpen = false,
    this.onOpenChanged,
    this.onOpenChangeComplete,
    this.snapPoints = const [],
    this.defaultSnapPoint,
    this.snapPoint,
    this.onSnapPointChanged,
    this.snapToSequentialPoints = false,
    this.swipeDirection = DDrawerSwipeDirection.down,
    this.showSwipeHandle = false,
    this.modalMode = DDrawerModalMode.modal,
    this.disablePointerDismissal = false,
    this.dismissOnEscape = true,
    this.useRootNavigator = false,
    this.barrierLabel = 'Dismiss drawer',
    this.routeSettings,
    this.initialFocusNode,
    this.finalFocusNode,
    this.requestInitialFocus = true,
    this.restoreFocus = true,
  }) : assert(open == null || !initiallyOpen),
       assert(
         snapPoint == null || snapPoints.length > 0,
         'A controlled snap point requires snapPoints.',
       ),
       assert(
         defaultSnapPoint == null || snapPoints.length > 0,
         'A default snap point requires snapPoints.',
       );

  final DDrawerTrigger trigger;
  final Widget content;
  final DDrawerController<T>? controller;
  final bool? open;
  final bool initiallyOpen;
  final ValueChanged<DDrawerChangeDetails<T>>? onOpenChanged;
  final ValueChanged<bool>? onOpenChangeComplete;
  final List<DDrawerSnapPoint> snapPoints;
  final DDrawerSnapPoint? defaultSnapPoint;
  final DDrawerSnapPoint? snapPoint;
  final ValueChanged<DDrawerSnapChangeDetails>? onSnapPointChanged;
  final bool snapToSequentialPoints;
  final DDrawerSwipeDirection swipeDirection;
  final bool showSwipeHandle;
  final DDrawerModalMode modalMode;
  final bool disablePointerDismissal;
  final bool dismissOnEscape;
  final bool useRootNavigator;
  final String barrierLabel;
  final RouteSettings? routeSettings;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;
  final bool requestInitialFocus;
  final bool restoreFocus;

  @override
  State<DDrawer<T>> createState() => _DDrawerState<T>();
}

class _DDrawerState<T> extends State<DDrawer<T>> {
  late DDrawerController<T> _controller;
  late bool _internalOpen;
  late DDrawerSnapPoint? _internalSnapPoint;
  final Object _attachment = Object();
  final ValueNotifier<DOverlayEnvironment?> _environment = ValueNotifier(null);
  final ValueNotifier<_DDrawerConfiguration<T>?> _configuration = ValueNotifier(
    null,
  );
  _DDrawerRoute<T>? _route;
  NavigatorState? _navigator;
  FocusNode? _previousFocus;
  _DDrawerStackHandle? _parentStack;
  _DDrawerProviderHandle? _provider;
  DDrawerChangeReason _closingReason = DDrawerChangeReason.routeRemoved;
  T? _pendingResult;

  bool get _desiredOpen => widget.open ?? _internalOpen;
  DDrawerSnapPoint? get _desiredSnapPoint =>
      widget.snapPoint ?? _internalSnapPoint;

  @override
  void initState() {
    super.initState();
    _internalOpen = widget.controller?.isOpen ?? widget.initiallyOpen;
    _internalSnapPoint =
        widget.controller?.snapPoint ??
        widget.defaultSnapPoint ??
        widget.snapPoints.firstOrNull;
    _controller =
        widget.controller ??
        DDrawerController<T>(
          initiallyOpen: _internalOpen,
          initialSnapPoint: _internalSnapPoint,
        );
    _attachController();
    _controller
      .._setOpen(_desiredOpen)
      .._setSnapPoint(_desiredSnapPoint);
    _controller._dismissDirection = widget.swipeDirection;
    if (_desiredOpen) _scheduleSync();
  }

  @override
  void didUpdateWidget(DDrawer<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller._setOpen(false);
      _controller._detach(_attachment);
      if (oldWidget.controller == null) _controller.dispose();
      _controller =
          widget.controller ??
          DDrawerController<T>(
            initiallyOpen: _desiredOpen,
            initialSnapPoint: _desiredSnapPoint,
          );
      _attachController();
    }
    if (widget.snapPoints != oldWidget.snapPoints &&
        _internalSnapPoint != null &&
        !widget.snapPoints.contains(_internalSnapPoint)) {
      _internalSnapPoint =
          widget.defaultSnapPoint ?? widget.snapPoints.firstOrNull;
    }
    _controller
      .._setOpen(_desiredOpen)
      .._setSnapPoint(_desiredSnapPoint)
      .._dismissDirection = widget.swipeDirection;
    _scheduleSync();
  }

  void _attachController() => _controller._attach(
    _attachment,
    _requestOpen,
    _requestClose,
    _requestSnap,
    widget.swipeDirection,
  );

  void _scheduleSync() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _syncRoute();
  });

  void _requestOpen(DDrawerChangeReason reason) {
    if (_desiredOpen) return;
    final details = DDrawerChangeDetails<T>(open: true, reason: reason);
    widget.onOpenChanged?.call(details);
    if (details.isCanceled || widget.open != null) return;
    setState(() => _internalOpen = true);
    _controller._setOpen(true);
    _scheduleSync();
  }

  bool _requestClose(T? result, DDrawerChangeReason reason) {
    if (!_desiredOpen && _route == null) return false;
    final details = DDrawerChangeDetails<T>(
      open: false,
      reason: reason,
      result: result,
    );
    widget.onOpenChanged?.call(details);
    if (details.isCanceled || widget.open != null) return false;
    _closingReason = reason;
    _pendingResult = result;
    setState(() => _internalOpen = false);
    _controller._setOpen(false);
    _route?.authorizePop(result);
    return true;
  }

  bool _requestSnap(DDrawerSnapPoint? point, DDrawerSnapChangeReason reason) {
    if (point != null && !widget.snapPoints.contains(point)) return false;
    final details = DDrawerSnapChangeDetails(point: point, reason: reason);
    widget.onSnapPointChanged?.call(details);
    if (details.isCanceled || widget.snapPoint != null) return false;
    if (_internalSnapPoint != point) setState(() => _internalSnapPoint = point);
    _controller._setSnapPoint(point);
    return true;
  }

  void _syncRoute() {
    if (_desiredOpen) {
      _route ??= _present();
    } else {
      _route?.authorizePop(_pendingResult);
    }
  }

  _DDrawerRoute<T> _present() {
    final navigator = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    );
    _navigator = navigator;
    _previousFocus = FocusManager.instance.primaryFocus;
    _parentStack = _DDrawerStackScope.maybeOf(context)?.handle;
    _parentStack?.push();
    _provider = _DDrawerProviderScope.maybeOf(context)?.handle;
    _provider?.push();
    final route = _DDrawerRoute<T>(
      settings: widget.routeSettings,
      environment: _environment,
      configuration: _configuration,
      modalMode: widget.modalMode,
      onDismissRequested: (reason) => _requestClose(null, reason),
      onCloseRequested: (result) =>
          _requestClose(result, DDrawerChangeReason.close),
      onSnapRequested: _requestSnap,
      onOpenComplete: () => widget.onOpenChangeComplete?.call(true),
      parentStack: _parentStack,
      requestInitialFocus: widget.requestInitialFocus,
      transitionDuration: DMotion.duration(
        context,
        const Duration(milliseconds: 450),
      ),
      reverseTransitionDuration: DMotion.duration(
        context,
        const Duration(milliseconds: 450),
      ),
    );
    unawaited(
      navigator.push<T>(route).then((result) {
        if (!mounted || _route != route) return;
        _route = null;
        _navigator = null;
        _parentStack?.pop();
        if (_parentStack != null) _parentStack!.swiping = false;
        _parentStack = null;
        _provider?.pop();
        _provider = null;
        _pendingResult = null;
        final wasOpen = _desiredOpen;
        if (widget.open == null) {
          setState(() => _internalOpen = false);
          _controller._setOpen(false);
        }
        if (wasOpen) {
          widget.onOpenChanged?.call(
            DDrawerChangeDetails<T>(
              open: false,
              reason: _closingReason,
              result: result,
            ),
          );
        }
        widget.onOpenChangeComplete?.call(false);
        if (widget.restoreFocus && route.wasCurrentWhenAuthorized) {
          final target = widget.finalFocusNode ?? _previousFocus;
          if (target?.canRequestFocus ?? false) target!.requestFocus();
        }
        _previousFocus = null;
      }),
    );
    return route;
  }

  @override
  Widget build(BuildContext context) {
    final nextConfiguration = _DDrawerConfiguration<T>(
      content: widget.content,
      barrierLabel: widget.barrierLabel,
      disablePointerDismissal: widget.disablePointerDismissal,
      dismissOnEscape: widget.dismissOnEscape,
      initialFocusNode: widget.initialFocusNode,
      requestInitialFocus: widget.requestInitialFocus,
      modalMode: widget.modalMode,
      snapPoints: List.unmodifiable(widget.snapPoints),
      snapPoint: _desiredSnapPoint,
      snapToSequentialPoints: widget.snapToSequentialPoints,
      swipeDirection: widget.swipeDirection,
      showSwipeHandle: widget.showSwipeHandle,
    );
    final nextEnvironment = DOverlayEnvironment.capture(context);
    void updateNotifiers() {
      if (_configuration.value != nextConfiguration) {
        _configuration.value = nextConfiguration;
      }
      if (_environment.value != nextEnvironment) {
        _environment.value = nextEnvironment;
      }
    }

    if (_route == null) {
      updateNotifiers();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) updateNotifiers();
      });
    }
    return _DDrawerRootScope(
      open: () => _requestOpen(DDrawerChangeReason.trigger),
      child: widget.trigger,
    );
  }

  @override
  void dispose() {
    _controller._setOpen(false);
    _controller._detach(_attachment);
    if (widget.controller == null) _controller.dispose();
    final route = _route;
    final navigator = _navigator;
    _route = null;
    _navigator = null;
    if (route != null && navigator != null) navigator.removeRoute(route);
    _parentStack?.pop();
    _provider?.pop();
    _environment.dispose();
    _configuration.dispose();
    super.dispose();
  }
}

class _DDrawerRootScope extends InheritedWidget {
  const _DDrawerRootScope({required this.open, required super.child});

  final VoidCallback open;

  static _DDrawerRootScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DDrawerRootScope>();

  @override
  bool updateShouldNotify(_DDrawerRootScope oldWidget) =>
      open != oldWidget.open;
}

@immutable
class _DDrawerConfiguration<T> {
  const _DDrawerConfiguration({
    required this.content,
    required this.barrierLabel,
    required this.disablePointerDismissal,
    required this.dismissOnEscape,
    required this.initialFocusNode,
    required this.requestInitialFocus,
    required this.modalMode,
    required this.snapPoints,
    required this.snapPoint,
    required this.snapToSequentialPoints,
    required this.swipeDirection,
    required this.showSwipeHandle,
  });

  final Widget content;
  final String barrierLabel;
  final bool disablePointerDismissal;
  final bool dismissOnEscape;
  final FocusNode? initialFocusNode;
  final bool requestInitialFocus;
  final DDrawerModalMode modalMode;
  final List<DDrawerSnapPoint> snapPoints;
  final DDrawerSnapPoint? snapPoint;
  final bool snapToSequentialPoints;
  final DDrawerSwipeDirection swipeDirection;
  final bool showSwipeHandle;

  @override
  bool operator ==(Object other) =>
      other is _DDrawerConfiguration<T> &&
      identical(other.content, content) &&
      other.barrierLabel == barrierLabel &&
      other.disablePointerDismissal == disablePointerDismissal &&
      other.dismissOnEscape == dismissOnEscape &&
      identical(other.initialFocusNode, initialFocusNode) &&
      other.requestInitialFocus == requestInitialFocus &&
      other.modalMode == modalMode &&
      listEquals(other.snapPoints, snapPoints) &&
      other.snapPoint == snapPoint &&
      other.snapToSequentialPoints == snapToSequentialPoints &&
      other.swipeDirection == swipeDirection &&
      other.showSwipeHandle == showSwipeHandle;

  @override
  int get hashCode => Object.hash(
    identityHashCode(content),
    barrierLabel,
    disablePointerDismissal,
    dismissOnEscape,
    identityHashCode(initialFocusNode),
    requestInitialFocus,
    modalMode,
    Object.hashAll(snapPoints),
    snapPoint,
    snapToSequentialPoints,
    swipeDirection,
    showSwipeHandle,
  );
}

class _DDrawerRoute<T> extends DOverlayRoute<T, _DDrawerConfiguration<T>> {
  _DDrawerRoute({
    super.settings,
    required super.environment,
    required super.configuration,
    required this.modalMode,
    required bool Function(DDrawerChangeReason) onDismissRequested,
    required bool Function(T?) onCloseRequested,
    required bool Function(DDrawerSnapPoint?, DDrawerSnapChangeReason)
    onSnapRequested,
    required VoidCallback onOpenComplete,
    required _DDrawerStackHandle? parentStack,
    required bool requestInitialFocus,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
  }) : super(
         requestFocus:
             requestInitialFocus && modalMode != DDrawerModalMode.nonModal,
         traversalEdgeBehavior: modalMode == DDrawerModalMode.nonModal
             ? TraversalEdgeBehavior.leaveFlutterView
             : TraversalEdgeBehavior.closedLoop,
         directionalTraversalEdgeBehavior:
             modalMode == DDrawerModalMode.nonModal
             ? TraversalEdgeBehavior.leaveFlutterView
             : TraversalEdgeBehavior.closedLoop,
         barrierLabelOf: (config) => config.barrierLabel,
         onPopBlocked: () => onDismissRequested(DDrawerChangeReason.back),
         pageBuilder: (context, config, animation) => _DDrawerRoutePage<T>(
           configuration: config,
           animation: animation,
           onDismissRequested: onDismissRequested,
           onCloseRequested: onCloseRequested,
           onSnapRequested: onSnapRequested,
           onOpenComplete: onOpenComplete,
           parentStack: parentStack,
         ),
       );

  final DDrawerModalMode modalMode;

  @override
  Widget buildModalBarrier() => modalMode == DDrawerModalMode.modal
      ? super.buildModalBarrier()
      : const IgnorePointer(child: SizedBox.expand());
}

class _DDrawerRoutePage<T> extends StatefulWidget {
  const _DDrawerRoutePage({
    required this.configuration,
    required this.animation,
    required this.onDismissRequested,
    required this.onCloseRequested,
    required this.onSnapRequested,
    required this.onOpenComplete,
    required this.parentStack,
  });

  final _DDrawerConfiguration<T> configuration;
  final Animation<double> animation;
  final bool Function(DDrawerChangeReason) onDismissRequested;
  final bool Function(T?) onCloseRequested;
  final bool Function(DDrawerSnapPoint?, DDrawerSnapChangeReason)
  onSnapRequested;
  final VoidCallback onOpenComplete;
  final _DDrawerStackHandle? parentStack;

  @override
  State<_DDrawerRoutePage<T>> createState() => _DDrawerRoutePageState<T>();
}

class _DDrawerRoutePageState<T> extends State<_DDrawerRoutePage<T>>
    with SingleTickerProviderStateMixin {
  final FocusScopeNode _focusScope = FocusScopeNode(debugLabel: 'DDrawer');
  final GlobalKey _popupKey = GlobalKey();
  final Object _tapRegionGroup = Object();
  late final AnimationController _travel = AnimationController.unbounded(
    vsync: this,
  )..addListener(_travelChanged);
  late final _DDrawerStackHandle _stack;
  double _extent = 1;
  double? _dismissOrigin;
  bool _initialized = false;
  bool _dragging = false;
  bool _overscrollDragging = false;
  bool _openCompletionSent = false;
  bool _hadFocus = false;
  bool _settlingAfterDrag = false;
  double _dragOrigin = 0;

  DDrawerSwipeDirection get _direction => _resolveDirection(
    widget.configuration.swipeDirection,
    Directionality.of(context),
  );

  bool get _vertical =>
      _direction == DDrawerSwipeDirection.up ||
      _direction == DDrawerSwipeDirection.down;

  @override
  void initState() {
    super.initState();
    _stack = _DDrawerStackHandle(
      () => mounted ? setState(() {}) : null,
      parent: widget.parentStack,
    );
    widget.animation.addListener(_routeAnimationChanged);
    widget.animation.addStatusListener(_routeStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sendOpenCompletionIfReady();
      if (!widget.configuration.requestInitialFocus) return;
      final initial = widget.configuration.initialFocusNode;
      if (initial?.canRequestFocus ?? false) {
        initial!.requestFocus();
      } else if (widget.configuration.modalMode != DDrawerModalMode.nonModal) {
        _focusScope.requestFocus();
        _focusScope.nextFocus();
      }
      _measurePopup();
    });
  }

  @override
  void didUpdateWidget(_DDrawerRoutePage<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      oldWidget.animation
        ..removeListener(_routeAnimationChanged)
        ..removeStatusListener(_routeStatusChanged);
      widget.animation
        ..addListener(_routeAnimationChanged)
        ..addStatusListener(_routeStatusChanged);
    }
    if (widget.configuration.snapPoint != oldWidget.configuration.snapPoint ||
        !listEquals(
          widget.configuration.snapPoints,
          oldWidget.configuration.snapPoints,
        )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_dragging) _settleTo(_activeSnapOffset(), 0);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measurePopup();
    });
  }

  void _routeAnimationChanged() {
    if (widget.animation.status == AnimationStatus.reverse &&
        _dismissOrigin == null) {
      _dismissOrigin = _travel.value;
    }
    if (widget.animation.status == AnimationStatus.reverse &&
        widget.parentStack != null) {
      final routeProgress = const Cubic(
        .22,
        1,
        .36,
        1,
      ).transform(widget.animation.value);
      final origin = _dismissOrigin ?? _travel.value;
      final position = origin + (_extent - origin) * (1 - routeProgress);
      widget.parentStack!.swipeProgress = (position / math.max(_extent, 1))
          .clamp(0, 1)
          .toDouble();
    }
    if (mounted) setState(() {});
  }

  void _routeStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _sendOpenCompletionIfReady();
  }

  void _sendOpenCompletionIfReady() {
    if (_openCompletionSent ||
        widget.animation.status != AnimationStatus.completed) {
      return;
    }
    _openCompletionSent = true;
    widget.onOpenComplete();
  }

  void _travelChanged() {
    if ((_dragging || _overscrollDragging || _settlingAfterDrag) &&
        widget.parentStack != null) {
      final distance = math.max(_extent - _dragOrigin, 1);
      widget.parentStack!.swipeProgress =
          ((_travel.value - _dragOrigin) / distance).clamp(0, 1).toDouble();
    }
    if (mounted) setState(() {});
  }

  void _measurePopup() {
    final render = _popupKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final next = _vertical ? render.size.height : render.size.width;
    if (next <= 0 || (next - _extent).abs() < .5) return;
    final oldSnap = _activeSnapOffset(extent: _extent);
    _extent = next;
    final newSnap = _activeSnapOffset();
    if (!_initialized || (_travel.value - oldSnap).abs() < 1) {
      _travel.value = newSnap;
    }
    _initialized = true;
  }

  double _activeSnapOffset({double? extent}) {
    final actualExtent = extent ?? _extent;
    if (!_vertical || widget.configuration.snapPoints.isEmpty) return 0;
    final point =
        widget.configuration.snapPoint ?? widget.configuration.snapPoints.first;
    final resolvedHeight = point.resolve(MediaQuery.sizeOf(context).height);
    return math.max(0, actualExtent - math.min(actualExtent, resolvedHeight));
  }

  List<_ResolvedSnapPoint> _resolvedSnapPoints() {
    if (!_vertical || widget.configuration.snapPoints.isEmpty) return const [];
    final viewportExtent = MediaQuery.sizeOf(context).height;
    final resolved = widget.configuration.snapPoints
        .map(
          (point) => _ResolvedSnapPoint(
            point,
            math.max(
              0,
              _extent - math.min(_extent, point.resolve(viewportExtent)),
            ),
          ),
        )
        .toList();
    final deduped = <_ResolvedSnapPoint>[];
    for (var index = resolved.length - 1; index >= 0; index--) {
      final candidate = resolved[index];
      if (deduped.any(
        (point) => (point.offset - candidate.offset).abs() <= 1,
      )) {
        continue;
      }
      deduped.add(candidate);
    }
    return deduped.reversed.toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
  }

  double _signedPrimaryDelta(Offset delta) => switch (_direction) {
    DDrawerSwipeDirection.down => delta.dy,
    DDrawerSwipeDirection.up => -delta.dy,
    DDrawerSwipeDirection.right => delta.dx,
    DDrawerSwipeDirection.left => -delta.dx,
    _ => throw StateError('Logical direction was not resolved.'),
  };

  double _signedPrimaryVelocity(Velocity velocity) =>
      _signedPrimaryDelta(velocity.pixelsPerSecond);

  void _dragStartGesture(DragStartDetails details) {
    _travel.stop();
    _dragging = true;
    _overscrollDragging = false;
    _settlingAfterDrag = false;
    _dragOrigin = _travel.value;
    widget.parentStack?.swiping = true;
    setState(() {});
  }

  void _dragUpdateGesture(DragUpdateDetails details) {
    final delta = _vertical
        ? Offset(0, details.primaryDelta ?? 0)
        : Offset(details.primaryDelta ?? 0, 0);
    _updateDrag(_signedPrimaryDelta(delta));
  }

  void _updateDrag(double delta) {
    var next = _travel.value + delta;
    final minimum = _resolvedSnapPoints().firstOrNull?.offset ?? 0;
    if (next < minimum && widget.configuration.snapPoints.isNotEmpty) {
      next = minimum - math.sqrt(minimum - next);
    } else if (next < minimum) {
      next = minimum + (next - minimum) * .2;
    }
    if (next > _extent) next = _extent + (next - _extent) * .2;
    _travel.value = next;
  }

  void _dragEndGesture(DragEndDetails details) {
    _finishDrag(_signedPrimaryVelocity(details.velocity));
  }

  void _dragCancelGesture() => _finishDrag(0);

  void _finishDrag(double velocity) {
    if (!_dragging && !_overscrollDragging) return;
    _dragging = false;
    _overscrollDragging = false;
    widget.parentStack?.swiping = false;
    final current = _travel.value.clamp(0, _extent).toDouble();
    final snapPoints = _resolvedSnapPoints();
    if (snapPoints.isEmpty) {
      final shouldDismiss =
          velocity >= 500 || current > math.max(_extent * .5, 10);
      if (shouldDismiss) {
        final accepted = widget.onDismissRequested(DDrawerChangeReason.swipe);
        if (accepted) {
          _dismissOrigin = current;
          return;
        }
      }
      _settlingAfterDrag = true;
      _settleTo(0, velocity);
      return;
    }

    _ResolvedSnapPoint target;
    var shouldDismiss = false;
    if (widget.configuration.snapToSequentialPoints) {
      final activeOffset = _activeSnapOffset();
      final currentIndex = _closestSnapPointIndex(snapPoints, activeOffset);
      var targetIndex = _closestSnapPointIndex(snapPoints, current);
      var effectiveTarget = current;
      final dragDirection = (current - activeOffset).sign;
      final velocityDirection = velocity.sign;
      final shouldAdvance =
          dragDirection != 0 &&
          velocityDirection == dragDirection &&
          velocity.abs() >= 500;
      if (shouldAdvance) {
        final adjacentIndex = (currentIndex + dragDirection.toInt()).clamp(
          0,
          snapPoints.length - 1,
        );
        if (adjacentIndex != currentIndex) {
          final adjacent = snapPoints[adjacentIndex];
          final shouldForceAdjacent = dragDirection > 0
              ? current < adjacent.offset
              : current > adjacent.offset;
          if (shouldForceAdjacent) {
            targetIndex = adjacentIndex;
            effectiveTarget = adjacent.offset;
          }
        } else if (dragDirection > 0) {
          shouldDismiss = true;
        }
      }
      target = snapPoints[targetIndex];
      if (!shouldDismiss) {
        shouldDismiss =
            (effectiveTarget - _extent).abs() <
            (effectiveTarget - target.offset).abs();
      }
    } else {
      final velocityOffset = velocity.abs() >= 500
          ? velocity.clamp(-4000, 4000) * .3
          : 0.0;
      final projected = (current + velocityOffset).clamp(0, _extent).toDouble();
      target = snapPoints[_closestSnapPointIndex(snapPoints, projected)];
      shouldDismiss =
          (projected - _extent).abs() < (projected - target.offset).abs();
    }

    if (shouldDismiss) {
      final accepted = widget.onDismissRequested(DDrawerChangeReason.swipe);
      if (accepted) {
        _dismissOrigin = current;
        return;
      }
      _settlingAfterDrag = true;
      _settleTo(_activeSnapOffset(), velocity);
      return;
    }
    final accepted = widget.onSnapRequested(
      target.point,
      DDrawerSnapChangeReason.swipe,
    );
    _settlingAfterDrag = true;
    _settleTo(accepted ? target.offset : _activeSnapOffset(), velocity);
  }

  int _closestSnapPointIndex(
    List<_ResolvedSnapPoint> snapPoints,
    double target,
  ) {
    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < snapPoints.length; index++) {
      final distance = (snapPoints[index].offset - target).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }
    return closestIndex;
  }

  void _settleTo(double target, double velocity) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _travel.value = target;
      _finishNestedSettle();
      return;
    }
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 340, damping: 32),
      _travel.value,
      target,
      velocity / 1000,
      tolerance: const Tolerance(distance: .1, velocity: .1),
    );
    unawaited(
      _travel.animateWith(simulation).whenComplete(_finishNestedSettle),
    );
  }

  void _finishNestedSettle() {
    if (!_settlingAfterDrag) return;
    _settlingAfterDrag = false;
    widget.parentStack?.swipeProgress = 0;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_vertical) return false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      final atDismissEdge = switch (_direction) {
        DDrawerSwipeDirection.down =>
          notification.metrics.pixels < notification.metrics.minScrollExtent &&
              delta < 0,
        DDrawerSwipeDirection.up =>
          notification.metrics.pixels > notification.metrics.maxScrollExtent &&
              delta > 0,
        _ => false,
      };
      if (atDismissEdge) {
        _beginOverscrollDrag();
        _updateDrag(delta.abs());
      }
    } else if (notification is OverscrollNotification) {
      final atDismissEdge = switch (_direction) {
        DDrawerSwipeDirection.down =>
          notification.metrics.pixels <=
                  notification.metrics.minScrollExtent + .5 &&
              notification.overscroll < 0,
        DDrawerSwipeDirection.up =>
          notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - .5 &&
              notification.overscroll > 0,
        _ => false,
      };
      if (!atDismissEdge) return false;
      _beginOverscrollDrag();
      _updateDrag(notification.overscroll.abs());
    } else if (notification is ScrollEndNotification && _overscrollDragging) {
      final primaryVelocity = notification.dragDetails?.primaryVelocity ?? 0;
      _finishDrag(
        _direction == DDrawerSwipeDirection.up
            ? -primaryVelocity
            : primaryVelocity,
      );
    }
    return false;
  }

  void _beginOverscrollDrag() {
    if (_overscrollDragging) return;
    _travel.stop();
    _overscrollDragging = true;
    _settlingAfterDrag = false;
    _dragOrigin = _travel.value;
    widget.parentStack?.swiping = true;
  }

  void _requestDismiss(DDrawerChangeReason reason) {
    _dismissOrigin ??= _travel.value;
    if (!widget.onDismissRequested(reason)) _dismissOrigin = null;
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.configuration;
    final direction = _direction;
    final curve = MediaQuery.disableAnimationsOf(context)
        ? Curves.linear
        : const Cubic(.22, 1, .36, 1);
    final routeProgress = curve.transform(widget.animation.value);
    final basePosition = widget.animation.status == AnimationStatus.reverse
        ? (_dismissOrigin ?? _travel.value) +
              (_extent - (_dismissOrigin ?? _travel.value)) *
                  (1 - routeProgress)
        : _extent + (_travel.value - _extent) * routeProgress;
    final stackScaleBase = 1 - math.min(_stack.depth * .05, .25);
    final stackScale = math
        .min(1.0, stackScaleBase + .05 * _stack.swipeProgress)
        .toDouble();
    final stackPeek = math
        .min(math.max(0, _stack.depth - _stack.swipeProgress) * 16.0, 64.0)
        .toDouble();
    final stackOffset = switch (direction) {
      DDrawerSwipeDirection.down => Offset(0, -stackPeek),
      DDrawerSwipeDirection.up => Offset(0, stackPeek),
      DDrawerSwipeDirection.right => Offset(-stackPeek, 0),
      DDrawerSwipeDirection.left => Offset(stackPeek, 0),
      _ => Offset.zero,
    };
    final movement = switch (direction) {
      DDrawerSwipeDirection.down => Offset(0, basePosition),
      DDrawerSwipeDirection.up => Offset(0, -basePosition),
      DDrawerSwipeDirection.right => Offset(basePosition, 0),
      DDrawerSwipeDirection.left => Offset(-basePosition, 0),
      _ => Offset.zero,
    };
    final swipeProgress = (_travel.value / math.max(_extent, 1)).clamp(0, 1);
    final overlayFloor = config.snapPoints.isEmpty ? 0.0 : .5;
    final overlayOpacity =
        (math.max(overlayFloor, 1 - swipeProgress) *
                const Cubic(.32, .72, 0, 1).transform(widget.animation.value))
            .toDouble();

    Widget popup = KeyedSubtree(
      key: _popupKey,
      child: _DDrawerGestureScope(
        onStart: _dragStartGesture,
        onUpdate: _dragUpdateGesture,
        onEnd: _dragEndGesture,
        onCancel: _dragCancelGesture,
        child: _DDrawerContentScope(
          close: (result) => widget.onCloseRequested(result as T?),
          showSwipeHandle: config.showSwipeHandle,
          hasSnapPoints: config.snapPoints.isNotEmpty,
          direction: direction,
          nestedDepth: _stack.depth,
          swiping: _dragging || _overscrollDragging || _stack.swiping,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: FocusScope(node: _focusScope, child: config.content),
            ),
          ),
        ),
      ),
    );
    popup = GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      },
      onVerticalDragStart: _vertical ? _dragStartGesture : null,
      onVerticalDragUpdate: _vertical ? _dragUpdateGesture : null,
      onVerticalDragEnd: _vertical ? _dragEndGesture : null,
      onVerticalDragCancel: _vertical ? _dragCancelGesture : null,
      onHorizontalDragStart: _vertical ? null : _dragStartGesture,
      onHorizontalDragUpdate: _vertical ? null : _dragUpdateGesture,
      onHorizontalDragEnd: _vertical ? null : _dragEndGesture,
      onHorizontalDragCancel: _vertical ? null : _dragCancelGesture,
      child: popup,
    );
    popup = Transform.translate(
      offset: movement + stackOffset,
      child: Transform.scale(
        scale: stackScale,
        alignment: _drawerOrigin(direction),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: _stack.depth > 0 ? .05 : 0),
            BlendMode.srcOver,
          ),
          child: IgnorePointer(ignoring: _stack.depth > 0, child: popup),
        ),
      ),
    );
    if (config.modalMode != DDrawerModalMode.modal) {
      popup = TapRegion(
        groupId: _tapRegionGroup,
        onTapOutside: config.disablePointerDismissal
            ? null
            : (_) => _requestDismiss(DDrawerChangeReason.outsidePress),
        child: Focus(
          onFocusChange: (focused) {
            if (focused) {
              _hadFocus = true;
            } else if (_hadFocus && !config.disablePointerDismissal) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_focusScope.hasFocus) {
                  _requestDismiss(DDrawerChangeReason.focusOut);
                }
              });
            }
          },
          child: popup,
        ),
      );
    }
    popup = _positionDrawer(direction, popup);

    final children = <Widget>[];
    if (config.modalMode == DDrawerModalMode.modal) {
      children.add(
        Positioned.fill(
          child: Opacity(
            opacity: overlayOpacity,
            child: DDrawerOverlay(
              dismissible: !config.disablePointerDismissal,
              semanticsLabel: config.barrierLabel,
              onDismiss: () =>
                  _requestDismiss(DDrawerChangeReason.outsidePress),
            ),
          ),
        ),
      );
    }
    children.add(popup);
    Widget page = _DDrawerStackScope(
      handle: _stack,
      child: Stack(children: children),
    );
    if (config.dismissOnEscape) {
      page = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _requestDismiss(DDrawerChangeReason.escape),
        },
        child: page,
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      child: page,
    );
  }

  Widget _positionDrawer(DDrawerSwipeDirection direction, Widget child) =>
      switch (direction) {
        DDrawerSwipeDirection.down => Align(
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        DDrawerSwipeDirection.up => Align(
          alignment: Alignment.topCenter,
          child: child,
        ),
        DDrawerSwipeDirection.right => Align(
          alignment: Alignment.centerRight,
          child: child,
        ),
        DDrawerSwipeDirection.left => Align(
          alignment: Alignment.centerLeft,
          child: child,
        ),
        _ => child,
      };

  @override
  void dispose() {
    _settlingAfterDrag = false;
    widget.parentStack
      ?..swiping = false
      ..swipeProgress = 0;
    widget.animation
      ..removeListener(_routeAnimationChanged)
      ..removeStatusListener(_routeStatusChanged);
    _travel
      ..removeListener(_travelChanged)
      ..dispose();
    _stack.dispose();
    if (widget.parentStack != null) widget.parentStack!.swiping = false;
    _focusScope.dispose();
    super.dispose();
  }
}

@immutable
class _ResolvedSnapPoint {
  const _ResolvedSnapPoint(this.point, this.offset);
  final DDrawerSnapPoint? point;
  final double offset;
}

class _DDrawerStackHandle extends ChangeNotifier {
  _DDrawerStackHandle(this.onChanged, {this.parent});
  final VoidCallback onChanged;
  final _DDrawerStackHandle? parent;
  int depth = 0;
  bool _swiping = false;
  double _swipeProgress = 0;
  bool _disposed = false;

  bool get swiping => _swiping;
  set swiping(bool value) {
    if (_disposed) return;
    if (_swiping == value) return;
    _swiping = value;
    parent?.swiping = value;
    onChanged();
    notifyListeners();
  }

  double get swipeProgress => _swipeProgress;
  set swipeProgress(double value) {
    if (_disposed) return;
    if ((_swipeProgress - value).abs() < .0001) return;
    _swipeProgress = value;
    parent?.swipeProgress = value;
    onChanged();
    notifyListeners();
  }

  void push() {
    if (_disposed) return;
    depth++;
    parent?.push();
    onChanged();
    notifyListeners();
  }

  void pop() {
    if (_disposed) return;
    if (depth == 0) return;
    depth = math.max(0, depth - 1);
    _swiping = false;
    _swipeProgress = 0;
    parent?.pop();
    onChanged();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _DDrawerStackScope extends InheritedNotifier<_DDrawerStackHandle> {
  const _DDrawerStackScope({
    required _DDrawerStackHandle handle,
    required super.child,
  }) : super(notifier: handle);

  _DDrawerStackHandle get handle => notifier!;

  static _DDrawerStackScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DDrawerStackScope>();
}

class _DDrawerContentScope extends InheritedWidget {
  const _DDrawerContentScope({
    required this.close,
    required this.showSwipeHandle,
    required this.hasSnapPoints,
    required this.direction,
    required this.nestedDepth,
    required this.swiping,
    required super.child,
  });

  final ValueChanged<Object?> close;
  final bool showSwipeHandle;
  final bool hasSnapPoints;
  final DDrawerSwipeDirection direction;
  final int nestedDepth;
  final bool swiping;

  static _DDrawerContentScope of(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<_DDrawerContentScope>();
    assert(result != null, 'DDrawerContent must be inside an open DDrawer.');
    return result!;
  }

  @override
  bool updateShouldNotify(_DDrawerContentScope oldWidget) =>
      close != oldWidget.close ||
      showSwipeHandle != oldWidget.showSwipeHandle ||
      hasSnapPoints != oldWidget.hasSnapPoints ||
      direction != oldWidget.direction ||
      nestedDepth != oldWidget.nestedDepth ||
      swiping != oldWidget.swiping;
}

class _DDrawerGestureScope extends InheritedWidget {
  const _DDrawerGestureScope({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required super.child,
  });

  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final GestureDragCancelCallback onCancel;

  static _DDrawerGestureScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DDrawerGestureScope>()!;

  @override
  bool updateShouldNotify(_DDrawerGestureScope oldWidget) => false;
}

DDrawerSwipeDirection _resolveDirection(
  DDrawerSwipeDirection direction,
  TextDirection textDirection,
) => switch (direction) {
  DDrawerSwipeDirection.start =>
    textDirection == TextDirection.ltr
        ? DDrawerSwipeDirection.left
        : DDrawerSwipeDirection.right,
  DDrawerSwipeDirection.end =>
    textDirection == TextDirection.ltr
        ? DDrawerSwipeDirection.right
        : DDrawerSwipeDirection.left,
  _ => direction,
};

Alignment _drawerOrigin(DDrawerSwipeDirection direction) => switch (direction) {
  DDrawerSwipeDirection.down => Alignment.bottomCenter,
  DDrawerSwipeDirection.up => Alignment.topCenter,
  DDrawerSwipeDirection.right => Alignment.centerRight,
  DDrawerSwipeDirection.left => Alignment.centerLeft,
  _ => Alignment.center,
};

/// Explicit composition boundary matching the reference portal part.
class DDrawerPortal extends StatelessWidget {
  const DDrawerPortal({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class DDrawerOverlay extends StatelessWidget {
  const DDrawerOverlay({
    super.key,
    required this.dismissible,
    required this.semanticsLabel,
    required this.onDismiss,
  });

  final bool dismissible;
  final String semanticsLabel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
    child: ModalBarrier(
      color: Colors.black.withValues(alpha: .1),
      dismissible: dismissible,
      semanticsLabel: semanticsLabel,
      onDismiss: onDismiss,
    ),
  );
}

/// The base-nova drawer popup surface.
class DDrawerContent extends StatelessWidget {
  const DDrawerContent({
    super.key,
    required this.children,
    this.width,
    this.height,
    this.maxWidth,
    this.maxHeight,
    this.inset = 0,
    this.bleedBackground,
    this.semanticLabel,
  }) : assert(width == null || width > 0),
       assert(height == null || height > 0),
       assert(maxWidth == null || maxWidth > 0),
       assert(maxHeight == null || maxHeight > 0),
       assert(inset >= 0);

  final List<Widget> children;
  final double? width;
  final double? height;
  final double? maxWidth;
  final double? maxHeight;
  final double inset;
  final Color? bleedBackground;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scope = _DDrawerContentScope.of(context);
    final tokens = DTokens.of(context);
    final media = MediaQuery.of(context);
    final direction = scope.direction;
    final vertical =
        direction == DDrawerSwipeDirection.up ||
        direction == DDrawerSwipeDirection.down;
    final wide = media.size.width >= 640;
    final defaultWidth = wide ? 384.0 : media.size.width * .75;
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight = math
        .max(0.0, media.size.height - keyboardInset - inset * 2)
        .toDouble();
    final defaultMaxHeight = math.max(0.0, availableHeight - 96).toDouble();
    final accessibleHeight = height == null
        ? null
        : math
              .min(
                availableHeight,
                height! * math.max(1, media.textScaler.scale(1)),
              )
              .toDouble();
    final resolvedHeight = vertical && scope.hasSnapPoints
        ? availableHeight
        : accessibleHeight;
    final constraints = vertical
        ? BoxConstraints(
            minWidth: math.max(0.0, media.size.width - inset * 2).toDouble(),
            maxWidth: math.max(0.0, media.size.width - inset * 2).toDouble(),
            maxHeight:
                maxHeight ??
                (scope.hasSnapPoints || height != null
                    ? availableHeight
                    : defaultMaxHeight),
          )
        : BoxConstraints(
            minWidth: width ?? defaultWidth,
            maxWidth: maxWidth ?? width ?? defaultWidth,
            minHeight: availableHeight,
            maxHeight: availableHeight,
          );
    final radius = Radius.circular(tokens.radius * 1.4);
    final borderRadius = switch (direction) {
      DDrawerSwipeDirection.down => BorderRadius.vertical(top: radius),
      DDrawerSwipeDirection.up => BorderRadius.vertical(bottom: radius),
      DDrawerSwipeDirection.right => BorderRadius.horizontal(left: radius),
      DDrawerSwipeDirection.left => BorderRadius.horizontal(right: radius),
      _ => BorderRadius.zero,
    };
    final border = switch (direction) {
      DDrawerSwipeDirection.down => Border(
        top: BorderSide(color: tokens.border),
      ),
      DDrawerSwipeDirection.up => Border(
        bottom: BorderSide(color: tokens.border),
      ),
      DDrawerSwipeDirection.right => Border(
        left: BorderSide(color: tokens.border),
      ),
      DDrawerSwipeDirection.left => Border(
        right: BorderSide(color: tokens.border),
      ),
      _ => null,
    };
    final bleed = bleedBackground ?? tokens.surface;
    final contentColumn = Flex(
      direction: vertical ? Axis.vertical : Axis.horizontal,
      mainAxisSize: vertical && !scope.hasSnapPoints && height == null
          ? MainAxisSize.min
          : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scope.showSwipeHandle) const DDrawerSwipeHandle(),
        Flexible(
          fit: scope.hasSnapPoints || !vertical || height != null
              ? FlexFit.tight
              : FlexFit.loose,
          child: Column(
            mainAxisSize: vertical && !scope.hasSnapPoints && height == null
                ? MainAxisSize.min
                : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
    Widget body = Material(
      animationDuration: Duration.zero,
      color: tokens.surface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: DiscourseTypography.sm,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: tokens.foreground,
      ),
      child: AnimatedOpacity(
        opacity: scope.nestedDepth > 0 && !scope.swiping ? 0 : 1,
        duration: DMotion.duration(context, const Duration(milliseconds: 300)),
        curve: const Cubic(.45, 1.005, 0, 1),
        child: contentColumn,
      ),
    );
    body = Stack(
      clipBehavior: Clip.none,
      children: [
        if (vertical)
          Positioned(
            left: 0,
            right: 0,
            top: direction == DDrawerSwipeDirection.up ? -48 : null,
            bottom: direction == DDrawerSwipeDirection.down ? -48 : null,
            height: 48,
            child: ColoredBox(color: bleed),
          )
        else if (!vertical)
          Positioned(
            top: 0,
            bottom: 0,
            left: direction == DDrawerSwipeDirection.right ? -48 : null,
            right: direction == DDrawerSwipeDirection.left ? -48 : null,
            width: 48,
            child: ColoredBox(color: bleed),
          ),
        body,
      ],
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: ConstrainedBox(
          constraints: constraints,
          child: SizedBox(
            width: vertical ? double.infinity : width ?? defaultWidth,
            height: resolvedHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: border,
                borderRadius: borderRadius,
              ),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class DDrawerSwipeHandle extends StatelessWidget {
  const DDrawerSwipeHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final content = _DDrawerContentScope.of(context);
    final gestures = _DDrawerGestureScope.of(context);
    final vertical =
        content.direction == DDrawerSwipeDirection.up ||
        content.direction == DDrawerSwipeDirection.down;
    final handle = DecoratedBox(
      decoration: BoxDecoration(
        color: DTokens.of(context).muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(width: vertical ? 96 : 4, height: vertical ? 4 : 96),
    );
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: vertical ? gestures.onStart : null,
          onVerticalDragUpdate: vertical ? gestures.onUpdate : null,
          onVerticalDragEnd: vertical ? gestures.onEnd : null,
          onVerticalDragCancel: vertical ? gestures.onCancel : null,
          onHorizontalDragStart: vertical ? null : gestures.onStart,
          onHorizontalDragUpdate: vertical ? null : gestures.onUpdate,
          onHorizontalDragEnd: vertical ? null : gestures.onEnd,
          onHorizontalDragCancel: vertical ? null : gestures.onCancel,
          child: SizedBox(
            width: vertical ? double.infinity : 12,
            height: vertical ? 12 : double.infinity,
            child: Center(child: handle),
          ),
        ),
      ),
    );
  }
}

class DDrawerHeader extends StatelessWidget {
  const DDrawerHeader({super.key, required this.children, this.textAlign});

  final List<Widget> children;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final direction = _DDrawerContentScope.of(context).direction;
    final vertical =
        direction == DDrawerSwipeDirection.up ||
        direction == DDrawerSwipeDirection.down;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
      child: DefaultTextStyle.merge(
        textAlign: textAlign ?? (vertical ? TextAlign.center : TextAlign.start),
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
      ),
    );
  }
}

class DDrawerFooter extends StatelessWidget {
  const DDrawerFooter({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          children[index],
        ],
      ],
    ),
  );
}

class DDrawerTitle extends StatelessWidget {
  const DDrawerTitle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    namesRoute: true,
    child: DefaultTextStyle(
      style: Theme.of(context).textTheme.titleMedium!.copyWith(
        fontSize: DiscourseTypography.base,
        height: 1.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: DTokens.of(context).foreground,
      ),
      child: child,
    ),
  );
}

class DDrawerDescription extends StatelessWidget {
  const DDrawerDescription({super.key, required this.child});
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

typedef DDrawerCloseBuilder =
    Widget Function(BuildContext context, VoidCallback close);

class DDrawerClose<T> extends StatelessWidget {
  const DDrawerClose({super.key, required this.builder, this.result});
  final DDrawerCloseBuilder builder;
  final T? result;

  @override
  Widget build(BuildContext context) {
    final scope = _DDrawerContentScope.of(context);
    return builder(context, () => scope.close(result));
  }
}

/// A flex-sized scroll region that hands dismiss-facing overscroll to Drawer.
class DDrawerScrollArea extends StatelessWidget {
  const DDrawerScrollArea({
    super.key,
    required this.child,
    this.controller,
    this.padding,
  });

  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Flexible(
    child: SingleChildScrollView(
      controller: controller,
      padding: padding,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child: child,
    ),
  );
}

/// Opens a route-owned Drawer and returns its typed result.
Future<T?> showDDrawer<T>({
  required BuildContext context,
  required DDrawerContentBuilder<T> builder,
  DDrawerSwipeDirection swipeDirection = DDrawerSwipeDirection.down,
  DDrawerModalMode modalMode = DDrawerModalMode.modal,
  List<DDrawerSnapPoint> snapPoints = const [],
  DDrawerSnapPoint? initialSnapPoint,
  bool showSwipeHandle = false,
  bool disablePointerDismissal = false,
  bool dismissOnEscape = true,
  bool useRootNavigator = false,
  String barrierLabel = 'Dismiss drawer',
  RouteSettings? routeSettings,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
  bool requestInitialFocus = true,
  bool restoreFocus = true,
}) async {
  final controller = DDrawerController<T>(
    initiallyOpen: true,
    initialSnapPoint: initialSnapPoint ?? snapPoints.firstOrNull,
  );
  final environment = ValueNotifier<DOverlayEnvironment?>(
    DOverlayEnvironment.capture(context),
  );
  final configuration = ValueNotifier<_DDrawerConfiguration<T>?>(
    _DDrawerConfiguration<T>(
      content: Builder(
        builder: (drawerContext) => builder(drawerContext, controller),
      ),
      barrierLabel: barrierLabel,
      disablePointerDismissal: disablePointerDismissal,
      dismissOnEscape: dismissOnEscape,
      initialFocusNode: initialFocusNode,
      requestInitialFocus: requestInitialFocus,
      modalMode: modalMode,
      snapPoints: List.unmodifiable(snapPoints),
      snapPoint: controller.snapPoint,
      snapToSequentialPoints: false,
      swipeDirection: swipeDirection,
      showSwipeHandle: showSwipeHandle,
    ),
  );
  final previousFocus = FocusManager.instance.primaryFocus;
  var watchingEnvironment = true;
  void watchEnvironment() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!watchingEnvironment || !context.mounted) return;
      final next = DOverlayEnvironment.capture(context);
      if (environment.value != next) environment.value = next;
      watchEnvironment();
    });
  }

  watchEnvironment();
  bool updateSnap(DDrawerSnapPoint? point, DDrawerSnapChangeReason reason) {
    controller._setSnapPoint(point);
    configuration.value = _DDrawerConfiguration<T>(
      content: configuration.value!.content,
      barrierLabel: barrierLabel,
      disablePointerDismissal: disablePointerDismissal,
      dismissOnEscape: dismissOnEscape,
      initialFocusNode: initialFocusNode,
      requestInitialFocus: requestInitialFocus,
      modalMode: modalMode,
      snapPoints: List.unmodifiable(snapPoints),
      snapPoint: point,
      snapToSequentialPoints: false,
      swipeDirection: swipeDirection,
      showSwipeHandle: showSwipeHandle,
    );
    return true;
  }

  late _DDrawerRoute<T> route;
  route = _DDrawerRoute<T>(
    settings: routeSettings,
    environment: environment,
    configuration: configuration,
    modalMode: modalMode,
    onDismissRequested: (_) {
      route.authorizePop();
      return true;
    },
    onCloseRequested: (result) {
      route.authorizePop(result);
      return true;
    },
    onSnapRequested: updateSnap,
    onOpenComplete: () {},
    parentStack: null,
    requestInitialFocus: requestInitialFocus,
    transitionDuration: DMotion.duration(
      context,
      const Duration(milliseconds: 450),
    ),
    reverseTransitionDuration: DMotion.duration(
      context,
      const Duration(milliseconds: 450),
    ),
  );
  controller._attach(
    route,
    (_) {},
    (result, _) => route.authorizePop(result),
    updateSnap,
    swipeDirection,
  );
  try {
    return await Navigator.of(
      context,
      rootNavigator: useRootNavigator,
    ).push<T>(route);
  } finally {
    watchingEnvironment = false;
    controller._detach(route);
    controller.dispose();
    environment.dispose();
    configuration.dispose();
    if (restoreFocus && route.wasCurrentWhenAuthorized) {
      final target = finalFocusNode ?? previousFocus;
      if (target?.canRequestFocus ?? false) target!.requestFocus();
    }
  }
}

typedef DDrawerContentBuilder<T> =
    Widget Function(BuildContext context, DDrawerController<T> controller);

class _DDrawerProviderHandle extends ChangeNotifier {
  int _openCount = 0;
  bool get active => _openCount > 0;

  void push() {
    _openCount++;
    notifyListeners();
  }

  void pop() {
    _openCount = math.max(0, _openCount - 1);
    notifyListeners();
  }
}

class DDrawerProvider extends StatefulWidget {
  const DDrawerProvider({super.key, required this.child});
  final Widget child;

  @override
  State<DDrawerProvider> createState() => _DDrawerProviderState();
}

class _DDrawerProviderState extends State<DDrawerProvider> {
  final _handle = _DDrawerProviderHandle();

  @override
  Widget build(BuildContext context) =>
      _DDrawerProviderScope(notifier: _handle, child: widget.child);

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }
}

class _DDrawerProviderScope extends InheritedNotifier<_DDrawerProviderHandle> {
  const _DDrawerProviderScope({required super.notifier, required super.child});

  _DDrawerProviderHandle get handle => notifier!;

  static _DDrawerProviderScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DDrawerProviderScope>();
}

typedef DDrawerActiveBuilder =
    Widget Function(BuildContext context, bool active, Widget? child);

/// Main-content wrapper that rebuilds while a provided drawer is active.
class DDrawerIndent extends StatelessWidget {
  const DDrawerIndent({super.key, required this.builder, this.child});

  final DDrawerActiveBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scope = _DDrawerProviderScope.maybeOf(context);
    assert(scope != null, 'DDrawerIndent must be below DDrawerProvider.');
    return builder(context, scope!.handle.active, child);
  }
}

/// Background-layer counterpart to [DDrawerIndent].
class DDrawerIndentBackground extends StatelessWidget {
  const DDrawerIndentBackground({super.key, required this.builder, this.child});

  final DDrawerActiveBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scope = _DDrawerProviderScope.maybeOf(context);
    assert(
      scope != null,
      'DDrawerIndentBackground must be below DDrawerProvider.',
    );
    return builder(context, scope!.handle.active, child);
  }
}

/// Invisible edge region that opens a mounted drawer after an inward swipe.
class DDrawerSwipeArea<T> extends StatefulWidget {
  const DDrawerSwipeArea({
    super.key,
    required this.controller,
    this.swipeDirection,
    this.disabled = false,
    this.extent = 24,
  }) : assert(extent > 0);

  final DDrawerController<T> controller;
  final DDrawerSwipeDirection? swipeDirection;
  final bool disabled;
  final double extent;

  @override
  State<DDrawerSwipeArea<T>> createState() => _DDrawerSwipeAreaState<T>();
}

class _DDrawerSwipeAreaState<T> extends State<DDrawerSwipeArea<T>> {
  double _travel = 0;

  DDrawerSwipeDirection _openingDirection(BuildContext context) {
    final requested =
        widget.swipeDirection ??
        _oppositeDirection(
          widget.controller._dismissDirection ?? DDrawerSwipeDirection.end,
        );
    return _resolveDirection(requested, Directionality.of(context));
  }

  void _update(DragUpdateDetails details) {
    final direction = _openingDirection(context);
    final delta = details.primaryDelta ?? 0;
    _travel += switch (direction) {
      DDrawerSwipeDirection.right || DDrawerSwipeDirection.down => delta,
      DDrawerSwipeDirection.left || DDrawerSwipeDirection.up => -delta,
      _ => 0,
    };
    if (_travel >= widget.extent) {
      _travel = 0;
      widget.controller.open();
    }
  }

  void _reset([Object? _]) => _travel = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.disabled) return const SizedBox.shrink();
    final direction = _openingDirection(context);
    final vertical =
        direction == DDrawerSwipeDirection.up ||
        direction == DDrawerSwipeDirection.down;
    return Semantics(
      hidden: true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: vertical ? null : _update,
        onHorizontalDragEnd: vertical ? null : _reset,
        onHorizontalDragCancel: vertical ? null : _reset,
        onVerticalDragUpdate: vertical ? _update : null,
        onVerticalDragEnd: vertical ? _reset : null,
        onVerticalDragCancel: vertical ? _reset : null,
        child: SizedBox(
          width: vertical ? double.infinity : widget.extent,
          height: vertical ? widget.extent : double.infinity,
        ),
      ),
    );
  }
}

/// Explicit keyboard-inset composition boundary.
///
/// Flutter's route receives live [MediaQuery.viewInsets]; descendants can read
/// the same inset without a second keyboard observer.
class DDrawerVirtualKeyboardProvider extends StatelessWidget {
  const DDrawerVirtualKeyboardProvider({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

DDrawerSwipeDirection _oppositeDirection(DDrawerSwipeDirection direction) =>
    switch (direction) {
      DDrawerSwipeDirection.up => DDrawerSwipeDirection.down,
      DDrawerSwipeDirection.down => DDrawerSwipeDirection.up,
      DDrawerSwipeDirection.left => DDrawerSwipeDirection.right,
      DDrawerSwipeDirection.right => DDrawerSwipeDirection.left,
      DDrawerSwipeDirection.start => DDrawerSwipeDirection.end,
      DDrawerSwipeDirection.end => DDrawerSwipeDirection.start,
    };
