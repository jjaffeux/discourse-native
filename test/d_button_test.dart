import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/ui/foundation/control_artwork.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'support/button_surface.dart';
import 'support/stock_glass.dart';

void main() {
  testWidgets(
    'ordinary glass buttons use regular glass without a cosmetic border',
    (tester) async {
      for (final dark in [false, true]) {
        for (final enabled in [true, false]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: DMaterialTheme.apply(
                dark ? AppTheme.dark : AppTheme.light,
                DAppearanceMaterial.liquidGlass,
              ),
              home: Center(
                child: DButton(
                  variant: DButtonVariant.outline,
                  label: const Text('Reply'),
                  onPressed: enabled ? () {} : null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final lens = find.byType(LiquidGlass);
          expectStockGlass(tester, lens);
          expect(buttonSurface(tester).borderColor.a, 0);
          expect(buttonSurface(tester).color.a, 0);
          final node = tester.element(lens);
          final fractional = <Opacity>[];
          node.visitAncestorElements((ancestor) {
            final widget = ancestor.widget;
            if (widget is Opacity && widget.opacity < 1) fractional.add(widget);
            return true;
          });
          expect(fractional, isEmpty);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'explicit glass button colors survive hover and disabled states',
    (tester) async {
      const background = Color(0xff51496d);
      const hover = Color(0xff6f5c96);
      const foreground = Color(0xffd8c3f6);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      for (final dark in [false, true]) {
        for (final state in [
          (enabled: true, loading: false),
          (enabled: false, loading: false),
          (enabled: true, loading: true),
        ]) {
          focus.unfocus();
          await mouse.moveTo(Offset.zero);
          await tester.pumpWidget(
            MaterialApp(
              theme: DMaterialTheme.apply(
                dark ? AppTheme.dark : AppTheme.light,
                DAppearanceMaterial.liquidGlass,
              ),
              home: Center(
                child: DButton.iconOnly(
                  size: DButtonSize.toolbar,
                  icon: const DIcon(DIcons.paperPlane, size: 12),
                  tooltip: 'Send',
                  focusNode: focus,
                  backgroundColor: background,
                  interactiveBackgroundColor: hover,
                  foregroundColor: foreground,
                  loading: state.loading,
                  onPressed: state.enabled ? () {} : null,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          final enabled = state.enabled && !state.loading;
          void expectTint(Color source) {
            final tint = source.withValues(alpha: .76 * (enabled ? 1 : .6));
            expectStockGlass(tester, find.byType(LiquidGlass), tint: tint);
          }

          expectTint(background);
          final button = find.byType(DButton);
          expect(tester.getSize(button), const Size(34, 34));
          if (!state.loading) {
            expect(
              IconTheme.of(tester.element(find.byType(DIcon))).color,
              foreground,
            );
          }
          await mouse.moveTo(tester.getCenter(button));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expectTint(enabled ? hover : background);
          await mouse.moveTo(Offset.zero);
          focus.requestFocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expectTint(enabled ? hover : background);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'interactive glass tint leaves resting and expanded fills intact',
    (tester) async {
      const background = Color(0xff51496d);
      const hover = Color(0xff6f5c96);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      for (final expanded in [false, true]) {
        focus.unfocus();
        await mouse.moveTo(Offset.zero);
        await tester.pumpWidget(
          MaterialApp(
            theme: DMaterialTheme.apply(
              AppTheme.dark,
              DAppearanceMaterial.liquidGlass,
            ),
            home: Center(
              child: DButton.iconOnly(
                icon: const DIcon(DIcons.paperPlane),
                tooltip: 'Send',
                focusNode: focus,
                backgroundColor: expanded ? background : null,
                interactiveBackgroundColor: hover,
                expanded: expanded,
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        void expectTint(Color? source) {
          expectStockGlass(
            tester,
            find.byType(LiquidGlass),
            tint: source?.withValues(alpha: .76),
          );
        }

        expectTint(expanded ? background : null);
        focus.requestFocus();
        await tester.pumpAndSettle();
        expectTint(expanded ? background : hover);
        await mouse.moveTo(tester.getCenter(find.byType(DButton)));
        await tester.pumpAndSettle();
        expectTint(hover);
        focus.unfocus();
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expectTint(expanded ? background : null);
      }
    },
  );

  testWidgets('transparent glass button override has no lens', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DMaterialTheme.apply(
          AppTheme.dark,
          DAppearanceMaterial.liquidGlass,
        ),
        home: Center(
          child: DButton.iconOnly(
            icon: const DIcon(DIcons.paperPlane),
            tooltip: 'Send',
            backgroundColor: Colors.transparent,
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNothing);
    expect(buttonSurface(tester).color.a, 0);
  });

  testWidgets('timeline icon buttons preserve their glyph bounds', (
    tester,
  ) async {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      for (final material in DAppearanceMaterial.values) {
        for (final scale in [1.0, 2.0]) {
          for (final density in [
            DButtonDensity.floatingCall,
            DButtonDensity.topicProgress,
            DButtonDensity.timelineEnd,
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: DMaterialTheme.apply(
                  AppTheme.light.copyWith(platform: platform),
                  material,
                ),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Center(
                      child: DButton.iconOnly(
                        size: DControlSize.toolbar,
                        density: density,
                        variant: DButtonVariant.ghost,
                        shape: DButtonShape.pill,
                        icon: const DIcon(DIcons.chevronDown),
                        tooltip: 'Jump to latest messages',
                        onPressed: () {},
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final button = find.byType(DButton);
            final icon = find.byType(DIcon);
            expect(
              tester.getSize(icon),
              Size.square(density == DButtonDensity.timelineEnd ? 11 : 14),
            );
            expect(tester.getCenter(icon), tester.getCenter(button));
            expect(
              tester.getRect(button),
              tester.getRect(
                find.descendant(
                  of: button,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is AnimatedContainer &&
                        widget.decoration is DButtonDecoration,
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });

  testWidgets('timeline presets retain artwork, focus and exact targets', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var presses = 0;
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      for (final material in DAppearanceMaterial.values) {
        for (final dark in [false, true]) {
          for (final scale in [1.0, 2.0]) {
            for (final density in [
              DButtonDensity.floatingCall,
              DButtonDensity.topicProgress,
              DButtonDensity.timelineEnd,
            ]) {
              final floating = density == DButtonDensity.floatingCall;
              final footer = density == DButtonDensity.topicProgress;
              await tester.pumpWidget(
                MaterialApp(
                  theme: DMaterialTheme.apply(
                    (dark ? AppTheme.dark : AppTheme.light).copyWith(
                      platform: platform,
                    ),
                    material,
                  ),
                  home: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Scaffold(
                      body: Center(
                        child: DButton(
                          density: density,
                          variant: DButtonVariant.ghost,
                          focusNode: focus,
                          label: const Text('25 / 120'),
                          onPressed: () => presses++,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final button = find.byType(DButton);
              final rect = tester.getRect(button);
              final fontSize = floating ? 11.5 : 12.5;
              expect(
                rect.height,
                closeTo(
                  (floating
                          ? 26
                          : footer
                          ? 30
                          : 34) +
                      fontSize * (scale - 1) * 1.5,
                  .01,
                ),
              );
              final surface = buttonSurface(tester);
              final glass = material == DAppearanceMaterial.liquidGlass;
              expect(
                surface.color.a,
                floating && !glass
                    ? closeTo(.4, .001)
                    : footer || floating
                    ? 0
                    : 1,
              );
              expect(
                surface.borderColor.a,
                floating && !glass ? greaterThan(0) : 0,
              );
              final raised = find.descendant(
                of: button,
                matching: find.byType(DMaterialSurface),
              );
              expect(
                raised,
                (floating || footer) && glass ? findsOneWidget : findsNothing,
              );
              if ((floating || footer) && glass) {
                final materialSurface = tester.widget<DMaterialSurface>(raised);
                expect(materialSurface.preserveColor, isTrue);
                expect(materialSurface.color.a, closeTo(dark ? .42 : .5, .001));
              }
              expect(surface.borderRadius.topLeft.x, 999);
              expect(
                find.descendant(
                  of: button,
                  matching: find.byType(BackdropFilter),
                ),
                floating && !glass ? findsOneWidget : findsNothing,
              );
              final artwork = find.descendant(
                of: button,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is AnimatedContainer &&
                      w.decoration is DButtonDecoration,
                ),
              );
              expect(rect, tester.getRect(artwork));
              final before = presses;
              await tester.tapAt(Offset(rect.left - 1, rect.center.dy));
              await tester.pump();
              expect(presses, before);
              await tester.tap(button);
              await tester.pump();
              expect(presses, before + 1);
              focus.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pump();
              expect(presses, before + 2);
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    }
  });

  for (final material in DAppearanceMaterial.values) {
    for (final brightness in Brightness.values) {
      testWidgets('launcher hover stays flat in $material $brightness', (
        tester,
      ) async {
        const canvas = Color(0xff323642);
        const capture = ValueKey('launcher-hover');
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final shadowsDisabled = debugDisableShadows;
        debugDisableShadows = false;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: DMaterialTheme.apply(
                AppTheme.forBrightness(brightness),
                material,
              ),
              home: Center(
                child: RepaintBoundary(
                  key: capture,
                  child: ColoredBox(
                    color: canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SizedBox(
                        width: 112,
                        child: DButton(
                          variant: DButtonVariant.launcher,
                          icon: const DIcon(DIcons.plus),
                          label: const Text('Topics'),
                          focusNode: focus,
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
          expect(buttonSurface(tester).color.a, 0);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(find.byType(DButton)));
          await tester.pumpAndSettle();
          final tint =
              (brightness == Brightness.dark ? Colors.white : Colors.black)
                  .withValues(
                    alpha: brightness == Brightness.dark ? .055 : .045,
                  );
          expect(buttonSurface(tester).borderColor.a, 0);
          final expected = Color.alphaBlend(tint, canvas);
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(find.byKey(capture))
                .toImage();
            try {
              final pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              void expectPixel(int x, int y, Color color) {
                final offset = (y * image.width + x) * 4;
                for (final (channel, value) in [
                  (0, color.r),
                  (1, color.g),
                  (2, color.b),
                ]) {
                  expect(
                    pixels.getUint8(offset + channel),
                    closeTo((value * 255).round(), 1),
                    reason: 'Flat launcher pixel at ($x, $y), channel $channel',
                  );
                }
              }

              for (var x = 48; x < 112; x++) {
                expectPixel(x, 24, expected); // Top edge has no raised rim.
                expectPixel(x, 32, expected); // Fill keeps the mockup opacity.
                expectPixel(x, 137, canvas); // No shadow outside the cell.
              }
              final output = Platform.environment['START_PAGE_CAPTURE_DIR'];
              if (output != null) {
                final file = File(
                  '$output/launcher-hover-${material.name}-${brightness.name}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(
                  (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!.buffer.asUint8List(),
                );
              }
            } finally {
              image.dispose();
            }
          });
          expect(buttonSurface(tester).color, tint);
          await mouse.down(tester.getCenter(find.byType(DButton)));
          await tester.pumpAndSettle();
          expect(buttonSurface(tester).color, tint);
          await mouse.up();
          await mouse.moveTo(Offset.zero);
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(buttonSurface(tester).color, tint);
          focus.unfocus();
          await tester.pumpAndSettle();
          expect(buttonSurface(tester).color.a, 0);
          expect(tester.takeException(), isNull);
        } finally {
          debugDisableShadows = shadowsDisabled;
        }
      });
    }
  }
  for (final material in DAppearanceMaterial.values) {
    for (final brightness in Brightness.values) {
      testWidgets('desktop header states stay flat in $material $brightness', (
        tester,
      ) async {
        const canvas = Color(0xff323642);
        const capture = ValueKey('header-capture');
        final shadowsDisabled = debugDisableShadows;
        debugDisableShadows = false;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        try {
          for (final iconOnly in [false, true]) {
            for (final expanded in [false, true]) {
              final variant = expanded
                  ? DButtonVariant.primary
                  : DButtonVariant.ghost;
              await tester.pumpWidget(
                MaterialApp(
                  theme: DMaterialTheme.apply(
                    AppTheme.forBrightness(
                      brightness,
                    ).copyWith(platform: TargetPlatform.macOS),
                    material,
                  ),
                  home: Center(
                    child: RepaintBoundary(
                      key: capture,
                      child: ColoredBox(
                        color: canvas,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: iconOnly
                              ? DButton.iconOnly(
                                  density: DButtonDensity.header,
                                  variant: variant,
                                  shape: DButtonShape.pill,
                                  icon: const DIcon(DIcons.bell, size: 17),
                                  tooltip: 'Notifications',
                                  expanded: expanded,
                                  onPressed: () {},
                                )
                              : DButton(
                                  density: DButtonDensity.header,
                                  variant: variant,
                                  shape: DButtonShape.pill,
                                  icon: const DIcon(DIcons.comment, size: 16),
                                  label: const Text('42'),
                                  expanded: expanded,
                                  onPressed: () {},
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final button = find.byType(DButton);
              await mouse.moveTo(
                expanded ? Offset.zero : tester.getCenter(button),
              );
              await tester.pumpAndSettle();
              final buttons = DTokens.of(tester.element(button)).buttonTheme;
              final fill = Color.alphaBlend(
                expanded ? buttons.primary.hover : buttons.accent.hover,
                canvas,
              );
              final bounds = tester.getRect(button);
              final origin = tester.getTopLeft(find.byKey(capture));
              final left = (bounds.left - origin.dx).round();
              final top = (bounds.top - origin.dy).round();
              final width = bounds.width.round();
              final height = bounds.height.round();
              await tester.runAsync(() async {
                final image = await tester
                    .renderObject<RenderRepaintBoundary>(find.byKey(capture))
                    .toImage();
                try {
                  final pixels = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!;
                  void expectPixel(int x, int y, Color color, String what) {
                    final offset = (y * image.width + x) * 4;
                    for (final (channel, value) in [
                      (0, color.r),
                      (1, color.g),
                      (2, color.b),
                    ]) {
                      expect(
                        pixels.getUint8(offset + channel),
                        closeTo((value * 255).round(), 1),
                        reason:
                            '$what at ($x, $y), channel $channel, '
                            'iconOnly=$iconOnly expanded=$expanded',
                      );
                    }
                  }

                  final corner = height ~/ 2;
                  for (var x = left + corner; x < left + width - corner; x++) {
                    expectPixel(x, top, fill, 'Top edge without a rim');
                    expectPixel(x, top + 3, fill, 'Flat fill without a lens');
                    expectPixel(x, top + height + 1, canvas, 'No shadow');
                  }
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
    }
  }
  for (final rtl in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'header preset has exact visible bounds rtl=$rtl scale=$scale',
        (tester) async {
          var presses = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Scaffold(
                    body: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: DSpacing.xs,
                        children: [
                          DButton(
                            key: const ValueKey('header-count'),
                            density: DButtonDensity.header,
                            variant: DButtonVariant.ghost,
                            icon: const Icon(Icons.chat, size: 16),
                            label: const Text('49'),
                            onPressed: () => presses++,
                          ),
                          DButton.iconOnly(
                            key: const ValueKey('header-bell'),
                            density: DButtonDensity.header,
                            variant: DButtonVariant.ghost,
                            icon: const Icon(Icons.notifications, size: 17),
                            tooltip: 'Notifications',
                            onPressed: () => presses++,
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
          final button = find.byKey(const ValueKey('header-count'));
          final bell = find.byKey(const ValueKey('header-bell'));
          final bounds = tester.getRect(button);
          final glyph = tester.getRect(
            find.descendant(of: button, matching: find.byType(Icon)),
          );
          final label = tester.getRect(find.text('49'));
          final height = 28 + (12.5 * scale - 12.5) * 1.5;
          expect(bounds.height, height);
          expect(tester.getSize(bell), Size(height + 4, height));
          expect(rtl ? glyph.left - label.right : label.left - glyph.right, 8);
          expect(
            rtl ? bounds.right - glyph.right : glyph.left - bounds.left,
            10,
          );
          expect(
            rtl ? label.left - bounds.left : bounds.right - label.right,
            10,
          );
          expect(
            rtl
                ? bounds.left - tester.getRect(bell).right
                : tester.getRect(bell).left - bounds.right,
            4,
          );
          final style = tester
              .widget<FilledButton>(
                find.descendant(
                  of: button,
                  matching: find.byType(FilledButton),
                ),
              )
              .style!;
          expect(style.textStyle!.resolve({})!.fontSize, 12.5);
          expect(
            tester.getRect(
              find.descendant(of: button, matching: find.byType(Material)),
            ),
            bounds,
          );
          await tester.tapAt(bounds.centerLeft - const Offset(1, 0));
          await tester.tapAt(bounds.centerRight + const Offset(1, 0));
          expect(presses, 0);
          await tester.tap(button);
          expect(presses, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets(
      'launcher owns square artwork, targets and keyboard activation in $direction',
      (tester) async {
        var presses = 0;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        for (final scale in [1.0, 2.0]) {
          focus.unfocus();
          await tester.pump();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: direction,
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 112 + (13 * scale - 13) * 3,
                        child: DButton(
                          variant: DButtonVariant.launcher,
                          icon: const DIcon(DIcons.plus),
                          label: const Text('Topics'),
                          focusNode: focus,
                          onPressed: () => presses++,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byType(DButton);
          final bounds = tester.getRect(button);
          expect(bounds.size, Size.square(112 + (13 * scale - 13) * 3));
          expect(tester.getRect(find.byType(FilledButton)), bounds);
          expect(
            tester.getCenter(find.byType(DAvatar)).dy,
            lessThan(tester.getCenter(find.text('Topics')).dy),
          );
          expect(buttonSurface(tester).color.a, 0);
          final before = presses;
          for (final point in [
            bounds.centerLeft - const Offset(1, 0),
            bounds.centerRight + const Offset(1, 0),
            bounds.topCenter - const Offset(0, 1),
            bounds.bottomCenter + const Offset(0, 1),
          ]) {
            await tester.tapAt(point);
          }
          expect(presses, before);
          await tester.tapAt(bounds.topLeft + const Offset(2, 2));
          await tester.pumpAndSettle();
          expect(presses, before + 1);
          focus.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(presses, before + 2);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: bounds.center);
          await tester.pumpAndSettle();
          expect(buttonSurface(tester).color.a, greaterThan(0));
          await mouse.removePointer();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'disabled launcher exposes a single destination and ignores activation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 112,
                child: DButton(
                  variant: DButtonVariant.launcher,
                  icon: DIcon(DIcons.plus),
                  label: Text('Topics'),
                  onPressed: null,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Topics'), findsOneWidget);
      await tester.tap(find.byType(DButton));
      await tester.pumpAndSettle();
      expect(buttonSurface(tester).color.a, 0);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'avatar trigger keeps its border flush and target visible on $platform',
      (tester) async {
        var presses = 0;
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Center(
                    child: DButton.iconOnly(
                      density: DButtonDensity.avatar,
                      variant: DButtonVariant.ghost,
                      tooltip: 'Profile',
                      icon: const DAvatar(
                        border: false,
                        fallback: DAvatarFallback(child: Text('U')),
                      ),
                      onPressed: () => presses++,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byType(DButton);
          final bounds = tester.getRect(button);
          expect(bounds.size, Size.square(36 * scale));
          expect(tester.getRect(find.byType(DAvatar)), bounds.deflate(2));
          expect(buttonSurface(tester).strokeWidth, 2);
          expect(
            buttonSurface(tester).borderColor,
            DTokens.of(tester.element(button)).border,
          );
          final before = presses;
          for (final point in [
            bounds.centerLeft - const Offset(1, 0),
            bounds.centerRight + const Offset(1, 0),
            bounds.topCenter - const Offset(0, 1),
            bounds.bottomCenter + const Offset(0, 1),
          ]) {
            await tester.tapAt(point);
          }
          expect(presses, before);
          await tester.tapAt(bounds.topCenter + const Offset(0, 1));
          await tester.pump();
          expect(presses, before + 1);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(buttonSurface(tester).ringWidth, greaterThan(0));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('back link matches mockup artwork on $platform', (
      tester,
    ) async {
      var presses = 0;
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: DButton(
                    label: const Text('Latest topics'),
                    icon: const Icon(Icons.chevron_left),
                    density: DButtonDensity.backLink,
                    variant: DButtonVariant.inline,
                    onPressed: () => presses++,
                  ),
                ),
              ),
            ),
          ),
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final style = button.style!.textStyle!.resolve({})!;
        expect(style.fontSize, 13);
        expect(style.fontWeight, FontWeight.w500);
        expect(style.height, 1.5);
        expect(button.style!.padding!.resolve({}), EdgeInsets.zero);
        expect(
          tester.getSize(find.byIcon(Icons.chevron_left)),
          const Size(11, 11),
        );
        expect(
          tester.getRect(find.byIcon(Icons.chevron_left)).left,
          tester.getRect(find.byType(DButton)).left - 2,
        );
        final surface = find.byWidgetPredicate(
          (widget) =>
              widget is AnimatedContainer &&
              widget.decoration is DButtonDecoration,
        );
        expect(tester.getSize(surface).height, (19.5 * scale).ceilToDouble());
        expect(buttonSurface(tester).color, Colors.transparent);
        if (platform == TargetPlatform.iOS) {
          expect(
            tester.getSize(find.byType(DButton)).height,
            tester.getSize(surface).height,
          );
        }
        await tester.tap(find.text('Latest topics'));
        await tester.pump();
      }
      expect(presses, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chat message action matches compact mockup geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: DButton.iconOnly(
              density: DButtonDensity.chatMessageAction,
              variant: DButtonVariant.ghost,
              icon: const Icon(Icons.add_reaction),
              tooltip: 'Add reaction',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final surface = find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer && widget.decoration is DButtonDecoration,
    );
    expect(tester.getSize(surface), const Size.square(26));
    expect(
      tester.getSize(find.byIcon(Icons.add_reaction)),
      const Size.square(16),
    );
    expect(buttonSurface(tester).borderRadius, BorderRadius.circular(6));
  });

  testWidgets('dashed tile fills its row and keeps one button target', (
    tester,
  ) async {
    var presses = 0;
    Future<void> pump(double scale) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: DButton(
                label: const Text('New theme'),
                icon: const Icon(Icons.add),
                variant: DButtonVariant.dashedTile,
                alignment: AlignmentDirectional.centerStart,
                onPressed: () => presses++,
              ),
            ),
          ),
        ),
      ),
    );
    await pump(1);
    final button = find.byType(DButton);
    expect(tester.getSize(button), const Size(320, 50));
    expect(buttonSurface(tester).dashed, isTrue);
    final iconFrame = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is DButtonDecoration &&
            (widget.decoration as DButtonDecoration).dashed,
      ),
    );
    expect(tester.getSize(iconFrame.last), const Size(34, 34));
    await tester.tapAt(tester.getRect(button).centerRight - const Offset(2, 0));
    await tester.pump();
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 2);
    await pump(2);
    expect(tester.getSize(button).height, greaterThan(50));
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'composer density preserves icons and limits only desktop width $platform',
      (tester) async {
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: Scaffold(
              body: Center(
                child: DButton.iconOnly(
                  density: DButtonDensity.composerBlock,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add block',
                  onPressed: () => presses++,
                ),
              ),
            ),
          ),
        );
        final button = find.byType(DButton);
        final desktop = platform == TargetPlatform.macOS;
        expect(
          tester.getSize(button),
          desktop ? const Size(20, 30) : const Size(30, 30),
        );
        expect(tester.getSize(find.byIcon(Icons.add)), const Size(12, 12));
        final rect = tester.getRect(button);
        await tester.tapAt(rect.centerLeft + const Offset(1, 0));
        await tester.pump();
        expect(presses, 1);
        await tester.tapAt(rect.centerLeft - const Offset(1, 0));
        await tester.pump();
        expect(presses, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, 2);
      },
    );
  }

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'icon shape retargets smoothly with reduced motion $reducedMotion',
      (tester) async {
        var selected = false;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return Center(
                    child: DButton.iconOnly(
                      density: DButtonDensity.standard,
                      shape: selected
                          ? DButtonShape.rounded
                          : DButtonShape.pill,
                      borderRadius: selected ? BorderRadius.circular(14) : null,
                      variant: DButtonVariant.ghost,

                      icon: const Icon(Icons.forum),
                      tooltip: 'Topics',
                      onPressed: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final painted = find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is DButtonDecoration,
        );
        double radius() =>
            (tester.widget<DecoratedBox>(painted).decoration
                    as DButtonDecoration)
                .borderRadius
                .topLeft
                .x;
        expect(radius(), 15);
        update(() => selected = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        if (reducedMotion) {
          expect(radius(), 14);
        } else {
          expect(radius(), inExclusiveRange(14, 15));
        }
        final interruptedRadius = radius();
        update(() => selected = false);
        await tester.pump();
        if (reducedMotion) {
          expect(radius(), 15);
        } else {
          expect(radius(), closeTo(interruptedRadius, .001));
          await tester.pump(const Duration(milliseconds: 60));
          expect(radius(), inExclusiveRange(interruptedRadius, 15));
        }
        await tester.pumpAndSettle();
        expect(radius(), 15);
      },
    );
  }

  testWidgets('glass dock buttons retain focus, loading and exact targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var presses = 0;
    for (final density in [
      DButtonDensity.mobileDock,
      DButtonDensity.mobileDockAction,
      DButtonDensity.mobileDockCollapsed,
    ]) {
      for (final scale in [1.0, 2.0]) {
        Future<void> pump({bool loading = false}) => tester.pumpWidget(
          MaterialApp(
            theme: DMaterialTheme.apply(
              AppTheme.light.copyWith(platform: TargetPlatform.iOS),
              DAppearanceMaterial.liquidGlass,
            ),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: DButton.iconOnly(
                    density: density,
                    shape: DButtonShape.pill,
                    icon: const Icon(Icons.add),
                    tooltip: 'New topic',
                    backgroundColor: density == DButtonDensity.mobileDock
                        ? Colors.white12
                        : null,
                    focusNode: focus,
                    loading: loading,
                    onPressed: () => presses++,
                  ),
                ),
              ),
            ),
          ),
        );
        focus.unfocus();
        await pump();
        await tester.pumpAndSettle();
        final button = find.byType(DButton);
        final bounds = tester.getRect(button);
        final lens = find.byType(LiquidGlass);
        expect(tester.getRect(lens), bounds);
        expectStockGlass(tester, lens);
        expect(
          tester.widget<LiquidGlass>(lens).shape,
          LiquidRoundedRectangle(borderRadius: bounds.height / 2),
        );
        expect(tester.getCenter(find.byIcon(Icons.add)), bounds.center);
        expect(find.byType(DMaterialSurface), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedContainer &&
                widget.decoration is DButtonDecoration,
          ),
          findsNothing,
        );
        final before = presses;
        await tester.tapAt(bounds.centerLeft - const Offset(1, 0));
        expect(presses, before);
        await tester.tap(button);
        await tester.pump();
        expect(presses, before + 1);
        focus.requestFocus();
        await tester.pumpAndSettle();
        final artwork = find.byType(DControlArtwork);
        final paint = tester.widget<CustomPaint>(
          find
              .descendant(of: artwork, matching: find.byType(CustomPaint))
              .first,
        );
        expect(paint.foregroundPainter, isNotNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(presses, before + 2);
        await pump(loading: true);
        await tester.pump();
        expect(tester.getRect(button), bounds);
        expect(find.byType(DSpinner), findsOneWidget);
        expect(
          find.ancestor(
            of: lens,
            matching: find.byWidgetPredicate(
              (widget) => widget is Opacity && widget.opacity < 1,
            ),
          ),
          findsNothing,
        );
        final data = tester.getSemantics(button).getSemanticsData();
        expect(data.label, 'New topic');
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.tap(button);
        await tester.pump();
        expect(presses, before + 2);
        expect(tester.takeException(), isNull);
      }
    }
    semantics.dispose();
  });

  testWidgets('an icon-only dock action stays circular within a wider slot', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: Center(
                child: DButton.iconOnly(
                  density: DButtonDensity.mobileDockAction,
                  shape: DButtonShape.pill,
                  icon: const Icon(Icons.add),
                  tooltip: 'New topic',
                  onPressed: () => presses++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final surface = find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedContainer && widget.decoration is DButtonDecoration,
    );
    final icon = find.byIcon(Icons.add);
    expect(tester.getSize(surface), const Size(50, 50));
    expect(tester.getSize(find.byType(DButton)), tester.getSize(surface));
    final decoration =
        tester.widget<AnimatedContainer>(surface).decoration!
            as DButtonDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(25));
    expect(tester.getSize(icon), const Size(20, 20));
    expect(tester.getCenter(icon), tester.getCenter(surface));
    expect(tester.getSemantics(find.byType(DButton)).label, 'New topic');
    await tester.tapAt(tester.getTopRight(surface) + const Offset(4, 25));
    expect(presses, 0);
    await tester.tap(find.byType(DButton));
    expect(presses, 1);
  });

  for (final direction in TextDirection.values) {
    testWidgets('inline actions align with surrounding text in $direction', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Topic content'),
                  DButton(
                    label: const Text('Replies'),
                    variant: DButtonVariant.inline,
                    size: DButtonSize.small,
                    onPressed: () => presses++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final content = tester.getRect(find.text('Topic content'));
      final label = tester.getRect(find.text('Replies'));
      expect(
        direction == TextDirection.ltr ? label.left : label.right,
        direction == TextDirection.ltr ? content.left : content.right,
      );
      expect(tester.getSize(find.byType(DButton)).height, 24);
      expect(buttonSurface(tester).color, Colors.transparent);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 1);
    });
  }

  for (final dark in [false, true]) {
    for (final variant in DButtonVariant.values) {
      testWidgets(
        'hover fill is stable from its first frame ($dark, $variant)',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: Center(
                  child: DButton(
                    variant: variant,
                    label: const Text('Personal'),
                    onPressed: _noop,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          Color paintedFill() => tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .map((box) => box.decoration)
              .whereType<DButtonDecoration>()
              .single
              .color;
          for (var visit = 0; visit < 2; visit++) {
            await mouse.moveTo(tester.getCenter(find.byType(DButton)));
            await tester.pump();
            final hover = buttonSurface(tester).color;
            for (final elapsed in [0, 16, 32, 75, 150]) {
              await tester.pump(Duration(milliseconds: elapsed));
              expect(paintedFill(), hover, reason: 'entry frame +$elapsed ms');
            }
            await mouse.moveTo(Offset.zero);
            await tester.pump();
            expect(paintedFill(), buttonSurface(tester).color);
            await tester.pump(const Duration(milliseconds: 16));
          }
        },
      );
    }
  }

  for (final dark in [false, true]) {
    for (final grouped in [false, true]) {
      testWidgets(
        'adjacent buttons clear hover independently (dark: $dark, grouped: $grouped)',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: TargetPlatform.macOS,
              ),
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) {
                      final children = [
                        for (var i = 0; i < 3; i++)
                          DButton.iconOnly(
                            key: ValueKey('button-$i'),
                            tooltip: 'Button $i',
                            variant: DButtonVariant.ghost,
                            onPressed: _noop,
                            icon: const Icon(Icons.settings),
                          ),
                      ];
                      return grouped
                          ? DButtonGroup(children: children)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final child in children)
                                  Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: child,
                                  ),
                              ],
                            );
                    },
                  ),
                ),
              ),
            ),
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          for (var active = 0; active < 3; active++) {
            await mouse.moveTo(
              tester.getCenter(find.byKey(ValueKey('button-$active'))),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 16));
            for (var i = 0; i < 3; i++) {
              final painted = tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byKey(ValueKey('button-$i')),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .map((box) => box.decoration)
                  .whereType<DButtonDecoration>()
                  .single;
              expect(
                painted.color.a,
                i == active ? greaterThan(0) : 0,
                reason: 'hover $active, button $i',
              );
            }
            await tester.pumpAndSettle();
          }
          await mouse.removePointer();
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets('Native text sizes retain compact surfaces', (tester) async {
    for (final (size, height, font, icon) in [
      (DButtonSize.small, 24.0, 12.5, 12.0),
      (DButtonSize.regular, 30.0, 12.5, 12.0),
      (DButtonSize.large, 40.0, 14.0, 16.0),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Center(
              child: DButton(
                label: const Text('Action'),
                icon: const Icon(Icons.add),
                onPressed: _noop,
                size: size,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rendered = find.byType(FilledButton);
      expect(tester.getSize(rendered).height, height);
      expect(tester.getSize(find.byIcon(Icons.add)), Size.square(icon));
      expect(DButton.fontSizeFor(size), font);
      expect(
        tester
            .widget<FilledButton>(rendered)
            .style!
            .textStyle!
            .resolve({})!
            .fontSize,
        font,
      );
    }
  });

  testWidgets(
    'primary actions use the pill radius and ordinary buttons use 8px',
    (tester) async {
      for (final (variant, expected) in [
        (DButtonVariant.primary, DRadius.pill),
        (DButtonVariant.outline, DRadius.control),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: DButton(
                label: const Text('Action'),
                variant: variant,
                onPressed: _noop,
              ),
            ),
          ),
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final shape =
            button.style!.shape!.resolve({})! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(expected));
      }
    },
  );

  testWidgets(
    'flat icon buttons use the fixed control radius and standard sizes',
    (tester) async {
      for (final (radius, size) in [
        (0.0, DButtonSize.small),
        (13.0, DButtonSize.regular),
        (0.0, DButtonSize.large),
      ]) {
        final base = AppTheme.light.copyWith(platform: TargetPlatform.macOS);
        final theme = base.copyWith(
          extensions: [
            ...base.extensions.values.where((value) => value is! DTokens),
            DTokens.fromTheme(base).copyWith(radius: radius),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Center(
                child: DButton.iconOnly(
                  tooltip: 'Action',
                  onPressed: _noop,
                  variant: DButtonVariant.ghost,
                  size: size,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        );

        final rendered = find.byType(FilledButton);
        final surface = find.descendant(
          of: rendered,
          matching: find.byType(Material),
        );
        final style = tester.widget<FilledButton>(rendered).style!;
        final shape = style.shape!.resolve({WidgetState.hovered});
        final targetDimension = DControlStyle.height(size);

        expect(tester.getSize(rendered), Size.square(targetDimension));
        expect(surface, findsOneWidget);
        expect(tester.getSize(surface), Size.square(targetDimension));
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
          (shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(DRadius.control),
        );
        expect(buttonSurface(tester).color, Colors.transparent);
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: Offset.zero);
        await pointer.moveTo(tester.getCenter(surface));
        await tester.pump();
        expect(
          buttonSurface(tester).color,
          DTokens.of(tester.element(rendered)).buttonTheme.accent.hover,
        );
        await pointer.removePointer();
      }
    },
  );

  testWidgets('outside the visible button neither hovers nor activates', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: DButton.iconOnly(
              tooltip: 'Action',
              onPressed: () => presses++,
              variant: DButtonVariant.ghost,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final rendered = find.byType(FilledButton);
    final surface = find.descendant(
      of: rendered,
      matching: find.byType(Material),
    );
    final targetRect = tester.getRect(rendered);
    final surfaceRect = tester.getRect(surface);
    final outside = targetRect.centerLeft - const Offset(1, 0);
    expect(targetRect, surfaceRect);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer();
    await pointer.moveTo(outside);
    await tester.pump();
    expect(buttonSurface(tester).color, Colors.transparent);
    await tester.tapAt(outside);
    await tester.pump();
    expect(presses, 0);
    await tester.tapAt(surfaceRect.center);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('buttons can override the radius for joined controls', (
    tester,
  ) async {
    const radius = BorderRadius.horizontal(left: Radius.circular(8));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Action'),
              onPressed: _noop,
              borderRadius: radius,
            ),
          ),
        ),
      ),
    );

    final rendered = tester.widget<FilledButton>(find.byType(FilledButton));
    final shape = rendered.style!.shape!.resolve({});

    expect(shape, isA<RoundedRectangleBorder>());
    expect((shape! as RoundedRectangleBorder).borderRadius, radius);
  });

  testWidgets('buttons use pointer and default cursors by enabled state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              DButton(label: Text('Action'), onPressed: _noop),
              DButton.iconOnly(
                tooltip: 'Icon action',
                onPressed: _noop,
                icon: Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );

    for (final button in tester.widgetList<FilledButton>(
      find.byType(FilledButton),
    )) {
      expect(button.style!.mouseCursor!.resolve({}), SystemMouseCursors.click);
      expect(
        button.style!.mouseCursor!.resolve({WidgetState.disabled}),
        SystemMouseCursors.basic,
      );
    }
  });

  testWidgets('interactive background can stay transparent', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: DButton.iconOnly(
              tooltip: 'Action',
              onPressed: _noop,
              variant: DButtonVariant.ghost,
              interactiveBackgroundColor: Colors.transparent,
              focusNode: focus,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(FilledButton));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(center);
    await tester.pump();
    expect(buttonSurface(tester).color, Colors.transparent, reason: 'hover');
    await mouse.down(center);
    await tester.pump();
    expect(buttonSurface(tester).color, Colors.transparent, reason: 'press');
    await mouse.up();
    await mouse.moveTo(Offset.zero);
    focus.requestFocus();
    await tester.pump();
    expect(buttonSurface(tester).color, Colors.transparent, reason: 'focus');
  });

  testWidgets('the loading spinner keeps the reference 16px in every size', (
    tester,
  ) async {
    for (final size in DButtonSize.values) {
      for (final iconOnly in [false, true]) {
        await _pumpButton(
          tester,
          iconOnly
              ? DButton.iconOnly(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                  size: size,
                  loading: true,
                  onPressed: _noop,
                )
              : DButton(
                  label: const Text('Save'),
                  loadingLabel: const Text('Saving'),
                  size: size,
                  loading: true,
                  onPressed: _noop,
                ),
        );
        expect(
          tester.getSize(find.byType(DSpinner)),
          const Size.square(16),
          reason: '${size.name} ${iconOnly ? 'icon' : 'text'}',
        );
      }
    }
  });

  testWidgets('shortcut tooltips render platform keycaps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Reply'),
              tooltip: 'Reply to this topic',
              tooltipSide: DTooltipSide.right,
              shortcut: DShortcut(
                SingleActivator(LogicalKeyboardKey.keyR, shift: true),
              ),
              onPressed: _noop,
            ),
          ),
        ),
      ),
    );

    final tooltip = find.byType(DTooltip);
    expect(
      tester.widget<DTooltip>(tooltip).semanticsTooltip,
      'Reply to this topic',
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tooltip));
    await tester.pump(DTooltip.defaultHoverDelay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final message = find.text('Reply to this topic');
    expect(
      tester.getRect(message).left,
      greaterThan(tester.getRect(find.byType(DButton)).right),
    );
    expect(DefaultTextStyle.of(tester.element(message)).style.fontSize, 12);
    expect(find.byType(DKbd), findsNWidgets(2));
    expect(find.text('⇧'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);

    DKbd keycap(int index) =>
        tester.widget<DKbd>(find.byKey(ValueKey('shortcut-key-0-$index')));

    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);
  });

  testWidgets('shortcut sequences retain completed key highlights', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: Center(
            child: DTooltip(
              message: 'Open projects',
              shortcut: DShortcut.sequence(
                SingleActivator(LogicalKeyboardKey.keyP),
                [SingleActivator(LogicalKeyboardKey.keyK)],
              ),
              child: Text('Projects'),
            ),
          ),
        ),
      ),
    );

    final tooltip = find.byType(DTooltip);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tooltip));
    await tester.pump(DTooltip.defaultHoverDelay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    DKbd keycap(int step) =>
        tester.widget<DKbd>(find.byKey(ValueKey('shortcut-key-$step-0')));

    expect(find.byType(DKbd), findsNWidgets(2));
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(keycap(0).highlighted, isTrue);
    expect(keycap(1).highlighted, isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(keycap(0).highlighted, isFalse);
    expect(keycap(1).highlighted, isFalse);
  });

  for (final (description, label, name) in [
    ('text', const Text('Save changes'), 'Save changes'),
    (
      'rich text',
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text.rich(
          TextSpan(
            text: 'Save ',
            children: [
              TextSpan(text: 'changes', semanticsLabel: 'preferences'),
            ],
          ),
        ),
      ),
      'Save preferences',
    ),
    (
      'custom widget',
      Semantics(
        label: 'Save preferences',
        excludeSemantics: true,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('Save'), Text(' changes')],
        ),
      ),
      'Save preferences',
    ),
  ]) {
    testWidgets('$description button keeps its name while loading', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var presses = 0;
        var expectedPresses = 0;
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(label: label, onPressed: () => presses++, loading: loading),
          );

          _expectButtonSemantics(tester, label: name, loading: loading);
          await tester.tap(find.byType(DButton));
          if (!loading) expectedPresses++;
          expect(presses, expectedPresses);

          if (loading) {
            final rendered = find.byType(FilledButton);
            expect(tester.getSize(rendered).width, moreOrLessEquals(36));
            expect(tester.getSize(rendered).height, moreOrLessEquals(30));
            expect(rendered, paintsExactlyCountTimes(#drawParagraph, 0));
            expect(find.byType(DSpinner), findsOneWidget);
          }
        }
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('loading text does not replace or duplicate the button name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final loadingText in ['Saving changes…', 'Save changes']) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(
              label: const Text('Save changes'),
              icon: const Icon(Icons.save, semanticLabel: 'Decorative icon'),
              loadingLabel: Text(loadingText),
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: 'Save changes',
            loading: loading,
          );
          if (loading) {
            expect(
              find.byType(FilledButton),
              paintsExactlyCountTimes(#drawParagraph, 1),
            );
            expect(find.byType(DSpinner), findsOneWidget);
          }
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('retained names do not affect loading geometry or baselines', (
    tester,
  ) async {
    for (final loadingLabel in [null, const Text('Saving changes…')]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  for (final semanticLabel in [null, 'Save preferences'])
                    IntrinsicWidth(
                      child: DButton(
                        label: const Text('Save changes to all preferences'),
                        semanticLabel: semanticLabel,
                        loadingLabel: loadingLabel,
                        loading: true,
                        onPressed: _noop,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final buttons = find.byType(FilledButton);
      final retainedNameRect = tester.getRect(buttons.at(0));
      final explicitNameRect = tester.getRect(buttons.at(1));
      expect(retainedNameRect.size, explicitNameRect.size);
      expect(retainedNameRect.top, explicitNameRect.top);
    }
  });

  testWidgets('explicit button names override labels and tooltips while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final loadingLabel in [null, const Text('Saving changes…')]) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton(
              label: const Text.rich(TextSpan(text: 'Save changes')),
              icon: const Icon(Icons.save, semanticLabel: 'Decorative icon'),
              tooltip: 'Save these settings',
              semanticLabel: 'Save preferences',
              loadingLabel: loadingLabel,
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: 'Save preferences',
            loading: loading,
          );
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('icon buttons retain their tooltip or explicit name while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final semanticLabel in [null, 'Add an item']) {
        for (final loading in [false, true, false]) {
          await _pumpButton(
            tester,
            DButton.iconOnly(
              icon: const Icon(Icons.add, semanticLabel: 'Decorative icon'),
              tooltip: 'Add',
              semanticLabel: semanticLabel,
              onPressed: _noop,
              loading: loading,
            ),
          );

          _expectButtonSemantics(
            tester,
            label: semanticLabel ?? 'Add',
            tooltip: '',
            loading: loading,
          );
          expect(
            tester.getSize(find.byType(FilledButton)),
            const Size.square(30),
          );
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('loading labels keep progress visible on text buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: DButton(
              label: Text('Save changes'),
              loadingLabel: Text('Saving changes…'),
              semanticLabel: 'Saving preferences',
              onPressed: _noop,
              loading: true,
              variant: DButtonVariant.primary,
            ),
          ),
        ),
      ),
    );

    final rendered = find.byType(FilledButton);
    final semantics = tester.ensureSemantics();
    try {
      expect(find.text('Save changes'), findsNothing);
      expect(find.text('Saving changes…'), findsOneWidget);
      expect(find.byType(DSpinner), findsOneWidget);
      expect(
        tester.getSize(rendered).width,
        greaterThan(tester.getSize(rendered).height),
      );
      expect(tester.widget<FilledButton>(rendered).onPressed, isNull);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Saving preferences')),
        isSemantics(
          label: 'Saving preferences',
          value: 'Loading',
          isButton: true,
          isEnabled: false,
          isLiveRegion: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pumpButton(WidgetTester tester, DButton button) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: button)),
      ),
    );

void _expectButtonSemantics(
  WidgetTester tester, {
  required String label,
  required bool loading,
  String tooltip = '',
}) {
  expect(
    tester.getSemantics(find.byType(DButton)),
    isSemantics(
      label: label,
      tooltip: tooltip,
      value: loading ? 'Loading' : '',
      isButton: true,
      hasEnabledState: true,
      isEnabled: !loading,
      hasTapAction: !loading,
      isLiveRegion: loading,
    ),
  );
}

void _noop() {}
