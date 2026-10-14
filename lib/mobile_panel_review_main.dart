import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'src/models/forum_background.dart';
import 'src/models/forum_theme_presets.dart';
import 'src/shell/forum_theme_surfaces.dart';
import 'src/theme/app_theme.dart';
import 'src/theme/d_icons.dart';

/// Account-free phone panel fixture. Saves native surface captures in /tmp.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MobilePanelReview());
}

class MobilePanelReview extends StatefulWidget {
  const MobilePanelReview({super.key});
  @override
  State<MobilePanelReview> createState() => _MobilePanelReviewState();
}

class _MobilePanelReviewState extends State<MobilePanelReview> {
  final _capture = GlobalKey();
  Brightness _brightness = Brightness.dark;
  DAppearanceMaterial _material = DAppearanceMaterial.standard;
  double _transparency = 0;
  bool _pushed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_save()));
  }

  Future<void> _save() async {
    if (Platform.isMacOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
    }
    if (!const bool.fromEnvironment('MOBILE_PANEL_CAPTURE')) return;
    for (final brightness in Brightness.values) {
      for (final material in DAppearanceMaterial.values) {
        for (final transparency in [0.0, .3]) {
          for (final pushed in [false, true]) {
            setState(() {
              _brightness = brightness;
              _material = material;
              _transparency = transparency;
              _pushed = pushed;
            });
            await Future<void>.delayed(const Duration(milliseconds: 400));
            await WidgetsBinding.instance.endOfFrame;
            final boundary =
                _capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            boundary.markNeedsPaint();
            WidgetsBinding.instance.scheduleFrame();
            await WidgetsBinding.instance.endOfFrame;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final path =
                '${Directory.systemTemp.path}/discourse-phone-panel-'
                '${brightness.name}-${material.name}-'
                '${transparency == 0 ? 'opaque' : 'translucent'}-'
                '${pushed ? 'reader' : 'root'}.png';
            await File(path).writeAsBytes(bytes!.buffer.asUint8List());
            debugPrint('PHONE_PANEL_CAPTURE $path');
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = forumThemePresets
        .firstWhere((theme) => theme.id == 'dracula')
        .forBrightness(_brightness)
        .copyWith(
          background: ForumBackground.appearance(transparency: _transparency),
        );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: DMaterialTheme.apply(
        AppTheme.fromPalette(palette.resolve(_brightness)),
        _material,
      ),
      home: Center(
        child: RepaintBoundary(
          key: _capture,
          child: SizedBox(
            width: 390,
            height: 844,
            child: ForumWindowBackground(
              child: Builder(
                builder: (context) {
                  final tokens = DTokens.of(context);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                        child: Row(
                          children: [
                            DButton.iconOnly(
                              icon: const DIcon(DIcons.barsStaggered),
                              tooltip: 'Menu',
                              variant: DButtonVariant.inline,
                              onPressed: () {},
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Discourse',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const Spacer(),
                            DButton.iconOnly(
                              icon: const DIcon(DIcons.magnifyingGlass),
                              tooltip: 'Search',
                              variant: DButtonVariant.inline,
                              onPressed: () {},
                            ),
                            DButton.iconOnly(
                              icon: const DIcon(DIcons.bell),
                              tooltip: 'Notifications',
                              variant: DButtonVariant.inline,
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ForumMobileSurface(
                          child: DPageSurface(
                            framed: false,
                            header: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                16,
                              ),
                              child: Text(
                                _pushed ? 'Topic reader' : 'Latest topics',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.foreground,
                                ),
                              ),
                            ),
                            headerControls: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                spacing: 8,
                                children: [
                                  for (final label in [
                                    'Latest',
                                    'Categories',
                                    'Tags',
                                  ])
                                    DButton(
                                      variant: DButtonVariant.secondary,
                                      onPressed: () {},
                                      label: Text(label),
                                    ),
                                ],
                              ),
                            ),
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                for (final title in [
                                  "What's everyone's sourdough hydration sweet spot?",
                                  'Leeds starter swap and bake-off at The Crown',
                                  'Starter maintenance when you bake twice a week',
                                  'Name one thing you own that you would truly miss',
                                  'Starting over with habits',
                                ]) ...[
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: tokens.foreground,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Community discussions, ideas and experiences.',
                                    style: TextStyle(
                                      color: tokens.mutedForeground,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const DSeparator(),
                                  const SizedBox(height: 16),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
