import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_test_harness.dart';

const _first = 'https://first.example';
const _second = 'https://second.example';
const _forums = [
  DiscourseInstance(url: _first, title: 'First'),
  DiscourseInstance(url: _second, title: 'Second'),
];

const _desktopPlatforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.linux,
});

final _toggle = find.byKey(const ValueKey('theme-mode-rail-button'));
final _gear = find.byKey(const ValueKey('settings-rail-button'));

ShellController _shell(WidgetTester tester) =>
    ShellScope.read(tester.element(find.byType(InstanceRail)));

String? _tooltip(WidgetTester tester) =>
    tester.widget<DButton>(_toggle).tooltip;

ThemeMode? _appThemeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp).first).themeMode;

Future<void> _setMode(
  WidgetTester tester,
  String site,
  AppThemeMode mode,
) async {
  await _shell(tester).forumSettings.setThemeMode(site, mode);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the desktop switch sits above the gear at 16 and flips the forum',
    (tester) async {
      await pumpShell(tester, desktop, instances: _forums);
      await tester.pumpAndSettle();
      await _setMode(tester, _first, AppThemeMode.light);

      expect(
        tester.getSize(
          find.descendant(of: _toggle, matching: find.byType(DIcon)),
        ),
        const Size.square(16),
      );
      expect(tester.getCenter(_toggle).dx, tester.getCenter(_gear).dx);
      expect(
        tester.getRect(_toggle).bottom,
        lessThanOrEqualTo(tester.getRect(_gear).top),
      );

      expect(_tooltip(tester), 'Switch to dark');
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(
        _shell(tester).forumSettings.themeModeFor(_first),
        AppThemeMode.dark,
      );
      expect(_appThemeMode(tester), ThemeMode.dark);
      expect(_tooltip(tester), 'Switch to light');

      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(
        _shell(tester).forumSettings.themeModeFor(_first),
        AppThemeMode.light,
      );
      expect(_appThemeMode(tester), ThemeMode.light);
      expect(tester.takeException(), isNull);
    },
    variant: _desktopPlatforms,
  );

  testWidgets('the desktop switch follows the forum picked on the rail', (
    tester,
  ) async {
    await pumpShell(tester, desktop, instances: _forums);
    await tester.pumpAndSettle();
    await _setMode(tester, _first, AppThemeMode.light);
    await _setMode(tester, _second, AppThemeMode.light);

    await tester.tap(find.byKey(const ValueKey(_second)));
    await tester.pumpAndSettle();
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    final settings = _shell(tester).forumSettings;
    expect(settings.themeModeFor(_second), AppThemeMode.dark);
    expect(settings.themeModeFor(_first), AppThemeMode.light);
    expect(_tooltip(tester), 'Switch to light');

    await tester.tap(find.byKey(const ValueKey(_first)));
    await tester.pumpAndSettle();
    expect(_tooltip(tester), 'Switch to dark');
    expect(tester.takeException(), isNull);
  }, variant: _desktopPlatforms);

  testWidgets('the desktop rail has no switch while no forum owns the theme', (
    tester,
  ) async {
    await pumpShell(tester, desktop, instances: const []);
    await tester.pumpAndSettle();

    expect(_appThemeMode(tester), ThemeMode.system);
    expect(_gear, findsOneWidget);
    expect(_toggle, findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _desktopPlatforms);
}
