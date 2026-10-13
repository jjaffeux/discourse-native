import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/header_notification_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large overlay counts keep the bell visible at 200% text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: headerNotificationButton(
                context,
                key: const ValueKey('bell'),
                countKey: const ValueKey('badge'),
                icon: const DIcon(DIcons.bell, size: 17),
                count: 128,
                color: Theme.of(context).discourse.notificationIndicator,
                surface: Theme.of(context).shell.content,
                tooltip: 'Notifications',
                semanticLabel: 'Notifications, 128 unread',
                onPressed: () {},
                overlayCount: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final glyph = tester.getRect(find.byType(DIcon));
    final badge = tester.getRect(find.byKey(const ValueKey('badge')));
    expect(badge.bottom - glyph.top, closeTo(6, .01));
    expect(glyph.bottom - badge.bottom, greaterThan(10));
    expect(find.text('99+'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final expanded in [false, true]) {
      for (final overlay in [false, true]) {
        testWidgets(
          'notification state dark=$dark open=$expanded overlay=$overlay',
          (tester) async {
            final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
              platform: TargetPlatform.macOS,
            );
            final semantics = tester.ensureSemantics();
            try {
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  home: Scaffold(
                    body: Builder(
                      builder: (context) {
                        return Center(
                          child: headerNotificationButton(
                            context,
                            key: const ValueKey('button'),
                            countKey: const ValueKey('count'),
                            icon: DIcon(
                              overlay ? DIcons.bell : DIcons.comment,
                              size: overlay ? 17 : 16,
                            ),
                            count: 3,
                            color: theme.discourse.success,
                            surface: theme.shell.content,
                            tooltip: 'Notifications',
                            semanticLabel: 'Notifications, 3 unread',
                            onPressed: () {},
                            hasPopup: true,
                            expanded: expanded,
                            overlayCount: overlay,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final button = find.byKey(const ValueKey('button'));
              final count = find.byKey(const ValueKey('count'));
              final control = tester.widget<DButton>(button);
              expect(
                control.variant,
                expanded ? DButtonVariant.primary : DButtonVariant.ghost,
              );
              expect(control.backgroundColor, isNull);
              expect(control.shape, DButtonShape.pill);
              expect(
                count,
                overlay && expanded ? findsNothing : findsOneWidget,
              );
              if (overlay && !expanded) {
                expect(tester.widget(count), isA<DBadge>());
                final badge = tester.widget<DBadge>(count);
                final primary = DTokens.of(
                  tester.element(button),
                ).buttonTheme.primary;
                expect(badge.backgroundColor, primary.background);
                expect(badge.foregroundColor, primary.foreground);
                final glyph = find.descendant(
                  of: button,
                  matching: find.byType(DIcon),
                );
                expect(
                  tester.getRect(count).center.dy,
                  lessThan(tester.getRect(glyph).top),
                );
              }
              expect(
                find.descendant(of: button, matching: find.byType(DSeparator)),
                overlay ? findsNothing : findsOneWidget,
              );
              if (!overlay) {
                final bounds = tester.getRect(button);
                final glyph = tester.getRect(
                  find.descendant(of: button, matching: find.byType(DIcon)),
                );
                final separator = tester.getRect(
                  find.descendant(
                    of: button,
                    matching: find.byType(DSeparator),
                  ),
                );
                final text = tester.getRect(count);
                expect(bounds.height, 28);
                expect(glyph.left - bounds.left, 10);
                expect(separator.left - glyph.right, 8);
                expect(text.left - separator.right, 8);
                expect(bounds.right - text.right, 10);
              } else {
                expect(tester.getSize(button), const Size(32, 28));
              }
              expect(
                tester.getSemantics(button).label,
                'Notifications, 3 unread',
              );
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
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
                                      size: index == 0 ? 16 : 17,
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
              expect(control.variant, DButtonVariant.ghost);
              expect(control.shape, DButtonShape.pill);
              expect(control.backgroundColor, isNull);
              final tokens = DTokens.of(tester.element(button));
              for (final fill in [
                Colors.transparent,
                tokens.buttonTheme.accent.hover,
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
