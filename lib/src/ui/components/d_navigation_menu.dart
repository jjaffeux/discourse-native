import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_popover.dart';

enum DNavigationMenuChangeReason {
  triggerPress,
  triggerHover,
  outsidePress,
  listNavigation,
  focusOut,
  escape,
  linkPress,
  controller,
  dynamic,
}

@immutable
class DNavigationMenuChange<T> {
  const DNavigationMenuChange({required this.value, required this.reason});

  final T? value;
  final DNavigationMenuChangeReason reason;
}

/// Optional imperative owner for a mounted [DNavigationMenu].
///
/// The menu never disposes a borrowed controller. Calls while detached are
/// intentionally ignored.
class DNavigationMenuController<T> extends ChangeNotifier {
  void Function(T value)? _open;
  VoidCallback? _close;
  T? Function()? _value;
  bool _disposed = false;

  T? get value => _value?.call();
  bool get isOpen => value != null;

  void open(T value) => _open?.call(value);
  void close() => _close?.call();

  void _attach({
    required void Function(T value) open,
    required VoidCallback close,
    required T? Function() value,
  }) {
    if (_disposed) return;
    _open = open;
    _close = close;
    _value = value;
  }

  void _detach() {
    _open = null;
    _close = null;
    _value = null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _detach();
    super.dispose();
  }
}

/// A shadcn/Base UI-style collection of site navigation links.
///
/// The root owns one shared viewport so moving between triggers animates the
/// panel instead of opening unrelated popovers. [value] enables controlled
/// mode; otherwise [defaultValue] seeds local state. A null value closes it.
class DNavigationMenu<T> extends StatefulWidget {
  const DNavigationMenu({
    super.key,
    required this.child,
    this.defaultValue,
    this.controller,
    this.onValueChanged,
    this.onSelectionChanged,
    this.onOpenChangeComplete,
    this.orientation = Axis.horizontal,
    this.align = DPopoverAlign.start,
    this.delay = const Duration(milliseconds: 50),
    this.closeDelay = const Duration(milliseconds: 50),
    this.viewport = true,
    this.semanticLabel = 'Primary navigation',
  }) : value = null,
       _controlled = false;

  const DNavigationMenu.controlled({
    super.key,
    required this.child,
    required this.value,
    this.controller,
    this.onValueChanged,
    this.onSelectionChanged,
    this.onOpenChangeComplete,
    this.orientation = Axis.horizontal,
    this.align = DPopoverAlign.start,
    this.delay = const Duration(milliseconds: 50),
    this.closeDelay = const Duration(milliseconds: 50),
    this.viewport = true,
    this.semanticLabel = 'Primary navigation',
  }) : defaultValue = null,
       _controlled = true;

  final DNavigationMenuList<T> child;
  final T? value;
  final T? defaultValue;
  final DNavigationMenuController<T>? controller;
  final ValueChanged<T?>? onValueChanged;
  final ValueChanged<DNavigationMenuChange<T>>? onSelectionChanged;
  final ValueChanged<bool>? onOpenChangeComplete;
  final Axis orientation;
  final DPopoverAlign align;
  final Duration delay;
  final Duration closeDelay;
  final bool viewport;
  final String semanticLabel;
  final bool _controlled;

  @override
  State<DNavigationMenu<T>> createState() => _DNavigationMenuState<T>();
}

class _DNavigationMenuState<T> extends State<DNavigationMenu<T>> {
  final _contentFocus = FocusScopeNode(debugLabel: 'Navigation menu content');
  final Map<T, FocusNode> _focusNodes = {};
  Timer? _openTimer;
  Timer? _closeTimer;
  T? _localValue;
  T? _lastValue;
  T? _invalidValueReported;
  T? _rovingValue;
  bool _pointerInList = false;
  bool _pointerInContent = false;

  bool get _controlled => widget._controlled;
  T? get value => _controlled ? widget.value : _localValue;
  List<DNavigationMenuItem<T>> get _items => widget.child.children;

  @override
  void initState() {
    super.initState();
    _localValue = widget.defaultValue;
    _lastValue = value;
    _attachController();
  }

