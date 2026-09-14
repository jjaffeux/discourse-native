import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/finders.dart';
import 'support/pixel_samples.dart';

void main() {
  group('DIcon', () {
    testWidgets('every bundled icon renders', (tester) async {
      // A malformed generated or app-specific SVG fails at parse time, inside
      // a future, where nothing else would notice.
      final icons = {...DIcons.byName.values, ...DNativeIcons.byName.values};
      for (final icon in icons) {
        await tester.pumpWidget(
          MaterialApp(home: Center(child: DIcon(icon, size: 24))),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: '${icon.name} did not render',
        );
        expect(find.dIcon(icon), findsOneWidget);
      }
    });

    testWidgets('sizes to the box it is given, not the viewBox', (
      tester,
    ) async {
      // `hand-point-right` is 448x512, so a widget that passed the viewBox
      // through would not be square.
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: DIcon(DIcons.handPointRight, size: 32)),
        ),
      );

      expect(
        tester.getSize(find.dIcon(DIcons.handPointRight)),
        const Size(32, 32),
      );
    });

    testWidgets('takes its size from IconTheme without a paint-time filter', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IconTheme(
            data: IconThemeData(size: 18, color: Color(0xFF00FF00)),
            child: Center(child: DIcon(DIcons.gear)),
          ),
        ),
      );

      expect(tester.getSize(find.dIcon(DIcons.gear)), const Size(18, 18));
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        picture.colorFilter,
        isNull,
        reason: 'runtime SVG color filters paint through Canvas.saveLayer',
      );
    });

    testWidgets('bakes the tint into the picture without a paint-time layer', (
      tester,
    ) async {
      const boundaryKey = ValueKey('tinted-icon-boundary');
      const iconWithoutRootFill = DIconData(
        'icon-without-root-fill',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
            '<circle cx="8" cy="8" r="8"/></svg>',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: ColoredBox(
            color: Colors.white,
            child: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: DIcon(
                  iconWithoutRootFill,
                  size: 32,
                  color: Color(0xFF00FF00),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(picture.colorFilter, isNull);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final centerPixel = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final center =
              (image.width * (image.height ~/ 2) + image.width ~/ 2) * 4;
          return pixels!.buffer.asUint8List(center, 4);
        } finally {
          image.dispose();
        }
      }))!;
      expect(centerPixel, [0, 255, 0, 255]);
    });

    test('aliases resolve to the icon Discourse maps them to', () {
      expect(DIcons.byName['d-liked'], DIcons.heart);
      expect(DIcons.byName['d-unliked'], DIcons.farHeart);
      expect(DIcons.byName['topic.closed'], DIcons.lock);
      expect(DIcons.byName['notification.mentioned'], DIcons.at);
    });

    testWidgets('AI badge keeps its fixed artwork across theme changes', (
      tester,
    ) async {
      const key = ValueKey('ai-icon');
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Center(
              child: RepaintBoundary(
                key: key,
                child: DIcon(
                  DIcons.discourseAi,
                  size: 128,
                  color: Color(0xFFFF0000),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final colors = await samplePixels(tester, find.byKey(key), const [
          Offset(64, 30), // Background above the lettering.
          Offset(83, 46), // Top bar of the I.
          Offset.zero, // Outside the rounded artwork.
        ]);
        expect(colors, const [
          Color(0xFF333333),
          Colors.white,
          Colors.transparent,
        ]);
        expect(DIcons.discourseAi.preserveColors, isTrue);
        expect(
          tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
          isNull,
        );
      }
    });

    testWidgets('preserves SVG colors, palette changes and icon opacity', (
      tester,
    ) async {
      const key = ValueKey('preserved-colors');
      const icon = DIconData(
        'palette-test',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 10">'
            '<path d="M0 0h10v10H0z"/>'
            '<path d="M10 0h10v10H10z" fill="#ff6600"/>'
            '<path d="M20 0h10v10H20z" fill="var(--secondary)"/>'
            '<path d="M30 0h10v10H30z" fill="var(--tertiary)"/>'
            '<path d="M40 0h10v10H40z" fill="var(--danger)"/>'
            '<path d="M50 0h10v10H50z" fill="var(--custom-color, #123456)"/>'
            '</svg>',
        preserveColors: true,
      );
      for (final brightness in Brightness.values) {
        final theme = ThemeData(brightness: brightness);
        for (final opacity in [1.0, 0.5]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: IconTheme(
                data: IconThemeData(
                  color: const Color(0xFF00FF00),
                  opacity: opacity,
                ),
                child: const Center(
                  child: RepaintBoundary(
                    key: key,
                    child: DIcon(icon, size: 60),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          final samples = (await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba,
              ))!.buffer.asUint8List();
              return [
                for (var i = 0; i < 6; i++)
                  bytes.sublist(
                    (30 * image.width +
                            (3.75 + (i * 10 + 5) * DIcon.glyphScale).floor()) *
                        4,
                    (30 * image.width +
                                (3.75 + (i * 10 + 5) * DIcon.glyphScale)
                                    .floor()) *
                            4 +
                        4,
                  ),
              ];
            } finally {
              image.dispose();
            }
          }))!;
          final colors = [
            const Color(0xFF00FF00),
            const Color(0xFFFF6600),
            theme.colorScheme.surface,
            theme.colorScheme.primary,
            theme.colorScheme.error,
            const Color(0xFF123456),
          ];
          for (var i = 0; i < colors.length; i++) {
            final color = colors[i];
            final expected = [
              (color.r * 255).round(),
              (color.g * 255).round(),
              (color.b * 255).round(),
              (opacity * 255).round(),
            ];
            for (var channel = 0; channel < 4; channel++) {
              expect(
                samples[i][channel],
                closeTo(expected[channel], 1),
                reason:
                    '$brightness opacity $opacity paint $i channel $channel',
              );
            }
          }
          expect(
            tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
            isNull,
          );
        }
      }
    });

    test('core catalog excludes optional plugin resources and aliases', () {
      for (final name in const [
        'discourse-sparkles',
        'gif',
        'square-poll-horizontal',
        'd-chat',
      ]) {
        expect(DIcons.byName, isNot(contains(name)), reason: name);
      }
    });
  });
}
