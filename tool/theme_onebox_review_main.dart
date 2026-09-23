// Offline review of the production theme onebox; preferences stay in memory.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/styleguide/examples/onebox_theme_sample.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const ThemeOneboxReview());
}

class ThemeOneboxReview extends StatefulWidget {
  const ThemeOneboxReview({super.key});

  @override
  State<ThemeOneboxReview> createState() => _ThemeOneboxReviewState();
}

class _ThemeOneboxReviewState extends State<ThemeOneboxReview> {
  bool _dark = false;
  bool _narrow = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _dark ? AppTheme.dark : AppTheme.light,
    home: DFocusHighlight(
      child: DCard(
        child: Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.lg,
                  children: [
                    const Text('Theme sharing'),
                    Wrap(
                      spacing: DSpacing.controlGap,
                      children: [
                        DToggle(
                          pressed: _dark,
                          onPressedChanged: (value) =>
                              setState(() => _dark = value),
                          child: const Text('Dark forum'),
                        ),
                        DToggle(
                          pressed: _narrow,
                          onPressedChanged: (value) =>
                              setState(() => _narrow = value),
                          child: const Text('Narrow card'),
                        ),
                      ],
                    ),
                    const Text('Made a calmer theme for my daily reading.'),
                    SizedBox(
                      width: _narrow ? 320 : 410,
                      child: const OneboxThemeSample(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
