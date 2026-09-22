// Offline review of the production appearance preview.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_preview.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Review());
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review();

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  String palette = 'Dracula';
  bool narrow = false;
  bool large = false;

  @override
  Widget build(BuildContext context) {
    final theme = switch (palette) {
      'Light' => AppTheme.light,
      'Dark' => AppTheme.dark,
      _ => AppTheme.fromPalette(
        forumThemePresets
            .firstWhere((theme) => theme.id == 'dracula')
            .resolve(Brightness.dark),
      ),
    };
    return DFocusHighlight(
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Wrap(
                    spacing: DSpacing.controlGap,
                    children: [
                      for (final value in ['Light', 'Dark', 'Dracula'])
                        DButton(
                          label: Text(value),
                          onPressed: () => setState(() => palette = value),
                        ),
                      DButton(
                        label: const Text('Narrow'),
                        onPressed: () => setState(() => narrow = !narrow),
                      ),
                      DButton(
                        label: const Text('Large text'),
                        onPressed: () => setState(() => large = !large),
                      ),
                      DButton(
                        label: const Text('Styleguide'),
                        onPressed: () => showComponentStyleguide(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Center(
                        child: SizedBox(
                          width: narrow ? 340 : 900,
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.linear(large ? 2 : 1),
                            ),
                            child: ForumThemePreview(
                              theme: theme,
                              siteUrl: 'https://preview.invalid',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
