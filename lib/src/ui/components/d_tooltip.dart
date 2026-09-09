import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_kbd.dart';

enum DTooltipSide { top, bottom, left, right, inlineStart, inlineEnd }

enum DTooltipAlign { start, center, end }

enum DTooltipTrackCursor { none, x, y, both }

enum DTooltipChangeReason {
  hover,
  focus,
  triggerPress,
  outsidePress,
  escape,
  disabled,
  imperative,
  lifecycle,
}

typedef DTooltipOpenChange =
    void Function(bool open, DTooltipChangeReason reason);

/// An imperative handle that can be borrowed by one or several tooltips.
///
/// With multiple triggers, give each [DTooltip] a distinct [DTooltip.triggerId]
/// and pass that ID to [show]. Each trigger composes its own content, so ordinary
/// Dart closures replace the web handle's payload/render-function pairing.
/// Calls before mounting or after removal are ignored. The handle never owns
/// focus, action callbacks or keyboard bindings. Its owner disposes it.
class DTooltipController extends ChangeNotifier {
  final _triggers = <DTooltipState>{};
  DTooltipState? _active;
  bool _disposed = false;
  bool _notificationScheduled = false;

  bool get isOpen => _active?._open ?? false;
  Object? get activeTriggerId => isOpen ? _active?.widget.triggerId : null;

  void show({Object? triggerId}) {
    if (_disposed) return;
    final candidates = _triggers.where(
      (state) => triggerId == null || state.widget.triggerId == triggerId,
    );
    if (candidates.isEmpty) return;
    candidates.first._request(true, DTooltipChangeReason.imperative);
  }

  void hide() => _active?._request(false, DTooltipChangeReason.imperative);

  /// Removes the popup immediately, including a pending exit animation.
  void dismiss() {
    for (final trigger in _triggers.toList()) {
      trigger._request(false, DTooltipChangeReason.imperative, immediate: true);
    }
  }

  void _changed(DTooltipState state) {
    if (_disposed) return;
    if (state._open) {
      final previous = _active;
      _active = state;
      if (previous != state) {
        previous?._request(false, DTooltipChangeReason.imperative);
      }
    } else if (_active == state) {
      _active = null;
    }
    notifyListeners();
  }

  // A trigger detaches during widget update/disposal. Notify after the frame so
  // listeners can rebuild siblings or ancestors without mutating a locked tree.
  void _notifyAfterFrame() {
    if (_disposed || _notificationScheduled) return;
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _triggers.clear();
    _active = null;
    super.dispose();
  }
}

/// Shares hover timing and opens neighboring tooltips instantly for [timeout]
/// after a tooltip closes. Nested providers form independent groups.
///
/// The shadcn provider defaults to zero delay. Explicit [DTooltip.hoverDelay]
/// overrides [delay]; keyboard focus and imperative opening are immediate.
class DTooltipProvider extends StatefulWidget {
  const DTooltipProvider({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.closeDelay = Duration.zero,
    this.timeout = const Duration(milliseconds: 400),
  });

  final Widget child;
  final Duration delay;
  final Duration closeDelay;
  final Duration timeout;

  @override
  State<DTooltipProvider> createState() => _DTooltipProviderState();
}

class _DTooltipProviderState extends State<DTooltipProvider> {
  DTooltipState? active;
  Timer? cooldown;
  bool warm = false;

  void opened(DTooltipState state) {
    cooldown?.cancel();
    warm = true;
    final previous = active;
    active = state;
    if (previous != state) {
      previous?._request(false, DTooltipChangeReason.hover);
    }
  }

  void closed(DTooltipState state) {
    if (active != state) return;
    active = null;
    cooldown?.cancel();
    cooldown = Timer(widget.timeout, () => warm = false);
  }

  @override
  void dispose() {
    cooldown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _TooltipGroup(
    owner: this,
    delay: widget.delay,
    closeDelay: widget.closeDelay,
    child: widget.child,
  );
}

class _TooltipGroup extends InheritedWidget {
  const _TooltipGroup({
    required this.owner,
    required this.delay,
    required this.closeDelay,
    required super.child,
  });

  final _DTooltipProviderState owner;
  final Duration delay;
  final Duration closeDelay;

