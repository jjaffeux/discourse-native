import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_tooltip.dart';

/// The imperative and observable API for a [DCarousel].
///
/// A controller passed to [DCarousel.controller] is borrowed and remains owned
/// by its caller. Without one, the carousel creates and disposes its own.
class DCarouselController extends ChangeNotifier {
  _DCarouselContentState? _client;
  int _selectedIndex = 0;
  int _itemCount = 0;
  bool _loop = false;

  bool get canScrollPrevious => _itemCount > 1 && (_loop || _selectedIndex > 0);
  bool get canScrollNext =>
      _itemCount > 1 && (_loop || _selectedIndex < _itemCount - 1);

  bool get hasClients => _client != null;

  Future<void> previous() =>
      _client?._step(-1, animated: true) ?? Future.value();
  Future<void> next() => _client?._step(1, animated: true) ?? Future.value();
  Future<void> select(int index, {bool animated = true}) =>
      _client?._select(index, animated: animated) ?? Future.value();

  void _attach(_DCarouselContentState client, int count, bool loop) {
    assert(_client == null || identical(_client, client));
    _client = client;
    _update(count: count, loop: loop, index: client._logicalIndex);
  }

  void _detach(_DCarouselContentState client) {
    if (identical(_client, client)) _client = null;
  }

  void _update({int? count, bool? loop, int? index}) {
    final nextCount = count ?? _itemCount;
    final nextLoop = loop ?? _loop;
    final nextIndex = index ?? _selectedIndex;
    if (nextCount == _itemCount &&
        nextLoop == _loop &&
        nextIndex == _selectedIndex) {
      return;
    }
    _itemCount = nextCount;
    _loop = nextLoop;
    _selectedIndex = nextIndex;
    notifyListeners();
  }
}

class DCarousel extends StatefulWidget {
  const DCarousel({
    super.key,
    required this.children,
    this.controller,

    this.loop = false,

    this.semanticLabel,
    this.onSelected,

    this.navigationInsets = true,
  });

  final List<Widget> children;
  final DCarouselController? controller;

  final bool loop;

  final String? semanticLabel;
  final ValueChanged<int>? onSelected;

  /// Reserves the reference's 48px control offset on the carousel axis.
  final bool navigationInsets;

  @override
  State<DCarousel> createState() => _DCarouselState();
}

