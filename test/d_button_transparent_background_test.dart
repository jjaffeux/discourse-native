import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  for (final variant in [
    DButtonVariant.ghost,
    DButtonVariant.transparentBackground,
    DButtonVariant.inline,
  ]) {
    testWidgets('$variant separates enabled actions from pale metadata', (
      tester,
    ) async {
      final forumLight = AppTheme.fromPalette(
        ResolvedSitePalette.fromJson(const {
          'brightness': 'light',
          'primary': 0xFF222222,
          'secondary': 0xFFFFFFFF,
          'tertiary': 0xFF0088CC,
          'metadataColor': 0xFF999999,
        }),
      );
      for (final theme in [
        forumLight,
        AppTheme.light,
        StyleguideTheme.forest.resolve(AppTheme.light),
        AppTheme.dark,
        StyleguideTheme.plum.resolve(AppTheme.light),
        forumLight,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Row(
                children: [
                  DButton(
                    label: const Text('Reply'),
                    icon: const DIcon(DIcons.reply, key: ValueKey('enabled')),
                    variant: variant,
                    onPressed: () {},
                  ),
                  DButton.iconOnly(
                    icon: const DIcon(DIcons.reply, key: ValueKey('disabled')),
                    tooltip: 'Unavailable reply',
                    variant: variant,
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tokens = DTokens.of(tester.element(find.text('Reply')));
        final foreground = IconTheme.of(
          tester.element(find.byKey(const ValueKey('enabled'))),
        ).color!;
        expect(
          DefaultTextStyle.of(tester.element(find.text('Reply'))).style.color,
          foreground,
        );
        expect(
          IconTheme.of(
            tester.element(find.byKey(const ValueKey('disabled'))),
          ).color,
          tokens.mutedForeground,
        );
        if (theme.brightness == Brightness.light) {
          expect(
            foreground.computeLuminance(),
            lessThan(tokens.mutedForeground.computeLuminance()),
          );
          for (final surface in [tokens.background, tokens.surface]) {
            expect(
              (surface.computeLuminance() + .05) /
                  (foreground.computeLuminance() + .05),
              greaterThanOrEqualTo(4.5),
            );
          }
        } else {
          expect(foreground, tokens.mutedForeground);
        }
      }
    });
  }

  for (final dark in [false, true]) {
    for (final iconOnly in [false, true]) {
      testWidgets(
        'transparent actions reveal a subtle hover fill (dark: $dark, icon: $iconOnly)',
        (tester) async {
          final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
            platform: TargetPlatform.macOS,
          );
          final focus = FocusNode();
          addTearDown(focus.dispose);
          var activations = 0;
          Future<void> pump({bool expanded = false}) => tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: iconOnly
                      ? DButton.iconOnly(
                          icon: const DIcon(DIcons.reply),
                          tooltip: 'Reply',
                          variant: DButtonVariant.transparentBackground,
                          focusNode: focus,
                          expanded: expanded,
                          onPressed: () => activations++,
                        )
                      : DButton(
                          label: const Text('Reply'),
                          icon: const DIcon(DIcons.reply),
                          variant: DButtonVariant.transparentBackground,
                          focusNode: focus,
                          expanded: expanded,
                          onPressed: () => activations++,
                        ),
                ),
              ),
            ),
          );
          await pump();
          final tokens = DTokens.of(tester.element(find.byType(DButton)));
          Color foreground() =>
              IconTheme.of(tester.element(find.byType(DIcon))).color!;
          void expectForeground(Color color, {bool filled = false}) {
            expect(foreground(), color);
            if (!iconOnly) {
              expect(
                DefaultTextStyle.of(
                  tester.element(find.text('Reply')),
                ).style.color,
                color,
              );
            }
            expect(
              buttonSurface(tester).color,
              filled ? DControlStyle.rowHover(tokens) : Colors.transparent,
            );
          }

          final resting = foreground();
          expect(resting, isNot(tokens.foreground));
          expectForeground(resting);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(find.byType(DButton)));
          await tester.pumpAndSettle();
          expectForeground(tokens.foreground, filled: true);
          await mouse.down(tester.getCenter(find.byType(DButton)));
          await tester.pumpAndSettle();
          expectForeground(tokens.foreground, filled: true);
          await mouse.up();
          await tester.pumpAndSettle();
          expect(activations, 1);
          await mouse.moveTo(Offset.zero);
          focus.unfocus();
          await tester.pumpAndSettle();
          expectForeground(resting);

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expectForeground(tokens.foreground);
          expect(buttonSurface(tester).ringWidth, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(activations, 2);
          focus.unfocus();
          await pump(expanded: true);
          await tester.pumpAndSettle();
          expectForeground(tokens.foreground, filled: true);
          await pump();
          await tester.pumpAndSettle();
          expectForeground(resting);
        },
      );
    }

    testWidgets('disabled/loading stays transparent and inert (dark: $dark)', (
      tester,
    ) async {
      var activations = 0;
      for (final loading in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
              platform: TargetPlatform.macOS,
            ),
            home: Scaffold(
              body: Center(
                child: DButton(
                  label: const Text('Reply'),
                  variant: DButtonVariant.transparentBackground,
                  expanded: true,
                  loading: loading,
                  onPressed: loading ? () => activations++ : null,
                ),
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byType(DButton)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(buttonSurface(tester).color, Colors.transparent);
        final tokens = DTokens.of(tester.element(find.byType(DButton)));
        expect(
          DefaultTextStyle.of(tester.element(find.text('Reply'))).style.color,
          isNot(tokens.foreground),
        );
        await tester.tap(find.byType(DButton));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(activations, 0);
        await mouse.removePointer();
      }
    });
  }
}
