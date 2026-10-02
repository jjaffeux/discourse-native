import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';
import 'd_page_surface.dart';
import 'd_scroll_behavior.dart';

/// Axes enabled by [DScrollArea]. Each axis has one native scroll position.
enum DScrollAxes { vertical, horizontal, both }

/// A themed scrollbar around an existing viewport. Does not own its controller
/// or add a scroll position; suitable for lazy lists and restored app panes.
class DScrollBar extends StatelessWidget {
  const DScrollBar({
    super.key,
    required this.child,
    this.controller,
    this.axis = Axis.vertical,
    this.showScrollbar = true,
    this.thumbVisibility = true,
    this.thumb = const DScrollThumb(),
    this.backgroundColor,
    this.cornerExtent = 0,
    this.notificationDepth = 0,
  });

  final Widget child;

  /// Borrowed. When omitted, a single PrimaryScrollController is required.
  final ScrollController? controller;
  final Axis axis;

  /// Whether to paint the thumb and allow scrollbar dragging or track clicks.
  /// Hiding it preserves the viewport, its state and native scrolling.
  final bool showScrollbar;

  /// Keeps a shown thumb visible at rest. False enables native fading;
  /// use [showScrollbar] to hide it even during scrolling and hover.
  final bool thumbVisibility;
  final DScrollThumb thumb;

  /// Painted container surface. Defaults to the current theme background.
  final Color? backgroundColor;

  /// Space reserved for the perpendicular scrollbar in a two-axis viewport.
  final double cornerExtent;

  /// Viewport depth to observe; use one for a viewport nested inside another.
  final int notificationDepth;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: DScrollBehavior(
      delegate: ScrollConfiguration.of(context),
    ).copyWith(scrollbars: false),
    // Keep the viewport subtree mounted when the scrollbar is hidden.
    child: _NaturalScrollbar(
      pageHeader: axis == Axis.vertical
          ? DPageSurface.headerGeometryOf(context)
          : null,
      controller: controller,
      thumbVisibility: showScrollbar && thumbVisibility,
      interactive: showScrollbar,
      thickness: thumb.thickness,
      crossAxisMargin: DScrollThumb.containerInset,
      mainAxisMargin: DScrollThumb.containerInset,
      padding: axis == Axis.vertical
          ? EdgeInsets.only(bottom: cornerExtent)
          : EdgeInsetsDirectional.only(end: cornerExtent),
      radius: thumb.radius,
      minThumbLength: thumb.minLength,
      thumbColor: showScrollbar
          ? thumb.color ??
                DScrollThumb.colorOn(
                  backgroundColor ?? DTokens.of(context).background,
                  foreground: DTokens.of(context).foreground,
                )
          : Colors.transparent,
      fadeDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      notificationPredicate: (notification) =>
          notification.metrics.axis == axis &&
          notification.depth == notificationDepth,
      scrollbarOrientation: axis == Axis.horizontal
          ? ScrollbarOrientation.bottom
          : Directionality.of(context) == TextDirection.rtl
          ? ScrollbarOrientation.left
          : ScrollbarOrientation.right,
      child: child,
    ),
  );
}

/// Painter configuration for the draggable thumb; RawScrollbar remains the
/// sole gesture and paint owner. Null color adapts to the container surface.
@immutable
class DScrollThumb {
  const DScrollThumb({
    this.color,
    this.thickness = defaultThickness,
    this.minLength = 16,
    this.radius = const Radius.circular(999),
  });

  /// Shared width in logical pixels for UI kit and native app scrollbars.
  static const double defaultThickness = 4;

  /// Clear space between the thumb and its container, in logical pixels.
  static const double containerInset = 2;

  /// A subdued thumb with at least 3:1 contrast against an opaque surface.
  /// Translucent surfaces should be composited over their backdrop by callers.
  static Color colorOn(Color background, {required Color foreground}) {
    double contrast(Color color) {
      final a = color.computeLuminance();
      final b = background.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    var target = Color.alphaBlend(foreground, background);
    if (contrast(target) < 3) {
      target = contrast(Colors.black) > contrast(Colors.white)
          ? Colors.black
          : Colors.white;
    }
    for (var step = 55; step < 100; step += 5) {
      final candidate = Color.lerp(background, target, step / 100)!;
      if (contrast(candidate) >= 3) return candidate;
    }
    return target;
  }

  final Color? color;
  final double thickness;
  final double minLength;
  final Radius radius;
}

/// The native single-axis viewport used by DScrollArea. Its controller is
/// borrowed. Compose with DScrollBar when a caller owns viewport placement.
class DScrollViewport extends StatelessWidget {
  const DScrollViewport({
    super.key,
    required this.child,
    required this.controller,
    this.axis = Axis.vertical,
    this.padding = EdgeInsets.zero,
    this.physics,
  });
  final Widget child;
  final ScrollController controller;
  final Axis axis;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    scrollDirection: axis,
    padding: padding,
    physics: physics,
    child: child,
  );
}

