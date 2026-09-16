import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../theme/app_theme.dart';
import 'shell_scope.dart';

class AppHomeTheme extends StatelessWidget {
  const AppHomeTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = ShellScope.maybeIdentityOf(context)?.appSettings;
    Widget themed(BuildContext context, Widget? child) {
      final brightness = switch (settings?.themeMode ?? AppThemeMode.system) {
        AppThemeMode.system => MediaQuery.platformBrightnessOf(context),
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
      };
      final homeTheme = brightness == Brightness.dark
          ? AppTheme.dark
          : AppTheme.light;
      return Theme(
        data: homeTheme.copyWith(platform: Theme.of(context).platform),
        child: child!,
      );
    }

    return settings == null
        ? themed(context, child)
        : ListenableBuilder(
            listenable: settings,
            builder: themed,
            child: child,
          );
  }
}
