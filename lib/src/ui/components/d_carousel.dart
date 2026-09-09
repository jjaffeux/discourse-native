import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';

enum DCarouselAlignment { start, center }

typedef DCarouselExtentResolver = double Function(double availableExtent);

/// The imperative and observable API for a [DCarousel].
///
/// A controller passed to [DCarousel.controller] is borrowed and remains owned
/// by its caller. Without one, the carousel creates and disposes its own.
class DCarouselController extends ChangeNotifier {
  _DCarouselContentState? _client;
  int _selectedIndex = 0;
  int _itemCount = 0;
  bool _loop = false;
  double _scrollProgress = 0;

  int get selectedIndex => _selectedIndex;
  int get itemCount => _itemCount;
  bool get canScrollPrevious => _itemCount > 1 && (_loop || _selectedIndex > 0);
  bool get canScrollNext =>
      _itemCount > 1 && (_loop || _selectedIndex < _itemCount - 1);
  double get scrollProgress => _scrollProgress;
  bool get hasClients => _client != null;

  Future<void> previous({bool animated = true}) =>
      _client?._step(-1, animated: animated) ?? Future.value();
  Future<void> next({bool animated = true}) =>
      _client?._step(1, animated: animated) ?? Future.value();
  Future<void> select(int index, {bool animated = true}) =>
      _client?._select(index, animated: animated) ?? Future.value();

  void _attach(_DCarouselContentState client, int count, bool loop) {
    assert(_client == null || identical(_client, client));
    _client = client;
    _update(
      count: count,
      loop: loop,
      index: client._logicalIndex,
      progress: client._progressFor(client._logicalIndex),
    );
  }

  void _detach(_DCarouselContentState client) {
    if (identical(_client, client)) _client = null;
  }

  void _update({int? count, bool? loop, int? index, double? progress}) {
    final nextCount = count ?? _itemCount;
    final nextLoop = loop ?? _loop;
    final nextIndex = index ?? _selectedIndex;
    final nextProgress = progress ?? _scrollProgress;
    if (nextCount == _itemCount &&
        nextLoop == _loop &&
        nextIndex == _selectedIndex &&
        nextProgress == _scrollProgress) {
      return;
    }
    _itemCount = nextCount;
    _loop = nextLoop;
    _selectedIndex = nextIndex;
    _scrollProgress = nextProgress;
    notifyListeners();
  }
}

abstract class DCarouselPlugin {
  void attach(DCarouselController controller, BuildContext context);
  void didChangeEnvironment(BuildContext context) {}
  void onInteraction() {}
  void detach() {}
  void dispose() {}
}

/// Embla-autoplay's native counterpart.
///
/// Autoplay is suppressed while reduced motion is enabled. Focus pauses it;
/// pointer hover can optionally pause it. With [stopOnInteraction], a user
/// scroll or navigation action stops playback until [play] is called.
class DCarouselAutoplay extends DCarouselPlugin {
  DCarouselAutoplay({
    this.delay = const Duration(seconds: 4),
    this.playOnInit = true,
    this.stopOnInteraction = true,
    this.stopOnMouseEnter = false,
    this.stopOnFocusIn = true,
  }) : assert(!delay.isNegative && delay != Duration.zero);

  final Duration delay;
  final bool playOnInit;
  final bool stopOnInteraction;
  final bool stopOnMouseEnter;
  final bool stopOnFocusIn;
  DCarouselController? _controller;
  Timer? _timer;
  bool _allowed = true;
  bool _reducedMotion = false;
  bool _hovered = false;
  bool _focused = false;

  bool get isPlaying => _timer?.isActive ?? false;

  @override
  void attach(DCarouselController controller, BuildContext context) {
    _controller = controller;
    controller.addListener(_controllerChanged);
    _allowed = playOnInit;
    didChangeEnvironment(context);
  }

  @override
  void didChangeEnvironment(BuildContext context) {
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _schedule();
  }

  void play() {
    _allowed = true;
    _schedule();
  }