/// The 10px intersection of two overflowing scrollbars. Transparent by
/// default, as in base-nova; a caller can color it to match an opaque surface.
class DScrollCorner extends StatelessWidget {
  const DScrollCorner({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: color == null ? null : ColoredBox(color: color!),
  );
}

/// Native scrolling with base-nova scrollbar artwork. Constrain the enabled
/// axes at the call site. Controllers supplied by callers are never disposed.
/// For virtualized content use [DScrollBar] around the existing ListView instead.
class DScrollArea extends StatefulWidget {
  const DScrollArea({
    super.key,
    required this.child,
    this.axes = DScrollAxes.vertical,
    this.controller,
    this.horizontalController,
    this.padding = EdgeInsets.zero,
    this.showScrollbar = true,
    this.thumbVisibility = true,
    this.borderRadius,
    this.backgroundColor,
    this.corner = const DScrollCorner(),
    this.physics,
  }) : assert(horizontalController == null || axes == DScrollAxes.both),
       assert(
         controller == null ||
             horizontalController == null ||
             !identical(controller, horizontalController),
       );

  final Widget child;
  final DScrollAxes axes;

  /// Vertical controller, or the sole controller for horizontal-only areas.
  final ScrollController? controller;

  /// Horizontal controller when [axes] is [DScrollAxes.both].
  final ScrollController? horizontalController;

  /// Insets the scrollable content on every enabled axis.
  final EdgeInsetsGeometry padding;

  /// Whether to show scrollbar thumbs and the two-axis corner.
  /// False preserves scrolling and keyboard navigation without scrollbar input.
  final bool showScrollbar;

  /// Keeps shown thumbs visible at rest; false enables native fading.
  final bool thumbVisibility;
  final BorderRadius? borderRadius;

  /// Painted container surface used to choose contrasting scrollbar thumbs.
  final Color? backgroundColor;
  final Widget corner;
  final ScrollPhysics? physics;

