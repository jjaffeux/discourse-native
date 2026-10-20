import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone pages and sidebar paint one surface over window chrome', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final material in DAppearanceMaterial.values) {
        for (final transparency in [0.0, .3]) {
          for (final (highContrast, sidebar) in [
            (false, false),
            (true, false),
            (false, true),
            (true, true),
          ]) {
            late Color fill;
            final surface = sidebar
                ? ForumMobileSurface.sidebar
                : ForumMobileSurface.new;
            const backdrop = Color(0xff143c68);
            final palette = forumThemePresets
                .firstWhere((theme) => theme.id == 'dracula')
                .forBrightness(brightness)
                .copyWith(
                  background: ForumBackground.appearance(
                    transparency: transparency,
                  ),
                );
            await tester.pumpWidget(
              MaterialApp(
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: DMaterialTheme.apply(
                  AppTheme.fromPalette(palette.resolve(brightness)),
                  material,
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    highContrast: highContrast,
                    disableAnimations: true,
                  ),
                  child: Center(
                    child: ForumWindowBackground(
                      child: Builder(
                        builder: (context) {
                          fill = ForumWindowBackground.panelColor(context)!;
                          return RepaintBoundary(
                            key: const ValueKey('phone-panel-pixels'),
                            child: ColoredBox(
                              color: backdrop,
                              child: SizedBox(
                                width: 240,
                                height: 360,
                                child: Column(
                                  children: [
                                    const SizedBox(height: 48),
                                    Expanded(
                                      child: surface(
                                        child: Builder(
                                          builder: (context) => ColoredBox(
                                            // Inner pages let the owner paint once.
                                            color:
                                                ForumWindowBackground.surfaceColor(
                                                  context,
                                                  Colors.red,
                                                ),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('phone-panel-pixels')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                void pixel(int x, int y, Color expected) {
                  final offset = (y * image.width + x) * 4;
                  for (final (channel, value) in [
                    expected.r,
                    expected.g,
                    expected.b,
                  ].indexed) {
                    expect(
                      bytes.getUint8(offset + channel),
                      closeTo(value * 255, 2),
                      reason:
                          '$brightness $material $transparency '
                          'contrast=$highContrast sidebar=$sidebar ($x,$y)',
                    );
                  }
                }

                final base = Color.alphaBlend(fill, backdrop);
                pixel(120, 20, backdrop); // Header stays on the window ground.
                pixel(120, 250, base); // Reading area owns a filled panel.
                for (final x in [1, 238]) {
                  pixel(x, 49, backdrop);
                  pixel(x, 358, backdrop);
                }
                if (highContrast) {
                  if (!sidebar) {
                    pixel(20, 52, base);
                    pixel(219, 52, base);
                  }
                } else {
                  final rim = Color.alphaBlend(
                    Colors.white.withValues(
                      alpha: brightness == Brightness.dark ? .14 : .75,
                    ),
                    base,
                  );
                  final softRim = Color.alphaBlend(
                    Colors.white.withValues(
                      alpha:
                          (brightness == Brightness.dark ? .12 : .55) *
                          1.6 *
                          .25,
                    ),
                    rim,
                  );
                  for (final (channel, bounds) in [
                    (rim.r, softRim.r),
                    (rim.g, softRim.g),
                    (rim.b, softRim.b),
                  ].indexed) {
                    expect(
                      bytes.getUint8(250 * image.width * 4 + channel),
                      inInclusiveRange(
                        bounds.$1 * 255 - 2,
                        bounds.$2 * 255 + 2,
                      ),
                    );
                  }
                  pixel(
                    120,
                    68,
                    Color.alphaBlend(
                      Colors.white.withValues(
                        alpha:
                            (brightness == Brightness.dark ? .066 : .5) *
                            (1 - 20.5 / 140),
                      ),
                      base,
                    ),
                  );
                  if (!sidebar) {
                    for (final x in [20, 219]) {
                      pixel(
                        x,
                        52,
                        Color.alphaBlend(
                          Colors.white.withValues(
                            alpha:
                                (brightness == Brightness.dark ? .066 : .5) *
                                (1 - 4.5 / 140),
                          ),
                          base,
                        ),
                      );
                    }
                  }
                }
              } finally {
                image.dispose();
              }
            });
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
}
