import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_aspect_ratio.dart';

/// A decorative placeholder for content whose size is known while loading.
///
/// Omitted dimensions fill bounded constraints and collapse on unbounded axes.
/// Use [Expanded], [FractionallySizedBox] or [DAspectRatio] for relative sizing.
/// Dimensions are logical pixels; the host continues to own text scaling.
///
/// Pulses independently, or shares the nearest [DSkeletonRegion]'s animation.
/// Reduced motion and disabled [TickerMode] always produce a static shape.
/// Group related shapes in a region to provide one accessible loading label.
class DSkeleton extends StatelessWidget {
  const DSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.color,
    this.animate = true,
  }) : assert(width == null || width >= 0),
       assert(height == null || height >= 0),
       shape = BoxShape.rectangle;

  const DSkeleton.circle({
    super.key,
    required double diameter,
    this.color,
    this.animate = true,
  }) : assert(diameter >= 0),
       width = diameter,
       height = diameter,
       borderRadius = null,
       shape = BoxShape.circle;

  final double? width;
  final double? height;

  /// Defaults to the theme's muted surface, matching shadcn's bg-muted.
  /// Override for a composition placed on that same muted background.
  final Color? color;

  /// Defaults to shadcn's medium radius (0.8 × the live site radius).
  /// Directional corners follow Directionality.
  final BorderRadiusGeometry? borderRadius;
  final BoxShape shape;

  /// False opts this shape out of pulsing, including inside an animated region.
  /// True still respects the region's setting and the host's motion preference.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final decoration = BoxDecoration(
      color: color ?? tokens.muted,
      shape: shape,
      borderRadius: shape == BoxShape.circle
          ? null
          : (borderRadius ?? BorderRadius.circular(tokens.radius * 0.8))
                .resolve(Directionality.of(context)),
    );
    final visual = IgnorePointer(
      child: ExcludeSemantics(
        child: Container(width: width, height: height, decoration: decoration),
      ),
    );
    final opacity = _SkeletonScope.maybeOf(context);
    if (!animate) return visual;
    if (opacity != null) {
      return FadeTransition(opacity: opacity, child: visual);
    }
    return _SkeletonPulse(child: _SkeletonFade(child: visual));
  }
}

/// An accessible loading composition with a shared pulse for its [DSkeleton]s.
///
/// All descendants are decorative: excluded from screen-reader traversal,
/// pointer input and keyboard focus. Keep real controls and scroll views
/// outside the region. Replace the region with actual content when ready;
/// the caller owns requests, loading/error state, focus and any announcements
/// on completion. This widget never mounts hidden loaded content.
class DSkeletonRegion extends StatelessWidget {
  const DSkeletonRegion({
    super.key,
    required this.semanticsLabel,
    required this.child,
    this.animate = true,
    this.liveRegion = true,
    this.expand = false,
  }) : assert(semanticsLabel != '');

  /// A localized label for the whole composition, for example 'Loading topics'.
  final String semanticsLabel;
  final Widget child;
  final bool animate;

  /// Whether assistive technology should announce this loading region.
  final bool liveRegion;

  /// Fills bounded axes, retaining natural size on unbounded axes.
  ///
  /// Use for an entire loading panel or viewport. The default leaves the
  /// composition's sizing to [child] and its incoming constraints.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final content = _SkeletonPulse(animate: animate, child: child);
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: ExcludeFocus(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: expand
                  ? LayoutBuilder(
                      builder: (context, constraints) => SizedBox(
                        width: constraints.hasBoundedWidth
                            ? constraints.maxWidth
                            : null,
                        height: constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : null,
                        child: content,
                      ),
                    )
                  : content,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({this.animate = true, required this.child});

  final bool animate;
  final Widget child;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    duration: DMotion.pulse,
    vsync: this,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.4, 0, 0.6, 1),
    reverseCurve: const Cubic(0.4, 0, 0.6, 1),
  );
  late final _opacity = Tween<double>(begin: 1, end: 0.5).animate(_curve);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_SkeletonPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _updateAnimation();
  }

  void _updateAnimation() {
    final active =
        widget.animate &&
        DMotion.duration(context, DMotion.pulse) != Duration.zero &&
        TickerMode.valuesOf(context).enabled;
    if (active) {
      if (!_controller.isAnimating) {
        unawaited(_controller.repeat(reverse: true));
      }
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SkeletonScope(opacity: _opacity, child: widget.child);
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.opacity, required super.child});

  final Animation<double> opacity;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>()?.opacity;

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      !identical(opacity, oldWidget.opacity);
}

class _SkeletonFade extends StatelessWidget {
  const _SkeletonFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _SkeletonScope.maybeOf(context)!, child: child);
}