  @override
  bool updateShouldNotify(_TooltipGroup oldWidget) =>
      owner != oldWidget.owner ||
      delay != oldWidget.delay ||
      closeDelay != oldWidget.closeDelay;
}

/// A shadcn tooltip around an existing trigger, with native input ownership.
///
/// [message] supplies the default text and an accessible tooltip description.
/// [content] replaces the visible text for rich informational compositions; keep
/// a concise [message] for assistive technology. The popup cannot acquire focus.
/// Supply the trigger's accessible name on the trigger itself. A disabled button
/// works as [child]; [focusable] adds one visible focus stop for an otherwise
/// unfocusable trigger, without enabling its action.
///
/// [open] is controlled when non-null: interaction requests call [onOpenChange]
/// and the parent decides whether to update it. Otherwise [defaultOpen] seeds
/// local state. [controller] can open or close mounted triggers without a key.
/// [DTooltipState.ensureTooltipVisible] is also available for existing callers.
///
/// A RawTooltip subtype preserves Flutter's `find.byTooltip` and inspection
/// contract. This component owns its state and uses OverlayPortal, Focus and
/// native gesture recognizers; it does not instantiate a second RawTooltip.
/// Popup visuals always use live DTokens, not Material TooltipTheme decoration.
class DTooltip extends RawTooltip {
  const DTooltip({
    super.key,
    required this.message,
    required super.child,
    this.content,
    this.shortcut,
    this.containsKeycaps = false,
    this.excludeFromSemantics = false,
    this.labelTrigger = false,
    this.side = DTooltipSide.top,
    this.align = DTooltipAlign.center,
    this.sideOffset = 4,
    this.alignOffset = 0,
    this.collisionPadding = 5,
    this.avoidCollisions = true,
    this.showArrow = true,
    this.maxWidth = 320,
    this.open,
    this.defaultOpen = false,
    this.controller,
    this.triggerId,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.disabled = false,
    this.focusable = false,
    this.focusNode,
    this.disableHoverablePopup = false,
    this.closeOnClick = true,
    this.trackCursorAxis = DTooltipTrackCursor.none,
    Duration? hoverDelay,
    Duration? dismissDelay,
    super.touchDelay = const Duration(milliseconds: 1800),
    super.triggerMode = TooltipTriggerMode.longPress,
    super.enableFeedback = true,
    super.onTriggered,
  }) : assert(sideOffset >= 0),
       assert(collisionPadding >= 0),
       assert(maxWidth > 0),
       _hoverDelay = hoverDelay,
       _dismissDelay = dismissDelay,
       super(
         semanticsTooltip: message,
         tooltipBuilder: _buildContent,
         hoverDelay: hoverDelay ?? Duration.zero,
         dismissDelay: dismissDelay ?? Duration.zero,
         ignorePointer: disableHoverablePopup,
         animationStyle: const AnimationStyle(
           duration: Duration(milliseconds: 150),
           reverseDuration: Duration(milliseconds: 150),
           curve: Curves.ease,
         ),
       );

  static const defaultConstraints = BoxConstraints(maxWidth: 320);
  static const defaultPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
  static const defaultMargin = EdgeInsets.all(5);
  static const double defaultVerticalOffset = 4;

  final String message;
  final Widget? content;
  final DShortcut? shortcut;

  /// Reduces trailing padding to 6px for custom content containing keycaps.
  /// [shortcut] enables this automatically.
  final bool containsKeycaps;
  final bool excludeFromSemantics;

  /// Names a trigger that has no independent accessible label. The message is
  /// then spoken as its name, not repeated as a tooltip description. Useful for
  /// native IconButton/PopupMenuButton adapters with their own tooltip disabled.
  final bool labelTrigger;
  final DTooltipSide side;
  final DTooltipAlign align;
  final double sideOffset;
  final double alignOffset;
  final double collisionPadding;
  final bool avoidCollisions;
  final bool showArrow;
  final double maxWidth;
  final bool? open;
  final bool defaultOpen;
  final DTooltipController? controller;
  final Object? triggerId;
  final DTooltipOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool disabled;
  final bool focusable;

  /// Borrowed focus node for the wrapper. Existing child focus is observed too.
  final FocusNode? focusNode;
  final bool disableHoverablePopup;
  final bool closeOnClick;
  final DTooltipTrackCursor trackCursorAxis;
  final Duration? _hoverDelay;
  final Duration? _dismissDelay;

