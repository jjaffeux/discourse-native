import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
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
import 'support/shell_test_harness.dart';

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

  testWidgets('notification filters remain reachable after window resizing', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpUserMenu(
      tester,
      const PluginManifest([]),
      platform: TargetPlatform.iOS,
    );
    await tester.pumpAndSettle();

    final profile = find.byKey(const ValueKey('user-menu-tab-profile'));
    final all = find.byKey(const ValueKey('user-menu-tab-all'));
    final other = find.byKey(const ValueKey('user-menu-tab-other'));
    final filterScroll = find
        .ancestor(of: all, matching: find.byType(Scrollable))
        .first;
    expect(
      tester.state<ScrollableState>(filterScroll).position.axis,
      Axis.horizontal,
    );
    expect(profile, findsNothing);

    await tester.binding.setSurfaceSize(const Size(320, 220));
    await tester.pumpAndSettle();
    expect(all.hitTestable(), findsOneWidget);
    expect(other.hitTestable(), findsNothing);
    expect(
      tester.state<ScrollableState>(filterScroll).position.maxScrollExtent,
      greaterThan(0),
    );

    await tester.drag(filterScroll, const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(other.hitTestable(), findsOneWidget);
    expect(all.hitTestable(), findsNothing);
    expect(profile, findsNothing);
    expect(tester.getRect(other).bottom, lessThanOrEqualTo(220));

    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpAndSettle();
    await tester.drag(filterScroll, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(all.hitTestable(), findsOneWidget);
    expect(profile, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notification filters and feed scroll independently without a profile tab',
    (tester) async {
      await _pumpUserMenu(
        tester,
        PluginManifest([
          for (var index = 0; index < 8; index++)
            _MenuModule(
              'extra-$index',
              'Extra activity $index',
              ValueKey('extra-user-menu-body-$index'),
            ),
        ]),
        notificationList: [
          for (var id = 1; id <= 20; id++)
            DiscourseNotification.test(
              id: id,
              typeId: NotificationTypeId(CoreNotificationTypes.replied.wireId),
              topicId: id,
              title: 'Notification topic $id',
              data: const {'display_username': 'reader'},
            ),
        ],
        platform: TargetPlatform.iOS,
      );
      await tester.pumpAndSettle();

      final profile = find.byKey(const ValueKey('user-menu-tab-profile'));
      expect(profile, findsNothing);
      final notificationScroll = find
          .ancestor(
            of: find.byKey(const ValueKey('notification-row-1')),
            matching: find.byType(Scrollable),
          )
          .first;
      final filterScroll = find
          .ancestor(
            of: find.byKey(const ValueKey('user-menu-tab-all')),
            matching: find.byType(Scrollable),
          )
          .first;
      final filterBounds = tester.getRect(
        find.byKey(const ValueKey('user-menu-mobile-tabs')),
      );
      final filterPosition = tester
          .state<ScrollableState>(filterScroll)
          .position;
      final feedPosition = tester
          .state<ScrollableState>(notificationScroll)
          .position;
      expect(filterPosition.axis, Axis.horizontal);
      expect(feedPosition.axis, Axis.vertical);
      expect(filterPosition.pixels, 0);
      await tester.drag(notificationScroll, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(feedPosition.pixels, greaterThan(0));
      expect(filterPosition.pixels, 0);
      expect(
        tester.getRect(find.byKey(const ValueKey('user-menu-mobile-tabs'))),
        filterBounds,
      );
      final feedOffset = feedPosition.pixels;
      await tester.drag(filterScroll, const Offset(-3000, 0));
      await tester.pumpAndSettle();
      expect(filterPosition.pixels, greaterThan(0));
      expect(feedPosition.pixels, feedOffset);
      expect(profile, findsNothing);

      final lastPlugin = find.byKey(
        const ValueKey('user-menu-tab-extra-7/activity'),
      );
      expect(lastPlugin.hitTestable(), findsOneWidget);
      await tester.tap(lastPlugin);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('extra-user-menu-body-7')),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    },
  );

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
        tester.getTopLeft(alphaTab).dx,
        lessThan(tester.getTopLeft(betaTab).dx),
      );

      await tester.ensureVisible(alphaTab);
      await tester.pumpAndSettle();
      await tester.tap(alphaTab);
      await tester.pump();
      expect(find.byKey(_alphaBodyKey), findsOneWidget);
      expect(find.byKey(_betaBodyKey), findsNothing);

      await tester.ensureVisible(betaTab);
      await tester.pumpAndSettle();
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

    await tester.ensureVisible(find.byKey(_alphaTabKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_alphaTabKey));
    await tester.pump();
    expect(dismissals, 0);

    await tester.tap(find.byKey(_alphaTabKey));
    await tester.pump();
    expect(dismissals, 1);
  });

  for (final host in const ['example.com', 'example.com/forum']) {
    testWidgets('a plugin tab active link stays on the forum at $host', (
      tester,
    ) async {
      final launched = watchBrowser(tester);
      await _pumpUserMenu(
        tester,
        const PluginManifest([
          _MenuModule(
            'alpha',
            'Alpha activity',
            _alphaBodyKey,
            linkWhenActive: '/u/reader/activity/alpha',
          ),
        ]),
        host: host,
      );

      await tester.ensureVisible(find.byKey(_alphaTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_alphaTabKey));
      await tester.pump();
      await tester.tap(find.byKey(_alphaTabKey));
      await tester.pumpAndSettle();

      expect(launched, ['https://$host/u/reader/activity/alpha']);
    });
  }

  testWidgets('mobile plugin tabs remain selected when the panel widens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
      platform: TargetPlatform.iOS,
    );
    final tab = find.byKey(_alphaTabKey);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(find.byKey(_alphaBodyKey), findsOneWidget);
    expect(dismissals, 0);

    await tester.binding.setSurfaceSize(const Size(900, 720));
    await tester.pumpAndSettle();
    expect(find.byKey(_alphaBodyKey), findsOneWidget);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(dismissals, 1);
    expect(tester.takeException(), isNull);
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
      platform: TargetPlatform.iOS,
    );

    final tab = find.byKey(_alphaTabKey);
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
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
  List<DiscourseNotification> notificationList = const [],
  String host = 'meta.example',
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  const user = DiscourseUser(
    id: 7,
    username: 'reader',
    name: 'Reader',
    canInviteToForum: true,
  );
  final plugins = PluginInstaller.install(manifest);
  final authenticator = FakeAuthenticator()..keys['https://$host'] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance(host).copyWith(user: user)]),
    api: FakeDiscourseApi(
      user: user,
      totals: totals,
      notificationList: notificationList,
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
        theme: AppTheme.light.copyWith(platform: platform),
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
