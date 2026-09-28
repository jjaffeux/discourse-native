import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/theme/app_theme.dart';

/// Runs the component examples without credentials or app stores.
/// Onebox samples may load public images or media after selection.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) => DFocusHighlight(
        child: DToaster(child: child ?? const SizedBox.shrink()),
      ),
      home: const ComponentStyleguidePage(),
    ),
  );
}
