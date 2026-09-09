import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_popover.dart';

enum DHoverCardChangeReason {
  triggerHover,
  triggerFocus,
  triggerPress,
  outsidePress,
  escape,
  imperative,
  lifecycle,
}

typedef DHoverCardOpenChange =
    void Function(bool open, DHoverCardChangeReason reason);

typedef DHoverCardTriggerBuilder =
    Widget Function(BuildContext context, DHoverCardTriggerState state);

typedef DHoverCardGroupBuilder =
    Widget Function(BuildContext context, List<Widget> triggers);

typedef DHoverCardPayloadBuilder<T> =
    DHoverCardContent Function(BuildContext context, T payload);

typedef DHoverCardTriggerChange<T> = void Function(Object id, T payload);

@immutable
class DHoverCardTriggerState {
  const DHoverCardTriggerState({required this.open, required this.focusNode});

  final bool open;
  final FocusNode focusNode;
}

/// Imperatively controls one mounted [DHoverCard].
///
/// Calls while detached are intentionally ignored. The caller disposes a
/// borrowed controller; [DHoverCard] only disposes its internal controller.
class DHoverCardController extends ChangeNotifier {
  _DHoverCardState? _owner;
  bool _disposed = false;

  bool get isOpen => _owner?._open ?? false;

  void open() => _owner?._request(
    true,
    DHoverCardChangeReason.imperative,
    immediate: true,
  );

  void close() => _owner?._request(
    false,
    DHoverCardChangeReason.imperative,
    immediate: true,
  );

  void _attach(_DHoverCardState owner) {
    if (_disposed) return;
    final previous = _owner;
    _owner = owner;
    if (previous != null && previous != owner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous.mounted) previous._setOpen(false, immediate: true);
      });
    }
  }

  void _detach(_DHoverCardState owner) {
    if (identical(_owner, owner)) _owner = null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    super.dispose();
  }
}

/// A shadcn/Base UI-style supplementary destination preview.
///
/// Pointer hover waits for [DHoverCardTrigger.delay]. Traditional keyboard
/// focus opens immediately. The popup never takes focus and is excluded from
/// assistive semantics, leaving the trigger's real link or button action as
/// the accessible interface. Touch activation is therefore owned entirely by
/// the trigger.
class DHoverCard extends StatefulWidget {
  const DHoverCard({
    super.key,
    required this.trigger,
    required this.content,
    this.open,
    this.defaultOpen = false,
    this.controller,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.enabled = true,
  });

  final DHoverCardTrigger trigger;
  final DHoverCardContent content;
  final bool? open;
  final bool defaultOpen;
  final DHoverCardController? controller;
  final DHoverCardOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool enabled;

  @override
  State<DHoverCard> createState() => _DHoverCardState();
}

/// One trigger and its strongly typed payload inside a [DHoverCardGroup].
@immutable
class DHoverCardGroupItem<T> {
  const DHoverCardGroupItem({
    required this.id,
    required this.payload,
    required this.builder,
    this.delay = const Duration(milliseconds: 600),
    this.closeDelay = const Duration(milliseconds: 300),
    this.focusNode,
    this.focusable = true,
  });

  final Object id;
  final T payload;
  final DHoverCardTriggerBuilder builder;
  final Duration delay;
  final Duration closeDelay;
  final FocusNode? focusNode;
  final bool focusable;
}

/// A single preview-card root shared by multiple payload-bearing triggers.
///
/// [builder] lays out the trigger widgets without imposing a Row, Wrap, or
/// inline layout. When an already-open group moves to another trigger, the new
/// payload and anchor are selected immediately instead of waiting for its
/// opening delay. This is the Flutter composition counterpart to Base UI's
/// same-root multiple-trigger and payload API. Detached triggers remain out of
/// scope: Flutter callers can keep the root near an arbitrary trigger layout,
/// while [DHoverCardController] provides detached imperative open/close for a
/// single trigger.
class DHoverCardGroup<T> extends StatefulWidget {
  const DHoverCardGroup({
    super.key,
    required this.items,
    required this.builder,
    required this.contentBuilder,
    this.open,
    this.defaultOpen = false,
    this.triggerId,
    this.defaultTriggerId,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.onTriggerChange,
    this.enabled = true,
  }) : assert(items.length > 1);

