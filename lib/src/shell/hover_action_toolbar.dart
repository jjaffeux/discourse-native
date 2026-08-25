import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The compact desktop action surface shared by hovered posts and messages.
///
/// Discourse chat presents its actions as one bordered strip: controls are
/// wider than they are tall, the outer surface owns the rounding, and an
/// individual control gets a rectangular hover fill. Keeping those decisions
/// here prevents the post and chat versions from gradually becoming two
/// different toolbars again.
class HoverActionToolbar extends StatelessWidget {
  const HoverActionToolbar({super.key, required this.children});

  static const double radius = 4;

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
        borderRadius: BorderRadius.circular(radius),
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

  /// Mirrors the web chat toolbar's compact, slightly horizontal controls.
  static const double width = 36;
  static const double height = 32;
  static const Size size = Size(width, height);

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  final FocusNode? focusNode;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      focusNode: focusNode,
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: width, height: height),
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return theme.shell.hover;
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide.none;
          }
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: theme.colorScheme.primary, width: 2);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return BorderSide(color: theme.colorScheme.outline);
          }
          return BorderSide.none;
        }),
      ),
      padding: EdgeInsets.zero,
      color: color ?? theme.colorScheme.onSurfaceVariant,
    );
  }
}