  void stop() {
    _allowed = false;
    _timer?.cancel();
  }

  void reset() => _schedule();

  void setHovered(bool hovered) {
    if (!stopOnMouseEnter) return;
    _hovered = hovered;
    _schedule();
  }

  void setFocused(bool focused) {
    if (!stopOnFocusIn) return;
    _focused = focused;
    _schedule();
  }

  @override
  void onInteraction() {
    if (stopOnInteraction) {
      stop();
    } else {
      reset();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final controller = _controller;
    if (!_allowed ||
        _reducedMotion ||
        (stopOnMouseEnter && _hovered) ||
        (stopOnFocusIn && _focused) ||
        controller == null ||
        controller.itemCount < 2) {
      return;
    }
    _timer = Timer(delay, () async {
      if (controller.canScrollNext) {
        await controller.next();
      } else {
        await controller.select(0);
      }
      _schedule();
    });
  }

  void _controllerChanged() => _schedule();

  @override
  void detach() {
    _timer?.cancel();
    _controller?.removeListener(_controllerChanged);
    _controller = null;
  }

  @override
  void dispose() => detach();
}

class DCarousel extends StatefulWidget {
  const DCarousel({
    super.key,
    required this.children,
    this.controller,
    this.orientation = Axis.horizontal,
    this.loop = false,
    this.initialIndex = 0,
    this.plugins = const [],
    this.ownedPlugins = const [],
    this.semanticLabel,
    this.onSelected,
    this.onScrollStart,
    this.onScrollEnd,
    this.focusNode,
    this.autofocus = false,
    this.navigationInsets = true,
  });

  final List<Widget> children;
  final DCarouselController? controller;
  final Axis orientation;
  final bool loop;
  final int initialIndex;
  final List<DCarouselPlugin> plugins;
  final List<DCarouselPlugin> ownedPlugins;
  final String? semanticLabel;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onScrollStart;
  final VoidCallback? onScrollEnd;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Reserves the reference's 48px control offset on the carousel axis.
  final bool navigationInsets;

  @override
  State<DCarousel> createState() => _DCarouselState();
}

class _DCarouselState extends State<DCarousel> {
  late DCarouselController _controller;
  late bool _ownsController;
  final Set<DCarouselPlugin> _attachedPlugins = {};

  Iterable<DCarouselPlugin> get _plugins sync* {
    yield* widget.plugins;
    yield* widget.ownedPlugins;
  }

  @override
  void initState() {
    super.initState();
    _adoptController();
  }