  final List<DHoverCardGroupItem<T>> items;
  final DHoverCardGroupBuilder builder;
  final DHoverCardPayloadBuilder<T> contentBuilder;
  final bool? open;
  final bool defaultOpen;
  final Object? triggerId;
  final Object? defaultTriggerId;
  final DHoverCardOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final DHoverCardTriggerChange<T>? onTriggerChange;
  final bool enabled;

  @override
  State<DHoverCardGroup<T>> createState() => _DHoverCardGroupState<T>();
}

class _DHoverCardGroupState<T> extends State<DHoverCardGroup<T>> {
  late bool _open = widget.defaultOpen;
  late Object _triggerId = widget.defaultTriggerId ?? widget.items.first.id;

  bool get _effectiveOpen => widget.open ?? _open;
  Object get _effectiveTriggerId => widget.triggerId ?? _triggerId;

  @override
  void initState() {
    super.initState();
    _debugCheckItems();
  }

  @override
  void didUpdateWidget(DHoverCardGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _debugCheckItems();
    if (!widget.items.any((item) => item.id == _triggerId)) {
      _triggerId = widget.defaultTriggerId ?? widget.items.first.id;
    }
  }

  void _debugCheckItems() {
    assert(() {
      final ids = widget.items.map((item) => item.id).toSet();
      if (ids.length != widget.items.length) {
        throw FlutterError('DHoverCardGroup item ids must be unique.');
      }
      final requested = widget.triggerId ?? widget.defaultTriggerId;
      if (requested != null && !ids.contains(requested)) {
        throw FlutterError(
          'DHoverCardGroup triggerId/defaultTriggerId must identify an item.',
        );
      }
      return true;
    }());
  }

  void _handleRequest(
    DHoverCardGroupItem<T> item,
    bool value,
    DHoverCardChangeReason reason,
  ) {
    if (!widget.enabled) return;
    if (value) {
      final triggerChanged = _effectiveTriggerId != item.id;
      final openChanged = !_effectiveOpen;
      if (widget.triggerId == null) _triggerId = item.id;
      if (widget.open == null) _open = true;
      if (triggerChanged) widget.onTriggerChange?.call(item.id, item.payload);
      if (openChanged) widget.onOpenChange?.call(true, reason);
      if (triggerChanged || openChanged) setState(() {});
      return;
    }
    if (_effectiveTriggerId != item.id || !_effectiveOpen) return;
    if (widget.open == null) _open = false;
    widget.onOpenChange?.call(false, reason);
    setState(() {});
  }

  void _handleCompletion(Object id, bool value) {
    if (value) {
      if (_effectiveOpen && _effectiveTriggerId == id) {
        widget.onOpenChangeComplete?.call(true);
      }
    } else if (!_effectiveOpen) {
      widget.onOpenChangeComplete?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeId = _effectiveTriggerId;
    final groupOpen = _effectiveOpen && widget.enabled;
    final triggers = <Widget>[
      for (final item in widget.items)
        DHoverCard(
          key: ValueKey(item.id),
          open: groupOpen && activeId == item.id,
          enabled: widget.enabled,
          onOpenChange: (value, reason) => _handleRequest(item, value, reason),
          onOpenChangeComplete: (value) => _handleCompletion(item.id, value),
          trigger: DHoverCardTrigger(
            delay: groupOpen && activeId != item.id
                ? Duration.zero
                : item.delay,
            closeDelay: item.closeDelay,
            focusNode: item.focusNode,
            focusable: item.focusable,
            builder: item.builder,
          ),
          content: widget.contentBuilder(context, item.payload),
        ),
    ];
    return widget.builder(context, triggers);
  }
}

class _DHoverCardLayers {
  static final Set<_DHoverCardState> mounted = <_DHoverCardState>{};
  static final List<_DHoverCardState> open = <_DHoverCardState>[];

  static void register(_DHoverCardState state) => mounted.add(state);

  static void unregister(_DHoverCardState state) {
    mounted.remove(state);
    open.remove(state);
  }

  static void beginHover(_DHoverCardState state) {
    for (final other in mounted.where((candidate) => candidate != state)) {
      other._cancelPendingOpen();
    }
  }

  static void activate(_DHoverCardState state) {
    final previous = open.lastOrNull;
    if (previous != null && previous != state) {
      previous._cancelTimers();
      previous._request(
        false,
        DHoverCardChangeReason.triggerHover,
        immediate: true,
      );
    }
    open
      ..remove(state)
      ..add(state);
  }

  static void deactivate(_DHoverCardState state) => open.remove(state);