  static Widget _buildContent(
    BuildContext context,
    Animation<double> animation,
  ) {
    final tooltip = context.findAncestorStateOfType<DTooltipState>()!.widget;
    return _TooltipContent(tooltip: tooltip);
  }

  static final _visible = <DTooltipState>{};

  static bool dismissAllToolTips() {
    final states = _visible.toList();
    for (final state in states) {
      state._request(false, DTooltipChangeReason.imperative);
    }
    return states.isNotEmpty;
  }

  @override
  DTooltipState createState() => DTooltipState();
}

class DTooltipState extends State<DTooltip>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _portal = OverlayPortalController();
  final _surfaceKey = GlobalKey();
  late final _animation = AnimationController(
    vsync: this,
    duration: widget.animationStyle.duration,
    reverseDuration: widget.animationStyle.reverseDuration,
  )..addStatusListener(_animationStatus);
  late final _curve = CurvedAnimation(parent: _animation, curve: Curves.ease);
  _DTooltipProviderState? _group;
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _open = false;
  bool _available = false;
  bool _hovered = false;
  bool _popupHovered = false;
  bool _focused = false;
  bool _focusVisible = false;
  bool _longPressed = false;
  bool _suspended = false;
  bool _syncScheduled = false;
  // The pointer has hovered this trigger or its popup since the popup opened.
  // Only then does leaving the pair dismiss it; a popup opened by keyboard, a
  // controller or a parent must not vanish because an unrelated pointer moved.
  bool _pointerEngaged = false;
  bool _listening = false;
  Offset? _pointer;
  LongPressGestureRecognizer? _longPress;
  int? _tapPointer;
  Offset? _tapStart;

  bool get isOpen => _open;

  Duration get _delay => _group?.warm == true
      ? Duration.zero
      : widget._hoverDelay ?? _group?.widget.delay ?? Duration.zero;
  Duration get _closeDelay =>
      widget._dismissDelay ?? _group?.widget.closeDelay ?? Duration.zero;

