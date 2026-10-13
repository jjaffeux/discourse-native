import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _switcherKey = ValueKey('sidebar-community-switcher');

Finder get _switcher => find.byKey(_switcherKey);

Finder get _chevron => find.descendant(
  of: _switcher,
  matching: find.byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == DIcons.chevronDown,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [260.0, 400.0]) {
    testWidgets('community header stays grouped in a $width sidebar', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        SidebarWidthStore.storageKey: width,
      });
      await pumpShell(
        tester,
        desktop,
        instances: [instance('commons.example', title: 'Commons')],
      );

      final logo = tester.getRect(find.byType(ForumIdentityHeader));
      final title = tester.getRect(
        find.descendant(of: _switcher, matching: find.text('Commons')),
      );
      final chevron = tester.getRect(_chevron);
      expect(title.left - logo.right, closeTo(DSpacing.sm, .01));
      expect(chevron.left - title.right, closeTo(DSpacing.sm, .01));
      expect(title.center.dy, closeTo(logo.center.dy, .01));
      expect(chevron.center.dy, closeTo(title.center.dy, .01));
      expect(chevron.right, lessThan(tester.getRect(_switcher).right - 20));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('long community names fit beside the chevron at 200% text', (
    tester,
  ) async {
    await pumpShell(
      tester,
      desktop,
      instances: [
        instance('commons.example', title: 'The Commons discussion community'),
      ],
    );
    final shell = ShellScope.of(tester.element(find.byType(InstanceSidebar)));
    await shell.appSettings.setTextScale(AppTextScale.percent200);
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: _switcher,
      matching: find.text('The Commons discussion community'),
    );
    expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
    expect(
      tester.getRect(_chevron).left - tester.getRect(title).right,
      closeTo(DSpacing.sm, .01),
    );
    expect(
      tester.getRect(_chevron).right,
      lessThanOrEqualTo(tester.getRect(_switcher).right),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('both the community title and chevron open the site menu', (
    tester,
  ) async {
    await pumpShell(tester, desktop);
    final option = find.byKey(
      const ValueKey((
        'sidebar-community-option',
        'https://team.discourse.org',
      )),
    );

    await tester.tap(
      find.descendant(of: _switcher, matching: find.text('Discourse Meta')),
    );
    await tester.pumpAndSettle();
    expect(option, findsOneWidget);
    expect(tester.widget<DButton>(_switcher).expanded, isTrue);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _switcher, matching: find.text('Discourse Team')),
      findsOneWidget,
    );

    await tester.tap(_chevron);
    await tester.pumpAndSettle();
    expect(option, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
