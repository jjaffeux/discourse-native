import 'dart:math' as math;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/joined_control.dart';
import '../foundation/tokens.dart';

enum DPopoverSide { top, bottom, left, right, inlineStart, inlineEnd }

enum DPopoverAlign { start, center, end }

enum DPopoverCollision { flip, shift, none }

enum DPopoverInteraction { mouse, touch, pen, keyboard, imperative }

enum DPopoverChangeReason {
  triggerPress,
  outsidePress,
  escape,
  closePress,
  imperative,
  lifecycle,
}

typedef DPopoverOpenChange =
    void Function(bool open, DPopoverChangeReason reason);

typedef DPopoverTriggerBuilder =
    Widget Function(BuildContext context, DPopoverTriggerState state);

typedef DPopoverCloseBuilder =
    Widget Function(BuildContext context, VoidCallback close);

@immutable
class DPopoverTriggerState {
  const DPopoverTriggerState({
    required this.open,
    required this.focusNode,
    required this.openPopover,
    required this.closePopover,
    required this.toggle,
  });

  final bool open;
  final FocusNode focusNode;
  final void Function([DPopoverInteraction? interaction]) openPopover;
  final VoidCallback closePopover;
  final void Function([DPopoverInteraction? interaction]) toggle;
}

/// Imperatively controls one mounted [DPopover].
///
/// Calls while detached are intentionally ignored. The owner disposes a
/// borrowed controller; [DPopover] only disposes its internally-created one.
class DPopoverController extends ChangeNotifier {
  _DPopoverState? _owner;
  bool _disposed = false;

  bool get isOpen => _owner?._open ?? false;

  void open() => _owner?._request(
    true,
    DPopoverChangeReason.imperative,
    DPopoverInteraction.imperative,
  );

  void close() => _owner?._request(
    false,
    DPopoverChangeReason.imperative,
    DPopoverInteraction.imperative,
  );

  void toggle() => isOpen ? close() : open();

  void _attach(_DPopoverState owner) {
    if (_disposed) return;
    _owner?._setOpen(false, immediate: true, restoreFocus: false);
    _owner = owner;
  }

