import 'package:flutter/material.dart';

import '../theme/d_button.dart';

/// The compact desktop action surface shared by hovered posts and messages.
///
/// Discourse chat presents its actions as one bordered strip: controls are
/// wider than they are tall, the outer surface owns the rounding, and an
/// individual control gets a rectangular hover fill. Keeping those decisions
/// here prevents the post and chat versions from gradually becoming two
/// different toolbars again.
class HoverActionToolbar extends StatelessWidget {
  const HoverActionToolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          theme.discourseButtons.borderRadius,
        ),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// One compact control inside a [HoverActionToolbar].
class HoverActionButton extends StatelessWidget {
  const HoverActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.focusNode,
    this.color,
  });

  static const double width = DButton.minimumDimension;
  static const double height = DButton.minimumDimension;
  static const Size size = Size(width, height);

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  final FocusNode? focusNode;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DButton.iconOnly(
      focusNode: focusNode,
      onPressed: onPressed,
      tooltip: tooltip,
      variant: color == theme.colorScheme.error
          ? DButtonVariant.transparentDanger
          : DButtonVariant.flat,
      icon: IconTheme.merge(
        data: IconThemeData(color: color ?? theme.colorScheme.onSurfaceVariant),
        child: icon,
      ),
    );
  }
}
