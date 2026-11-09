import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/sidebar_width_store.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/method_channel_url_launcher.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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

Finder get _openInBrowser => find.text('Open forum in browser');

Finder get _removeForum => find.text('Remove forum');

Finder get _menu => find.byType(DDropdownMenuContent);

Finder _inSwitcher(String title) =>
    find.descendant(of: _switcher, matching: find.text(title));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_chevron);
  await tester.pumpAndSettle();
}

Future<void> _switchThroughRail(WidgetTester tester, String url) async {
  await tester.tap(
    find.descendant(
      of: find.byType(InstanceRail),
      matching: find.byKey(ValueKey<String>(url)),
    ),
  );
  await tester.pumpAndSettle();
}

ShellController _shell(WidgetTester tester) =>
    ShellScope.of(tester.element(find.byType(InstanceSidebar)));

List<String> _recordLaunches(WidgetTester tester, {bool opens = true}) {
  final previous = UrlLauncherPlatform.instance;
  UrlLauncherPlatform.instance = MethodChannelUrlLauncher();
  addTearDown(() => UrlLauncherPlatform.instance = previous);
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return opens;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return launched;
}

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

  testWidgets('both the community title and chevron open the forum menu', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    await tester.tap(_inSwitcher('Discourse Meta'));
    await tester.pumpAndSettle();
    expect(_openInBrowser, findsOneWidget);
    expect(tester.widget<DButton>(_switcher).expanded, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_openInBrowser, findsNothing);

    await _openMenu(tester);
    expect(_openInBrowser, findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the forum menu is drawn to the mockup', (tester) async {
    await pumpShell(tester, desktop);
    await _openMenu(tester);

    expect(tester.getSize(_menu).width, 220);

    final open = find.ancestor(
      of: _openInBrowser,
      matching: find.byType(DDropdownMenuItem),
    );
    final remove = find.ancestor(
      of: _removeForum,
      matching: find.byType(DDropdownMenuItem),
    );
    final rule = tester.getRect(find.byType(DDropdownMenuSeparator));
    expect(rule.top - tester.getRect(open).bottom, 0);
    expect(tester.getRect(remove).top - rule.bottom, 0);
    expect(rule.height, 11);

    expect(
      tester.getTopLeft(_openInBrowser).dx - tester.getTopLeft(open).dx,
      36,
    );
    expect(
      tester.widget<DDropdownMenuItem>(remove).variant,
      DDropdownMenuItemVariant.destructive,
    );
    for (final row in [open, remove]) {
      final icon = find.descendant(of: row, matching: find.byType(DIcon));
      expect(tester.widget<DIcon>(icon).size, 13);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('forums are switched from the rail, not the forum menu', (
    tester,
  ) async {
    await pumpShell(tester, desktop);
    await _openMenu(tester);
    expect(
      find.descendant(of: _menu, matching: find.text('Discourse Team')),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _switchThroughRail(tester, 'https://team.discourse.org');

    expect(_inSwitcher('Discourse Team'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Open forum in browser opens the forum you are in', (
    tester,
  ) async {
    final launched = _recordLaunches(tester);
    await pumpShell(tester, desktop);
    await _switchThroughRail(tester, 'https://team.discourse.org');

    await _openMenu(tester);
    await tester.tap(_openInBrowser);
    await tester.pumpAndSettle();

    expect(launched, ['https://team.discourse.org']);
    expect(_openInBrowser, findsNothing);
    expect(
      DToast.of(tester.element(find.byType(InstanceSidebar))).toasts,
      isEmpty,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a browser that will not open says so', (tester) async {
    _recordLaunches(tester, opens: false);
    await pumpShell(tester, desktop);

    await _openMenu(tester);
    await tester.tap(_openInBrowser);
    await tester.pumpAndSettle();

    expect(
      DToast.of(
        tester.element(find.byType(InstanceSidebar)),
      ).toasts.map((toast) => toast.options.description),
      ['Could not open the link. Please try again.'],
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Remove forum confirms before removing the forum you are in', (
    tester,
  ) async {
    final store = FakeInstanceStore(twoSites);
    await pumpShell(tester, desktop, store: store);
    await _switchThroughRail(tester, 'https://team.discourse.org');

    await _openMenu(tester);
    await tester.tap(_removeForum);
    await tester.pumpAndSettle();
    expect(find.text('Remove Discourse Team?'), findsOneWidget);
    expect(_removeForum, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Remove Discourse Team?'), findsNothing);
    expect(_shell(tester).instances, hasLength(2));

    await _openMenu(tester);
    await tester.tap(_removeForum);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(_shell(tester).instances.map((forum) => forum.url), [
      'https://meta.discourse.org',
    ]);
    expect((await store.load()).map((forum) => forum.url), [
      'https://meta.discourse.org',
    ]);
    expect(_inSwitcher('Discourse Meta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