class _DCarouselState extends State<DCarousel> {
  late DCarouselController _controller;
  late bool _ownsController;
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
  void didUpdateWidget(DCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) _controller.dispose();
      _adoptController();
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final previousKey = ((rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft));
    final nextKey = ((rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight));
    if (event.logicalKey == previousKey) {
      unawaited(_controller.previous());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == nextKey) {
      unawaited(_controller.next());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DCarouselScope(
      controller: _controller,
      loop: widget.loop,
      onSelected: widget.onSelected,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        role: widget.semanticLabel == null ? null : SemanticsRole.region,
        child: Focus(
          focusNode: null,
          autofocus: false,
          onKeyEvent: _onKey,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final child in widget.children)
                if (widget.navigationInsets && child is DCarouselContent)
                  Padding(
                    padding: (const EdgeInsets.symmetric(horizontal: 48)),
                    child: child,
                  )
                else
                  child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DCarouselScope extends InheritedWidget {
  const _DCarouselScope({
    required this.controller,
    required this.loop,
    required this.onSelected,
    required super.child,
  });
  final DCarouselController controller;

  final bool loop;

  final ValueChanged<int>? onSelected;

  static _DCarouselScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DCarouselScope>();
    assert(scope != null, 'Carousel parts require a DCarousel ancestor.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DCarouselScope oldWidget) =>
      controller != oldWidget.controller || loop != oldWidget.loop;
}

class DCarouselContent extends StatefulWidget {
  const DCarouselContent({
    super.key,
    required this.children,

    this.spacing = DSpacing.lg,

    this.height,
  }) : assert(spacing >= 0);

  final List<DCarouselItem> children;

  final double spacing;

  final double? height;

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
  bool _initialized = false;

  int get _count => widget.children.length;
  bool get _loops => _loopRequested && _count > 1;
  int _initialPage(int logical) =>
      _loops ? _count * _loopCyclesBeforeStart + logical : logical;
  int _logicalPage(int page) => _count == 0 ? 0 : page % _count;

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
      _logicalIndex = 0;
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
    _api?._update(count: _count, loop: _scope.loop, index: _logicalIndex);
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

  void _changed(int page) {
    _pageIndex = page;
    final logical = _logicalPage(page);
    if (logical == _logicalIndex) return;
    setState(() => _logicalIndex = logical);
    _api?._update(index: logical);
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
        const fraction = 1.0;
        _ensurePageController(fraction);
        final hostScrollBehavior = ScrollConfiguration.of(context);
        final viewport = ScrollConfiguration(
          behavior: hostScrollBehavior.copyWith(
            dragDevices: {
              ...hostScrollBehavior.dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: PageView.builder(
            key: const ValueKey('d-carousel-viewport'),
            controller: _pageController,
            scrollDirection: Axis.horizontal,
            physics: null,
            padEnds: false,
            itemCount: _loops ? null : _count,
            onPageChanged: _changed,
            itemBuilder: (context, page) {
              final index = _logicalPage(page);
              return Semantics(
                container: true,
                label: context.l10n.slideOf(
                  (index + 1).toString(),
                  (_count).toString(),
                ),
                child: Padding(
                  padding: (EdgeInsetsDirectional.only(end: widget.spacing)),
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
    this.size = DButtonSize.small,
  });

  final DCarouselNavigationDirection direction;
  final String? semanticLabel;
  final DButtonSize size;

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
    final horizontalIcon = directionality == TextDirection.rtl
        ? (previous ? DIcons.chevronRight : DIcons.chevronLeft)
        : (previous ? DIcons.chevronLeft : DIcons.chevronRight);
    final icon = (DIcon(horizontalIcon, size: 16));
    final label =
        widget.semanticLabel ??
        (previous ? context.l10n.previousSlide : context.l10n.nextSlide);
    return PositionedDirectional(
      start: ((previous ? 0 : null)),
      end: ((!previous ? 0 : null)),
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment.center,
        child: DButton.iconOnly(
          key: ValueKey('d-carousel-${widget.direction.name}'),
          icon: icon,
          tooltip: label,
          semanticLabel: label,
          variant: DButtonVariant.outline,
          size: widget.size,
          borderRadius: BorderRadius.circular(DTokens.of(context).radius * 2.6),
          onPressed: enabled
              ? () {
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
  const DCarouselPrevious({super.key, super.semanticLabel, super.size})
    : super(direction: DCarouselNavigationDirection.previous);
}

class DCarouselNext extends DCarouselNavigation {
  const DCarouselNext({super.key, super.semanticLabel, super.size})
    : super(direction: DCarouselNavigationDirection.next);
}

/// A carousel position indicator whose interaction matches its painted pill.
class DCarouselDot extends StatelessWidget {
  const DCarouselDot({
    super.key,
    required this.selected,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    this.focusNode,
    this.onFocusChange,
  });

  static const diameter = 10.0;
  static const selectedWidth = 22.0;

  final bool selected;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Color? color;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: semanticLabel,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: DTooltip(
        message: semanticLabel,
        excludeFromSemantics: true,
        child: InkWell(
          focusNode: focusNode,
          onFocusChange: onFocusChange,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: DMotion.duration(
              context,
              const Duration(milliseconds: 250),
            ),
            curve: Curves.easeOut,
            width: selected ? selectedWidth : diameter,
            height: diameter,
            decoration: BoxDecoration(
              color:
                  color ??
                  (selected
                      ? DTokens.of(context).foreground
                      : DTokens.of(context).border),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    ),
  );
}
