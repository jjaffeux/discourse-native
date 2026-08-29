import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact interactive value inside prose or metadata.
///
/// Inline actions keep their layout visually still under a pointer: the hand
/// cursor is enough hover feedback for a value that already reads as a link or
/// action. Keyboard focus remains visible, unlike pointer hover, so the target
/// does not disappear for people navigating without a mouse.
class InlineAction extends StatelessWidget {
  const InlineAction({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.excludeChildSemantics = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(2)),
  }) : _isLink = false;

  const InlineAction.link({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.excludeChildSemantics = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(2)),
  }) : _isLink = true;

  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;
  final bool excludeChildSemantics;
  final BorderRadius borderRadius;
  final bool _isLink;

  @override
  Widget build(BuildContext context) {
    final semanticChild = excludeChildSemantics
        ? ExcludeSemantics(child: child)
        : child;
    return Semantics(
      container: true,
      button: !_isLink,
      link: _isLink,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          focusColor: Theme.of(context).shell.hover,
          borderRadius: borderRadius,
          child: semanticChild,
        ),
      ),
    );
  }
}
