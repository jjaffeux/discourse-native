import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

Map<String, ThemeData> _savedThemes(String site, String file) {
  final saved =
      jsonDecode(
            File('docs/mockups/button-directions/$file').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final appearance = SiteAppearance.fromJson(
    saved['appearance'] as Map<String, dynamic>,
  );
  return {
    '$site light': AppTheme.fromPalette(appearance.base!),
    '$site dark': AppTheme.fromPalette(appearance.alternate!),
  };
}

void main() {
  final themes = {
    ..._savedThemes('dev', 'palette.json'),
    ..._savedThemes('meta', 'meta-palette.json'),
    for (final palette in StyleguideTheme.values.where(
      (palette) => palette != StyleguideTheme.current,
    ))
      palette.label: palette.resolve(AppTheme.light),
  };

  test(
    'contextual surfaces retain readable text in resting and hover states',
    () {
      for (final entry in themes.entries) {
        final tokens = entry.value.extension<DTokens>()!;
        final controls = tokens.controls!;
        expect(
          controls.accent.border,
          controls.outline.border,
          reason: '${entry.key}: active and neutral controls share an outline',
        );
        for (final surface in [
          controls.outline,
          controls.primary,
          controls.accent,
        ]) {
          for (final background in [surface.background, surface.hover]) {
            expect(
              _contrast(surface.foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: '${entry.key}: $surface on $background',
            );
          }
        }
        expect(tokens.focusRing, entry.value.colorScheme.primary);
        expect(controls.primary.background, isNot(tokens.focusRing));
        expect(tokens.controlRadius, 8);
      }
      // The host's original radius still applies to non-control surfaces.
      expect(themes['dev dark']!.extension<DTokens>()!.radius, 4);
    },
  );

  testWidgets('primary tint animates independently of its focus ring', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: themes['dev dark']!.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(
            child: DButton(
              focusNode: focus,
              label: const Text('Reply'),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final trigger = find.byType(DButton);
    final tokens = DTokens.of(tester.element(trigger));
    final surface = tokens.controls!.primary;
    expect(buttonSurface(tester).color, surface.background);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(trigger));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    final painted =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: trigger,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is DecoratedBox &&
                          widget.decoration is DButtonDecoration,
                    ),
                  ),
                )
                .decoration
            as DButtonDecoration;
    expect(painted.color, isNot(surface.background));
    expect(painted.color, isNot(surface.hover));
    await tester.pumpAndSettle();
    expect(buttonSurface(tester).color, surface.hover);
    await mouse.moveTo(Offset.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(buttonSurface(tester).ringWidth, 3);
    expect(
      buttonSurface(tester).ringColor,
      tokens.focusRing.withValues(alpha: tokens.focusRing.a * .5),
    );
    expect(buttonSurface(tester).color, surface.background);
  });

  for (final showLabel in [false, true]) {
    testWidgets(
      'active notification tint follows selection and live palette (label: $showLabel)',
      (tester) async {
        final trigger = find.byKey(const ValueKey('notification-trigger'));
        final bookmark = find.byKey(const ValueKey('bookmark-trigger'));
        final theme = ValueNotifier(themes['dev dark']!);
        final value = ValueNotifier(2);
        addTearDown(theme.dispose);
        addTearDown(value.dispose);
        await tester.pumpWidget(
          ValueListenableBuilder<ThemeData>(
            valueListenable: theme,
            builder: (_, currentTheme, _) => MaterialApp(
              theme: currentTheme.copyWith(platform: TargetPlatform.macOS),
              home: Scaffold(
                body: Center(
                  child: DButtonGroup(
                    children: [
                      DButton.iconOnly(
                        key: const ValueKey('bookmark-trigger'),
                        icon: const Icon(Icons.bookmark_outline),
                        tooltip: 'Bookmark',
                        variant: DButtonVariant.outline,
                        onPressed: () {},
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: value,
                        builder: (_, current, _) => DNotificationLevelMenu<int>(
                          buttonKey: const ValueKey('notification-trigger'),
                          value: current,
                          onChanged: (next) => value.value = next,
                          showLabel: showLabel,
                          size: DButtonSize.regular,
                          variant: DButtonVariant.outline,
                          semanticLabel: 'Notifications',
                          options: const [
                            DNotificationLevelOption(
                              value: 2,
                              label: 'Watching',
                              description: 'Notify on every reply',
                              icon: Icon(Icons.notifications),
                              emphasized: true,
                            ),
                            DNotificationLevelOption(
                              value: 1,
                              label: 'Normal',
                              description: 'Mentions only',
                              icon: Icon(Icons.notifications_none),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        DTokens tokens() => DTokens.of(tester.element(trigger));
        expect(
          buttonSurface(tester, of: trigger).color,
          tokens().controls!.accent.background,
        );
        expect(
          buttonSurface(tester, of: trigger).borderColor,
          tokens().controls!.accent.border,
        );
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        theme.value = themes['meta light']!;
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsOneWidget);
        expect(
          buttonSurface(tester, of: trigger).color,
          tokens().controls!.accent.background,
        );
        expect(
          buttonSurface(tester, of: trigger).borderColor,
          buttonSurface(tester, of: bookmark).borderColor,
        );
        expect(buttonSurface(tester, of: trigger).joinedAxis, Axis.horizontal);
        expect(tester.getRect(bookmark).right, tester.getRect(trigger).left);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is DDropdownMenuRadioItem<int> && widget.value == 1,
          ),
        );
        await tester.pumpAndSettle();
        expect(value.value, 1);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(find.byTooltip('Notifications: Normal'), findsOneWidget);
        expect(
          buttonSurface(tester, of: trigger).color,
          tokens().controls!.outline.background,
        );
      },
    );
  }
}