  void _adoptController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? DCarouselController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final plugin in _plugins) {
      if (_attachedPlugins.add(plugin)) {
        plugin.attach(_controller, context);
      } else {
        plugin.didChangeEnvironment(context);
      }
    }
  }

  @override
  void didUpdateWidget(DCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPlugins = <DCarouselPlugin>{
      ...oldWidget.plugins,
      ...oldWidget.ownedPlugins,
    };
    final newPlugins = <DCarouselPlugin>{
      ...widget.plugins,
      ...widget.ownedPlugins,
    };
    for (final plugin in oldPlugins.difference(newPlugins)) {
      plugin.detach();
      _attachedPlugins.remove(plugin);
      if (oldWidget.ownedPlugins.contains(plugin)) plugin.dispose();
    }
    if (oldWidget.controller != widget.controller) {
      for (final plugin in _attachedPlugins) {
        plugin.detach();
      }
      _attachedPlugins.clear();
      if (_ownsController) _controller.dispose();
      _adoptController();
    }
    for (final plugin in newPlugins) {
      if (_attachedPlugins.add(plugin)) plugin.attach(_controller, context);
    }
  }

  void _interaction() {
    for (final plugin in _plugins) {
      plugin.onInteraction();
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final previousKey = widget.orientation == Axis.horizontal
        ? (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)
        : LogicalKeyboardKey.arrowUp;
    final nextKey = widget.orientation == Axis.horizontal
        ? (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)
        : LogicalKeyboardKey.arrowDown;
    if (event.logicalKey == previousKey) {
      _interaction();
      unawaited(_controller.previous());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == nextKey) {
      _interaction();
      unawaited(_controller.next());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    for (final plugin in _plugins) {
      plugin.detach();
    }
    for (final plugin in widget.ownedPlugins) {
      plugin.dispose();
    }
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DCarouselScope(
      controller: _controller,
      orientation: widget.orientation,
      loop: widget.loop,
      initialIndex: widget.initialIndex,
      onSelected: widget.onSelected,
      onScrollStart: widget.onScrollStart,
      onScrollEnd: widget.onScrollEnd,
      onInteraction: _interaction,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          onFocusChange: (focused) {
            for (final plugin in _plugins.whereType<DCarouselAutoplay>()) {
              plugin.setFocused(focused);
            }
          },
          child: MouseRegion(
            onEnter: (_) {
              for (final plugin in _plugins.whereType<DCarouselAutoplay>()) {
                plugin.setHovered(true);
              }
            },
            onExit: (_) {
              for (final plugin in _plugins.whereType<DCarouselAutoplay>()) {
                plugin.setHovered(false);
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final child in widget.children)
                  if (widget.navigationInsets && child is DCarouselContent)
                    Padding(
                      padding: widget.orientation == Axis.horizontal
                          ? const EdgeInsets.symmetric(horizontal: 48)
                          : const EdgeInsets.symmetric(vertical: 48),
                      child: child,
                    )
                  else
                    child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DCarouselScope extends InheritedWidget {
  const _DCarouselScope({
    required this.controller,
    required this.orientation,
    required this.loop,
    required this.initialIndex,
    required this.onSelected,
    required this.onScrollStart,
    required this.onScrollEnd,
    required this.onInteraction,
    required super.child,
  });
  final DCarouselController controller;
  final Axis orientation;
  final bool loop;
  final int initialIndex;
  final ValueChanged<int>? onSelected;
  final VoidCallback? onScrollStart;
  final VoidCallback? onScrollEnd;
  final VoidCallback onInteraction;

  static _DCarouselScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DCarouselScope>();
    assert(scope != null, 'Carousel parts require a DCarousel ancestor.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DCarouselScope oldWidget) =>
      controller != oldWidget.controller ||
      orientation != oldWidget.orientation ||
      loop != oldWidget.loop ||
      initialIndex != oldWidget.initialIndex;
}

class DCarouselContent extends StatefulWidget {
  const DCarouselContent({
    super.key,
    required this.children,
    this.extentFraction = 1,
    this.extentResolver,
    this.spacing = DSpacing.lg,
    this.alignment = DCarouselAlignment.start,
    this.height,
    this.physics,
  }) : assert(extentFraction > 0 && extentFraction <= 1),
       assert(spacing >= 0);

  final List<DCarouselItem> children;
  final double extentFraction;
  final DCarouselExtentResolver? extentResolver;
  final double spacing;
  final DCarouselAlignment alignment;
  final double? height;
  final ScrollPhysics? physics;

  @override
  State<DCarouselContent> createState() => _DCarouselContentState();
}

class _DCarouselContentState extends State<DCarouselContent> {
  static const _loopCyclesBeforeStart = 10000;

  PageController? _pageController;
  DCarouselController? _api;
  int _logicalIndex = 0;
  int _pageIndex = 0;
  bool _loopRequested = false;
  double? _fraction;
  bool _scrolling = false;
  bool _initialized = false;

  int get _count => widget.children.length;
  bool get _loops => _loopRequested && _count > 1;
  int _initialPage(int logical) =>
      _loops ? _count * _loopCyclesBeforeStart + logical : logical;
  int _logicalPage(int page) => _count == 0 ? 0 : page % _count;
  double _progressFor(int logical) => _count < 2 ? 0 : logical / (_count - 1);
  double _progressForPage(double page) {
    if (_count < 2) return 0;
    final logicalPage = page % _count;
    return (logicalPage / (_count - 1)).clamp(0, 1);
  }

  _DCarouselScope get _scope => _DCarouselScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _scope;
    if (_api != scope.controller) {
      _api?._detach(this);
      _api = scope.controller;
    }
    if (!_initialized) {
      _loopRequested = scope.loop;
      _logicalIndex = _count == 0 ? 0 : scope.initialIndex.clamp(0, _count - 1);
      _pageIndex = _initialPage(_logicalIndex);
      _initialized = true;
    } else if (_loopRequested != scope.loop) {
      _loopRequested = scope.loop;
      _pageIndex = _initialPage(_logicalIndex);
      _fraction = null;
    }
    _api!._attach(this, _count, scope.loop);
  }

  @override
  void didUpdateWidget(DCarouselContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final countChanged = oldWidget.children.length != _count;
    if (_count == 0) {
      _logicalIndex = 0;
    } else if (_logicalIndex >= _count) {
      _logicalIndex = _count - 1;
    }
    if (countChanged) {
      // A virtual loop page is a multiple of the item count. Re-anchor after a
      // collection edit so modulo mapping cannot point at a different item.
      _pageIndex = _initialPage(_logicalIndex);
      _fraction = null;
    }
    _api?._update(
      count: _count,
      loop: _scope.loop,
      index: _logicalIndex,
      progress: _progressFor(_logicalIndex),
    );
  }

  void _ensurePageController(double fraction) {
    if (_pageController != null && _fraction == fraction) return;
    final old = _pageController;
    _fraction = fraction;
    _pageController = PageController(
      initialPage: _pageIndex,
      viewportFraction: fraction,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  Future<void> _step(int delta, {required bool animated}) {
    if (_count < 2) return Future.value();
    if (_loops) return _selectPage(_pageIndex + delta, animated: animated);
    final target = (_logicalIndex + delta).clamp(0, _count - 1);
    return _selectPage(target, animated: animated);
  }

  Future<void> _select(int index, {required bool animated}) {
    if (_count == 0 || index < 0 || index >= _count) return Future.value();
    if (!_loops) return _selectPage(index, animated: animated);

    // Select the nearest occurrence of this logical item. Previous/next use
    // [_step] so their direction remains explicit even in an even-sized loop.
    var delta = index - _logicalIndex;
    if (delta > _count / 2) {
      delta -= _count;
    } else if (delta < -_count / 2) {
      delta += _count;
    }
    return _selectPage(_pageIndex + delta, animated: animated);
  }

  Future<void> _selectPage(int page, {required bool animated}) {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return Future.value();
    if (!animated || MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(page);
      return Future.value();
    }
    return controller.animateToPage(
      page,
      duration: DMotion.change,
      curve: Curves.easeOutCubic,
    );
  }

  bool _notification(ScrollNotification notification) {
    if (notification is ScrollStartNotification && !_scrolling) {
      _scrolling = true;
      if (notification.dragDetails != null) _scope.onInteraction();
      _scope.onScrollStart?.call();
    } else if (notification is ScrollUpdateNotification) {
      final position = notification.metrics;
      final progress = _loops && position is PageMetrics
          ? _progressForPage(position.page ?? _pageIndex.toDouble())
          : position.maxScrollExtent <= 0
          ? 0.0
          : position.pixels / position.maxScrollExtent;
      _api?._update(progress: progress);
    } else if (notification is ScrollEndNotification && _scrolling) {
      _scrolling = false;
      _scope.onScrollEnd?.call();
    }
    return false;
  }

  void _changed(int page) {
    _pageIndex = page;
    final logical = _logicalPage(page);
    if (logical == _logicalIndex) return;
    setState(() => _logicalIndex = logical);
    _api?._update(index: logical, progress: _progressFor(logical));
    _scope.onSelected?.call(logical);
  }

  @override
  void dispose() {
    _api?._detach(this);
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = _scope.orientation == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        var fraction =
            widget.extentResolver?.call(available) ?? widget.extentFraction;
        fraction = fraction.clamp(.01, 1);
        _ensurePageController(fraction);
        final viewport = NotificationListener<ScrollNotification>(
          onNotification: _notification,
          child: PageView.builder(
            key: const ValueKey('d-carousel-viewport'),
            controller: _pageController,
            scrollDirection: _scope.orientation,
            physics: widget.physics,
            padEnds: widget.alignment == DCarouselAlignment.center,
            itemCount: _loops ? null : _count,
            onPageChanged: _changed,
            itemBuilder: (context, page) {
              final index = _logicalPage(page);
              return Semantics(
                container: true,
                label: 'Slide ${index + 1} of $_count',
                child: Padding(
                  padding: _scope.orientation == Axis.horizontal
                      ? EdgeInsetsDirectional.only(end: widget.spacing)
                      : EdgeInsets.only(bottom: widget.spacing),
                  child: widget.children[index],
                ),
              );
            },
          ),
        );
        return ClipRect(
          child: widget.height == null
              ? viewport
              : SizedBox(height: widget.height, child: viewport),
        );
      },
    );
  }
}

class DCarouselItem extends StatelessWidget {
  const DCarouselItem({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

enum DCarouselNavigationDirection { previous, next }

class DCarouselNavigation extends StatefulWidget {
  const DCarouselNavigation({
    super.key,
    required this.direction,
    this.semanticLabel,
  });

  final DCarouselNavigationDirection direction;
  final String? semanticLabel;

  @override
  State<DCarouselNavigation> createState() => _DCarouselNavigationState();
}

class _DCarouselNavigationState extends State<DCarouselNavigation> {
  DCarouselController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _DCarouselScope.of(context).controller;
    if (_controller == next) return;
    _controller?.removeListener(_changed);
    _controller = next..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _DCarouselScope.of(context);
    final previous = widget.direction == DCarouselNavigationDirection.previous;
    final enabled = previous
        ? scope.controller.canScrollPrevious
        : scope.controller.canScrollNext;
    final directionality = Directionality.of(context);
    final horizontal = scope.orientation == Axis.horizontal;
    final horizontalIcon = directionality == TextDirection.rtl
        ? (previous ? DIcons.chevronRight : DIcons.chevronLeft)
        : (previous ? DIcons.chevronLeft : DIcons.chevronRight);
    final icon = horizontal
        ? DIcon(horizontalIcon, size: 16)
        : RotatedBox(
            quarterTurns: previous ? 2 : 0,
            child: const DIcon(DIcons.chevronDown, size: 16),
          );
    final label =
        widget.semanticLabel ?? (previous ? 'Previous slide' : 'Next slide');
    return PositionedDirectional(
      start: horizontal ? (previous ? 0 : null) : 0,
      end: horizontal ? (!previous ? 0 : null) : 0,
      top: horizontal ? 0 : (previous ? 0 : null),
      bottom: horizontal ? 0 : (!previous ? 0 : null),
      child: Align(
        alignment: horizontal ? Alignment.center : Alignment.topCenter,
        child: DButton.iconOnly(
          key: ValueKey('d-carousel-${widget.direction.name}'),
          icon: icon,
          tooltip: label,
          semanticLabel: label,
          variant: DButtonVariant.outline,
          size: DButtonSize.regular,
          borderRadius: BorderRadius.circular(DTokens.of(context).radius * 2.6),
          onPressed: enabled
              ? () {
                  scope.onInteraction();
                  unawaited(
                    previous
                        ? scope.controller.previous()
                        : scope.controller.next(),
                  );
                }
              : null,
        ),
      ),
    );
  }
}

class DCarouselPrevious extends DCarouselNavigation {
  const DCarouselPrevious({super.key, super.semanticLabel})
    : super(direction: DCarouselNavigationDirection.previous);
}

class DCarouselNext extends DCarouselNavigation {
  const DCarouselNext({super.key, super.semanticLabel})
    : super(direction: DCarouselNavigationDirection.next);
}
