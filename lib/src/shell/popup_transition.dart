import 'package:flutter/widgets.dart';

import 'curved_animation_builder.dart';

/// The entrance and exit of an anchored popup: a fade with a slight scale
/// from its anchor, eased out on the way in and in on the way out.
///
/// The command menu and the anchored pickers share it so the two kinds of
/// popup never drift apart.
class PopupTransition extends StatelessWidget {
  const PopupTransition({
    super.key,
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CurvedAnimationBuilder(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
      builder: (context, curved) => FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          alignment: alignment,
          child: child,
        ),
      ),
    );
  }
}
