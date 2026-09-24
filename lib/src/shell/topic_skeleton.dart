import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

/// Fill for the topic reader's loading placeholders.
///
/// The UI kit skeleton paints with `muted`, which a forum palette maps to its
/// `--primary-very-low`: a tint a few percent off the page, halved again by
/// the pulse. Light pages use the border neutral instead. On dark pages that
/// neutral is a hairline colour, still faint on the app's own dark theme, so
/// they mix the text colour into the page.
Color topicSkeletonColor(BuildContext context) {
  final tokens = DTokens.of(context);
  return Theme.of(context).brightness == Brightness.light
      ? tokens.border
      : Color.lerp(tokens.background, tokens.foreground, .18)!;
}

/// Keeps loading placeholders transparent for a short grace period.
///
/// A topic that arrives within it fills its reserved space directly, without
/// flashing placeholders first. The space itself is laid out immediately.
class TopicSkeletonReveal extends StatefulWidget {
  const TopicSkeletonReveal({super.key, required this.child});

  static const delay = Duration(milliseconds: 150);

  final Widget child;

  @override
  State<TopicSkeletonReveal> createState() => _TopicSkeletonRevealState();
}

class _TopicSkeletonRevealState extends State<TopicSkeletonReveal> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(TopicSkeletonReveal.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _visible ? 1 : 0,
    duration: DMotion.duration(context, DMotion.enter),
    // Assistive technology hears about loading as soon as it begins.
    alwaysIncludeSemantics: true,
    child: TickerMode(enabled: _visible, child: widget.child),
  );
}
