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
}

Future<void> _pumpUserMenu(WidgetTester tester, PluginManifest manifest) async {
  const user = DiscourseUser(id: 7, username: 'reader', name: 'Reader');
  final plugins = PluginInstaller.install(manifest);
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      totals: const NotificationTotals(),
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
        home: const Scaffold(
          body: Center(child: UserMenuPanel(onDismiss: _ignore)),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _MenuModule implements PluginModule {
  const _MenuModule(this.id, this.label, this.bodyKey);

  final String id;
  final String label;
  final Key bodyKey;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(id: PluginId(id));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(_MenuPlugin(id, label, bodyKey));
  }
}

final class _MenuPlugin implements SitePlugin, UserMenuSectionPlugin {
  const _MenuPlugin(this.name, this.label, this.bodyKey);

  @override
  final String name;
  final String label;
  final Key bodyKey;

  @override
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) =>
      [
        PluginUserMenuSection(
          id: PluginUserMenuSectionId(owner: PluginId(name), name: 'activity'),
          icon: DIcons.bell,
          label: label,
          builder: (_, _) => Text('$label content', key: bodyKey),
        ),
      ];
}

void _ignore() {}
