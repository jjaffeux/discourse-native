import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/color_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tinted palettes keep readable text and preserve authored colors', () {
    double contrast(Color a, Color b) {
      final luminances = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (luminances.last + .05) / (luminances.first + .05);
    }

    for (final source in forumThemePresets) {
      final authored = source.toJson();
      for (final color in [
        Colors.white,
        Colors.black,
        Colors.pink,
        Colors.lime,
      ]) {
        for (final mode in Brightness.values) {
          final modeColors = source.forBrightness(mode).toJson();
          final custom = ForumTheme.fromJson({
            ...modeColors,
            'background': ForumBackground(color: color, strength: 1).toJson(),
          }, id: 'custom');
          final palette = custom.resolve(mode);
          for (final foreground in [palette.primary, palette.metadataColor]) {
            expect(
              contrast(foreground, palette.secondary),
              greaterThanOrEqualTo(minimumTextContrastRatio),
              reason: '${source.id} $mode $color',
            );
          }
          expect(
            contrast(palette.selectedForeground, palette.selected),
            greaterThanOrEqualTo(minimumTextContrastRatio),
          );
          final zero = ForumTheme.fromJson({
            ...modeColors,
            'background': ForumBackground(color: color, strength: 0).toJson(),
          }, id: 'zero').resolve(mode).toJson()..remove('background');
          expect(zero, source.resolve(mode).toJson());
          expect(custom.toJson()['colors'], modeColors['colors']);
        }
      }
      expect(source.toJson(), authored);
    }
  });

  testWidgets(
    'custom controls fit narrow RTL and large text in both palettes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final brightness in Brightness.values) {
        for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.forBrightness(
                brightness,
              ).copyWith(platform: platform),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: DCard(
                      child: ForumThemeEditor(
                        theme: forumThemePresets.first,
                        brightness: brightness,
                        sources: const SizedBox.shrink(),
                        onSave: (_) async {},
                        onCancel: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('color-picker-inline-plane')),
            findsNWidgets(6),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$brightness $platform',
          );
        }
      }
    },
  );

  test('backgrounds survive storage, export, mode changes and resolution', () {
    for (final effect in ForumBackgroundEffect.values) {
      for (final strength in [0.0, .73, 1.0]) {
        final background = ForumBackground(
          color: const Color(0xff4714b2),
          effect: effect,
          strength: strength,
          noiseIntensity: .73,
          transparency: .17,
        );
        final theme = ForumTheme.fromJson({
          ...forumThemePresets.first.forBrightness(Brightness.light).toJson(),
          'background': background.toJson(),
        }, id: 'custom-background');
        expect(ForumTheme.fromJson(theme.toJson(), id: theme.id), theme);
        expect(
          ForumThemePreferences.fromJson(
            ForumThemePreferences().save(theme).toJson(),
          ).customTheme,
          theme,
        );
        for (final brightness in Brightness.values) {
          expect(theme.forBrightness(brightness).background, background);
          final palette = theme.resolve(brightness);
          expect(
            ResolvedSitePalette.fromJson(palette.toJson()).background,
            background,
          );
          expect(
            AppTheme.fromPalette(
              palette,
            ).extension<ForumThemeEffects>()!.background,
            background,
          );
        }
      }
    }
    expect(forumThemePresets.first.background, isNull);
    const valid = ForumBackground(color: Colors.blue);
    for (final value in [-.1, 1.1, double.nan, '73']) {
      expect(
        () => ForumBackground.fromJson({...valid.toJson(), 'strength': value}),
        throwsFormatException,
      );
    }
    expect(
      () => ForumBackground.fromJson({...valid.toJson(), 'effect': 'unknown'}),
      throwsFormatException,
    );
    expect(
      () => ForumBackground.fromJson({...valid.toJson(), 'color': '#broken'}),
      throwsFormatException,
    );
  });

  test('legacy backgrounds use subtle defaults and reject unsafe values', () {
    const valid = ForumBackground(color: Colors.blue);
    final legacy = valid.toJson()
      ..remove('noiseIntensity')
      ..remove('transparency');
    expect(ForumBackground.fromJson(legacy).noiseIntensity, .2);
    expect(ForumBackground.fromJson(legacy).transparency, .1);
    for (final key in ['noiseIntensity', 'transparency']) {
      for (final invalid in [
        null,
        -.1,
        1.1,
        double.nan,
        double.infinity,
        '20',
      ]) {
        expect(
          () => ForumBackground.fromJson({...valid.toJson(), key: invalid}),
          throwsFormatException,
          reason: '$key: $invalid',
        );
      }
    }
    expect(
      () => ForumBackground.fromJson({...valid.toJson(), 'transparency': .31}),
      throwsFormatException,
    );
  });

  testWidgets(
    'panel transparency updates independently with opaque footers at zero',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final transparency in [0.0, .1, .2]) {
          final custom = ForumTheme.fromJson({
            ...forumThemePresets.first.forBrightness(brightness).toJson(),
            'background': ForumBackground(
              color: Colors.purple,
              effect: ForumBackgroundEffect.noise,
              transparency: transparency,
            ).toJson(),
          }, id: 'custom-panels');
          Color? panel;
          Color? footer;
          Color? nested;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.fromPalette(custom.resolve(brightness)),
              home: ForumWindowBackground(
                child: Builder(
                  builder: (context) {
                    panel = ForumWindowBackground.panelColor(context);
                    footer = ForumWindowBackground.footerColor(
                      context,
                      Colors.blue,
                    );
                    return ForumWindowBackground(
                      child: Builder(
                        builder: (context) {
                          nested = ForumWindowBackground.panelColor(context);
                          return const SizedBox.expand();
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(panel!.a, closeTo(1 - transparency, .001));
          expect(footer!.a, closeTo(1 - transparency * .25, .001));
          expect(nested, panel);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'inline palette accepts drag and keyboard, honors disabled and rejected edits',
    (tester) async {
      var color = const Color(0xff4714b2);
      var enabled = true;
      var accept = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return DColorPicker.inline(
                    value: color,
                    semanticLabel: 'Background palette',
                    onChanged: enabled
                        ? (value) {
                            if (accept) setState(() => color = value);
                          }
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      );
      final plane = find.byKey(const ValueKey('color-picker-inline-plane'));
      expect(tester.getSize(plane).width, 320);
      await tester.dragFrom(
        tester.getTopLeft(plane) + const Offset(60, 60),
        const Offset(120, 20),
      );
      await tester.pump();
      expect(color, isNot(const Color(0xff4714b2)));
      final before = HSLColor.fromColor(color);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(HSLColor.fromColor(color).hue, greaterThan(before.hue));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        HSLColor.fromColor(color).lightness,
        greaterThan(before.lightness),
      );
      final accepted = color;
      update(() => accept = false);
      await tester.pump();
      await tester.tapAt(tester.getTopLeft(plane) + const Offset(10, 10));
      await tester.pump();
      expect(
        tester.widget<DColorPicker>(find.byType(DColorPicker)).value,
        accepted,
      );
      update(() {
        enabled = false;
        accept = true;
      });
      await tester.pump();
      await tester.tapAt(tester.getCenter(plane));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(color, accepted);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filled strength slider supports drag, keyboard and endpoints', (
    tester,
  ) async {
    var value = 50.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            height: 136,
            child: StatefulBuilder(
              builder: (context, setState) => DSlider(
                variant: DSliderVariant.filled,
                orientation: Axis.vertical,
                value: value,
                semanticLabel: 'Strength',
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DSlider));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(value, 51);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(value, 100);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(value, 0);
    await tester.dragFrom(
      tester.getCenter(find.byType(DSlider)),
      const Offset(0, -30),
    );
    await tester.pump();
    expect(value, greaterThan(50));
  });

  testWidgets('only nonzero lava animates and reduced motion stops it', (
    tester,
  ) async {
    Future<void> show(
      ForumBackgroundEffect effect, {
      bool reduced = false,
      double strength = .7,
    }) async {
      final theme = ForumTheme.fromJson({
        ...forumThemePresets.first.forBrightness(Brightness.dark).toJson(),
        'background': ForumBackground(
          color: Colors.purple,
          strength: strength,
          effect: effect,
        ).toJson(),
      }, id: 'custom-motion');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromPalette(theme.resolve(Brightness.dark)),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const ForumWindowBackground(
              child: ForumWindowBackground(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    await show(ForumBackgroundEffect.lava);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      ),
      findsOneWidget,
      reason: 'Nested mobile shells must share one effect painter.',
    );
    expect(tester.binding.hasScheduledFrame, isTrue);
    await show(ForumBackgroundEffect.lava, reduced: true);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await show(ForumBackgroundEffect.noise);
    await tester.pumpAndSettle();
    await show(ForumBackgroundEffect.normal);
    await tester.pumpAndSettle();
    await show(ForumBackgroundEffect.lava, strength: 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
