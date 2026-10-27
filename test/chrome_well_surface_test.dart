import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'chrome capsule and well edges match their references in light and dark',
    (tester) async {
      const key = ValueKey('chrome-well');
      const canvas = Color(0xff4e4264);
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          final theme = AppTheme.forBrightness(brightness);
          Future<void> mount(Widget child) async {
            await tester.pumpWidget(
              MaterialApp(
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: theme,
                home: Material(
                  type: MaterialType.transparency,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Center(
                      child: RepaintBoundary(
                        key: key,
                        child: ColoredBox(color: canvas, child: child),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          Future<(ui.Image, ByteData)> pixels() async =>
              (await tester.runAsync(() async {
                final image = await tester
                    .renderObject<RenderRepaintBoundary>(find.byKey(key))
                    .toImage(pixelRatio: 2);
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                return (image, bytes);
              }))!;

          // The capsule is a bar group, edged as the search input is. The
          // sidebar switch is a well, which app.css draws as the groups' fill
          // ringed inside by the 12% border-subtle line alone, with none of
          // their lighting: `:is(.glass-well, .glass-inset)`.
          for (final (name, control, ringed) in <(String, Widget, bool)>[
            (
              'navigation capsule',
              IntrinsicWidth(
                child: DCard(
                  variant: DCardVariant.capsule,
                  size: DCardSize.small,
                  borderColor: Colors.transparent,
                  child: SizedBox(width: 140, height: 24 * scale),
                ),
              ),
              false,
            ),
            (
              'sidebar switch',
              const SizedBox(
                width: 126,
                child: DTabs<String>(
                  selectFirstOnMount: false,
                  children: [
                    DTabList<String>(
                      expandSelected: true,
                      children: [
                        DTabTrigger(
                          value: 'forum',
                          selectedLabelOnly: true,
                          semanticLabel: 'Forum',
                          child: Text('Forum'),
                        ),
                        DTabTrigger(
                          value: 'chat',
                          selectedLabelOnly: true,
                          semanticLabel: 'Chat',
                          child: Text('Chat'),
                        ),
                        DTabTrigger(
                          value: 'shortcuts',
                          selectedLabelOnly: true,
                          semanticLabel: 'Shortcuts',
                          child: Text('Shortcuts'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              true,
            ),
          ]) {
            await mount(control);
            final size = tester.getSize(find.byKey(key));

            final (actual, actualBytes) = await pixels();
            await mount(
              SizedBox(
                width: size.width,
                height: size.height,
                child: ringed
                    ? Builder(
                        builder: (context) {
                          final tokens = DTokens.of(context);
                          final dark = brightness == Brightness.dark;
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(
                                alpha: dark ? .16 : .045,
                              ),
                              border: Border.all(
                                color: Color.lerp(
                                  tokens.background,
                                  tokens.foreground,
                                  .12,
                                )!,
                              ),
                              borderRadius: BorderRadius.circular(DRadius.pill),
                            ),
                          );
                        },
                      )
                    : DInputGroup(
                        variant: DInputGroupVariant.search,
                        viewportHeight: size.height,
                        children: [DInputGroupInput()],
                      ),
              ),
            );
            final (reference, referenceBytes) = await pixels();
            try {
              expect(actual.width, reference.width);
              expect(actual.height, reference.height);
              final interior = RRect.fromRectAndRadius(
                Offset.zero & size,
                const Radius.circular(999),
              ).deflate(1);
              // Compare the entire outer 1px and the transparent corners.
              // Content and the switch's selected tab sit further inside.
              for (var y = 0; y < actual.height; y++) {
                for (var x = 0; x < actual.width; x++) {
                  if (interior.contains(Offset((x + .5) / 2, (y + .5) / 2))) {
                    continue;
                  }
                  final offset = (y * actual.width + x) * 4;
                  for (var channel = 0; channel < 4; channel++) {
                    expect(
                      actualBytes.getUint8(offset + channel),
                      closeTo(referenceBytes.getUint8(offset + channel), 3),
                      reason: '$name $brightness flat ${scale}x ($x,$y)',
                    );
                  }
                }
              }
            } finally {
              actual.dispose();
              reference.dispose();
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
