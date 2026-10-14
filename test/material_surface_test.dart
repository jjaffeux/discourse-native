import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/shell/forum_appearance_effects.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

void main() {
  testWidgets('opacity control reports the panel and native ground ceilings', (
    tester,
  ) async {
    for (final material in DAppearanceMaterial.values) {
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationStyle: AnimationStyle.noAnimation,
          theme: DMaterialTheme.apply(AppTheme.dark, material),
          home: Material(
            child: ForumAppearanceEffects(
              effects: const ForumBackground.appearance(transparency: .3),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(
        find.text(material == DAppearanceMaterial.liquidGlass ? '35%' : '60%'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('plain and translucent panels retain the same palette tint', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final material in DAppearanceMaterial.values) {
        for (final transparency in [0.0, .3]) {
          for (final reduced in [false, true]) {
            Color? panel;
            late Color expected;
            await tester.pumpWidget(
              MaterialApp(
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: DMaterialTheme.apply(
                  AppTheme.forBrightness(
                    brightness,
                    background: ForumBackground.appearance(
                      transparency: transparency,
                    ),
                  ),
                  material,
                ),
                home: MediaQuery(
                  data: MediaQueryData(highContrast: reduced),
                  child: ForumWindowBackground(
                    child: Builder(
                      builder: (context) {
                        final tokens = DTokens.of(context);
                        expected = Color.lerp(
                          tokens.background,
                          tokens.foreground,
                          .03,
                        )!;
                        panel = ForumWindowBackground.panelColor(context);
                        return const SizedBox.expand();
                      },
                    ),
                  ),
                ),
              ),
            );
            final alpha = reduced || transparency == 0 ? 1.0 : .6;
            expect(panel, expected.withValues(alpha: alpha));
            final canvas = tester.widget<DecoratedBox>(
              find.byKey(const ValueKey('forum-window-canvas')),
            );
            if (transparency == 0 && material == DAppearanceMaterial.standard) {
              final tokens = DTokens.of(
                tester.element(find.byType(Builder).last),
              );
              expect(
                (canvas.decoration as BoxDecoration).color,
                Color.lerp(tokens.background, Colors.black, .14),
              );
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });

  for (final material in DAppearanceMaterial.values) {
    testWidgets('panel rim stays uniform while its top highlight fades ($material)', (
      tester,
    ) async {
      const backdrop = Color(0xff153d99);
      const fill = Color(0x99333643);
      for (final dark in [false, true]) {
        for (final height in [240.0, 560.0]) {
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: DMaterialTheme.apply(
                dark ? AppTheme.dark : AppTheme.light,
                material,
              ),
              home: Center(
                child: RepaintBoundary(
                  key: const ValueKey('panel-paint'),
                  child: SizedBox(
                    width: 200,
                    height: height,
                    child: const ColoredBox(
                      color: backdrop,
                      child: DCard(
                        border: false,
                        spacing: 0,
                        backgroundColor: fill,
                        child: Expanded(child: SizedBox.expand()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('panel-paint')),
                )
                .toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final base = Color.alphaBlend(fill, backdrop);
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
                    reason: '$dark $height ($x,$y)',
                  );
                }
              }

              pixel(100, 200, base);
              pixel(
                100,
                20,
                Color.alphaBlend(
                  Colors.white.withValues(
                    alpha: (dark ? .066 : .5) * (1 - 20.5 / 140),
                  ),
                  base,
                ),
              );
              // The constant rim receives a small contribution from the
              // blurred inset shadow at both vertical edges. GPU blur kernels
              // vary slightly, so bound that contribution and check constancy.
              final sideBase = Color.alphaBlend(
                Colors.white.withValues(alpha: dark ? .14 : .75),
                base,
              );
              final sideLit = Color.alphaBlend(
                Colors.white.withValues(
                  alpha: (dark ? .12 : .55) * 1.6 * .25,
                ),
                sideBase,
              );
              for (final (channel, bounds) in [
                (sideBase.r, sideLit.r),
                (sideBase.g, sideLit.g),
                (sideBase.b, sideLit.b),
              ].indexed) {
                final value = bytes.getUint8(200 * image.width * 4 + channel);
                expect(
                  value,
                  inInclusiveRange(bounds.$1 * 255 - 2, bounds.$2 * 255 + 2),
                );
                expect(
                  bytes.getUint8(160 * image.width * 4 + channel),
                  closeTo(value, 1),
                );
              }
              // The top adds the reference's soft inset 0 1px 1px catch.
              final topBase = Color.alphaBlend(
                Colors.white.withValues(alpha: dark ? .14 : .75),
                Color.alphaBlend(
                  Colors.white.withValues(
                    alpha: (dark ? .066 : .5) * (1 - .5 / 140),
                  ),
                  base,
                ),
              );
              final topLit = Color.alphaBlend(
                Colors.white.withValues(alpha: (dark ? .12 : .55) * 1.6),
                topBase,
              );
              const offset = 100 * 4;
              for (final (channel, bounds) in [
                (topBase.r, topLit.r),
                (topBase.g, topLit.g),
                (topBase.b, topLit.b),
              ].indexed) {
                expect(
                  bytes.getUint8(offset + channel),
                  inInclusiveRange(bounds.$1 * 255 + 1, bounds.$2 * 255 + 2),
                );
              }
              pixel(0, 0, backdrop);
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        }
      }
    });
  }

  testWidgets('recessed actions paint inner depth and leave no outer shadow', (
    tester,
  ) async {
    final shadowsDisabled = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final material in DAppearanceMaterial.values) {
        for (final brightness in Brightness.values) {
          final dark = brightness == Brightness.dark;
          final canvas = dark
              ? const Color(0xff404458)
              : const Color(0xffdadfe8);
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: DMaterialTheme.apply(
                AppTheme.forBrightness(brightness),
                material,
              ),
              home: Center(
                child: RepaintBoundary(
                  key: const ValueKey('inset-action'),
                  child: SizedBox.square(
                    dimension: 80,
                    child: ColoredBox(
                      color: canvas,
                      child: Center(
                        child: DButton.iconOnly(
                          variant: DButtonVariant.recessed,
                          shape: DButtonShape.pill,
                          size: DControlSize.documentTab,
                          icon: const SizedBox.shrink(),
                          tooltip: 'All tabs',
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final surface = tester.widget<DMaterialSurface>(
            find.byType(DMaterialSurface),
          );
          expect(surface.depth, DSurfaceDepth.recessed);
          expect(tester.getSize(find.byType(DButton)), const Size.square(35));
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('inset-action')),
                )
                .toImage(pixelRatio: 2);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              Color pixel(double x, double y) {
                final offset =
                    ((y * 2).floor() * image.width + (x * 2).floor()) * 4;
                return Color.fromARGB(
                  bytes.getUint8(offset + 3),
                  bytes.getUint8(offset),
                  bytes.getUint8(offset + 1),
                  bytes.getUint8(offset + 2),
                );
              }

              for (final (x, y) in [
                (40.0, 21.0),
                (40.0, 59.0),
                (21.0, 40.0),
                (59.0, 40.0),
                (24.0, 24.0),
              ]) {
                expect(
                  pixel(x, y),
                  canvas,
                  reason: '$material $brightness outside ($x, $y)',
                );
              }
              final center = pixel(40, 40).computeLuminance();
              expect(center, lessThan(canvas.computeLuminance()));
              expect(
                pixel(40, 23.5).computeLuminance(),
                lessThan(center),
                reason: '$material $brightness top shadow',
              );
              expect(
                pixel(40, 57).computeLuminance(),
                greaterThan(center),
                reason: '$material $brightness bottom rim',
              );
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      debugDisableShadows = shadowsDisabled;
    }
  });

  testWidgets('bounded panels leave the canvas clear outside rounded corners', (
    tester,
  ) async {
    const canvas = Color(0xff153d99);
    final shadowsDisabled = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final material in DAppearanceMaterial.values) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: DMaterialTheme.apply(
                AppTheme.forBrightness(brightness),
                material,
              ),
              home: const Center(
                child: RepaintBoundary(
                  key: ValueKey('panel-corners'),
                  child: SizedBox.square(
                    dimension: 96,
                    child: ColoredBox(
                      color: canvas,
                      // The workspace bounds clip overflowing page shadows.
                      child: DResizablePanelGroup(
                        children: [
                          DResizablePanel(
                            id: 'page',
                            child: DCard(
                              border: false,
                              spacing: 0,
                              backgroundColor: Color(0xcc2154c1),
                              borderRadius: BorderRadius.all(
                                Radius.circular(16),
                              ),
                              child: Expanded(child: SizedBox.expand()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('panel-corners')),
                )
                .toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            for (final (x, y) in [(0, 0), (95, 0), (0, 95), (95, 95)]) {
              final offset = (y * image.width + x) * 4;
              expect(bytes.buffer.asUint8List(offset, 4), [
                0x15,
                0x3d,
                0x99,
                0xff,
              ], reason: '$material $brightness corner ($x, $y)');
            }
            // The fix must keep the translucent page fill itself.
            final center = (48 * image.width + 48) * 4;
            expect(bytes.getUint8(center + 2), greaterThan(0x99));
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      debugDisableShadows = shadowsDisabled;
    }
  });

  test(
    'material migrates independently of fonts, textures and opacity',
    () async {
      for (final version in [1, 2]) {
        final old = SharedAppearance.fromJson({
          'version': version,
          'effects': const ForumBackground.appearance(
            transparency: .3,
            effect: ForumBackgroundEffect.paper,
          ).toJson(),
        });
        expect(old.material, DAppearanceMaterial.standard);
        final chosen = old.copyWith(material: DAppearanceMaterial.liquidGlass);
        expect(chosen.effects, old.effects);
        final store = ForumSettingsStore.memory();
        final settings = ForumSettingsController(store: store);
        await settings.setShared(chosen);
        expect(await store.loadAppearance(), chosen);
        final restored = ForumSettingsController(store: store);
        await restored.loadShared([]);
        expect(restored.shared.material, DAppearanceMaterial.liquidGlass);
        settings.dispose();
        restored.dispose();
      }
      expect(
        SharedAppearance.fromJson(const {
          'version': 3,
          'material': 'damaged',
        }).material,
        DAppearanceMaterial.standard,
      );
    },
  );

  testWidgets(
    'both materials preserve visible control targets, gaps and disabled actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final mode in DAppearanceMaterial.values) {
        for (final brightness in Brightness.values) {
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: DMaterialTheme.apply(
                AppTheme.forBrightness(brightness),
                mode,
              ),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Center(
                  child: Wrap(
                    spacing: 12,
                    children: [
                      DButton(
                        key: const ValueKey('action'),
                        label: const Text('Reply'),
                        onPressed: () => taps++,
                      ),
                      const DButton(
                        key: ValueKey('disabled'),
                        label: Text('Disabled'),
                        onPressed: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final action = find.byKey(const ValueKey('action'));
          final rect = tester.getRect(action);
          await tester.tapAt(rect.center);
          await tester.tapAt(Offset(rect.left - 1, rect.center.dy));
          await tester.tapAt(Offset(rect.right + 1, rect.center.dy));
          await tester.tap(find.byKey(const ValueKey('disabled')));
          expect(taps, 1, reason: '$mode $brightness');
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('switching material retains an unsaved editor and its focus', (
    tester,
  ) async {
    var mode = DAppearanceMaterial.standard;
    late StateSetter change;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          change = setState;
          return MaterialApp(
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: DMaterialTheme.apply(AppTheme.light, mode),
            home: Center(
              child: DMaterialSurface(
                depth: DSurfaceDepth.menu,
                color: Colors.white,
                radius: BorderRadius.circular(12),
                child: DCard(
                  spacing: 0,
                  child: SizedBox(
                    width: 240,
                    child: DInput(focusNode: focus, initialValue: 'Draft'),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.enterText(find.byType(TextField), 'An unsaved draft');
    final state = tester.state(find.byType(DInput));
    for (final material in [
      DAppearanceMaterial.liquidGlass,
      DAppearanceMaterial.standard,
    ]) {
      change(() => mode = material);
      await tester.pump();
      expect(tester.state(find.byType(DInput)), same(state));
      expect(find.text('An unsaved draft'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse opens a glass dropdown without an immediate dismissal', (
    tester,
  ) async {
    final changes = <(bool, DPopoverChangeReason)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: DMaterialTheme.apply(
          AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          DAppearanceMaterial.liquidGlass,
        ),
        home: DFocusHighlight(
          child: Center(
            child: DDropdownMenu(
              onOpenChange: (open, reason) => changes.add((open, reason)),
              content: DDropdownMenuContent(
                children: [
                  DDropdownMenuItem(
                    onPressed: () {},
                    child: const Text('Menu action'),
                  ),
                ],
              ),
              child: DDropdownMenuTrigger.button(
                label: const Text('Open menu'),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Open menu')));
    await tester.pump();
    await mouse.down(tester.getCenter(find.text('Open menu')));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('Menu action'), findsOneWidget, reason: '$changes');
    expect(changes.map((c) => c.$1), [true]);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'high contrast and OS Reduce Transparency restore opaque material live',
    (tester) async {
      const channel = MethodChannel(
        'org.discourse.native/material_accessibility',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => true,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationStyle: AnimationStyle.noAnimation,
          theme: DMaterialTheme.apply(
            AppTheme.light,
            DAppearanceMaterial.liquidGlass,
          ),
          home: DMaterialAccessibility(
            child: Builder(
              builder: (context) => Text('${DMaterialTheme.glassOf(context)}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('false'), findsOneWidget);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('reduceTransparencyChanged', false),
        ),
        (_) {},
      );
      await tester.pump();
      expect(find.text('true'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationStyle: AnimationStyle.noAnimation,
          theme: DMaterialTheme.apply(
            AppTheme.light,
            DAppearanceMaterial.liquidGlass,
          ),
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: Builder(
              builder: (context) => Text('${DMaterialTheme.glassOf(context)}'),
            ),
          ),
        ),
      );
      expect(find.text('false'), findsOneWidget);
    },
  );

  testWidgets(
    'panel opacity is shared; only native glass thins the ground; hatch precedes content',
    (tester) async {
      for (final mode in DAppearanceMaterial.values) {
        Color? panel;
        await tester.pumpWidget(
          MaterialApp(
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: DMaterialTheme.apply(
              AppTheme.forBrightness(
                Brightness.dark,
                background: const ForumBackground.appearance(
                  transparency: .3,
                  effect: ForumBackgroundEffect.hatch,
                ),
              ),
              mode,
            ),
            home: ForumWindowBackground(
              child: Builder(
                builder: (context) {
                  panel = ForumWindowBackground.panelColor(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );
        await tester.pump();
        expect(panel!.a, closeTo(.6, .001));
        final canvas =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('forum-window-canvas')),
                    )
                    .decoration
                as BoxDecoration;
        expect(
          canvas.color!.a,
          closeTo(mode == DAppearanceMaterial.liquidGlass ? .35 : 1, .001),
        );
        final hatch = find.byKey(const ValueKey('forum-hatch-texture'));
        final content = find.byKey(const ValueKey('forum-window-content'));
        expect(hatch, findsOneWidget);
        expect(tester.getTopLeft(hatch), tester.getTopLeft(content));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'glass fallback paints visible frost without tinting its foreground',
    (tester) async {
      Future<List<int>> capture(DAppearanceMaterial material) async {
        await tester.pumpWidget(
          MaterialApp(
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: DMaterialTheme.apply(AppTheme.light, material),
            home: Center(
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: SizedBox(
                  width: 180,
                  height: 90,
                  child: ColoredBox(
                    color: const Color(0xff2299aa),
                    child: Center(
                      child: DMaterialSurface(
                        color: const Color(0xffeeeeee),
                        radius: BorderRadius.circular(8),
                        child: const SizedBox(
                          width: 100,
                          height: 48,
                          child: Center(child: Text('Readable')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return (await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              )
              .toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes!.buffer.asUint8List().toList();
        }))!;
      }

      final standard = await capture(DAppearanceMaterial.standard);
      final glass = await capture(DAppearanceMaterial.liquidGlass);
      expect(glass, isNot(standard));
      expect(
        find.byType(LiquidGlassLite).evaluate().isNotEmpty ||
            find.byType(LiquidGlassLens).evaluate().isNotEmpty,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