  void _attachController() => widget.controller?._attach(
    open: (next) => _select(next, DNavigationMenuChangeReason.controller),
    close: () => _select(null, DNavigationMenuChangeReason.controller),
    value: () => value,
  );

  @override
  void didUpdateWidget(DNavigationMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach();
      _attachController();
    }
    _reconcileItems();
  }

  void _reconcileItems() {
    final values = _items.map((item) => item.value).toSet();
    for (final removed
        in _focusNodes.keys.where((key) => !values.contains(key)).toList()) {
      _focusNodes.remove(removed)?.dispose();
    }
    _syncRovingFocus();
    final selected = value;
    final selectedItem = _item(selected);
    final invalid =
        selected != null &&
        (selectedItem == null ||
            selectedItem.disabled ||
            selectedItem.content == null);
    if (!invalid) {
      _invalidValueReported = null;
      return;
    }
    if (_invalidValueReported == selected) return;
    _invalidValueReported = selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && value == selected) {
        _select(null, DNavigationMenuChangeReason.dynamic);
      }
    });
  }

  bool _isEnabled(DNavigationMenuItem<T> item) =>
      !item.disabled &&
      (item.link == null ||
          (!item.link!.disabled && item.link!.onPressed != null));

  void _syncRovingFocus() {
    final enabled = _items.where(_isEnabled).toList();
    if (enabled.isEmpty) {
      _rovingValue = null;
    } else if (!enabled.any((item) => item.value == _rovingValue)) {
      _rovingValue = enabled.first.value;
    }
    for (final entry in _focusNodes.entries) {
      entry.value.skipTraversal = entry.key != _rovingValue;
    }
  }

  void _setRovingValue(T next) {
    if (_rovingValue == next) return;
    _rovingValue = next;
    _syncRovingFocus();
  }

  FocusNode _focusFor(T value) => _focusNodes.putIfAbsent(value, () {
    late final FocusNode node;
    node =
        FocusNode(
          debugLabel: 'Navigation menu $value',
          skipTraversal: value != _rovingValue,
        )..addListener(() {
          if (!node.hasFocus) return;
          _setRovingValue(value);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !node.hasFocus) return;
            final focusContext = node.context;
            if (focusContext == null) return;
            Scrollable.ensureVisible(
              focusContext,
              duration: DMotion.duration(focusContext, DMotion.exit),
              alignment: .5,
            );
          });
        });
    return node;
  });

  DNavigationMenuItem<T>? _item(T? wanted) {
    if (wanted == null) return null;
    for (final item in _items) {
      if (item.value == wanted) return item;
    }
    return null;
  }

  void _select(T? next, DNavigationMenuChangeReason reason) {
    final item = _item(next);
    if (next != null &&
        (item == null || item.disabled || item.content == null)) {
      return;
    }
    if (value == next) return;
    _lastValue = value;
    if (!_controlled) setState(() => _localValue = next);
    widget.onValueChanged?.call(next);
    widget.onSelectionChanged?.call(
      DNavigationMenuChange(value: next, reason: reason),
    );
    widget.controller?._changed();
  }

  void _scheduleOpen(T next) {
    _closeTimer?.cancel();
    _openTimer?.cancel();
    _openTimer = Timer(widget.delay, () {
      if (mounted) {
        _select(next, DNavigationMenuChangeReason.triggerHover);
      }
    });
  }

  void _scheduleClose([
    DNavigationMenuChangeReason reason = DNavigationMenuChangeReason.focusOut,
  ]) {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _closeTimer = Timer(widget.closeDelay, () {
      if (mounted && !_pointerInList && !_pointerInContent) {
        _select(null, reason);
      }
    });
  }

  void _moveFrom(T current, int delta) {
    final enabled = _items.where(_isEnabled).toList();
    if (enabled.isEmpty) return;
    var index = enabled.indexWhere((item) => item.value == current);
    if (index < 0) index = 0;
    index = (index + delta) % enabled.length;
    if (index < 0) index += enabled.length;
    final next = enabled[index];
    _focusFor(next.value).requestFocus();
    if (value != null && next.content != null) {
      _select(next.value, DNavigationMenuChangeReason.listNavigation);
    }
  }

  void _focusBoundary(bool first) {
    final enabled = _items.where(_isEnabled).toList();
    if (enabled.isEmpty) return;
    _focusFor((first ? enabled.first : enabled.last).value).requestFocus();
  }

  KeyEventResult _navigateList(T current, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final horizontal = widget.orientation == Axis.horizontal;
    final reversed =
        horizontal && Directionality.of(context) == TextDirection.rtl;
    final forward = horizontal
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowDown;
    final backward = horizontal
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowUp;
    if (event.logicalKey == forward || event.logicalKey == backward) {
      _moveFrom(current, (event.logicalKey == forward) != reversed ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home ||
        event.logicalKey == LogicalKeyboardKey.end) {
      _focusBoundary(event.logicalKey == LogicalKeyboardKey.home);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusContent({required bool last}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusContentWhenReady(last: last, attempts: 3);
    });
  }

  void _focusContentWhenReady({required bool last, required int attempts}) {
    if (!mounted || value == null) return;
    if (_contentFocus.context == null) {
      if (attempts > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusContentWhenReady(last: last, attempts: attempts - 1);
        });
      }
      return;
    }
    _contentFocus.requestFocus();
    if (last) {
      _contentFocus.previousFocus();
    } else {
      _contentFocus.nextFocus();
    }
  }

  void _popoverChanged(bool open, DPopoverChangeReason reason) {
    if (open || value == null) return;
    final triggerToRestore = reason == DPopoverChangeReason.escape
        ? value
        : null;
    final mapped = switch (reason) {
      DPopoverChangeReason.outsidePress =>
        DNavigationMenuChangeReason.outsidePress,
      DPopoverChangeReason.escape => DNavigationMenuChangeReason.escape,
      _ => DNavigationMenuChangeReason.focusOut,
    };
    _select(null, mapped);
    if (triggerToRestore != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && value == null) {
          _focusFor(triggerToRestore).requestFocus();
        }
      });
    }
  }

  Widget _content(DNavigationMenuItem<T> item) {
    final content = item.content!;
    final direction = _activationDirection(item.value);
    final duration = DMotion.duration(
      context,
      const Duration(milliseconds: 350),
    );
    return MouseRegion(
      onEnter: (_) {
        _pointerInContent = true;
        _closeTimer?.cancel();
      },
      onExit: (_) {
        _pointerInContent = false;
        _scheduleClose();
      },
      child: FocusScope(
        node: _contentFocus,
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: duration,
          switchInCurve: const Cubic(0.22, 1, 0.36, 1),
          switchOutCurve: const Cubic(0.22, 1, 0.36, 1),
          transitionBuilder: (child, animation) {
            final offset = direction == 0
                ? Offset.zero
                : Offset(direction * .5, 0);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: offset,
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(key: ValueKey(item.value), child: content.child),
        ),
      ),
    );
  }

  double _activationDirection(T next) {
    final previous = _items.indexWhere((item) => item.value == _lastValue);
    final current = _items.indexWhere((item) => item.value == next);
    if (previous < 0 || current == previous) return 0;
    final physical = current > previous ? 1.0 : -1.0;
    return Directionality.of(context) == TextDirection.rtl
        ? -physical
        : physical;
  }

  @override
  Widget build(BuildContext context) {
    _reconcileItems();
    final selected = _item(value);
    final requestedWidth = selected?.content?.width ?? 1;
    final safeWidth = (MediaQuery.sizeOf(context).width - 10)
        .clamp(1.0, requestedWidth)
        .toDouble();
    final content = DPopoverContent(
      width: safeWidth,
      constraints: BoxConstraints(
        maxHeight: selected?.content?.maxHeight ?? 420,
      ),
      padding: EdgeInsets.zero,
      align: widget.align,
      sideOffset: 8,
      child: selected == null
          ? const SizedBox.shrink()
          : _DNavigationMenuLinkScope(
              close: () => _select(null, DNavigationMenuChangeReason.linkPress),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _content(selected),
              ),
            ),
    );
    final menuList = _DNavigationMenuLinkScope(
      close: () => _select(null, DNavigationMenuChangeReason.linkPress),
      child: _DNavigationMenuScope<T>(
        state: this,
        child: MouseRegion(
          onEnter: (_) {
            _pointerInList = true;
            _closeTimer?.cancel();
          },
          onExit: (_) {
            _pointerInList = false;
            _scheduleClose();
          },
          child: widget.child,
        ),
      ),
    );
    return Focus(
      canRequestFocus: false,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _closeTimer?.cancel();
        } else if (value != null) {
          _scheduleClose(DNavigationMenuChangeReason.focusOut);
        }
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: DPopover(
          open: selected != null,
          onOpenChange: _popoverChanged,
          onOpenChangeComplete: widget.onOpenChangeComplete,
          restoreFocus: false,
          focusContentOnOpen: false,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          transitionCurve: const Cubic(0.22, 1, 0.36, 1),
          content: content,
          child: widget.viewport ? DPopoverAnchor(child: menuList) : menuList,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    widget.controller?._detach();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _contentFocus.dispose();
    super.dispose();
  }
}

