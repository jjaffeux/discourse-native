import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _alphaTabKey = ValueKey('user-menu-tab-alpha/activity');
const _betaTabKey = ValueKey('user-menu-tab-beta/activity');
const _alphaBodyKey = ValueKey('alpha-user-menu-body');
const _betaBodyKey = ValueKey('beta-user-menu-body');

void main() {
  testWidgets('plugin-absent user menu renders no contributed sections', (
    tester,
  ) async {
    await _pumpUserMenu(tester, const PluginManifest([]));

    expect(find.byKey(_alphaTabKey), findsNothing);
    expect(find.byKey(_betaTabKey), findsNothing);
    expect(find.byKey(_alphaBodyKey), findsNothing);
    expect(find.byKey(_betaBodyKey), findsNothing);
  });

  testWidgets(
    'multiple plugin user-menu sections render in registry order and select independently',
    (tester) async {
      await _pumpUserMenu(
        tester,
        const PluginManifest([
          _MenuModule('alpha', 'Alpha activity', _alphaBodyKey),
          _MenuModule('beta', 'Beta activity', _betaBodyKey),
        ]),
      );

      final alphaTab = find.byKey(_alphaTabKey);
      final betaTab = find.byKey(_betaTabKey);
      expect(alphaTab, findsOneWidget);
      expect(betaTab, findsOneWidget);
      expect(
        tester.getTopLeft(alphaTab).dy,
        lessThan(tester.getTopLeft(betaTab).dy),
      );

      await tester.tap(alphaTab);
      await tester.pump();
      expect(find.byKey(_alphaBodyKey), findsOneWidget);
      expect(find.byKey(_betaBodyKey), findsNothing);

      await tester.tap(betaTab);
      await tester.pump();
      expect(find.byKey(_alphaBodyKey), findsNothing);
      expect(find.byKey(_betaBodyKey), findsOneWidget);
    },
  );

  testWidgets('reselecting a plugin tab opens its active link', (tester) async {
    var dismissals = 0;
    await _pumpUserMenu(
      tester,
      const PluginManifest([
        _MenuModule(
          'alpha',
          'Alpha activity',
          _alphaBodyKey,
          linkWhenActive: '/latest',
        ),
      ]),
      onDismiss: () => dismissals += 1,
    );

    await tester.tap(find.byKey(_alphaTabKey));
    await tester.pump();
    expect(dismissals, 0);

    await tester.tap(find.byKey(_alphaTabKey));
    await tester.pump();
    expect(dismissals, 1);
  });

  testWidgets('an open touch section rebuilds from live totals', (
    tester,
  ) async {
    final controller = await _pumpUserMenu(
      tester,
      const PluginManifest([
        _MenuModule(
          'alpha',
          'Alpha activity',
          _alphaBodyKey,
          showsUnreadCount: true,
        ),
      ]),
      totals: const NotificationTotals(unreadNotifications: 3),
    );

    unawaited(showUserMenuSheet(tester.element(find.byType(UserMenuPanel))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha activity').last);
    await tester.pumpAndSettle();
    expect(find.text('Unread: 3'), findsOneWidget);

    controller.accountActivity.applyCounts(
      _siteUrl,
      (held) => held.copyWith(unreadNotifications: 0),
    );
    await tester.pump();

    expect(find.text('Unread: 0'), findsOneWidget);
  });
}

Future<ShellController> _pumpUserMenu(
  WidgetTester tester,
  PluginManifest manifest, {
  VoidCallback onDismiss = _ignore,
  NotificationTotals totals = const NotificationTotals(),
}) async {
  const user = DiscourseUser(id: 7, username: 'reader', name: 'Reader');
  final plugins = PluginInstaller.install(manifest);
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      totals: totals,
      notificationList: const [],
    ),
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    plugins: plugins,
  );
  addTearDown(() async {
    controller.dispose();
    await plugins.close();
  });
  await controller.load();

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Center(child: UserMenuPanel(onDismiss: onDismiss)),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

final class _MenuModule implements PluginModule {
  const _MenuModule(
    this.id,
    this.label,
    this.bodyKey, {
    this.linkWhenActive,
    this.showsUnreadCount = false,
  });

  final String id;
  final String label;
  final Key bodyKey;
  final String? linkWhenActive;
  final bool showsUnreadCount;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(id: PluginId(id));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(
      _MenuPlugin(
        id,
        label,
        bodyKey,
        linkWhenActive: linkWhenActive,
        showsUnreadCount: showsUnreadCount,
      ),
    );
  }
}

final class _MenuPlugin implements SitePlugin, UserMenuSectionPlugin {
  const _MenuPlugin(
    this.name,
    this.label,
    this.bodyKey, {
    this.linkWhenActive,
    this.showsUnreadCount = false,
  });

  @override
  final String name;
  final String label;
  final Key bodyKey;
  final String? linkWhenActive;
  final bool showsUnreadCount;

  @override
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) =>
      [
        PluginUserMenuSection(
          id: PluginUserMenuSectionId(owner: PluginId(name), name: 'activity'),
          icon: DIcons.bell,
          label: label,
          linkWhenActive: linkWhenActive,
          builder: (_, _) => Text(
            showsUnreadCount
                ? 'Unread: ${context.totals?.unreadNotifications ?? 0}'
                : '$label content',
            key: bodyKey,
          ),
        ),
      ];
}

void _ignore() {}
