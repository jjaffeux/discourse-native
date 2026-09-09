import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/theme/app_theme.dart';

/// Runs the component examples without credentials, networking, or app stores.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) =>
          DToaster(child: child ?? const SizedBox.shrink()),
      home: const ComponentStyleguidePage(),
    ),
  );
}
