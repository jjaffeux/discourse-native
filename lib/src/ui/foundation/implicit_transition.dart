import 'package:flutter/widgets.dart';

/// Animates [builder]'s value from its previous [value] to the new one, the
/// way an [ImplicitlyAnimatedWidget] does, but creates its controller, ticker
/// and curve only when [value] first changes.
///
/// The controls in a scrolling row, such as a topic row's metadata links,
/// mount and unmount by the dozen without ever changing state. An
/// [AnimatedContainer] or [AnimatedDefaultTextStyle] allocates all three for
/// each of them on mount and disposes them on unmount.
///
/// A change of [value] restarts the transition from the value currently
/// shown, and a [Duration.zero] change shows the new value at once.
class DImplicitTransition<T extends Object> extends StatefulWidget {
  const DImplicitTransition({
    super.key,
    required this.value,
    required this.duration,
    required this.lerp,
    required this.builder,
    this.curve = Curves.linear,
  });

  final T value;
  final Duration duration;
  final Curve curve;
  final T Function(T begin, T end, double t) lerp;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<DImplicitTransition<T>> createState() => _DImplicitTransitionState<T>();
}

class _DImplicitTransitionState<T extends Object>
    extends State<DImplicitTransition<T>>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curve;

  /// The transition in flight, or null once the last one finished.
  ({T begin, T end})? _span;

  T get _shown => switch (_span) {
    final span? => widget.lerp(span.begin, span.end, _curve!.value),
    null => widget.value,
  };

  @override
  void didUpdateWidget(DImplicitTransition<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _span?.end ?? oldWidget.value;
    if (widget.value == target) return;
    final from = _span == null
        ? oldWidget.value
        : oldWidget.lerp(_span!.begin, _span!.end, _curve!.value);
    if (widget.duration == Duration.zero) {
      _controller?.stop();
      _span = null;
      return;
    }
    final controller = _controller ??= AnimationController(vsync: this)
      ..addListener(_tick)
      ..addStatusListener(_settle);
    final curve = _curve ??= CurvedAnimation(
      parent: controller,
      curve: widget.curve,
    );
    curve.curve = widget.curve;
    _span = (begin: from, end: widget.value);
    controller
      ..duration = widget.duration
      ..forward(from: 0);
  }

  void _tick() => setState(() {});

  void _settle(AnimationStatus status) {
    if (status.isCompleted) setState(() => _span = null);
  }

  @override
  void dispose() {
    _curve?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}
