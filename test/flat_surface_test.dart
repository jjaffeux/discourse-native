import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_appearance_effects.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

        for (final highContrast in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
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
            expect(
              find.descendant(
                of: find.byKey(key),
                matching: find.byWidgetPredicate(
                  (widget) => widget is Material && widget.color == expected,
                ),
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('page sheets keep caller alpha and become opaque during a pull', (
    tester,
  ) async {
    for (final source in const [Color(0x80583F70), Colors.transparent]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
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
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(DSheetContent),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      expect(fill(), source);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(fill(), source.withValues(alpha: 1));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(fill(), source);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('opacity control reports the panel opacity', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        themeAnimationStyle: AnimationStyle.noAnimation,
        theme: AppTheme.dark,
        home: Material(
          child: ForumAppearanceEffects(
            effects: const ForumBackground.appearance(transparency: .3),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('60%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain and translucent panels retain the same palette tint', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final transparency in [0.0, .3]) {
        for (final highContrast in [false, true]) {
          Color? panel;
          late Color expected;
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: AppTheme.forBrightness(
                brightness,
                background: ForumBackground.appearance(
                  transparency: transparency,
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
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
          final alpha = transparency == 0 ? 1.0 : .6;
          expect(panel, expected.withValues(alpha: alpha));
          final canvas = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('forum-window-canvas')),
          );
          if (transparency == 0) {
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
  });

  testWidgets('bounded panels leave the canvas clear outside rounded corners', (
    tester,
  ) async {
    const canvas = Color(0xff153d99);
    final shadowsDisabled = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: AppTheme.forBrightness(brightness),
            home: const Center(
              child: RepaintBoundary(
                key: ValueKey('panel-corners'),
                child: SizedBox.square(
                  dimension: 96,
                  child: ColoredBox(
                    color: canvas,
                    child: DResizablePanelGroup(
                      children: [
                        DResizablePanel(
                          id: 'page',
                          child: DCard(
                            border: false,
                            spacing: 0,
                            backgroundColor: Color(0xcc2154c1),
                            borderRadius: BorderRadius.all(Radius.circular(16)),
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
            ], reason: '$brightness corner ($x, $y)');
          }
          final center = (48 * image.width + 48) * 4;
          expect(bytes.getUint8(center + 2), greaterThan(0x99));
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    } finally {
      debugDisableShadows = shadowsDisabled;
    }
  });

  testWidgets(
    'flat controls preserve visible targets, gaps and disabled actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: AppTheme.forBrightness(brightness),
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
        expect(taps, 1, reason: '$brightness');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('mouse opens a dropdown without an immediate dismissal', (
    tester,
  ) async {
    final changes = <(bool, DPopoverChangeReason)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
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
    'panel opacity is shared; the ground stays opaque; hatch precedes content',
    (tester) async {
      Color? panel;
      await tester.pumpWidget(
        MaterialApp(
          themeAnimationStyle: AnimationStyle.noAnimation,
          theme: AppTheme.forBrightness(
            Brightness.dark,
            background: const ForumBackground.appearance(
              transparency: .3,
              effect: ForumBackgroundEffect.hatch,
            ),
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
      expect(canvas.color!.a, 1);
      final hatch = find.byKey(const ValueKey('forum-hatch-texture'));
      final content = find.byKey(const ValueKey('forum-window-content'));
      expect(hatch, findsOneWidget);
      expect(tester.getTopLeft(hatch), tester.getTopLeft(content));
      expect(tester.takeException(), isNull);
    },
  );
}
