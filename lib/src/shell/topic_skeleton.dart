import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

/// Shares one reveal timeline through a topic's reader handoff.
class TopicSkeletonScope extends StatefulWidget {
  const TopicSkeletonScope({super.key, required this.child});

  final Widget child;

  @override
  State<TopicSkeletonScope> createState() => _TopicSkeletonScopeState();
}

class _TopicSkeletonScopeState extends State<TopicSkeletonScope>
    with SingleTickerProviderStateMixin {
  late final _opacity = AnimationController(vsync: this);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(TopicSkeletonReveal.delay, () {
      _opacity.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _opacity.duration = DMotion.duration(context, DMotion.enter);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _TopicSkeletonAnimation(opacity: _opacity, child: widget.child);
}

class _TopicSkeletonAnimation extends InheritedWidget {
  const _TopicSkeletonAnimation({required this.opacity, required super.child});

  final Animation<double> opacity;

  @override
  bool updateShouldNotify(_TopicSkeletonAnimation oldWidget) =>
      opacity != oldWidget.opacity;
}

/// Keeps loading placeholders transparent for a short grace period.
///
/// A topic that arrives within it fills its reserved space directly, without
/// flashing placeholders first. The space itself is laid out immediately.
class TopicSkeletonReveal extends StatelessWidget {
  const TopicSkeletonReveal({super.key, required this.child});

  static const delay = Duration(milliseconds: 150);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = context
        .dependOnInheritedWidgetOfExactType<_TopicSkeletonAnimation>();
    if (animation == null) {
      return TopicSkeletonScope(child: TopicSkeletonReveal(child: child));
    }
    return FadeTransition(
      opacity: animation.opacity,
      // Assistive technology hears about loading as soon as it begins.
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: animation.opacity,
        builder: (context, child) =>
            TickerMode(enabled: animation.opacity.value > 0, child: child!),
        child: child,
      ),
    );
  }
}
