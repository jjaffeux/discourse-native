import 'package:discourse_native/discourse_ui.dart';

import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/button_surface.dart';
import 'support/theme_settings.dart' as settings;

const _actionKeys = [
  'add-instance-rail-button',
  'styleguide-rail-button',
  'settings-rail-button',
];

void _expectIconColor(WidgetTester tester, Finder button, Color expected) {
  final icons = find.descendant(
    of: button,
    matching: find.byWidgetPredicate(
      (widget) => widget is DIcon || widget is Icon,
    ),
  );
  expect(icons, findsOneWidget);
  final icon = tester.widget(icons);
  final override = icon is DIcon ? icon.color : (icon as Icon).color;
  expect(override ?? IconTheme.of(tester.element(icons)).color, expected);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'rail actions match mockup colors at rest, hover, and press',
    (tester) async {
      final shell = settings.controller();

      try {
        await shell.load();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);

        final themes = [
          AppTheme.light,
          AppTheme.dark,
          for (final preset in forumThemePresets)
            for (final brightness in Brightness.values)
              for (final tint in [0.0, 0.6])
                AppTheme.fromPalette(
                  preset.copyWith(tint: tint).resolve(brightness),
                ),
        ];
        for (final theme in themes) {
          // Footer actions use --text-muted, a 50/50 sRGB mix. The add-site
          // plus always uses --text-strong, including while idle.
          final muted = Color.lerp(
            theme.colorScheme.surface,
            theme.colorScheme.onSurface,
            .5,
          )!;
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                theme: theme.copyWith(
                  platform: debugDefaultTargetPlatformOverride,
                ),
                home: const Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: 64, child: InstanceRail()),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final key in _actionKeys) {
            final expected = key == 'add-instance-rail-button'
                ? theme.colorScheme.onSurface
                : muted;
            final button = find.byKey(ValueKey(key));
            _expectIconColor(tester, button, expected);
            final surface = buttonSurface(tester, of: button);
            expect(surface.color, Colors.transparent);
            expect(surface.borderColor, Colors.transparent);

            await mouse.moveTo(tester.getCenter(button));
            await tester.pumpAndSettle();
            _expectIconColor(tester, button, expected);
            expect(buttonSurface(tester, of: button), surface);

            await mouse.down(tester.getCenter(button));
            await tester.pumpAndSettle();
            _expectIconColor(tester, button, expected);
            expect(buttonSurface(tester, of: button), surface);
            // Cancel avoids opening the action while testing its pressed color.
            await mouse.cancel();
            await mouse.moveTo(Offset.zero);
            await tester.pumpAndSettle();
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        shell.dispose();
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
