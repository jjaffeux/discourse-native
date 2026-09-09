import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';

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
    this.thumbVisibility = true,
    this.thumb = const DScrollThumb(),
    this.cornerExtent = 0,
    this.notificationDepth = 0,
  });

  final Widget child;

  /// Borrowed. When omitted, a single PrimaryScrollController is required.
  final ScrollController? controller;
  final Axis axis;
  final bool thumbVisibility;
  final DScrollThumb thumb;

  /// Space reserved for the perpendicular scrollbar in a two-axis viewport.
  final double cornerExtent;

  /// Viewport depth to observe; use one for a viewport nested inside another.
  final int notificationDepth;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: RawScrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      interactive: true,
      thickness: thumb.thickness,
      crossAxisMargin: 1,
      mainAxisMargin: 1,
      padding: axis == Axis.vertical
          ? EdgeInsets.only(bottom: cornerExtent)
          : EdgeInsetsDirectional.only(end: cornerExtent),
      radius: thumb.radius,
      minThumbLength: thumb.minLength,
      thumbColor: thumb.color ?? DTokens.of(context).border,
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
/// sole gesture and paint owner. Null color reads the current theme border.
@immutable
class DScrollThumb {
  const DScrollThumb({
    this.color,
    this.thickness = 7,
    this.minLength = 16,
    this.radius = const Radius.circular(999),
  });
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
    this.thumbVisibility = true,
    this.borderRadius,
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
  final bool thumbVisibility;
  final BorderRadius? borderRadius;
  final Widget corner;
  final ScrollPhysics? physics;

  @override
  State<DScrollArea> createState() => _DScrollAreaState();
}

class _DScrollAreaState extends State<DScrollArea> {
  final _focus = FocusNode(skipTraversal: true);
  final _owned = ScrollController();
  final _ownedHorizontal = ScrollController();
  bool _focusVisible = false;
  bool _hasCorner = false;
  bool _hasOverflow = false;
  bool _metricsScheduled = false;

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
    _focus.dispose();
    _owned.dispose();
    _ownedHorizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final both = widget.axes == DScrollAxes.both;
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
      thumbVisibility: widget.thumbVisibility,
      cornerExtent: _hasCorner ? 10 : 0,
      child: content,
    );
    if (both) {
      content = DScrollBar(
        controller: horizontal,
        axis: Axis.horizontal,
        notificationDepth: 1,
        thumbVisibility: widget.thumbVisibility,
        cornerExtent: _hasCorner ? 10 : 0,
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
          if (_hasCorner)
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
        onShowFocusHighlight: (value) => setState(() => _focusVisible = value),
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
