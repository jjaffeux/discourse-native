import 'package:flutter/widgets.dart';

/// Owns the [CurvedAnimation] a transition derives from a route or overlay
/// animation.
///
/// A [CurvedAnimation] registers a status listener on its parent and only
/// `dispose` removes it, so one constructed inside `build` or a transition
/// builder leaks a listener on every rebuild — on every frame, for a route
/// transition. Building through this widget creates the curve once, replaces
/// it when the parent or a curve changes, and disposes it with the element.
class CurvedAnimationBuilder extends StatefulWidget {
  const CurvedAnimationBuilder({
    super.key,
    required this.parent,
    required this.curve,
    this.reverseCurve,
    required this.builder,
  });

  final Animation<double> parent;
  final Curve curve;
  final Curve? reverseCurve;
  final Widget Function(BuildContext context, Animation<double> animation)
  builder;

  @override
  State<CurvedAnimationBuilder> createState() => _CurvedAnimationBuilderState();
}

class _CurvedAnimationBuilderState extends State<CurvedAnimationBuilder> {
  late CurvedAnimation _curved = _create();

  CurvedAnimation _create() => CurvedAnimation(
    parent: widget.parent,
    curve: widget.curve,
    reverseCurve: widget.reverseCurve,
  );

  @override
  void didUpdateWidget(CurvedAnimationBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.parent, widget.parent) &&
        oldWidget.curve == widget.curve &&
        oldWidget.reverseCurve == widget.reverseCurve) {
      return;
    }
    _curved.dispose();
    _curved = _create();
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _curved);
}
