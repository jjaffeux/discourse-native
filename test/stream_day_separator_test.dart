import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  testWidgets('pinned dates keep flat fills and exact chip targets', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        for (final scale in [1.0, 2.0]) {
          var taps = 0;
          final theme = AppTheme.forBrightness(
            brightness,
          ).copyWith(platform: platform);
          await tester.pumpWidget(
            MaterialApp(
              themeAnimationStyle: AnimationStyle.noAnimation,
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
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
          expect(buttonSurface(tester, of: button).color, theme.shell.content);
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
  });
}
