import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppHomeTheme extends StatelessWidget {
  const AppHomeTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Home follows the system appearance, independently of the selected forum.
    final homeTheme =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? AppTheme.dark
        : AppTheme.light;
    return Theme(
      data: homeTheme.copyWith(platform: Theme.of(context).platform),
      child: child,
    );
  }
}
