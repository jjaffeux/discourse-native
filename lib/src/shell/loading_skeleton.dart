import 'dart:async';

import 'package:flutter/material.dart';

/// A synchronized, accessible pulse for decorative loading placeholders.
///
/// The child describes the eventual content's geometry. Individual
/// [LoadingSkeletonBlock]s read the animation from the private scope below, so
/// every shape breathes together while structural elements such as dividers
/// remain still.
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    required this.semanticsLabel,
    required this.child,
  });

  final String semanticsLabel;
  final Widget child;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  static const _legDuration = Duration(milliseconds: 675);

  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late final Animation<double> _opacity;
  bool? _animationsDisabled;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: _legDuration, vsync: this);
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeInOut,
    );
    _opacity = Tween<double>(begin: 0.62, end: 1).animate(_curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled == _animationsDisabled) return;
    _animationsDisabled = disabled;

    if (disabled) {
      _controller
        ..stop()
        ..value = 1;
    } else {
      unawaited(_controller.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: _LoadingSkeletonScope(
              opacity: _opacity,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingSkeletonScope extends InheritedWidget {
  const _LoadingSkeletonScope({required this.opacity, required super.child});

  final Animation<double> opacity;

  static Animation<double> of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_LoadingSkeletonScope>();
    assert(scope != null, 'LoadingSkeletonBlock requires a LoadingSkeleton');
    return scope!.opacity;
  }

  @override
  bool updateShouldNotify(_LoadingSkeletonScope oldWidget) =>
      !identical(opacity, oldWidget.opacity);
}

/// One neutral rectangle or circle inside a [LoadingSkeleton].
class LoadingSkeletonBlock extends StatelessWidget {
  const LoadingSkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
  }) : shape = BoxShape.rectangle;

  const LoadingSkeletonBlock.circle({super.key, required double diameter})
    : width = diameter,
      height = diameter,
      borderRadius = null,
      shape = BoxShape.circle;

  final double? width;
  final double height;
  final BorderRadiusGeometry? borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _LoadingSkeletonScope.of(context),
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: shape,
            borderRadius: borderRadius,
          ),
        ),
      ),
    );
  }
}