  static bool isTopmost(_DHoverCardState state) =>
      open.isNotEmpty && identical(open.last, state);
}

class _DHoverCardState extends State<DHoverCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _surfaceKey = GlobalKey();
  late final DHoverCardController _ownedController = DHoverCardController();
  late final FocusNode _ownedFocus = FocusNode(
    debugLabel: 'DHoverCard trigger',
  );
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 100),
  )..addStatusListener(_animationStatus);
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  Timer? _openTimer;
  Timer? _closeTimer;
  Offset? _pointer;
  bool _open = false;
  bool _initialized = false;
  bool _syncScheduled = false;
  bool _triggerHovered = false;
  bool _contentHovered = false;
  bool _keyboardFocused = false;
  bool _suspended = false;

  DHoverCardController get _controller => widget.controller ?? _ownedController;
  FocusNode get _focus => widget.trigger.focusNode ?? _ownedFocus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_globalPointer);
    FocusManager.instance.addEarlyKeyEventHandler(_globalKey);
    _focus.addListener(_focusListener);
    _controller._attach(this);
    _DHoverCardLayers.register(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(DHoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)._detach(this);
      _controller._attach(this);
    }
    if (oldWidget.trigger.focusNode != widget.trigger.focusNode) {
      (oldWidget.trigger.focusNode ?? _ownedFocus).removeListener(
        _focusListener,
      );
      _focus.addListener(_focusListener);
      if (_focus.hasFocus) {
        _focusChanged(true);
      } else {
        _keyboardFocused = false;
        _cancelTimers();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_focus.hasFocus) {
            _request(
              false,
              DHoverCardChangeReason.triggerFocus,
              immediate: true,
            );
          }
        });
      }
    }
    if (!widget.enabled) {
      _cancelTimers();
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      if (_suspended || !widget.enabled) {
        _setOpen(false, immediate: true);
      } else if (widget.open != null) {
        _setOpen(widget.open!);
      } else if (!_initialized) {
        _setOpen(widget.defaultOpen);
      }
      _initialized = true;
      if (MediaQuery.disableAnimationsOf(context) && _animation.isAnimating) {
        _animation.value = _open ? 1 : 0;
        if (!_open) _portal.hide();
      }
    });
  }

  void _cancelTimers() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _openTimer = null;
    _closeTimer = null;
  }

  void _cancelPendingOpen() {
    _openTimer?.cancel();
    _openTimer = null;
  }

  void _request(
    bool value,
    DHoverCardChangeReason reason, {
    bool immediate = false,
  }) {
    if (!mounted || !widget.enabled || value == _open) return;
    if (widget.open == null) _setOpen(value, immediate: immediate);
    widget.onOpenChange?.call(value, reason);
  }

  void _setOpen(bool value, {bool immediate = false}) {
    if (!mounted || value == _open) return;
    _open = value;
    final noMotion = immediate || MediaQuery.disableAnimationsOf(context);
    if (value) {
      _DHoverCardLayers.activate(this);
      _portal.show();
      if (noMotion) {
        _animation.value = 1;
      } else {
        _animation.forward();
      }
    } else {
      _DHoverCardLayers.deactivate(this);
      if (noMotion) {
        _animation.value = 0;
        _portal.hide();
      } else {
        _animation.reverse();
      }
    }
    setState(() {});
    _controller._changed();
  }

  void _animationStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.dismissed) {
      _portal.hide();
      widget.onOpenChangeComplete?.call(false);
    } else if (status == AnimationStatus.completed) {
      widget.onOpenChangeComplete?.call(true);
    }
  }

  void _scheduleOpen() {
    if (!widget.enabled || _suspended) return;
    _DHoverCardLayers.beginHover(this);
    _closeTimer?.cancel();
    _closeTimer = null;
    if (_open || _openTimer != null) return;
    final delay = widget.trigger.delay;
    if (delay == Duration.zero) {
      _request(true, DHoverCardChangeReason.triggerHover);
    } else {
      _openTimer = Timer(delay, () {
        _openTimer = null;
        if (_triggerHovered && mounted) {
          _request(true, DHoverCardChangeReason.triggerHover);
        }
      });
    }
  }

  void _scheduleClose(DHoverCardChangeReason reason) {
    _openTimer?.cancel();
    _openTimer = null;
    if (!_open || _keyboardFocused || _triggerHovered || _contentHovered) {
      return;
    }
    if (_inBridge(_pointer)) {
      _closeTimer?.cancel();
      _closeTimer = null;
      return;
    }
    _closeTimer?.cancel();
    final delay = widget.trigger.closeDelay;
    if (delay == Duration.zero) {
      _request(false, reason);
    } else {
      _closeTimer = Timer(delay, () {
        _closeTimer = null;
        if (!_keyboardFocused &&
            !_triggerHovered &&
            !_contentHovered &&
            !_inBridge(_pointer)) {
          _request(false, reason);
        }
      });
    }
  }

  Rect? _globalRect(BuildContext? target) {
    final box = target?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  bool _inBridge(Offset? point) {
    if (!_open || point == null) return false;
    final anchor = _globalRect(context);
    final popup = _globalRect(_surfaceKey.currentContext);
    if (anchor == null || popup == null) return false;
    if (anchor.contains(point) || popup.contains(point)) return true;
    final a = anchor.inflate(2);
    final b = popup.inflate(2);
    final List<Offset> corners;
    if (b.bottom <= a.top) {
      corners = [a.topLeft, a.topRight, b.bottomRight, b.bottomLeft];
    } else if (b.top >= a.bottom) {
      corners = [a.bottomLeft, a.bottomRight, b.topRight, b.topLeft];
    } else if (b.right <= a.left) {
      corners = [a.topLeft, a.bottomLeft, b.bottomRight, b.topRight];
    } else if (b.left >= a.right) {
      corners = [a.topRight, a.bottomRight, b.bottomLeft, b.topLeft];
    } else {
      return false;
    }
    return (Path()..addPolygon(corners, true)).contains(point);
  }

  void _triggerEnter(PointerEnterEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _triggerHovered = true;
    _pointer = event.position;
    _scheduleOpen();
  }

  void _triggerExit(PointerExitEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _triggerHovered = false;
    _pointer = event.position;
    _scheduleClose(DHoverCardChangeReason.triggerHover);
  }

  void _focusListener() => _focusChanged(_focus.hasFocus);

  void _focusChanged(bool focused) {
    _keyboardFocused =
        focused &&
        widget.trigger.focusable &&
        widget.enabled &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (_keyboardFocused) {
      _cancelTimers();
      _request(true, DHoverCardChangeReason.triggerFocus, immediate: true);
    } else if (!focused) {
      _scheduleClose(DHoverCardChangeReason.triggerFocus);
    }
  }

  void _globalPointer(PointerEvent event) {
    if (!mounted) return;
    if (event is PointerHoverEvent || event is PointerMoveEvent) {
      _pointer = event.position;
      if (_open && !_triggerHovered && !_contentHovered) {
        _scheduleClose(DHoverCardChangeReason.triggerHover);
      }
      return;
    }
    if (event is! PointerDownEvent) {
      return;
    }
    final point = event.position;
    if (_globalRect(context)?.contains(point) ?? false) {
      _cancelTimers();
      if (_open && _DHoverCardLayers.isTopmost(this)) {
        _request(false, DHoverCardChangeReason.triggerPress, immediate: true);
      }
      return;
    }
    if (!_open || !_DHoverCardLayers.isTopmost(this)) return;
    if (_globalRect(_surfaceKey.currentContext)?.contains(point) ?? false) {
      return;
    }
    _cancelTimers();
    _request(false, DHoverCardChangeReason.outsidePress, immediate: true);
  }

  KeyEventResult _globalKey(KeyEvent event) {
    if (_open &&
        event is KeyDownEvent &&
        _focus.hasFocus &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _cancelTimers();
      _request(false, DHoverCardChangeReason.triggerPress, immediate: true);
      return KeyEventResult.ignored;
    }
    if (_open &&
        _DHoverCardLayers.isTopmost(this) &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelTimers();
      _request(false, DHoverCardChangeReason.escape, immediate: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _dismissForLifecycle() {
    _cancelTimers();
    if (!_open) return;
    _setOpen(false, immediate: true);
    widget.onOpenChange?.call(false, DHoverCardChangeReason.lifecycle);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _suspended = state != AppLifecycleState.resumed;
    if (_suspended) {
      _dismissForLifecycle();
    } else {
      _scheduleSync();
    }
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _suspended = event.state == ViewFocusState.unfocused;
    if (_suspended) {
      _dismissForLifecycle();
    } else {
      _scheduleSync();
    }
  }

  Widget _overlay(BuildContext overlayContext, OverlayChildLayoutInfo info) {
    if (!widget.enabled ||
        _suspended ||
        info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final target = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final media = MediaQuery.of(context);
    final viewport = Offset.zero & info.overlaySize;
    final safeBoundary = Rect.fromLTRB(
      media.padding.left,
      media.padding.top,
      info.overlaySize.width -
          math.max(media.padding.right, media.viewInsets.right),
      info.overlaySize.height -
          math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    final boundary =
        widget.content.collisionBoundary?.intersect(viewport) ?? safeBoundary;
    if (target.intersect(boundary).isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _open) _dismissForLifecycle();
      });
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: ExcludeSemantics(
        child: ExcludeFocus(
          excluding: true,
          child: _HoverCardPositioner(
            target: target,
            boundary: boundary,
            content: widget.content,
            direction: Directionality.of(context),
            animation: _curve,
            child: MouseRegion(
              onEnter: (_) {
                _contentHovered = true;
                _closeTimer?.cancel();
                _closeTimer = null;
              },
              onExit: (event) {
                _contentHovered = false;
                _pointer = event.position;
                _scheduleClose(DHoverCardChangeReason.triggerHover);
              },
              child: KeyedSubtree(
                key: _surfaceKey,
                child: SelectionArea(child: widget.content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget trigger = _HoverCardTriggerScope(
      state: this,
      open: _open,
      child: widget.trigger,
    );
    trigger = MouseRegion(
      onEnter: _triggerEnter,
      onExit: _triggerExit,
      child: trigger,
    );
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: trigger,
    );
  }

  @override
  void dispose() {
    _cancelTimers();
    _DHoverCardLayers.unregister(this);
    _controller._detach(this);
    _focus.removeListener(_focusListener);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_globalPointer);
    FocusManager.instance.removeEarlyKeyEventHandler(_globalKey);
    WidgetsBinding.instance.removeObserver(this);
    _curve.dispose();
    _animation.dispose();
    _ownedFocus.dispose();
    _ownedController.dispose();
    super.dispose();
  }
}

/// Composes the existing trigger widget with preview state and delays.
class DHoverCardTrigger extends StatelessWidget {
  const DHoverCardTrigger({
    super.key,
    required this.builder,
    this.delay = const Duration(milliseconds: 600),
    this.closeDelay = const Duration(milliseconds: 300),
    this.focusNode,
    this.focusable = true,
  });

  final DHoverCardTriggerBuilder builder;
  final Duration delay;
  final Duration closeDelay;
  final FocusNode? focusNode;
  final bool focusable;

  @override
  Widget build(BuildContext context) {
    final root = _HoverCardTriggerScope.of(context);
    assert(
      identical(root.widget.trigger, this),
      'DHoverCardTrigger must be supplied as DHoverCard.trigger.',
    );
    return builder(
      context,
      DHoverCardTriggerState(open: root._open, focusNode: root._focus),
    );
  }
}

class _HoverCardTriggerScope extends InheritedWidget {
  const _HoverCardTriggerScope({
    required this.state,
    required this.open,
    required super.child,
  });

  final _DHoverCardState state;
  final bool open;

  static _DHoverCardState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_HoverCardTriggerScope>();
    assert(scope != null, 'DHoverCardTrigger requires DHoverCard.');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(_HoverCardTriggerScope oldWidget) =>
      open != oldWidget.open;
}

/// The styled preview surface and its positioning policy.
class DHoverCardContent extends StatelessWidget {
  const DHoverCardContent({
    super.key,
    required this.child,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.center,
    this.sideOffset = 4,
    this.alignOffset = 4,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.width = 256,
    this.constraints = const BoxConstraints(),
    this.padding = const EdgeInsets.all(10),
  }) : assert(sideOffset >= 0),
       assert(collisionPadding >= 0),
       assert(width > 0);

  final Widget child;
  final DPopoverSide side;
  final DPopoverAlign align;
  final double sideOffset;
  final double alignOffset;
  final DPopoverCollision sideCollision;
  final DPopoverCollision alignCollision;
  final double collisionPadding;
  final Rect? collisionBoundary;
  final double width;
  final BoxConstraints constraints;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: tokens.foreground,
      fontSize: DiscourseTypography.sm,
      height: DiscourseTypography.lineHeightSmall,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      decoration: TextDecoration.none,
    );
    return DefaultTextStyle(
      style: style,
      child: IconTheme.merge(
        data: IconThemeData(color: tokens.foreground, size: 16),
        child: ConstrainedBox(
          constraints: constraints.copyWith(minWidth: width, maxWidth: width),
          child: CustomPaint(
            foregroundPainter: _HoverCardRingPainter(
              color: tokens.foreground.withValues(
                alpha: tokens.foreground.a * 0.10,
              ),
              radius: tokens.radius,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    offset: const Offset(0, 4),
                    blurRadius: 6,
                    spreadRadius: -1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                primary: false,
                padding: padding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverCardRingPainter extends CustomPainter {
  const _HoverCardRingPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = RRect.fromRectAndRadius(
      (Offset.zero & size).inflate(0.5),
      Radius.circular(radius + 0.5),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HoverCardRingPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}

class _HoverCardPositioner extends SingleChildRenderObjectWidget {
  const _HoverCardPositioner({
    required this.target,
    required this.boundary,
    required this.content,
    required this.direction,
    required this.animation,
    required super.child,
  });

  final Rect target;
  final Rect boundary;
  final DHoverCardContent content;
  final TextDirection direction;
  final Animation<double> animation;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHoverCard(this);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHoverCard renderObject,
  ) => renderObject.configuration = this;
}

class _RenderHoverCard extends RenderShiftedBox {
  _RenderHoverCard(this._configuration) : super(null);

  _HoverCardPositioner _configuration;
  DPopoverSide _side = DPopoverSide.bottom;
  Offset _transformOrigin = Offset.zero;

  set configuration(_HoverCardPositioner value) {
    if (_configuration.animation != value.animation && attached) {
      _configuration.animation.removeListener(markNeedsPaint);
      value.animation.addListener(markNeedsPaint);
    }
    _configuration = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _configuration.animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _configuration.animation.removeListener(markNeedsPaint);
    super.detach();
  }

  DPopoverSide _physical(DPopoverSide side) => switch (side) {
    DPopoverSide.inlineStart =>
      _configuration.direction == TextDirection.ltr
          ? DPopoverSide.left
          : DPopoverSide.right,
    DPopoverSide.inlineEnd =>
      _configuration.direction == TextDirection.ltr
          ? DPopoverSide.right
          : DPopoverSide.left,
    _ => side,
  };

  DPopoverSide _opposite(DPopoverSide side) => switch (side) {
    DPopoverSide.top => DPopoverSide.bottom,
    DPopoverSide.bottom => DPopoverSide.top,
    DPopoverSide.left => DPopoverSide.right,
    _ => DPopoverSide.left,
  };

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = _configuration;
    final config = c.content;
    final boundary = c.boundary.deflate(config.collisionPadding);
    _side = _physical(config.side);
    child!.layout(
      BoxConstraints(
        maxWidth: math.max(0, boundary.width),
        maxHeight: math.max(0, boundary.height),
      ),
      parentUsesSize: true,
    );
    var childSize = child!.size;
    final vertical = _side == DPopoverSide.top || _side == DPopoverSide.bottom;
    double room(DPopoverSide side) => switch (side) {
      DPopoverSide.top => c.target.top - boundary.top - config.sideOffset,
      DPopoverSide.bottom =>
        boundary.bottom - c.target.bottom - config.sideOffset,
      DPopoverSide.left => c.target.left - boundary.left - config.sideOffset,
      _ => boundary.right - c.target.right - config.sideOffset,
    };
    if (config.sideCollision == DPopoverCollision.flip) {
      final opposite = _opposite(_side);
      final extent = vertical ? childSize.height : childSize.width;
      if (extent > room(_side) && room(opposite) > room(_side)) {
        _side = opposite;
      }
    }
    final placedVertical =
        _side == DPopoverSide.top || _side == DPopoverSide.bottom;
    if (config.sideCollision == DPopoverCollision.flip) {
      child!.layout(
        BoxConstraints(
          maxWidth: math.max(0, placedVertical ? boundary.width : room(_side)),
          maxHeight: math.max(
            0,
            placedVertical ? room(_side) : boundary.height,
          ),
        ),
        parentUsesSize: true,
      );
      childSize = child!.size;
    }
    var align = config.align;
    if (placedVertical && c.direction == TextDirection.rtl) {
      align = switch (align) {
        DPopoverAlign.start => DPopoverAlign.end,
        DPopoverAlign.end => DPopoverAlign.start,
        _ => align,
      };
    }
    double aligned(
      DPopoverAlign placement,
      double start,
      double center,
      double end,
      double extent,
    ) => switch (placement) {
      DPopoverAlign.start => start,
      DPopoverAlign.center => center - extent / 2,
      DPopoverAlign.end => end - extent,
    };
    final logicalOffset =
        config.alignOffset *
        (placedVertical && c.direction == TextDirection.rtl ? -1 : 1);
    Offset place(DPopoverAlign placement) => switch (_side) {
      DPopoverSide.top => Offset(
        aligned(
              placement,
              c.target.left,
              c.target.center.dx,
              c.target.right,
              childSize.width,
            ) +
            logicalOffset,
        c.target.top - config.sideOffset - childSize.height,
      ),
      DPopoverSide.bottom => Offset(
        aligned(
              placement,
              c.target.left,
              c.target.center.dx,
              c.target.right,
              childSize.width,
            ) +
            logicalOffset,
        c.target.bottom + config.sideOffset,
      ),
      DPopoverSide.left => Offset(
        c.target.left - config.sideOffset - childSize.width,
        aligned(
              placement,
              c.target.top,
              c.target.center.dy,
              c.target.bottom,
              childSize.height,
            ) +
            config.alignOffset,
      ),
      _ => Offset(
        c.target.right + config.sideOffset,
        aligned(
              placement,
              c.target.top,
              c.target.center.dy,
              c.target.bottom,
              childSize.height,
            ) +
            config.alignOffset,
      ),
    };
    var offset = place(align);
    if (config.alignCollision == DPopoverCollision.flip &&
        align != DPopoverAlign.center) {
      final overflows = placedVertical
          ? offset.dx < boundary.left ||
                offset.dx + childSize.width > boundary.right
          : offset.dy < boundary.top ||
                offset.dy + childSize.height > boundary.bottom;
      if (overflows) {
        align = align == DPopoverAlign.start
            ? DPopoverAlign.end
            : DPopoverAlign.start;
        offset = place(align);
      }
    }
    var dx = offset.dx;
    var dy = offset.dy;
    if (config.sideCollision == DPopoverCollision.shift) {
      if (placedVertical) {
        dy = dy.clamp(
          boundary.top,
          math.max(boundary.top, boundary.bottom - childSize.height),
        );
      } else {
        dx = dx.clamp(
          boundary.left,
          math.max(boundary.left, boundary.right - childSize.width),
        );
      }
    }
    if (config.alignCollision == DPopoverCollision.shift) {
      if (placedVertical) {
        dx = dx.clamp(
          boundary.left,
          math.max(boundary.left, boundary.right - childSize.width),
        );
      } else {
        dy = dy.clamp(
          boundary.top,
          math.max(boundary.top, boundary.bottom - childSize.height),
        );
      }
    }
    offset = Offset(dx, dy);
    (child!.parentData! as BoxParentData).offset = offset;
    final anchor = c.target.center - offset;
    _transformOrigin = switch (_side) {
      DPopoverSide.top => Offset(
        anchor.dx,
        childSize.height + config.sideOffset,
      ),
      DPopoverSide.bottom => Offset(anchor.dx, -config.sideOffset),
      DPopoverSide.left => Offset(
        childSize.width + config.sideOffset,
        anchor.dy,
      ),
      _ => Offset(-config.sideOffset, anchor.dy),
    };
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final value = _configuration.animation.value;
    if (value <= 0 || child!.size.isEmpty) return;
    final origin = (child!.parentData! as BoxParentData).offset;
    context.pushOpacity(offset, (255 * value).round(), (context, offset) {
      final slide = (1 - value) * 8;
      final delta = switch (_side) {
        DPopoverSide.top => Offset(0, slide),
        DPopoverSide.bottom => Offset(0, -slide),
        DPopoverSide.left => Offset(slide, 0),
        _ => Offset(-slide, 0),
      };
      final scale = 0.95 + value * 0.05;
      final pivot = origin + _transformOrigin;
      final transform = Matrix4.identity()
        ..translateByDouble(pivot.dx + delta.dx, pivot.dy + delta.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
      context.pushTransform(needsCompositing, offset, transform, (
        context,
        offset,
      ) {
        context.paintChild(child!, offset + origin);
      });
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final childParentData = child!.parentData! as BoxParentData;
    return result.addWithPaintOffset(
      offset: childParentData.offset,
      position: position,
      hitTest: (result, transformed) =>
          child!.hitTest(result, position: transformed),
    );
  }
}
