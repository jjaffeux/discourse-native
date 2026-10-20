import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'support/button_surface.dart';
import 'support/stock_glass.dart';

void main() {
  testWidgets('only pinned action dates use the denser frosted glass', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.forBrightness(brightness);
      for (final floating in [false, true]) {
        for (final interactive in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: DMaterialTheme.apply(
                theme,
                DAppearanceMaterial.liquidGlass,
              ),
              home: Center(
                child: StreamDaySeparator(
                  day: DateTime(2020, 1, 2),
                  floating: floating,
                  onTap: interactive ? () {} : null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final lens = find.byType(LiquidGlass);
          if (!interactive) {
            expect(lens, findsNothing);
          } else {
            if (floating) {
              final tint = theme.extension<DTokens>()!.surface.withValues(
                alpha: .68,
              );
              expectStockGlass(
                tester,
                lens,
                tint: tint,
                frost: 16,
                saturation: 1.85,
              );
            } else {
              final tint = tester
                  .widget<DButton>(find.byType(DButton))
                  .backgroundColor!
                  .withValues(alpha: .76);
              expectStockGlass(tester, lens, tint: tint);
            }
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('pinned dates keep fallback fills and exact chip targets', (
    tester,
  ) async {
    const channel = MethodChannel(
      'org.discourse.native/material_accessibility',
    );
    var reduceTransparency = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => reduceTransparency,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    for (final brightness in Brightness.values) {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        for (final scale in [1.0, 2.0]) {
          for (final (material, highContrast, reduced) in [
            (null, false, false),
            (DAppearanceMaterial.standard, false, false),
            (DAppearanceMaterial.liquidGlass, false, false),
            (DAppearanceMaterial.liquidGlass, true, false),
            (DAppearanceMaterial.liquidGlass, false, true),
          ]) {
            await tester.pumpWidget(const SizedBox());
            reduceTransparency = reduced;
            var taps = 0;
            final baseTheme = AppTheme.forBrightness(
              brightness,
            ).copyWith(platform: platform);
            final theme = material == null
                ? baseTheme
                : DMaterialTheme.apply(baseTheme, material);
            await tester.pumpWidget(
              MaterialApp(
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: theme,
                home: DMaterialAccessibility(
                  child: MediaQuery(
                    data: MediaQueryData(
                      highContrast: highContrast,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DButton(
                            key: const ValueKey('ordinary-chip'),
                            variant: DButtonVariant.outline,
                            size: DButtonSize.chip,
                            shape: DButtonShape.pill,
                            label: const Text(
                              '2 January 2020',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            onPressed: () {},
                          ),
                          StreamDaySeparator(
                            day: DateTime(2020, 1, 2),
                            floating: true,
                            onTap: () => taps++,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final button = find.descendant(
              of: find.byType(StreamDaySeparator),
              matching: find.byType(DButton),
            );
            final rect = tester.getRect(button);
            expect(
              rect.size,
              tester.getSize(find.byKey(const ValueKey('ordinary-chip'))),
            );
            expect(
              rect,
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
            final glass =
                material == DAppearanceMaterial.liquidGlass &&
                !highContrast &&
                !reduced;
            expect(
              find.descendant(of: button, matching: find.byType(LiquidGlass)),
              glass ? findsOneWidget : findsNothing,
            );
            if (!glass) {
              if (material == null) {
                expect(
                  buttonSurface(tester, of: button).color,
                  theme.shell.content,
                );
              } else {
                expect(
                  tester
                      .widgetList<DecoratedBox>(
                        find.descendant(
                          of: button,
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .map((box) => box.decoration)
                      .whereType<BoxDecoration>()
                      .any(
                        (decoration) => decoration.color == theme.shell.content,
                      ),
                  isTrue,
                );
              }
            }
            await tester.tapAt(rect.topCenter - const Offset(0, 1));
            expect(taps, 0);
            await tester.tapAt(rect.center);
            await tester.pump();
            expect(taps, 1);
            expect(
              find.bySemanticsLabel('Go to start of 2 January 2020'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
}