  @override
  State<DScrollArea> createState() => _DScrollAreaState();
}

class _DScrollAreaState extends State<DScrollArea> {
  final _focus = FocusNode(skipTraversal: true);
  final _owned = ScrollController();
  final _ownedHorizontal = ScrollController();
  bool _focusHighlightRequested = false;
  bool _focusVisible = false;
  bool _hasCorner = false;
  bool _hasOverflow = false;
  bool _metricsScheduled = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_updateFocusVisibility);
  }

  void _updateFocusVisibility() {
    // FocusableActionDetector reports focus within its subtree. The viewport
    // ring belongs only to the viewport's own keyboard focus.
    final visible = _focusHighlightRequested && _focus.hasPrimaryFocus;
    if (visible != _focusVisible) setState(() => _focusVisible = visible);
  }

  void _updateOverflow() {
    if (_metricsScheduled) return;
    _metricsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsScheduled = false;
      if (!mounted) return;
      final vertical = widget.controller ?? _owned;
      final horizontal = widget.horizontalController ?? _ownedHorizontal;
      bool overflows(ScrollController controller) =>
          controller.hasClients &&
          controller.positions.length == 1 &&
          controller.position.hasContentDimensions &&
          controller.position.maxScrollExtent >
              controller.position.minScrollExtent;
      final primaryOverflow = overflows(vertical);
      final horizontalOverflow =
          widget.axes == DScrollAxes.both && overflows(horizontal);
      final hasOverflow = primaryOverflow || horizontalOverflow;
      final hasCorner = primaryOverflow && horizontalOverflow;
      // Like tabindex=-1, skipping the root does not disable descendants or
      // forcibly blur a viewport that already has keyboard focus.
      _focus.skipTraversal = !hasOverflow;
      if (hasCorner != _hasCorner || hasOverflow != _hasOverflow) {
        setState(() {
          _hasCorner = hasCorner;
          _hasOverflow = hasOverflow;
        });
      }
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_updateFocusVisibility);
    _focus.dispose();
    _owned.dispose();
    _ownedHorizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final both = widget.axes == DScrollAxes.both;
    final showCorner = widget.showScrollbar && _hasCorner;
    final primary = widget.controller ?? _owned;
    final horizontal = widget.horizontalController ?? _ownedHorizontal;
    Widget content = widget.child;
    if (both) {
      content = Padding(padding: widget.padding, child: content);
      content = DScrollViewport(
        controller: horizontal,
        axis: Axis.horizontal,
        physics: widget.physics,
        child: content,
      );
    }
    content = DScrollViewport(
      controller: primary,
      axis: widget.axes == DScrollAxes.horizontal
          ? Axis.horizontal
          : Axis.vertical,
      padding: both ? EdgeInsets.zero : widget.padding,
      physics: widget.physics,
      child: content,
    );
    content = DScrollBar(
      controller: primary,
      axis: widget.axes == DScrollAxes.horizontal
          ? Axis.horizontal
          : Axis.vertical,
      showScrollbar: widget.showScrollbar,
      thumbVisibility: widget.thumbVisibility,
      backgroundColor: widget.backgroundColor,
      cornerExtent: showCorner ? 10 : 0,
      child: content,
    );
    if (both) {
      content = DScrollBar(
        controller: horizontal,
        axis: Axis.horizontal,
        notificationDepth: 1,
        showScrollbar: widget.showScrollbar,
        thumbVisibility: widget.thumbVisibility,
        backgroundColor: widget.backgroundColor,
        cornerExtent: showCorner ? 10 : 0,
        child: content,
      );
    }
    content = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _updateOverflow();
        return false;
      },
      child: content,
    );
    if (both) {
      content = Stack(
        children: [
          content,
          if (showCorner)
            PositionedDirectional(
              bottom: 0,
              end: 0,
              width: 10,
              height: 10,
              child: IgnorePointer(child: widget.corner),
            ),
        ],
      );
    }
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (!_hasOverflow || !_focus.hasPrimaryFocus || event is KeyUpEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        final keyboard = HardwareKeyboard.instance;
        if (keyboard.isControlPressed ||
            keyboard.isAltPressed ||
            keyboard.isMetaPressed ||
            (keyboard.isShiftPressed && key != LogicalKeyboardKey.space)) {
          return KeyEventResult.ignored;
        }
        final horizontalKey =
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight;
        if (horizontalKey && widget.axes == DScrollAxes.vertical) {
          return KeyEventResult.ignored;
        }
        final target = horizontalKey && both ? horizontal : primary;
        if (!target.hasClients || target.positions.length != 1) {
          return KeyEventResult.ignored;
        }
        final position = target.position;
        double delta;
        if (key == LogicalKeyboardKey.home) {
          delta = position.minScrollExtent - position.pixels;
        } else if (key == LogicalKeyboardKey.end) {
          delta = position.maxScrollExtent - position.pixels;
        } else if (key == LogicalKeyboardKey.pageDown ||
            key == LogicalKeyboardKey.space) {
          delta =
              position.viewportDimension *
              .9 *
              (key == LogicalKeyboardKey.space && keyboard.isShiftPressed
                  ? -1
                  : 1);
        } else if (key == LogicalKeyboardKey.pageUp) {
          delta = -position.viewportDimension * .9;
        } else if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight) {
          delta = 40;
        } else if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowLeft) {
          delta = -40;
        } else {
          return KeyEventResult.ignored;
        }
        if (horizontalKey && Directionality.of(context) == TextDirection.rtl) {
          delta = -delta;
        }
        final offset = (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (MediaQuery.disableAnimationsOf(context)) {
          target.jumpTo(offset);
        } else {
          target.animateTo(
            offset,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
        return KeyEventResult.handled;
      },
      child: FocusableActionDetector(
        focusNode: _focus,
        onShowFocusHighlight: (value) {
          _focusHighlightRequested = value;
          _updateFocusVisibility();
        },
        child: CustomPaint(
          foregroundPainter: _focusVisible
              ? _ScrollFocusRing(
                  radius: widget.borderRadius ?? tokens.borderRadius,
                  color: tokens.focusRing.withValues(
                    alpha: tokens.focusRing.a * .5,
                  ),
                )
              : null,
          child: ClipRRect(
            borderRadius: widget.borderRadius ?? tokens.borderRadius,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// CSS rings leave the transparent viewport untouched and occupy only the
/// exterior band. A spread-only BoxShadow also fills the interior in Flutter.
class _ScrollFocusRing extends CustomPainter {
  const _ScrollFocusRing({required this.radius, required this.color});
  final BorderRadius radius;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final inner = radius.toRRect(Offset.zero & size);
    canvas.drawDRRect(inner.inflate(3), inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrollFocusRing oldDelegate) =>
      radius != oldDelegate.radius || color != oldDelegate.color;
}

// RawScrollbar adds a 48px touch/trackpad region and hover padding internally.
// Keep its scrolling lifecycle and gestures, but use exact painter bounds.
class _NaturalScrollbar extends RawScrollbar {
  const _NaturalScrollbar({
    required super.child,
    super.controller,
    super.thumbVisibility,
    super.interactive,
    super.thickness,
    super.crossAxisMargin,
    super.mainAxisMargin,
    super.padding,
    super.radius,
    super.minThumbLength,
    super.thumbColor,
    super.fadeDuration,
    super.notificationPredicate,
    super.scrollbarOrientation,
    this.pageHeader,
  });

  final DPageHeaderGeometry? pageHeader;

  @override
  RawScrollbarState<_NaturalScrollbar> createState() =>
      _NaturalScrollbarState();
}

class _NaturalScrollbarState extends RawScrollbarState<_NaturalScrollbar> {
  late final ScrollbarPainter _naturalPainter;

  @override
  ScrollbarPainter get scrollbarPainter => _naturalPainter;

  @override
  void initState() {
    super.initState();
    final original = super.scrollbarPainter;
    _naturalPainter = _NaturalScrollbarPainter(
      color: original.color,
      fadeoutOpacityAnimation: original.fadeoutOpacityAnimation,
    );
    original.dispose();
    widget.pageHeader?.addListener(_updateHeaderInset);
  }

  void _updateHeaderInset() {
    scrollbarPainter.padding = (widget.padding ?? EdgeInsets.zero).add(
      EdgeInsets.only(top: widget.pageHeader?.visibleExtent ?? 0),
    );
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    _updateHeaderInset();
  }

  @override
  void didUpdateWidget(_NaturalScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageHeader != widget.pageHeader) {
      oldWidget.pageHeader?.removeListener(_updateHeaderInset);
      widget.pageHeader?.addListener(_updateHeaderInset);
    }
  }

  @override
  void dispose() {
    widget.pageHeader?.removeListener(_updateHeaderInset);
    super.dispose();
  }
}

class _NaturalScrollbarPainter extends ScrollbarPainter {
  _NaturalScrollbarPainter({
    required super.color,
    required super.fadeoutOpacityAnimation,
  });

  Size? _size;

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    super.paint(canvas, size);
  }

  // The column the thumb travels in. Flutter's track also includes the
  // unpainted container margins, and its touch and faded mouse-hover targets
  // add a 48px circle around the thumb; only this band is interactive.
  bool _bandContains(Offset position) {
    final size = _size;
    final direction = textDirection;
    if (size == null || direction == null) return false;
    final inset = padding.resolve(direction);
    final band = switch (scrollbarOrientation) {
      ScrollbarOrientation.top => Rect.fromLTWH(
        inset.left,
        inset.top + crossAxisMargin,
        size.width - inset.horizontal,
        thickness,
      ),
      ScrollbarOrientation.bottom => Rect.fromLTWH(
        inset.left,
        size.height - inset.bottom - crossAxisMargin - thickness,
        size.width - inset.horizontal,
        thickness,
      ),
      ScrollbarOrientation.left => Rect.fromLTWH(
        inset.left + crossAxisMargin,
        inset.top,
        thickness,
        size.height - inset.vertical,
      ),
      _ => Rect.fromLTWH(
        size.width - inset.right - crossAxisMargin - thickness,
        inset.top,
        thickness,
        size.height - inset.vertical,
      ),
    };
    return band.contains(position);
  }

  // A faded thumb is revealed by a mouse hovering its band, so native fading
  // does not leave it unreachable until the content is scrolled.
  @override
  bool hitTestInteractive(
    Offset position,
    PointerDeviceKind kind, {
    bool forHover = false,
  }) =>
      _bandContains(position) &&
      super.hitTestInteractive(position, kind, forHover: forHover);

  @override
  bool hitTest(Offset? position) =>
      position != null && hitTestInteractive(position, PointerDeviceKind.mouse);

  @override
  bool hitTestOnlyThumbInteractive(Offset position, PointerDeviceKind kind) =>
      super.hitTestOnlyThumbInteractive(position, PointerDeviceKind.mouse);
}