class _DNavigationMenuScope<T> extends InheritedWidget {
  _DNavigationMenuScope({required this.state, required super.child})
    : value = state.value,
      configuration = state.widget;
  final _DNavigationMenuState<T> state;
  final T? value;
  final DNavigationMenu<T> configuration;

  @override
  bool updateShouldNotify(_DNavigationMenuScope<T> oldWidget) =>
      value != oldWidget.value || configuration != oldWidget.configuration;
}

class _DNavigationMenuLinkScope extends InheritedWidget {
  const _DNavigationMenuLinkScope({required this.close, required super.child});
  final VoidCallback close;

  @override
  bool updateShouldNotify(_DNavigationMenuLinkScope oldWidget) => false;
}

class DNavigationMenuList<T> extends StatelessWidget {
  const DNavigationMenuList({super.key, required this.children});
  final List<DNavigationMenuItem<T>> children;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DNavigationMenuScope<T>>();
    assert(
      scope != null,
      'DNavigationMenuList must be inside DNavigationMenu.',
    );
    final root = scope!.state;
    final row = Flex(
      direction: root.widget.orientation,
      mainAxisSize: MainAxisSize.min,
      children: [for (final item in children) item],
    );
    return root.widget.orientation == Axis.horizontal
        ? ClipRect(
            clipper: const _NavigationListClipper(),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              primary: false,
              clipBehavior: Clip.none,
              child: row,
            ),
          )
        : row;
  }
}

