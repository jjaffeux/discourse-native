import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Paints the shared window canvas behind the title bar, rail and panel gaps.
class ForumWindowBackground extends StatelessWidget {
  const ForumWindowBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      gradient: Theme.of(
        context,
      ).extension<ForumThemeEffects>()?.windowGradient,
    ),
    child: child,
  );
}

/// Applies navigation colors through the Native kit's existing theme boundary.
class ForumSidebarTheme extends StatelessWidget {
  const ForumSidebarTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sidebar = theme.extension<ForumThemeEffects>()?.sidebarTheme;
    if (sidebar == null) return child;
    return Theme(
      data: sidebar.copyWith(platform: theme.platform),
      child: child,
    );
  }
}
