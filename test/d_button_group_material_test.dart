import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('joined material fills continue through square inner corners', (
    tester,
  ) async {
    final shadowsDisabled = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final brightness in Brightness.values) {
        for (final direction in TextDirection.values) {
          for (final axis in Axis.values) {
            const capture = ValueKey('joined-fill');
            final horizontal = axis == Axis.horizontal;
            await tester.pumpWidget(
              MaterialApp(
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: AppTheme.forBrightness(
                  brightness,
                ).copyWith(platform: TargetPlatform.iOS),
                home: Directionality(
                  textDirection: direction,
                  child: Center(
                    child: RepaintBoundary(
                      key: capture,
                      child: ColoredBox(
                        color: const Color(0xff2154c1),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: DButtonGroup(
                            orientation: horizontal
                                ? DButtonGroupOrientation.horizontal
                                : DButtonGroupOrientation.vertical,
                            children: [
                              for (final label in ['Bookmark', 'Notifications'])
                                DButton.iconOnly(
                                  size: DButtonSize.filter,
                                  icon: const SizedBox.shrink(),
                                  tooltip: label,
                                  variant: DButtonVariant.outline,
                                  onPressed: () {},
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final origin = tester.getTopLeft(find.byKey(capture));
            final group = tester
                .getRect(find.byType(DButtonGroup))
                .shift(-origin);
            final description = 'flat $brightness $direction $axis';
            await tester.runAsync(() async {
              final image = await tester
                  .renderObject<RenderRepaintBoundary>(find.byKey(capture))
                  .toImage(pixelRatio: 3);
              try {
                final directory =
                    Platform.environment['JOINED_MATERIAL_EXPORT_DIR'];
                if (directory != null) {
                  await Directory(directory).create(recursive: true);
                  final png = (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!;
                  await File(
                    '$directory/$description.png',
                  ).writeAsBytes(png.buffer.asUint8List());
                }
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                int blueAt(double x, double y) => bytes.getUint8(
                  ((y * 3).floor() * image.width + (x * 3).floor()) * 4 + 2,
                );
                // A square join must never show a hole where a rounded
                // segment fails to fill it.
                for (final inset in [3.0, 4.0]) {
                  for (final trailing in [false, true]) {
                    final cross = horizontal
                        ? trailing
                              ? group.bottom - inset
                              : group.top + inset
                        : trailing
                        ? group.right - inset
                        : group.left + inset;
                    final start = horizontal ? group.left + 13 : group.top + 13;
                    final end = horizontal
                        ? group.right - 13
                        : group.bottom - 13;
                    final expected = horizontal
                        ? blueAt(start, cross)
                        : blueAt(cross, start);
                    for (
                      var position = start;
                      position <= end;
                      position += .5
                    ) {
                      final seam = horizontal
                          ? group.center.dx
                          : group.center.dy;
                      if ((position - seam).abs() < 1.5) continue;
                      final actual = horizontal
                          ? blueAt(position, cross)
                          : blueAt(cross, position);
                      expect(
                        actual,
                        closeTo(expected, 12),
                        reason:
                            '$description inset=$inset trailing=$trailing position=$position',
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
    } finally {
      debugDisableShadows = shadowsDisabled;
    }
  });

  {
    for (final brightness in Brightness.values) {
      for (final direction in TextDirection.values) {
        for (final axis in Axis.values) {
          testWidgets(
            'joined shadow is continuous: flat $brightness $direction $axis',
            (tester) async {
              final shadowsDisabled = debugDisableShadows;
              debugDisableShadows = false;
              try {
                const canvas = Color(0xff2154c1);
                const capture = ValueKey('joined-shadow');
                var taps = 0;
                final horizontal = axis == Axis.horizontal;
                await tester.pumpWidget(
                  MaterialApp(
                    themeAnimationStyle: AnimationStyle.noAnimation,
                    theme: AppTheme.forBrightness(
                      brightness,
                    ).copyWith(platform: TargetPlatform.macOS),
                    home: Directionality(
                      textDirection: direction,
                      child: Center(
                        child: RepaintBoundary(
                          key: capture,
                          child: ColoredBox(
                            color: canvas,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: DButtonGroup(
                                orientation: horizontal
                                    ? DButtonGroupOrientation.horizontal
                                    : DButtonGroupOrientation.vertical,
                                children: [
                                  DButton.iconOnly(
                                    icon: const Icon(Icons.remove),
                                    tooltip: 'Decrease',
                                    variant: DButtonVariant.outline,
                                    onPressed: () => taps++,
                                  ),
                                  if (horizontal)
                                    const DButtonGroupText(child: Text('100%'))
                                  else
                                    DButton.iconOnly(
                                      icon: const Icon(Icons.refresh),
                                      tooltip: 'Reset',
                                      variant: DButtonVariant.outline,
                                      onPressed: () => taps++,
                                    ),
                                  DButton.iconOnly(
                                    icon: const Icon(Icons.add),
                                    tooltip: 'Increase',
                                    variant: DButtonVariant.outline,
                                    onPressed: () => taps++,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                final origin = tester.getTopLeft(find.byKey(capture));
                final group = tester
                    .getRect(find.byType(DButtonGroup))
                    .shift(-origin);
                final captureData = (await tester.runAsync(() async {
                  final image = await tester
                      .renderObject<RenderRepaintBoundary>(find.byKey(capture))
                      .toImage(pixelRatio: 2);
                  try {
                    final pixels = (await image.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    ))!;
                    return (pixels, image.width);
                  } finally {
                    image.dispose();
                  }
                }))!;
                final (pixels, imageWidth) = captureData;
                int blueAt(double x, double y) => pixels.getUint8(
                  ((y * 2).floor() * imageWidth + (x * 2).floor()) * 4 + 2,
                );
                final start = horizontal ? group.left + 16 : group.top + 16;
                final end = horizontal ? group.right - 16 : group.bottom - 16;
                final shadow = horizontal
                    ? blueAt(group.center.dx, group.bottom + 1)
                    : blueAt(group.right + 1, group.center.dy);
                expect(
                  shadow,
                  0xc1,
                  reason: 'Flat controls leave the surrounding canvas clear.',
                );
                for (var position = start; position <= end; position += .5) {
                  final actual = horizontal
                      ? blueAt(position, group.bottom + 1)
                      : blueAt(group.right + 1, position);
                  expect(
                    actual,
                    closeTo(shadow, 1),
                    reason: 'No shadow seams at $position.',
                  );
                }
                // Passive text and the outer shadow must not enlarge the targets.
                if (horizontal) {
                  await tester.tap(find.byType(DButtonGroupText));
                  expect(taps, 0);
                }
                await tester.tapAt(
                  origin + Offset(group.center.dx, group.bottom + 2),
                );
                expect(taps, 0);
                await tester.tap(find.byTooltip('Increase'));
                expect(taps, 1);
                expect(tester.takeException(), isNull);
              } finally {
                debugDisableShadows = shadowsDisabled;
              }
            },
          );
        }
      }
    }
  }
}
