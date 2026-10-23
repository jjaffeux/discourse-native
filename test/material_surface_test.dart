import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/shell/forum_appearance_effects.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:discourse_native/src/ui/foundation/sidebar_row_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'support/stock_glass.dart';

void main() {
  testWidgets(
    'iOS saved panels contain frost while portals keep native glass',
    (tester) async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        for (final material in DAppearanceMaterial.values) {
          for (final highContrast in [false, true]) {
            final portals = {
              for (final depth in [
                DSurfaceDepth.menu,
                DSurfaceDepth.dialog,
                DSurfaceDepth.sheet,
              ])
                depth: OverlayPortalController(),
            };
            Widget control(
              String name, {
              DSurfaceDepth depth = DSurfaceDepth.raised,
            }) => DMaterialSurface(
              key: ValueKey(name),
              color: const Color(0xff323543),
              radius: BorderRadius.circular(10),
              depth: depth,
              child: const SizedBox(width: 80, height: 24),
            );
            await tester.pumpWidget(
              MaterialApp(
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: DMaterialTheme.apply(
                  AppTheme.dark.copyWith(platform: platform),
                  material,
                ),
                home: MediaQuery(
                  data: MediaQueryData(highContrast: highContrast),
                  child: Column(
                    children: [
                      control('header'),
                      Expanded(
                        child: DPageSurface(
                          child: Column(
                            children: [
                              DCard(child: control('card-control')),
                              SizedBox(
                                height: 80,
                                child: DPageSurface(
                                  child: control('nested-control'),
                                ),
                              ),
                              SizedBox(
                                height: 40,
                                child: DPageSurface(
                                  framed: false,
                                  child: control('unframed-control'),
                                ),
                              ),
                              SizedBox(
                                height: 100,
                                child: DSheetViewport(
                                  onDismiss: () {},
                                  content: DSheetContent(
                                    side: DSheetSide.bottom,
                                    variant: DSheetVariant.page,
                                    showCloseButton: false,
                                    children: [
                                      Expanded(child: control('sheet-control')),
                                    ],
                                  ),
                                ),
                              ),
                              control(
                                'date',
                                depth: DSurfaceDepth.floatingDate,
                              ),
                              for (final entry in portals.entries)
                                OverlayPortal(
                                  controller: entry.value,
                                  overlayChildBuilder: (_) => Positioned(
                                    top: 0,
                                    left: entry.key.index * 80,
                                    child: DMaterialSurface(
                                      key: ValueKey('portal-${entry.key}'),
                                      depth: entry.key,
                                      color: const Color(0xff323543),
                                      radius: BorderRadius.circular(10),
                                      child: control(
                                        'portal-control-${entry.key}',
                                      ),
                                    ),
                                  ),
                                  child: const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ),
                      ),
                      control('dock', depth: DSurfaceDepth.primaryCapsule),
                    ],
                  ),
                ),
              ),
            );
            for (final portal in portals.values) {
              portal.show();
            }
            await tester.pumpAndSettle();
            final glass =
                material == DAppearanceMaterial.liquidGlass && !highContrast;
            final saved = glass && platform == TargetPlatform.iOS;
            final panels = find.byWidgetPredicate(
              (widget) =>
                  widget is DMaterialSurface &&
                  widget.depth == DSurfaceDepth.panel,
            );
            expect(panels, findsNWidgets(3));
            for (final panel in panels.evaluate()) {
              final clip = find
                  .descendant(
                    of: find.byWidget(panel.widget),
                    matching: find.byType(Material),
                  )
                  .first;
              expect(
                tester.widget<Material>(clip).clipBehavior,
                saved ? Clip.antiAliasWithSaveLayer : Clip.antiAlias,
              );
            }
            for (final name in [
              'card-control',
              'nested-control',
              'unframed-control',
              'sheet-control',
              'date',
            ]) {
              final lenses = find.descendant(
                of: find.byKey(ValueKey(name)),
                matching: find.byType(LiquidGlass),
              );
              expect(lenses, glass ? findsOneWidget : findsNothing);
              if (glass) {
                expectStockGlass(
                  tester,
                  lenses,
                  frost: name == 'date' ? 16 : null,
                  tint: name == 'date'
                      ? DTokens.of(
                          tester.element(lenses),
                        ).surface.withValues(alpha: .68)
                      : null,
                  saturation: name == 'date' ? 1.85 : 1.4,
                );
              }
            }
            for (final name in [
              'header',
              'dock',
              ...portals.keys.map((depth) => 'portal-$depth'),
            ]) {
              final lenses = find.descendant(
                of: find.byKey(ValueKey(name)),
                matching: find.byType(LiquidGlass),
              );
              expect(lenses, glass ? findsWidgets : findsNothing);
              for (final element in lenses.evaluate()) {
                final layer = tester.widget<LiquidGlassLayer>(
                  find
                      .descendant(
                        of: find.byWidget(element.widget),
                        matching: find.byType(LiquidGlassLayer),
                      )
                      .first,
                );
                expect(layer.fake, isFalse, reason: name);
              }
            }
            if (saved) {
              final gesture = await tester.startGesture(
                tester.getCenter(
                  find.byKey(const ValueKey('sheet-drag-handle')),
                ),
              );
              await gesture.moveBy(const Offset(0, 10));
              await gesture.moveBy(const Offset(0, 25));
              await tester.pump();
              for (final panel in panels.evaluate()) {
                final clip = find
                    .descendant(
                      of: find.byWidget(panel.widget),
                      matching: find.byType(Material),
                    )
                    .first;
                expect(
                  tester.widget<Material>(clip).clipBehavior,
                  Clip.antiAliasWithSaveLayer,
                );
              }
              await gesture.cancel();
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets('nested previews cannot erase their enclosing saved panel', (
    tester,
  ) async {
    final glass = DMaterialTheme.apply(
      AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
      DAppearanceMaterial.liquidGlass,
    );
    for (final highContrast in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: glass,
          home: DPageSurface(
            child: Theme(
              data: highContrast
                  ? glass
                  : DMaterialTheme.apply(glass, DAppearanceMaterial.standard),
              child: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
                child: DPageSurface(
                  child: Theme(
                    data: glass,
                    child: MediaQuery(
                      data: const MediaQueryData(),
                      child: DMaterialSurface(
                        color: Colors.white,
                        radius: BorderRadius.circular(10),
                        child: const SizedBox.expand(),
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
      expectStockGlass(tester, find.byType(LiquidGlass));
      final clips = tester
          .widgetList<Material>(find.byType(Material))
          .where((m) => m.borderRadius != null)
          .map((m) => m.clipBehavior);
      expect(clips, containsAll([Clip.antiAliasWithSaveLayer, Clip.antiAlias]));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('glass controls use the regular glass preset', (tester) async {
    const fill = Color(0xff323543);
    for (final depth in [
      DSurfaceDepth.raised,
      DSurfaceDepth.primaryCapsule,
      DSurfaceDepth.chromeSelection,
    ]) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: DMaterialTheme.apply(
              AppTheme.forBrightness(brightness),
              DAppearanceMaterial.liquidGlass,
            ),
            home: Center(
              child: DMaterialSurface(
                depth: depth,
                color: fill,
                radius: BorderRadius.circular(10),
                child: const SizedBox(width: 216, height: 200),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expectStockGlass(
          tester,
          find.byType(LiquidGlass),
          tint: depth == DSurfaceDepth.primaryCapsule
              ? DMaterialSurface.glassTintFor(fill)
              : null,
        );
        final shadows = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .expand((box) => box.boxShadow ?? const <BoxShadow>[]);
        expect(shadows, isEmpty);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'floating glass frosts the supplied tint without doubling alpha',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final depth in [
          DSurfaceDepth.menu,
          DSurfaceDepth.dialog,
          DSurfaceDepth.sheet,
        ]) {
          for (final source in const [
            Color(0xFF333644),
            Color(0x80583F70),
            Colors.transparent,
          ]) {
            for (final preserveColor in [false, true]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: DMaterialTheme.apply(
                    AppTheme.forBrightness(brightness),
                    DAppearanceMaterial.liquidGlass,
                  ),
                  home: Center(
                    child: DMaterialSurface(
                      depth: depth,
                      color: source,
                      preserveColor: preserveColor,
                      radius: BorderRadius.circular(10),
                      child: const SizedBox(width: 216, height: 200),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final lens = find.byType(LiquidGlass);
              if (source.a == 0) {
                expect(lens, findsNothing);
              } else {
                final tint = source.withValues(
                  alpha: source.a * (preserveColor ? 1 : .68),
                );
                expectStockGlass(tester, lens, tint: tint, frost: 16);
              }
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );

  testWidgets('menus and reading pages share each theme palette tint', (
    tester,
  ) async {
    const menuKey = ValueKey('themed-menu');
    const pageKey = ValueKey('themed-page');
    const sheetKey = ValueKey('themed-page-sheet');
    for (final preset in forumThemePresets) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.fromPalette(preset.resolve(brightness));
        final tokens = theme.extension<DTokens>()!;
        final expected = Color.lerp(tokens.background, tokens.foreground, .03)!;
        for (final material in DAppearanceMaterial.values) {
          for (final reduced in [false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: DMaterialTheme.apply(theme, material),
                home: MediaQuery(
                  data: MediaQueryData(highContrast: reduced),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: menuKey,
                          width: 220,
                          height: 280,
                          child: DSheetContent(
                            side: DSheetSide.bottom,
                            variant: DSheetVariant.menu,
                            showCloseButton: false,
                            children: [SizedBox(height: 80)],
                          ),
                        ),
                        SizedBox(
                          key: pageKey,
                          width: 220,
                          height: 280,
                          child: DPageSurface(child: SizedBox.expand()),
                        ),
                        SizedBox(
                          key: sheetKey,
                          width: 220,
                          height: 280,
                          child: DSheetViewport(
                            content: DSheetContent(
                              side: DSheetSide.bottom,
                              variant: DSheetVariant.page,
                              showCloseButton: false,
                              children: [Expanded(child: SizedBox.expand())],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (final key in [menuKey, pageKey, sheetKey]) {
              final surface = find.descendant(
                of: find.byKey(key),
                matching: find.byType(DMaterialSurface),
              );
              expect(tester.widget<DMaterialSurface>(surface).color, expected);
              final lens = find.descendant(
                of: surface,
                matching: find.byType(LiquidGlass),
              );
              final glass =
                  material == DAppearanceMaterial.liquidGlass && !reduced;
              if (key == menuKey && glass) {
                expect(
                  tester.widget<LiquidGlass>(lens).appearance!.tint,
                  expected.withValues(alpha: .68),
                );
              } else {
                expect(lens, findsNothing);
                expect(
                  find.descendant(
                    of: surface,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is DecoratedBox &&
                          widget.decoration is BoxDecoration &&
                          (widget.decoration as BoxDecoration).color ==
                              expected,
                    ),
                  ),
                  findsOneWidget,
                );
              }
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });

  testWidgets('page sheets keep caller alpha and become opaque during a pull', (
    tester,
  ) async {
    for (final material in DAppearanceMaterial.values) {
      for (final source in const [Color(0x80583F70), Colors.transparent]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: DMaterialTheme.apply(
              AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
              material,
            ),
            home: DSheetViewport(
              onDismiss: () {},
              content: DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.page,
                showCloseButton: false,
                backgroundColor: source,
                children: const [
                  Expanded(child: Center(child: Text('Reading page'))),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Color fill() => tester
            .widget<DMaterialSurface>(find.byType(DMaterialSurface))
            .color;
        expect(fill(), source);
        expect(find.byType(LiquidGlass), findsNothing);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
        );
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 60));
        await tester.pump();
        expect(fill(), source.withValues(alpha: 1));
        expect(find.byType(LiquidGlass), findsNothing);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(fill(), source);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'selected sidebar rows use regular glass and dormant rows stay flat',
    (tester) async {
      for (final selected in [false, true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: DMaterialTheme.apply(
              AppTheme.light,
              DAppearanceMaterial.liquidGlass,
            ),
            home: Center(
              child: DSidebarRowSurface(
                selected: selected,
                hovered: false,
                radius: BorderRadius.circular(8),
                child: const SizedBox(
                  width: 120,
                  height: 32,
                  child: Text('Topics'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final lens = find.byType(LiquidGlass);
        expect(lens, selected ? findsOneWidget : findsNothing);
        if (selected) {
          expectStockGlass(tester, lens);
        }
        expect(
          tester.getSize(find.byType(DSidebarRowSurface)),
          const Size(120, 32),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

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
    testWidgets(
      'panel rim stays uniform while its top highlight fades ($material)',
      (tester) async {
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
                for (final y in [20, 130]) {
                  pixel(
                    100,
                    y,
                    Color.alphaBlend(
                      Colors.white.withValues(
                        alpha: (dark ? .066 : .5) * (1 - (y + .5) / 140),
                      ),
                      base,
                    ),
                  );
                }
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
      },
    );
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

  testWidgets('panel paint changes retain editing state and scroll position', (
    tester,
  ) async {
    const channel = MethodChannel(
      'org.discourse.native/material_accessibility',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => false,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final focus = FocusNode();
    final text = TextEditingController();
    final scroll = ScrollController();
    addTearDown(focus.dispose);
    addTearDown(text.dispose);
    addTearDown(scroll.dispose);
    var material = DAppearanceMaterial.liquidGlass;
    var contrast = false;
    late StateSetter change;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          change = setState;
          return MaterialApp(
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: DMaterialTheme.apply(
              AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
              material,
            ),
            home: DMaterialAccessibility(
              child: MediaQuery(
                data: MediaQueryData(highContrast: contrast),
                child: Center(
                  child: SizedBox(
                    width: 260,
                    height: 200,
                    child: DPageSurface(
                      child: SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          children: [
                            const SizedBox(height: 90),
                            DInput(controller: text, focusNode: focus),
                            const SizedBox(height: 700),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'An unsaved draft');
    const selection = TextSelection(baseOffset: 3, extentOffset: 8);
    text.selection = selection;
    scroll.jumpTo(45);
    await tester.pump();
    final state = tester.state(find.byType(DInput));
    for (final (nextMaterial, highContrast, reduced) in [
      (DAppearanceMaterial.standard, false, false),
      (DAppearanceMaterial.liquidGlass, false, false),
      (DAppearanceMaterial.liquidGlass, true, false),
      (DAppearanceMaterial.liquidGlass, false, true),
      (DAppearanceMaterial.liquidGlass, false, false),
    ]) {
      change(() {
        material = nextMaterial;
        contrast = highContrast;
      });
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('reduceTransparencyChanged', reduced),
        ),
        (_) {},
      );
      await tester.pump();
      expect(tester.state(find.byType(DInput)), same(state));
      expect(text.text, 'An unsaved draft');
      expect(text.selection, selection);
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, 45);
      final panel = find.byWidgetPredicate(
        (widget) =>
            widget is DMaterialSurface && widget.depth == DSurfaceDepth.panel,
      );
      final clip = tester.widget<Material>(
        find.descendant(of: panel, matching: find.byType(Material)).first,
      );
      expect(
        clip.clipBehavior,
        nextMaterial == DAppearanceMaterial.liquidGlass &&
                !highContrast &&
                !reduced
            ? Clip.antiAliasWithSaveLayer
            : Clip.antiAlias,
      );
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

  testWidgets('the macOS window canvas stays opaque under glass transparency', (
    tester,
  ) async {
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
          DAppearanceMaterial.liquidGlass,
        ).copyWith(platform: TargetPlatform.macOS),
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
    final canvas =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('forum-window-canvas')),
                )
                .decoration
            as BoxDecoration;
    expect(canvas.color!.a, 1);
    expect(panel!.a, closeTo(.6, .001));
  });

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
        find.byType(FakeGlass).evaluate().isNotEmpty ||
            find.byType(LiquidGlass).evaluate().isNotEmpty,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