  void _detach(_DPopoverState owner) {
    if (_owner == owner) _owner = null;
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

/// A shadcn/Base UI-style rich floating surface.
///
/// [open] selects controlled mode. Otherwise [defaultOpen] seeds local state.
/// The [child] normally contains one [DPopoverTrigger]; add [DPopoverAnchor]
/// around any other descendant to position against it instead. Trigger and
/// close builders let their nested control remain the single semantic button.
class DPopover extends StatefulWidget {
  const DPopover({
    super.key,
    required this.child,
    required this.content,
    this.open,
    this.defaultOpen = false,
    this.controller,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.restoreFocus = true,
  });

  final Widget child;
  final DPopoverContent content;
  final bool? open;
  final bool defaultOpen;
  final DPopoverController? controller;
  final DPopoverOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool restoreFocus;

  @override
  State<DPopover> createState() => _DPopoverState();
}

class _DPopoverLayers {
  static final List<_DPopoverState> _open = <_DPopoverState>[];

  static void activate(_DPopoverState state) {
    _open
      ..remove(state)
      ..add(state);
  }

  static void deactivate(_DPopoverState state) => _open.remove(state);

  static bool isTopmost(_DPopoverState state) =>
      _open.isNotEmpty && identical(_open.last, state);
}

class _DPopoverState extends State<DPopover>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _portal = OverlayPortalController();
  final _surfaceKey = GlobalKey();
  final _surfaceFocus = FocusScopeNode(debugLabel: 'DPopover content');
  late final _ownedController = DPopoverController();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 100),
  )..addStatusListener(_animationStatus);
  late final _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );
  BuildContext? _triggerContext;
  BuildContext? _anchorContext;
  FocusNode? _triggerFocus;
  FocusNode? _previousFocus;
  bool _open = false;
  bool _initialized = false;
  bool _syncScheduled = false;
  bool _suspended = false;
  bool _restoreFocusForNextClose = true;
  DPopoverInteraction _interaction = DPopoverInteraction.imperative;

  DPopoverController get _controller => widget.controller ?? _ownedController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_globalPointer);
    FocusManager.instance.addEarlyKeyEventHandler(_observeGlobalKey);
    _controller._attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(DPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)._detach(this);
      _controller._attach(this);
    }
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      if (_suspended) {
        _setOpen(false, immediate: true);
      } else if (widget.open != null) {
        _setOpen(widget.open!, restoreFocus: _restoreFocusForNextClose);
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

  void _request(
    bool value,
    DPopoverChangeReason reason,
    DPopoverInteraction interaction,
  ) {
    if (!mounted || value == _open) return;
    _interaction = interaction;
    if (!value) {
      _restoreFocusForNextClose = reason != DPopoverChangeReason.outsidePress;
    }
    if (widget.open == null) _setOpen(value);
    widget.onOpenChange?.call(value, reason);
  }

  void _setOpen(
    bool value, {
    bool immediate = false,
    bool restoreFocus = true,
  }) {
    if (!mounted || value == _open) return;
    _open = value;
    final noMotion = immediate || MediaQuery.disableAnimationsOf(context);
    if (value) {
      _DPopoverLayers.activate(this);
      _previousFocus = FocusManager.instance.primaryFocus;
      _portal.show();
      if (noMotion) {
        _animation.value = 1;
      } else {
        _animation.forward();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_open) return;
        if (_interaction == DPopoverInteraction.touch) {
          _surfaceFocus.requestFocus();
        } else {
          _surfaceFocus.requestFocus();
          _surfaceFocus.nextFocus();
        }
      });
    } else {
      _DPopoverLayers.deactivate(this);
      if (noMotion) {
        _animation.value = 0;
        _portal.hide();
        widget.onOpenChangeComplete?.call(false);
      } else {
        _animation.reverse();
      }
      if (restoreFocus && _restoreFocusForNextClose && widget.restoreFocus) {
        final target = _triggerFocus?.canRequestFocus == true
            ? _triggerFocus
            : _previousFocus;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_open && target?.canRequestFocus == true) {
            target!.requestFocus();
          }
        });
      }
      _restoreFocusForNextClose = true;
    }
    if (mounted) setState(() {});
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

  void _dismissForLifecycle() {
    if (!_open) return;
    _setOpen(false, immediate: true, restoreFocus: false);
    widget.onOpenChange?.call(false, DPopoverChangeReason.lifecycle);
  }

  Rect? _globalRect(BuildContext? target) {
    final box = target?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  void _globalPointer(PointerEvent event) {
    if (!_open ||
        !_DPopoverLayers.isTopmost(this) ||
        event is! PointerDownEvent) {
      return;
    }
    final point = event.position;
    if (_globalRect(_surfaceKey.currentContext)?.contains(point) ?? false) {
      return;
    }
    if (_globalRect(_triggerContext)?.contains(point) ?? false) return;
    if (_openDescendantMenus().isNotEmpty) return;
    _request(
      false,
      DPopoverChangeReason.outsidePress,
      _interactionFor(event.kind),
    );
  }

  List<MenuController> _openDescendantMenus() {
    final surfaceContext = _surfaceKey.currentContext;
    if (surfaceContext is! Element) return const [];
    final surroundingMenu = MenuController.maybeOf(surfaceContext);
    final found = <MenuController>[];
    void visit(Element element) {
      final menu = MenuController.maybeOf(element);
      if (menu != null &&
          !identical(menu, surroundingMenu) &&
          menu.isOpen &&
          !found.contains(menu)) {
        found.add(menu);
      }
      element.visitChildElements(visit);
    }

    surfaceContext.visitChildElements(visit);
    return found;
  }

  KeyEventResult _observeGlobalKey(KeyEvent event) {
    if (_open &&
        _DPopoverLayers.isTopmost(this) &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      final menus = _openDescendantMenus();
      if (menus.isNotEmpty) {
        menus.last.close();
        return KeyEventResult.handled;
      }
      _request(
        false,
        DPopoverChangeReason.escape,
        DPopoverInteraction.keyboard,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  DPopoverInteraction _interactionFor(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.touch => DPopoverInteraction.touch,
    PointerDeviceKind.stylus ||
    PointerDeviceKind.invertedStylus => DPopoverInteraction.pen,
    _ => DPopoverInteraction.mouse,
  };

  Widget _overlay(BuildContext overlayContext, OverlayChildLayoutInfo info) {
    final anchorContext = _anchorContext ?? _triggerContext;
    if (_suspended || anchorContext == null) return const SizedBox.shrink();
    final anchorBox = anchorContext.findRenderObject();
    final overlayBox = Overlay.of(context).context.findRenderObject();
    if (anchorBox is! RenderBox ||
        overlayBox is! RenderBox ||
        !anchorBox.attached ||
        !anchorBox.hasSize ||
        !overlayBox.attached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _open) {
          _request(
            false,
            DPopoverChangeReason.lifecycle,
            DPopoverInteraction.imperative,
          );
        }
      });
      return const SizedBox.shrink();
    }
    final target = MatrixUtils.transformRect(
      anchorBox.getTransformTo(overlayBox),
      Offset.zero & anchorBox.size,
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
        if (mounted && _open) {
          _request(
            false,
            DPopoverChangeReason.lifecycle,
            DPopoverInteraction.imperative,
          );
        }
      });
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: DJoinedControlScope.boundary(
        child: _PopoverScope(
          close: () => _request(
            false,
            DPopoverChangeReason.closePress,
            DPopoverInteraction.keyboard,
          ),
          child: _PopoverPositioner(
            target: target,
            boundary: boundary,
            content: widget.content,
            direction: Directionality.of(context),
            animation: _curve,
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (intent) {
                    _request(
                      false,
                      DPopoverChangeReason.escape,
                      DPopoverInteraction.keyboard,
                    );
                    return null;
                  },
                ),
              },
              child: FocusScope(
                node: _surfaceFocus,
                child: KeyedSubtree(key: _surfaceKey, child: widget.content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _registerTrigger(BuildContext context, FocusNode focusNode) {
    _triggerContext = context;
    _triggerFocus = focusNode;
  }

  void _unregisterTrigger(BuildContext context) {
    if (_triggerContext != context) return;
    _triggerContext = null;
    _triggerFocus = null;
    if (_open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _open && _triggerContext == null) {
          _setOpen(false, immediate: true, restoreFocus: false);
        }
      });
    }
  }

  void _registerAnchor(BuildContext context) => _anchorContext = context;

  void _anchorMoved() {
    if (!_open || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) setState(() {});
    });
  }

  void _unregisterAnchor(BuildContext context) {
    if (_anchorContext != context) return;
    _anchorContext = null;
    if (_open && _triggerContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _open &&
            _anchorContext == null &&
            _triggerContext == null) {
          _setOpen(false, immediate: true, restoreFocus: false);
        }
      });
    }
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

  @override
  Widget build(BuildContext context) => _PopoverRootScope(
    state: this,
    open: _open,
    child: OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _overlay,
      child: widget.child,
    ),
  );

  @override
  void dispose() {
    _DPopoverLayers.deactivate(this);
    _controller._detach(this);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_globalPointer);
    FocusManager.instance.removeEarlyKeyEventHandler(_observeGlobalKey);
    WidgetsBinding.instance.removeObserver(this);
    _curve.dispose();
    _animation.dispose();
    _surfaceFocus.dispose();
    _ownedController.dispose();
    super.dispose();
  }
}

