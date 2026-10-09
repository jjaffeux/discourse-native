import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';

/// Keeps the departing content during its fade, without retaining its actions.
class DReveal extends StatefulWidget {
  const DReveal({super.key, required this.visible, required this.child});
  final bool visible;
  final Widget child;
  @override
  State<DReveal> createState() => _DRevealState();
}

class _DRevealState extends State<DReveal> with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );
  Widget? _last;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(DReveal old) {
    super.didUpdateWidget(old);
    _update();
  }

  void _update() {
    if (widget.visible) _last = widget.child;
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = widget.visible ? 1 : 0;
    } else {
      _animation.animateTo(
        widget.visible ? 1 : 0,
        duration: DMotion.change,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) => IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeFocus(
        excluding: !widget.visible,
        child: ExcludeSemantics(
          excluding: !widget.visible,
          child: ClipRect(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              heightFactor: _animation.value,
              child: Opacity(
                opacity: _animation.value,
                child: _animation.value == 0 ? const SizedBox.shrink() : _last,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
