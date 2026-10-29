import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_picker.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['PRESENTATION_POLISH_RENDER_DIR'] == null) return;
    for (final (family, asset) in [
      ('Lato', 'Lato-Regular.ttf'),
      ('Open Sans', 'OpenSans.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$asset'))).load();
    }
  });

  testWidgets(
    'palette families keep the same order in both modes, custom first',
    (tester) async {
      List<Object>? lightOrder;
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await _pump(tester, brightness: brightness);
        final choices = tester.widgetList<DItem>(find.byType(DItem)).toList();
        final order = [
          for (final row in choices) (row.key! as ValueKey<Object>).value,
        ];
        expect(order.take(5), [
          ('theme-choice', 'custom-mint'),
          ('theme-choice', 'custom-sunset'),
          ('theme-choice', 'forum'),
          ('theme-choice', 'discourse'),
          ('theme-choice', 'neutral'),
        ]);
        if (lightOrder == null) {
          lightOrder = order;
        } else {
          expect(order, lightOrder);
        }
        await _capture(tester, 'palette-${brightness.name}');
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'status safe area has a solid app ground with ${brightness.name} effects',
      (tester) async {
        for (final effect in [
          ForumBackgroundEffect.gradient,
          ForumBackgroundEffect.hatch,
        ]) {
          await _pump(tester, brightness: brightness, effect: effect);
          final ground = find.byKey(const ValueKey('mobile-status-bar-ground'));
          final color = DTokens.of(tester.element(ground)).wellFill;
          expect(tester.getRect(ground), const Rect.fromLTWH(0, 0, 390, 47));
          final heading = find.text('Themes');
          expect(tester.getRect(heading).top, greaterThanOrEqualTo(47));
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            final image = await boundary.toImage();
            try {
              final pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              for (final point in [
                const Offset(5, 5),
                const Offset(195, 23),
                const Offset(384, 46),
              ]) {
                final offset =
                    (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
                for (final (channel, expected) in [
                  color.r,
                  color.g,
                  color.b,
                  1.0,
                ].indexed) {
                  expect(
                    pixels.getUint8(offset + channel),
                    closeTo(expected * 255, 1),
                  );
                }
              }
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  ForumBackgroundEffect effect = ForumBackgroundEffect.gradient,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
  final base = forumThemePresets.first;
  final preferences = ForumThemePreferences(
    customThemes: [
      base.copyWith(id: 'custom-mint', name: 'Harbor mint'),
      base.copyWith(id: 'custom-sunset', name: 'Evening sail'),
    ],
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(
        base
            .resolve(brightness)
            .withEffects(
              ForumBackground.appearance(effect: effect, noiseIntensity: .4),
            ),
        fontFamily: 'Lato',
      ).copyWith(platform: TargetPlatform.iOS),
      home: MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(disableAnimations: true),
        child: RepaintBoundary(
          key: const ValueKey('capture'),
          child: ForumWindowBackground(
            mobile: true,
            child: SafeArea(
              child: DPageSurface.headed(
                title: const Text('Themes'),
                child: DScrollArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ForumThemePicker(
                      preferences: preferences,
                      forum: base.copyWith(id: 'forum', name: 'Forum default'),
                      brightness: brightness,
                      onForum: () {},
                      onPreset: (_, _) {},
                      onTheme: (_) {},
                      onNewTheme: ({base}) {},
                      onEdit: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['PRESENTATION_POLISH_RENDER_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
