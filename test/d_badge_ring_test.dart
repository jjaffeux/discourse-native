import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final variant in [
      DBadgeVariant.ghost,
      DBadgeVariant.outline,
      DBadgeVariant.destructive,
    ]) {
      testWidgets(
        '${dark ? 'dark' : 'light'} ${variant.name} ring preserves interior and idle invalid has only a border',
        (tester) async {
          final key = GlobalKey();
          final focus = FocusNode();
          addTearDown(focus.dispose);
          final background = dark ? Colors.black : Colors.white;
          final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
            platform: TargetPlatform.macOS,
          );
          Future<void> mount({
            bool invalid = false,
            bool enabled = true,
            bool reducedMotion = false,
            double radius = 4,
          }) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme.copyWith(
                  extensions: [
                    theme.extension<DTokens>()!.copyWith(radius: radius),
                  ],
                ),
                home: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox(
                      width: 160,
                      height: 100,
                      child: ColoredBox(
                        color: background,
                        child: MediaQuery(
                          data: MediaQueryData(
                            disableAnimations: reducedMotion,
                          ),
                          child: Center(
                            child: DBadge.action(
                              variant: variant,
                              invalid: invalid,
                              focusNode: focus,
                              onPressed: enabled ? () {} : null,
                              child: const SizedBox(width: 80, height: 36),
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

          Future<List<int>> pixels() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            return (await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              // Center; 1/2/3/4 pixels above the 40px visual; inner border;
              // corner outside the rounded badge and ring.
              final result = [
                for (final point in [
                  (80, 50),
                  (80, 29),
                  (80, 28),
                  (80, 27),
                  (80, 26),
                  (80, 30),
                  (31, 30),
                ])
                  data.getUint32((point.$2 * 160 + point.$1) * 4),
              ];
              image.dispose();
              return result;
            }))!;
          }

          await mount();
          final idle = await pixels();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final focused = await pixels();
          expect(focus.hasFocus, isTrue);
          final tokens = theme.extension<DTokens>()!;
          void expectRingColor(int rgba, Color color) {
            final expected = Color.alphaBlend(color, background).toARGB32();
            for (final (actualShift, expectedShift) in [
              (24, 16),
              (16, 8),
              (8, 0),
            ]) {
              expect(
                (rgba >> actualShift) & 255,
                closeTo((expected >> expectedShift) & 255, 1),
              );
            }
            expect(rgba & 255, 255);
          }

          expectRingColor(
            focused[2],
            variant == DBadgeVariant.destructive
                ? tokens.destructive.withValues(alpha: dark ? .4 : .2)
                : tokens.focusRing.withValues(alpha: .5),
          );

          expect(
            focused[0],
            idle[0],
            reason: 'focus must not tint the transparent/translucent interior',
          );
          for (final i in [1, 2, 3]) {
            expect(focused[i], isNot(idle[i]), reason: '3px exterior ring');
          }
          expect(focused[4], idle[4], reason: 'ring stops after 3px');
          expect(
            focused[6],
            idle[6],
            reason: 'rounded corner remains outside the ring',
          );
          focus.unfocus();
          await tester.pumpAndSettle();
          expect(await pixels(), idle);
          await mount(invalid: true);
          final invalid = await pixels();
          expect(invalid[0], idle[0]);
          expect(
            invalid.sublist(1, 5),
            idle.sublist(1, 5),
            reason: 'aria-invalid sets ring color, not width',
          );
          expect(
            invalid[5],
            isNot(idle[5]),
            reason: 'idle invalid border remains visible',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          // The 150ms cubic-bezier(.4, 0, .2, 1) transition is ~45% complete
          // at 50ms, so the ring is 1-2px wide and the second exterior pixel
          // is only partly covered.
          await tester.pump(const Duration(milliseconds: 50));
          final halfway = await pixels();
          expect(halfway[0], idle[0]);
          await tester.pumpAndSettle();
          final invalidFocused = await pixels();
          expectRingColor(
            invalidFocused[2],
            tokens.destructive.withValues(alpha: dark ? .4 : .2),
          );

          expect(invalidFocused[0], idle[0]);
          expect(halfway[2], isNot(invalid[2]));
          expect(
            halfway[2],
            isNot(invalidFocused[2]),
            reason: 'ring animates rather than appearing abruptly',
          );
          expect(invalidFocused[2], isNot(invalid[2]));
          await mount(invalid: true, enabled: false);
          expect(
            (await pixels()).sublist(1, 5),
            idle.sublist(1, 5),
            reason: 'disabled cannot retain focus ring',
          );
          await mount(reducedMotion: true, radius: 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final square = await pixels();
          expect(square[0], idle[0]);
          expect(
            square[2],
            isNot(idle[2]),
            reason: 'reduced motion paints final ring immediately',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