class _NavigationListClipper extends CustomClipper<Rect> {
  const _NavigationListClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -4, size.width, size.height + 6);

  @override
  bool shouldReclip(_NavigationListClipper oldClipper) => false;
}

class DNavigationMenuItem<T> extends StatelessWidget {
  const DNavigationMenuItem({
    super.key,
    required this.value,
    required this.trigger,
    required this.content,
    this.disabled = false,
  }) : link = null;

  const DNavigationMenuItem.link({
    super.key,
    required this.value,
    required this.link,
    this.disabled = false,
  }) : trigger = null,
       content = null;

  final T value;
  final DNavigationMenuTrigger? trigger;
  final DNavigationMenuContent? content;
  final DNavigationMenuLink? link;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DNavigationMenuScope<T>>();
    assert(
      scope != null,
      'DNavigationMenuItem must be inside DNavigationMenuList.',
    );
    final root = scope!.state;
    if (link != null) {
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) => root._navigateList(value, event),
        child: link!._with(
          focusNode: root._focusFor(value),
          disabled: disabled,
        ),
      );
    }
    return trigger!._build(context, root, this);
  }
}

class DNavigationMenuTrigger extends StatelessWidget {
  const DNavigationMenuTrigger({super.key, required this.child});
  final Widget child;

  Widget _build<T>(
    BuildContext context,
    _DNavigationMenuState<T> root,
    DNavigationMenuItem<T> item,
  ) {
    final open = root.value == item.value;
    Widget action = _NavigationAction(
      focusNode: root._focusFor(item.value),
      disabled: item.disabled,
      active: open,
      hasPopup: true,
      onHover: () => root._scheduleOpen(item.value),
      onPressed: () => root._select(
        open ? null : item.value,
        DNavigationMenuChangeReason.triggerPress,
      ),
      onKeyEvent: (event) {
        final navigation = root._navigateList(item.value, event);
        if (navigation == KeyEventResult.handled) return navigation;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final horizontal = root.widget.orientation == Axis.horizontal;
        final firstKey = horizontal
            ? LogicalKeyboardKey.arrowDown
            : (Directionality.of(context) == TextDirection.ltr
                  ? LogicalKeyboardKey.arrowRight
                  : LogicalKeyboardKey.arrowLeft);
        if (event.logicalKey == firstKey ||
            (horizontal && event.logicalKey == LogicalKeyboardKey.arrowUp)) {
          root._select(item.value, DNavigationMenuChangeReason.listNavigation);
          root._focusContent(
            last: horizontal && event.logicalKey == LogicalKeyboardKey.arrowUp,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: child),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: open ? .5 : 0,
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 300),
            ),
            child: const Icon(Icons.keyboard_arrow_down, size: 12),
          ),
        ],
      ),
    );
    if (!root.widget.viewport &&
        (open || (root.value == null && root._lastValue == item.value))) {
      action = DPopoverAnchor(child: action);
    }
    return MouseRegion(
      onEnter: (_) => root._scheduleOpen(item.value),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          action,
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: -6,
            height: 6,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: DMotion.duration(
                context,
                const Duration(milliseconds: 150),
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: 8,
                  maxWidth: 8,
                  minHeight: 8,
                  maxHeight: 8,
                  child: Transform.translate(
                    offset: const Offset(0, 4.8),
                    child: Transform.rotate(
                      angle: .785398,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: DTokens.of(context).border,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(
                              DTokens.of(context).radius * .6,
                            ),
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0x1A000000), blurRadius: 6),
                          ],
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

  @override
  Widget build(BuildContext context) => throw FlutterError(
    'DNavigationMenuTrigger is configured by DNavigationMenuItem and cannot be mounted alone.',
  );
}