  String? get _description => widget.excludeFromSemantics || widget.labelTrigger
      ? null
      : widget.shortcut == null
      ? widget.message
      : '${widget.message}, ${widget.shortcut!.semanticLabel(Theme.of(context).platform)}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?._triggers.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = context
        .dependOnInheritedWidgetOfExactType<_TooltipGroup>()
        ?.owner;
    if (group != _group) {
      _group?.closed(this);
      _group = group;
    }
    _available =
        !widget.disabled &&
        widget.message.isNotEmpty &&
        TooltipVisibility.of(context) &&
        TickerMode.valuesOf(context).enabled;
    _scheduleSync();
  }

  @override
  void didUpdateWidget(DTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      widget.controller?._triggers.add(this);
    }
    _available =
        !widget.disabled &&
        widget.message.isNotEmpty &&
        TooltipVisibility.of(context) &&
        TickerMode.valuesOf(context).enabled;
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      if (!_available || _suspended) {
        _cancelTimers();
        _hovered = _popupHovered = false;
        if (_open) {
          _request(
            false,
            DTooltipChangeReason.disabled,
            immediate: true,
            force: true,
          );
        }
      } else if (widget.open != null) {
        _setOpen(widget.open!);
      } else if (!_initialized) {
        _setOpen(widget.defaultOpen);
      }
      _initialized = true;
      // Replacing a borrowed handle does not change the popup's open state.
      // Adopt that already-open trigger after build, including notifying the
      // new handle's listeners and closing its previously active trigger.
      final controller = widget.controller;
      if (_open && controller != null && controller._active != this) {
        controller._changed(this);
      }
      if (MediaQuery.disableAnimationsOf(context) && _animation.isAnimating) {
        _animation.value = _open ? 1 : 0;
      }
    });
  }

  bool _initialized = false;

  /// Opens immediately when mounted and available. Controlled tooltips request
  /// their parent's update; this method never overrides [DTooltip.open].
  bool ensureTooltipVisible() {
    if (_open || !_available || _suspended) return false;
    _request(true, DTooltipChangeReason.imperative);
    return true;
  }

  void hide() => _request(false, DTooltipChangeReason.imperative);

  void _cancelTimers() {
    _showTimer?.cancel();
    _showTimer = null;
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _request(
    bool value,
    DTooltipChangeReason reason, {
    bool immediate = false,
    bool force = false,
  }) {
    _cancelTimers();
    if (!mounted || (value && (!_available || _suspended))) return;
    if (value == _open) {
      if (!value && immediate) {
        _animation.value = 0;
        _portal.hide();
      }
      return;
    }
    if (widget.open == null || force) _setOpen(value, immediate: immediate);
    widget.onOpenChange?.call(value, reason);
  }

  void _setOpen(bool value, {bool immediate = false}) {
    if (!mounted || value == _open) return;
    _open = value;
    final still = immediate || MediaQuery.disableAnimationsOf(context);
    if (value) {
      final overlay = Overlay.of(context);
      for (final previous in DTooltip._visible.toList()) {
        if (previous != this && Overlay.of(previous.context) == overlay) {
          previous._request(false, DTooltipChangeReason.hover);
        }
      }
      DTooltip._visible.add(this);
      _group?.opened(this);
      _pointerEngaged = _hovered || _popupHovered;
      _portal.show();
      if (still) {
        _animation.value = 1;
      } else {
        _animation.forward();
      }
      widget.onTriggered?.call();
    } else {
      DTooltip._visible.remove(this);
      _group?.closed(this);
      _pointerEngaged = false;
      if (still) {
        _animation.value = 0;
        _portal.hide();
      } else {
        _animation.reverse();
      }
    }
    _syncGlobalListeners();
    widget.controller?._changed(this);
  }

  // Global pointer and key observation exists only while a popup is open or a
  // tap is being observed, so hundreds of idle triggers cost nothing per event.
  void _syncGlobalListeners() {
    final needed = mounted && (_open || _tapPointer != null);
    if (needed == _listening) return;
    _listening = needed;
    if (needed) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_globalPointer);
      FocusManager.instance.addEarlyKeyEventHandler(_keyEvent);
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_globalPointer);
      FocusManager.instance.removeEarlyKeyEventHandler(_keyEvent);
    }
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

  void _enter(PointerEnterEvent event) {
    _hovered = true;
    _pointerEngaged = true;
    _pointer = event.position;
    _hideTimer?.cancel();
    if (_open || !_available || _suspended) return;
    _showTimer?.cancel();
    if (_delay == Duration.zero) {
      _request(true, DTooltipChangeReason.hover);
    } else {
      _showTimer = Timer(_delay, () {
        if (_hovered) _request(true, DTooltipChangeReason.hover);
      });
    }
  }

  void _exit(PointerExitEvent event) {
    _hovered = false;
    _pointer = event.position;
    _showTimer?.cancel();
    _scheduleHide();
  }

  void _scheduleHide() {
    if (_focused || _hovered || _popupHovered || _longPressed) return;
    if (!widget.disableHoverablePopup && _inBridge(_pointer)) return;
    // A pending close keeps its deadline; movement outside the pair does not
    // postpone it.
    if (_hideTimer?.isActive ?? false) return;
    if (_closeDelay == Duration.zero) {
      _request(false, DTooltipChangeReason.hover);
    } else {
      _hideTimer = Timer(_closeDelay, () {
        if (!_hovered && !_popupHovered && !_focused && !_longPressed) {
          _request(false, DTooltipChangeReason.hover);
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

  void _globalPointer(PointerEvent event) {
    if (!mounted) return;
    if (event.pointer == _tapPointer) {
      if (event is PointerCancelEvent ||
          (event is PointerMoveEvent &&
              (event.position - _tapStart!).distance > kTouchSlop)) {
        _tapPointer = null;
        _tapStart = null;
        _syncGlobalListeners();
      } else if (event is PointerUpEvent) {
        _tapPointer = null;
        _tapStart = null;
        if (widget.enableFeedback) unawaited(Feedback.forTap(context));
        _request(true, DTooltipChangeReason.triggerPress);
        _hideTimer = Timer(
          widget.touchDelay,
          () => _request(false, DTooltipChangeReason.triggerPress),
        );
        _syncGlobalListeners();
      }
    }
    if (event is PointerDownEvent) {
      if (!_open) return;
      if (_globalRect(_surfaceKey.currentContext)?.contains(event.position) ??
          false) {
        return;
      }
      final onTrigger = _globalRect(context)?.contains(event.position) ?? false;
      if (onTrigger &&
          (!widget.closeOnClick ||
              event.pointer == _longPress?.primaryPointer ||
              event.pointer == _tapPointer)) {
        return;
      }
      _request(
        false,
        onTrigger
            ? DTooltipChangeReason.triggerPress
            : DTooltipChangeReason.outsidePress,
      );
    } else if (event is PointerHoverEvent || event is PointerMoveEvent) {
      _pointer = event.position;
      if (_open && _pointerEngaged && !_hovered && !_popupHovered) {
        _scheduleHide();
      }
    }
  }

  void _pointerDown(PointerDownEvent event) {
    // Pressing the trigger withdraws a pending hover hint for every pointer.
    _showTimer?.cancel();
    if (!_available || event.kind == PointerDeviceKind.mouse) return;
    switch (widget.triggerMode) {
      case TooltipTriggerMode.manual:
        break;
      case TooltipTriggerMode.longPress:
        _longPress ??= LongPressGestureRecognizer(debugOwner: this)
          ..onLongPress = () {
            _longPressed = true;
            if (widget.enableFeedback) {
              unawaited(Feedback.forLongPress(context));
            }
            _request(true, DTooltipChangeReason.triggerPress);
          }
          ..onLongPressEnd = (_) {
            _longPressed = false;
            _hideTimer = Timer(
              widget.touchDelay,
              () => _request(false, DTooltipChangeReason.triggerPress),
            );
          }
          ..onLongPressCancel = () => _longPressed = false;
        _longPress!.addPointer(event);
      case TooltipTriggerMode.tap:
        // Observe a completed tap without entering the child's gesture arena.
        // Buttons keep their activation callback; scroll/cancel withdraws it.
        _tapPointer = event.pointer;
        _tapStart = event.position;
        _syncGlobalListeners();
    }
  }

  void _focusChanged(bool focused) {
    _focused =
        focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      _request(true, DTooltipChangeReason.focus);
    } else if (!focused && !_hovered && !_popupHovered) {
      _request(false, DTooltipChangeReason.focus);
    }
  }

  KeyEventResult _keyEvent(KeyEvent event) {
    if (!_open || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _request(false, DTooltipChangeReason.escape);
      return KeyEventResult.handled;
    }
    if (_focused &&
        widget.closeOnClick &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _request(false, DTooltipChangeReason.triggerPress);
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _suspended = state != AppLifecycleState.resumed;
    if (_suspended) {
      _request(
        false,
        DTooltipChangeReason.lifecycle,
        immediate: true,
        force: true,
      );
    }
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _suspended = event.state == ViewFocusState.unfocused;
    if (_suspended) {
      _request(
        false,
        DTooltipChangeReason.lifecycle,
        immediate: true,
        force: true,
      );
    }
  }

  Widget _overlay(BuildContext overlayContext, OverlayChildLayoutInfo info) {
    if (!_available ||
        _suspended ||
        info.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final target = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final media = MediaQuery.of(context);
    final boundary = Rect.fromLTRB(
      media.padding.left,
      media.padding.top,
      info.overlaySize.width -
          math.max(media.padding.right, media.viewInsets.right),
      info.overlaySize.height -
          math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    // Trigger clips determine whether its anchor remains visible. They must
    // not confine the popup: a rounded avatar/button can open into its Overlay.
    var visibleAnchor = target.intersect(boundary);
    RenderObject? child = context.findRenderObject();
    while (child != null && child != overlay) {
      final parent = child.parent;
      if (parent is RenderObject) {
        final clip = parent.describeApproximatePaintClip(child);
        if (clip != null) {
          visibleAnchor = visibleAnchor.intersect(
            MatrixUtils.transformRect(parent.getTransformTo(overlay), clip),
          );
        }
      }
      child = parent;
    }
    if (visibleAnchor.isEmpty || boundary.isEmpty) {
      if (_open) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _request(
              false,
              DTooltipChangeReason.lifecycle,
              immediate: true,
              force: true,
            );
          }
        });
      }
      return const SizedBox.shrink();
    }
    Offset? cursor;
    if (widget.trackCursorAxis != DTooltipTrackCursor.none &&
        _hovered &&
        _pointer != null) {
      cursor = overlay.globalToLocal(_pointer!);
    }
    return Positioned.fill(
      child: ExcludeSemantics(
        child: ExcludeFocus(
          child: SelectionContainer.disabled(
            child: _TooltipPositioner(
              target: target,
              boundary: boundary,
              tooltip: widget,
              direction: Directionality.of(context),
              cursor: cursor,
              animation: _curve,
              color: DTokens.of(context).foreground,
              radius: DTokens.of(context).radius * 0.8,
              child: IgnorePointer(
                ignoring: widget.disableHoverablePopup,
                child: MouseRegion(
                  onEnter: (_) {
                    _popupHovered = true;
                    _pointerEngaged = true;
                    _hideTimer?.cancel();
                  },
                  onExit: (event) {
                    _popupHovered = false;
                    _pointer = event.position;
                    _scheduleHide();
                  },
                  child: SingleChildScrollView(
                    key: _surfaceKey,
                    child: widget.tooltipBuilder(overlayContext, _curve),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Focus(
      focusNode: widget.focusNode,
      includeSemantics: widget.focusable,
      canRequestFocus: widget.focusable,
      skipTraversal: !widget.focusable,
      onFocusChange: (value) {
        _focusChanged(value);
        if (mounted) setState(() => _focusVisible = _focused);
      },
      child: widget.child,
    );
    child = OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: _TooltipMouseRegion(
        onEnter: _enter,
        onExit: _exit,
        onHover: (event) {
          if (widget.trackCursorAxis != DTooltipTrackCursor.none && _open) {
            setState(() => _pointer = event.position);
          }
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _pointerDown,
          child: _TooltipFocusRing(
            visible: widget.focusable && _focusVisible,
            child: child,
          ),
        ),
      ),
    );
    child = Semantics(
      label: widget.labelTrigger ? widget.message : null,
      tooltip: _description,
      child: child,
    );
    return widget.labelTrigger ? MergeSemantics(child: child) : child;
  }

  void _detachController(DTooltipController? controller) {
    controller?._triggers.remove(this);
    if (controller?._active == this) {
      controller?._active = null;
      controller?._notifyAfterFrame();
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    _longPress?.onLongPressCancel = null;
    _longPress?.dispose();
    _detachController(widget.controller);
    _group?.closed(this);
    DTooltip._visible.remove(this);
    _open = false;
    _tapPointer = null;
    _syncGlobalListeners();
    WidgetsBinding.instance.removeObserver(this);
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }
}

// The focusable wrapper shows the library's focus-visible ring: 3px of the
// ring color at half opacity, painted outside the wrapper so no child edge is
// covered.
class _TooltipFocusRing extends StatelessWidget {
  const _TooltipFocusRing({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: tokens.borderRadius,
        border: visible
            ? Border.all(
                color: tokens.focusRing.withValues(alpha: .5),
                width: 3,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
      child: child,
    );
  }
}

class _TooltipContent extends StatelessWidget {
  const _TooltipContent({required this.tooltip});
  final DTooltip tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final foreground = tokens.background;
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(
      color: foreground,
      fontSize: DiscourseTypography.xs,
      height: DiscourseTypography.lineHeightCaption,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      wordSpacing: 0,
      decoration: TextDecoration.none,
    );
    return DefaultTextStyle(
      style: style,
      textAlign: TextAlign.start,
      child: IconTheme.merge(
        data: IconThemeData(color: foreground, size: 16),
        child: DKbdTheme(
          foregroundColor: foreground,
          backgroundColor: foreground.withValues(
            alpha:
                foreground.a *
                (Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.20),
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              12,
              6,
              tooltip.shortcut != null || tooltip.containsKeycaps ? 6 : 12,
              6,
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                tooltip.content ?? Text(tooltip.message),
                if (tooltip.shortcut case final shortcut?)
                  DShortcutKeycaps(shortcut: shortcut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TooltipPositioner extends SingleChildRenderObjectWidget {
  const _TooltipPositioner({
    required this.target,
    required this.boundary,
    required this.tooltip,
    required this.direction,
    required this.cursor,
    required this.animation,
    required this.color,
    required this.radius,
    required super.child,
  });

  final Rect target;
  final Rect boundary;
  final DTooltip tooltip;
  final TextDirection direction;
  final Offset? cursor;
  final Animation<double> animation;
  final Color color;
  final double radius;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTooltip(this);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTooltip renderObject,
  ) => renderObject.configuration = this;
}

class _RenderTooltip extends RenderShiftedBox {
  _RenderTooltip(this._configuration) : super(null);
  _TooltipPositioner _configuration;
  DTooltipSide _side = DTooltipSide.top;
  Offset _arrow = Offset.zero;
  Offset _transformOrigin = Offset.zero;

  set configuration(_TooltipPositioner value) {
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

  DTooltipSide _physical(DTooltipSide side) => switch (side) {
    DTooltipSide.inlineStart =>
      _configuration.direction == TextDirection.ltr
          ? DTooltipSide.left
          : DTooltipSide.right,
    DTooltipSide.inlineEnd =>
      _configuration.direction == TextDirection.ltr
          ? DTooltipSide.right
          : DTooltipSide.left,
    _ => side,
  };

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = _configuration;
    final t = c.tooltip;
    final b = c.boundary.deflate(t.collisionPadding);
    final tracksX =
        c.cursor != null && t.trackCursorAxis != DTooltipTrackCursor.y;
    final tracksY =
        c.cursor != null && t.trackCursorAxis != DTooltipTrackCursor.x;
    final anchor = Rect.fromLTRB(
      tracksX ? c.cursor!.dx : c.target.left,
      tracksY ? c.cursor!.dy : c.target.top,
      tracksX ? c.cursor!.dx : c.target.right,
      tracksY ? c.cursor!.dy : c.target.bottom,
    );
    final spaces = {
      DTooltipSide.top: anchor.top - b.top - t.sideOffset,
      DTooltipSide.bottom: b.bottom - anchor.bottom - t.sideOffset,
      DTooltipSide.left: anchor.left - b.left - t.sideOffset,
      DTooltipSide.right: b.right - anchor.right - t.sideOffset,
    };
    _side = _physical(t.side);
    child!.layout(
      BoxConstraints(
        maxWidth: math.max(0.0, math.min(t.maxWidth, b.width)),
        maxHeight: math.max(0.0, b.height),
      ),
      parentUsesSize: true,
    );
    final vertical = _side == DTooltipSide.top || _side == DTooltipSide.bottom;
    final opposite = switch (_side) {
      DTooltipSide.top => DTooltipSide.bottom,
      DTooltipSide.bottom => DTooltipSide.top,
      DTooltipSide.left => DTooltipSide.right,
      _ => DTooltipSide.left,
    };
    final extent = vertical ? child!.size.height : child!.size.width;
    if (t.avoidCollisions &&
        extent > spaces[_side]! &&
        spaces[opposite]! > spaces[_side]!) {
      _side = opposite;
    }
    if (t.avoidCollisions) {
      child!.layout(
        BoxConstraints(
          maxWidth: math.max(
            0,
            math.min(t.maxWidth, vertical ? b.width : spaces[_side]!),
          ),
          maxHeight: math.max(0.0, vertical ? spaces[_side]! : b.height),
        ),
        parentUsesSize: true,
      );
    }
    final childSize = child!.size;
    var align = t.align;
    if (vertical && c.direction == TextDirection.rtl) {
      align = switch (align) {
        DTooltipAlign.start => DTooltipAlign.end,
        DTooltipAlign.end => DTooltipAlign.start,
        _ => align,
      };
    }
    var center = anchor.center;
    if (c.cursor case final cursor?) {
      center = Offset(
        t.trackCursorAxis == DTooltipTrackCursor.y ? center.dx : cursor.dx,
        t.trackCursorAxis == DTooltipTrackCursor.x ? center.dy : cursor.dy,
      );
    }
    double aligned(double start, double middle, double end, double extent) =>
        switch (align) {
          DTooltipAlign.start => start,
          DTooltipAlign.center => middle - extent / 2,
          DTooltipAlign.end => end - extent,
        };
    final crossOffset =
        t.alignOffset * (vertical && c.direction == TextDirection.rtl ? -1 : 1);
    var offset = switch (_side) {
      DTooltipSide.top => Offset(
        aligned(anchor.left, center.dx, anchor.right, childSize.width) +
            crossOffset,
        anchor.top - t.sideOffset - childSize.height,
      ),
      DTooltipSide.bottom => Offset(
        aligned(anchor.left, center.dx, anchor.right, childSize.width) +
            crossOffset,
        anchor.bottom + t.sideOffset,
      ),
      DTooltipSide.left => Offset(
        anchor.left - t.sideOffset - childSize.width,
        aligned(anchor.top, center.dy, anchor.bottom, childSize.height) +
            crossOffset,
      ),
      _ => Offset(
        anchor.right + t.sideOffset,
        aligned(anchor.top, center.dy, anchor.bottom, childSize.height) +
            crossOffset,
      ),
    };
    if (t.avoidCollisions) {
      offset = Offset(
        offset.dx.clamp(b.left, math.max(b.left, b.right - childSize.width)),
        offset.dy.clamp(b.top, math.max(b.top, b.bottom - childSize.height)),
      );
    }
    (child!.parentData! as BoxParentData).offset = offset;
    final arrowX = (center.dx - offset.dx).clamp(
      math.min(10.0, childSize.width / 2),
      math.max(childSize.width / 2, childSize.width - 10),
    );
    // The registry pins side arrows to the popup's vertical middle
    // (top-1/2! overrides the positioner's anchor-tracking offset); only the
    // top and bottom arrows follow the anchor within the 5px arrow padding.
    final arrowY = childSize.height / 2;
    _arrow = switch (_side) {
      DTooltipSide.top => Offset(arrowX.toDouble(), childSize.height - 2),
      DTooltipSide.bottom => Offset(arrowX.toDouble(), 2),
      DTooltipSide.left => Offset(childSize.width - 1, arrowY),
      _ => Offset(1, arrowY),
    };
    // Base UI scales around the trigger-facing edge plus the side gap, rather
    // than the diamond's center (for top: 50% calc(100% + sideOffset)).
    _transformOrigin = switch (_side) {
      DTooltipSide.top => Offset(_arrow.dx, childSize.height + t.sideOffset),
      DTooltipSide.bottom => Offset(_arrow.dx, -t.sideOffset),
      DTooltipSide.left => Offset(childSize.width + t.sideOffset, _arrow.dy),
      _ => Offset(-t.sideOffset, _arrow.dy),
    };
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = _configuration;
    final opacity = c.animation.value;
    if (opacity <= 0 || child!.size.isEmpty) return;
    final origin = (child!.parentData! as BoxParentData).offset;
    context.pushOpacity(offset, (255 * opacity).round(), (context, offset) {
      final slide = c.animation.status == AnimationStatus.reverse
          ? 0.0
          : (1 - opacity) * 8;
      final delta = switch (_side) {
        DTooltipSide.top => Offset(0, slide),
        DTooltipSide.bottom => Offset(0, -slide),
        DTooltipSide.left => Offset(slide, 0),
        _ => Offset(-slide, 0),
      };
      final scale = 0.95 + opacity * 0.05;
      final pivot = origin + _transformOrigin;
      final transform = Matrix4.identity()
        ..translateByDouble(pivot.dx + delta.dx, pivot.dy + delta.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
      context.pushTransform(needsCompositing, offset, transform, (
        context,
        offset,
      ) {
        final canvas = context.canvas;
        final body = (offset + origin) & child!.size;
        final paint = Paint()..color = c.color;
        if (c.tooltip.showArrow) {
          canvas.save();
          canvas.translate(body.left + _arrow.dx, body.top + _arrow.dy);
          canvas.rotate(math.pi / 4);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-5, -5, 10, 10),
              const Radius.circular(2),
            ),
            paint,
          );
          canvas.restore();
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(c.radius)),
          paint,
        );
        context.paintChild(child!, offset + origin);
      });
    });
  }
}

// Only the innermost tooltip trigger receives hover when tooltips are composed.
// Ordinary MouseRegions (for example the child's button) still receive events.
class _TooltipMouseRegion extends MouseRegion {
  const _TooltipMouseRegion({
    super.onEnter,
    super.onExit,
    super.onHover,
    super.child,
  });

  @override
  RenderMouseRegion createRenderObject(BuildContext context) =>
      _TooltipMouseRegionBox(
        onEnter: onEnter,
        onExit: onExit,
        onHover: onHover,
      );
}

class _TooltipMouseRegionBox extends RenderMouseRegion {
  _TooltipMouseRegionBox({super.onEnter, super.onExit, super.onHover});

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final hit =
        hitTestChildren(result, position: position) || hitTestSelf(position);
    if (hit &&
        !result.path.any((entry) => entry.target is _TooltipMouseRegionBox)) {
      result.add(BoxHitTestEntry(this, position));
    }
    return hit;
  }
}
