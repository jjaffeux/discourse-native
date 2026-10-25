import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'shell_scope.dart';

class AppHomeTheme extends StatelessWidget {
  const AppHomeTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shared = ShellScope.identityOf(context).forumSettings.shared;
    final homeTheme = AppTheme.forBrightness(
      MediaQuery.platformBrightnessOf(context),
      fontFamily: shared.interfaceFont.family,
      readingFontFamily: shared.readingFamily,
    );
    return Theme(
      data: homeTheme.copyWith(platform: Theme.of(context).platform),
      child: child,
    );
  }
}
