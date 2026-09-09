import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/shell/stream_day_separator.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/styleguide/styleguide_theme.dart';
import 'src/theme/app_theme.dart';

/// Offline review fixture: actual production dates plus the library styleguide.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool dark = false;
  bool narrow = false;
  bool large = false;
  bool rtl = false;
  bool reduced = false;
  bool plum = false;
  int jumps = 0;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: plum
        ? StyleguideTheme.plum.resolve(AppTheme.light)
        : dark
        ? AppTheme.dark
        : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Marker Review 3d0a')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                DButton(
                  onPressed: () => showComponentStyleguide(context),
                  label: const Text('Open styleguide'),
                ),
                DButton(
                  onPressed: () => setState(() => dark = !dark),
                  label: const Text('Light / dark'),
                ),
                DButton(
                  onPressed: () => setState(() => plum = !plum),
                  label: const Text('Plum palette'),
                ),
                DButton(
                  onPressed: () => setState(() => narrow = !narrow),
                  label: const Text('360px'),
                ),
                DButton(
                  onPressed: () => setState(() => large = !large),
                  label: const Text('200% text'),
                ),
                DButton(
                  onPressed: () => setState(() => rtl = !rtl),
                  label: const Text('RTL'),
                ),
                DButton(
                  onPressed: () => setState(() => reduced = !reduced),
                  label: const Text('Reduced motion'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Date jumps: $jumps'),
            Center(
              child: SizedBox(
                width: narrow ? 360 : 640,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(large ? 2 : 1),
                    disableAnimations: reduced,
                  ),
                  child: Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Column(
                      children: [
                        const Text(
                          'Actual StreamDaySeparator used by topic and Chat timelines',
                        ),
                        StreamDaySeparator(
                          day: DateTime(2026, 9, 8),
                          onTap: () => setState(() => jumps++),
                        ),
                        const Text('Local message before the date boundary.'),
                        StreamDaySeparator(
                          day: DateTime.now(),
                          onTap: () => setState(() => jumps++),
                        ),
                        const Text('Local message after the date boundary.'),
                        StreamDaySeparator(
                          day: DateTime.now(),
                          floating: true,
                          onTap: () => setState(() => jumps++),
                        ),
                        StreamDaySeparator(
                          day: DateTime.now(),
                          showDivider: false,
                        ),
                        const DMarker(
                          liveRegion: true,
                          icon: DMarkerIcon(
                            child: DSpinner(semanticLabel: null),
                          ),
                          child: DMarkerContent(
                            shimmer: true,
                            child: Text('Thinking...'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