class DNavigationMenuContent extends StatelessWidget {
  const DNavigationMenuContent({
    super.key,
    required this.child,
    this.width = 384,
    this.maxHeight = 420,
  }) : assert(width > 0),
       assert(maxHeight > 0);

  final Widget child;
  final double width;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => child;
}

class DNavigationMenuLink extends StatefulWidget {
  const DNavigationMenuLink({
    super.key,
    required this.child,
    this.onPressed,
    this.active = false,
    this.disabled = false,
    this.closeOnActivate = false,
    this.focusNode,
    this.semanticLabel,
    this.triggerStyle = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool active;
  final bool disabled;
  final bool closeOnActivate;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final bool triggerStyle;

  DNavigationMenuLink _with({FocusNode? focusNode, bool disabled = false}) =>
      DNavigationMenuLink(
        key: key,
        onPressed: onPressed,
        active: active,
        disabled: this.disabled || disabled,
        closeOnActivate: closeOnActivate,
        focusNode: focusNode ?? this.focusNode,
        semanticLabel: semanticLabel,
        triggerStyle: triggerStyle,
        child: child,
      );

  @override
  State<DNavigationMenuLink> createState() => _DNavigationMenuLinkState();
}

class _DNavigationMenuLinkState extends State<DNavigationMenuLink> {
  late final FocusNode _ownedFocus = FocusNode(
    debugLabel: 'Navigation menu link',
  );
  bool _hovered = false;
  bool _focused = false;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  bool get _enabled => !widget.disabled && widget.onPressed != null;

  void _activate() {
    if (!_enabled) return;
    widget.onPressed!();
    if (widget.closeOnActivate) {
      context
          .dependOnInheritedWidgetOfExactType<_DNavigationMenuLinkScope>()
          ?.close();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    selected: widget.active,
    enabled: _enabled,
    label: widget.semanticLabel,
    onTap: _enabled ? _activate : null,
    child: _NavigationAction(
      focusNode: _focus,
      disabled: !_enabled,
      active: widget.active,
      triggerStyle: widget.triggerStyle,
      onPressed: _activate,
      onHoverChanged: (value) => setState(() => _hovered = value),
      onFocusChanged: (value) => setState(() => _focused = value),
      forceHovered: _hovered,
      forceFocused: _focused,
      child: widget.child,
    ),
  );

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }
}

class _NavigationAction extends StatefulWidget {
  const _NavigationAction({
    required this.child,
    required this.focusNode,
    required this.onPressed,
    this.onHover,
    this.onKeyEvent,
    this.onHoverChanged,
    this.onFocusChanged,
    this.disabled = false,
    this.active = false,
    this.hasPopup = false,
    this.triggerStyle = true,
    this.forceHovered = false,
    this.forceFocused = false,
  });

  final Widget child;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onHover;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onFocusChanged;
  final bool disabled;
  final bool active;
  final bool hasPopup;
  final bool triggerStyle;
  final bool forceHovered;
  final bool forceFocused;

  @override
  State<_NavigationAction> createState() => _NavigationActionState();
}

class _NavigationActionState extends State<_NavigationAction> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final interactive = !widget.disabled;
    final highlighted =
        widget.active ||
        _hovered ||
        _focused ||
        widget.forceHovered ||
        widget.forceFocused;
    final radius = tokens.radius * (widget.triggerStyle ? 1 : .8);
    final touch = Theme.of(context).platform == TargetPlatform.iOS;
    final visualHeight = widget.triggerStyle ? 36.0 : null;
    final action = Focus(
      canRequestFocus: false,
      onKeyEvent: (_, KeyEvent event) {
        final result = widget.onKeyEvent?.call(event) ?? KeyEventResult.ignored;
        if (result == KeyEventResult.handled) return result;
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: interactive,
        mouseCursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) {
          setState(() => _hovered = value);
          widget.onHoverChanged?.call(value);
          if (value) widget.onHover?.call();
        },
        onShowFocusHighlight: (value) {
          setState(() => _focused = value);
          widget.onFocusChanged?.call(value);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: interactive
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapCancel: interactive
              ? () => setState(() => _pressed = false)
              : null,
          onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
          onTap: interactive ? widget.onPressed : null,
          child: CustomPaint(
            foregroundPainter: _focused
                ? _NavigationFocusRingPainter(
                    color: tokens.focusRing.withValues(
                      alpha: tokens.focusRing.a * .5,
                    ),
                    radius: radius,
                  )
                : null,
            child: AnimatedContainer(
              duration: DMotion.duration(
                context,
                const Duration(milliseconds: 150),
              ),
              constraints: BoxConstraints(
                minHeight: touch ? 48 : (visualHeight ?? 0),
              ),
              padding: widget.triggerStyle
                  ? const EdgeInsetsDirectional.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    )
                  : const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: highlighted
                    ? tokens.muted.withValues(
                        alpha: widget.active
                            ? tokens.muted.a * .5
                            : tokens.muted.a,
                      )
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: tokens.foreground.withValues(
                    alpha: widget.disabled ? .5 : 1,
                  ),
                  fontSize: DiscourseTypography.sm,
                  height: DiscourseTypography.lineHeightSmall,
                  fontWeight: widget.triggerStyle
                      ? FontWeight.w500
                      : FontWeight.w400,
                  letterSpacing: 0,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 16,
                    color: tokens.foreground.withValues(
                      alpha: widget.disabled ? .5 : 1,
                    ),
                  ),
                  child: Opacity(
                    opacity: _pressed ? .85 : 1,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return widget.hasPopup
        ? Semantics(
            button: true,
            enabled: interactive,
            expanded: widget.active,
            child: action,
          )
        : action;
  }
}

class _NavigationFocusRingPainter extends CustomPainter {
  const _NavigationFocusRingPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 3.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(width / 2),
        Radius.circular(radius + width / 2),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_NavigationFocusRingPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
