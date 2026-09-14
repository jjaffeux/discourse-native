import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/header_notification_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final rtl in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('capsules fit 320px, dark=$dark rtl=$rtl scale=$scale', (
          tester,
        ) async {
          final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
            platform: TargetPlatform.macOS,
          );
          final semantics = tester.ensureSemantics();
          try {
            var opened = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: Directionality(
                        textDirection: rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Center(
                          child: SizedBox(
                            width: 320,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                for (final (index, color) in [
                                  (0, theme.discourse.success),
                                  (1, theme.discourse.notificationIndicator),
                                ])
                                  headerNotificationButton(
                                    context,
                                    key: ValueKey('button-$index'),
                                    countKey: ValueKey('count-$index'),
                                    icon: DIcon(
                                      index == 0 ? DIcons.comment : DIcons.bell,
                                      size: 20,
                                    ),
                                    count: 128,
                                    color: color,
                                    surface: theme.shell.content,
                                    tooltip: index == 0
                                        ? 'Chat'
                                        : 'Notifications',
                                    semanticLabel:
                                        '${index == 0 ? 'Chat' : 'Notifications'}, 128 unread',
                                    onPressed: () => opened++,
                                  ),
                                const SizedBox(width: 32, height: 32),
                              ],
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
            expect(tester.takeException(), isNull);
            expect(find.text('99+'), findsNWidgets(2));
            final first = tester.getRect(
              find.byKey(const ValueKey('button-0')),
            );
            final second = tester.getRect(
              find.byKey(const ValueKey('button-1')),
            );
            expect(first.overlaps(second), isFalse);
            for (var index = 0; index < 2; index++) {
              final button = find.byKey(ValueKey('button-$index'));
              final count = find.byKey(ValueKey('count-$index'));
              expect(
                tester.widget<Text>(count).textDirection,
                TextDirection.ltr,
              );
              final bounds = tester.getRect(button);
              expect(bounds.contains(tester.getTopLeft(count)), isTrue);
              expect(bounds.contains(tester.getBottomRight(count)), isTrue);
              final control = tester.widget<DButton>(button);
              for (final fill in [
                control.backgroundColor!,
                control.interactiveBackgroundColor!,
              ]) {
                final painted = Color.alphaBlend(fill, theme.shell.content);
                final a = painted.computeLuminance();
                final b = control.foregroundColor!.computeLuminance();
                expect(
                  (math.max(a, b) + .05) / (math.min(a, b) + .05),
                  greaterThanOrEqualTo(4.5),
                );
              }
              expect(tester.getSemantics(button).label, contains('128 unread'));
              await tester.tap(button);
            }
            expect(opened, 2);
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