class _PopoverRootScope extends InheritedWidget {
  const _PopoverRootScope({
    required this.state,
    required this.open,
    required super.child,
  });

  final _DPopoverState state;
  final bool open;

  static _DPopoverState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_PopoverRootScope>();
    assert(
      scope != null,
      'DPopoverTrigger and DPopoverAnchor require DPopover.',
    );
    return scope!.state;
  }

  @override
  bool updateShouldNotify(_PopoverRootScope oldWidget) =>
      open != oldWidget.open;
}

/// Composes an existing action widget with popover state and activation.
class DPopoverTrigger extends StatefulWidget {
  const DPopoverTrigger({super.key, required this.builder, this.focusNode});

  final DPopoverTriggerBuilder builder;
  final FocusNode? focusNode;

  @override
  State<DPopoverTrigger> createState() => _DPopoverTriggerWidgetState();
}

class _DPopoverTriggerWidgetState extends State<DPopoverTrigger> {
  late FocusNode _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  _DPopoverState? _root;
  DPopoverInteraction? _pointerInteraction;

  DPopoverInteraction _resolveInteraction(DPopoverInteraction? supplied) {
    if (supplied != null) return supplied;
    final pointer = _pointerInteraction;
    _pointerInteraction = null;
    if (pointer != null) return pointer;
    return FocusManager.instance.highlightMode == FocusHighlightMode.traditional
        ? DPopoverInteraction.keyboard
        : DPopoverInteraction.mouse;
  }

  @override
  void initState() {
    super.initState();
    _ownedFocus = FocusNode(debugLabel: 'DPopover trigger');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _root = _PopoverRootScope.of(context).._registerTrigger(context, _focus);
  }

