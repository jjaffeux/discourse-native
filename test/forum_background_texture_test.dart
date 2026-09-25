import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_texture.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Paper and Lava lamp are visible at maximum intensity', (
    tester,
  ) async {
    Future<Uint8List> capture(
      ForumBackgroundEffect effect,
      double intensity,
    ) async {
      final palette = forumThemePresets.first
          .forBrightness(Brightness.dark)
          .copyWith(
            background: ForumBackground.appearance(
              effect: effect,
              noiseIntensity: intensity,
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromPalette(palette.resolve(Brightness.dark)),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(
              child: RepaintBoundary(
                key: ValueKey('texture-capture'),
                child: SizedBox.square(
                  dimension: 256,
                  child: ForumWindowBackground(child: SizedBox.expand()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (intensity == 0 ||
            find
                .byKey(const ValueKey('forum-reference-texture'))
                .evaluate()
                .isNotEmpty) {
          break;
        }
      }
      if (intensity > 0) {
        expect(tester.takeException(), isNull);
        expect(find.byType(ForumTexture), findsOneWidget);
        expect(
          find.byKey(const ValueKey('forum-reference-texture')),
          findsOneWidget,
        );
      }
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('texture-capture')),
      );
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();
        return bytes;
      }))!;
    }

    for (final effect in [
      ForumBackgroundEffect.paper,
      ForumBackgroundEffect.lava,
    ]) {
      final plain = await capture(effect, 0);
      final textured = await capture(effect, 1);
      var difference = 0;
      for (var i = 0; i < plain.length; i++) {
        difference += (plain[i] - textured[i]).abs();
      }
      expect(
        difference / plain.length,
        greaterThan(effect == ForumBackgroundEffect.paper ? 0.2 : 1),
        reason: '$effect',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
