import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/shell/skeleton_fill.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Discourse's default schemes, as a site's CSS resolves them. The dark
  // scheme's --primary-very-low sits a few levels above its page.
  final discourseDark = ResolvedSitePalette.fromJson(const {
    'brightness': 'dark',
    'primary': 0xFFDDDDDD,
    'secondary': 0xFF222222,
    'tertiary': 0xFF099DD7,
    'primaryVeryLow': 0xFF282828,
    'primaryLow': 0xFF313131,
    'primaryLowMid': 0xFF7A7A7A,
    'contentBorderColor': 0xFF313131,
  });
  final discourseLight = ResolvedSitePalette.fromJson(const {
    'brightness': 'light',
    'primary': 0xFF222222,
    'secondary': 0xFFFFFFFF,
    'tertiary': 0xFF0088CC,
    'primaryVeryLow': 0xFFF8F8F8,
    'primaryLow': 0xFFE9E9E9,
    'primaryLowMid': 0xFFBDBDBD,
    'contentBorderColor': 0xFFE9E9E9,
  });

  testWidgets('placeholders stay visible at the pulse trough on every host', (
    tester,
  ) async {
    final themes = <String, ThemeData>{
      'app dark': AppTheme.dark,
      'app light': AppTheme.light,
      'Discourse dark': AppTheme.fromPalette(discourseDark),
      'Discourse light': AppTheme.fromPalette(discourseLight),
      for (final preset in forumThemePresets)
        for (final brightness in Brightness.values) ...{
          '${preset.id} ${brightness.name}': AppTheme.fromPalette(
            preset.resolve(brightness),
          ),
          // Darker sidebars give navigation a theme of its own.
          '${preset.id} ${brightness.name}, darker sidebars':
              AppTheme.fromPalette(
                preset.copyWith(darkerSidebars: true).resolve(brightness),
              ),
        },
    };
    for (final MapEntry(key: name, value: theme) in themes.entries) {
      // Each host's fill beside the colour that host paints beneath it.
      final hosts = <String, (Color, Color)>{};
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: theme,
          home: Column(
            children: [
              Builder(
                builder: (context) {
                  final tokens = DTokens.of(context);
                  final shell = Theme.of(context).shell;
                  final page = skeletonFill(context);
                  hosts['content page'] = (page, shell.content);
                  hosts['card'] = (page, tokens.background);
                  hosts['topic sidebar'] = (
                    skeletonFill(context, on: SkeletonSurface.panel),
                    shell.panel,
                  );
                  final floating = skeletonFill(
                    context,
                    on: SkeletonSurface.floating,
                  );
                  hosts['popover'] = (floating, tokens.surface);
                  // Reactors share one builder between hover cards and the
                  // touch sheet, which paints the page colour.
                  hosts['reactions sheet'] = (
                    floating,
                    Theme.of(context).bottomSheetTheme.modalBackgroundColor!,
                  );
                  return const SizedBox.shrink();
                },
              ),
              ForumSidebarTheme(
                child: Builder(
                  builder: (context) {
                    final tokens = DTokens.of(context);
                    hosts['navigation sidebar'] = (
                      skeletonFill(context, on: SkeletonSurface.panel),
                      tokens.muted,
                    );
                    final row = skeletonFill(context, on: SkeletonSurface.row);
                    hosts['idle sidebar row'] = (row, tokens.muted);
                    hosts['selected sidebar row'] = (row, tokens.hover);
                    // Popovers opened from the sidebar inherit its theme.
                    hosts['sidebar popover'] = (
                      skeletonFill(context, on: SkeletonSurface.floating),
                      tokens.surface,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      expect(hosts, hasLength(9), reason: name);
      for (final MapEntry(key: host, value: (fill, surface)) in hosts.entries) {
        // The pulse halves the fill's opacity. The UI kit's muted fill reached
        // only 1.02-1.05 there on dark pages, and matched sidebars and panels
        // exactly: they paint muted themselves.
        final trough = Color.alphaBlend(
          fill.withValues(alpha: fill.a / 2),
          surface,
        );
        expect(
          _contrast(trough, surface),
          greaterThanOrEqualTo(1.08),
          reason: '$host on $name',
        );
      }
    }
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + .05) / (darker + .05);
}