  @override
  void didUpdateWidget(DPopoverTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _root?._registerTrigger(context, _focus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _PopoverRootScope.of(context);
    return _PopoverAnchorTracker(
      onTransformChanged: root._anchorMoved,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) =>
            _pointerInteraction = root._interactionFor(event.kind),
        child: widget.builder(
          context,
          DPopoverTriggerState(
            open: root._open,
            focusNode: _focus,
            openPopover: ([interaction]) => root._request(
              true,
              DPopoverChangeReason.triggerPress,
              _resolveInteraction(interaction),
            ),
            closePopover: () => root._request(
              false,
              DPopoverChangeReason.triggerPress,
              _resolveInteraction(null),
            ),
            toggle: ([interaction]) => root._request(
              !root._open,
              DPopoverChangeReason.triggerPress,
              _resolveInteraction(interaction),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _root?._unregisterTrigger(context);
    _ownedFocus.dispose();
    super.dispose();
  }
}

/// Marks a descendant as the popup's positioning anchor.
class DPopoverAnchor extends StatefulWidget {
  const DPopoverAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<DPopoverAnchor> createState() => _DPopoverAnchorState();
}

class _DPopoverAnchorState extends State<DPopoverAnchor> {
  _DPopoverState? _root;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _root = _PopoverRootScope.of(context).._registerAnchor(context);
  }

  @override
  Widget build(BuildContext context) => _PopoverAnchorTracker(
    onTransformChanged: _root!._anchorMoved,
    child: widget.child,
  );

  @override
  void dispose() {
    _root?._unregisterAnchor(context);
    super.dispose();
  }
}

/// The styled popup and its positioning policy.
class DPopoverContent extends StatelessWidget {
  const DPopoverContent({
    super.key,
    required this.child,
    this.semanticLabel,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.center,
    this.sideOffset = 4,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.width = 288,
    this.constraints = const BoxConstraints(),
    this.padding = const EdgeInsets.all(10),
  }) : assert(sideOffset >= 0),
       assert(collisionPadding >= 0),
       assert(width > 0);

  final Widget child;
  final String? semanticLabel;
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
    final radius = tokens.radius;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DefaultTextStyle(
        style: style,
        child: IconTheme.merge(
          data: IconThemeData(color: tokens.foreground, size: 16),
          child: ConstrainedBox(
            constraints: constraints.copyWith(minWidth: width, maxWidth: width),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: tokens.foreground.withValues(
                    alpha: tokens.foreground.a * 0.10,
                  ),
                ),
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

class DPopoverHeader extends StatelessWidget {
  const DPopoverHeader({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 2,
    children: children,
  );
}

class DPopoverTitle extends StatelessWidget {
  const DPopoverTitle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: FontWeight.w500),
      child: child,
    ),
  );
}

class DPopoverDescription extends StatelessWidget {
  const DPopoverDescription({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(color: DTokens.of(context).mutedForeground),
    child: child,
  );
}

/// Composes a nested action with the nearest popover's close operation.
class DPopoverClose extends StatelessWidget {
  const DPopoverClose({super.key, required this.builder});

  final DPopoverCloseBuilder builder;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_PopoverScope>();
    assert(scope != null, 'DPopoverClose must be inside DPopoverContent.');
    return builder(context, scope!.close);
  }
}

class _PopoverScope extends InheritedWidget {
  const _PopoverScope({required this.close, required super.child});

  final VoidCallback close;

  @override
  bool updateShouldNotify(_PopoverScope oldWidget) => close != oldWidget.close;
}

class _PopoverAnchorTracker extends SingleChildRenderObjectWidget {
  const _PopoverAnchorTracker({
    required this.onTransformChanged,
    required super.child,
  });

  final VoidCallback onTransformChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPopoverAnchorTracker(onTransformChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPopoverAnchorTracker renderObject,
  ) => renderObject.onTransformChanged = onTransformChanged;
}

class _RenderPopoverAnchorTracker extends RenderProxyBox {
  _RenderPopoverAnchorTracker(this.onTransformChanged);

  VoidCallback onTransformChanged;
  Offset? _lastOrigin;
  Size? _lastSize;

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = localToGlobal(Offset.zero);
    if (_lastOrigin != null && (_lastOrigin != origin || _lastSize != size)) {
      onTransformChanged();
    }
    _lastOrigin = origin;
    _lastSize = size;
    super.paint(context, offset);
  }
}

class _PopoverPositioner extends SingleChildRenderObjectWidget {
  const _PopoverPositioner({
    required this.target,
    required this.boundary,
    required this.content,
    required this.direction,
    required this.animation,
    required super.child,
  });

  final Rect target;
  final Rect boundary;
  final DPopoverContent content;
  final TextDirection direction;
  final Animation<double> animation;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPopover(this);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPopover renderObject,
  ) => renderObject.configuration = this;
}

class _RenderPopover extends RenderShiftedBox {
  _RenderPopover(this._configuration) : super(null);

  _PopoverPositioner _configuration;
  DPopoverSide _side = DPopoverSide.bottom;
  Offset _transformOrigin = Offset.zero;

  set configuration(_PopoverPositioner value) {
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
