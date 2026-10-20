import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _source = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(owner: PluginId('list-audit'), name: 'feed'),
  filterByTypes: [NotificationTypeName('replied')],
  reconnectMessage: 'Reconnect',
  failureMessage: 'Unavailable',
  emptyMessage: 'No notifications',
);

void main() => menuListVirtualizationTests();

void menuListVirtualizationTests() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final plugin in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'menu feeds keep long rows lazy on $platform plugin=$plugin scale=$scale',
          (tester) async {
            tester.view.physicalSize = Size(
              platform == TargetPlatform.iOS ? 390 : 900,
              900,
            );
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final notifications = [
              for (var id = 1; id <= 200; id++)
                DiscourseNotification.test(
                  id: id,
                  typeId: const NotificationTypeId(2),
                  title: 'Notification $id',
                  data: const {'display_username': 'alice'},
                ),
            ];
            final host = _FeedHost(NotificationFeed.of(notifications));
            final runtime = PluginInstaller.install(
              PluginManifest([_FeedModule(host)]),
            );
            const user = DiscourseUser(id: 7, username: 'reader');
            final shell = ShellController(
              instanceStore: FakeInstanceStore([
                instance('meta.example').copyWith(user: user),
              ]),
              api: FakeDiscourseApi(
                user: user,
                totals: const NotificationTotals(),
                notificationList: notifications,
              ),
              authenticator: FakeAuthenticator()..keys[_site] = 'key',
              drafts: FakeDraftStore(),
              trackers: FakeSiteTracker.reset(),
              updater: FakeUpdater(),
              updateStore: FakeUpdateStore(),
              plugins: runtime,
            );
            addTearDown(() async {
              shell.dispose();
              await runtime.close();
              host.dispose();
            });
            await shell.load();
            await tester.pumpWidget(
              ShellScope(
                controller: shell,
                child: MaterialApp(
                  theme: AppTheme.light.copyWith(platform: platform),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: const Scaffold(
                    body: Align(
                      alignment: Alignment.topRight,
                      child: UserMenuButton(),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(UserMenuButton.bellKey));
            await tester.pumpAndSettle();
            if (plugin) {
              final tab = find.byKey(
                const ValueKey('user-menu-tab-list-audit/feed'),
              );
              await tester.ensureVisible(tab);
              await tester.pumpAndSettle();
              await tester.tap(tab);
              await tester.pumpAndSettle();
            }
            final mounted = find
                .byType(NotificationRow, skipOffstage: false)
                .evaluate()
                .length;
            debugPrint(
              'list-audit menu platform=$platform plugin=$plugin scale=$scale mounted=$mounted total=200',
            );
            expect(mounted, inExclusiveRange(0, 40));
            final viewport = find.descendant(
              of: find.byType(UserMenuPanel),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable && widget.axis == Axis.vertical,
              ),
            );
            expect(viewport, findsOneWidget);
            final tabs = find.byKey(const ValueKey('user-menu-mobile-tabs'));
            if (platform == TargetPlatform.iOS) {
              await tester.drag(
                find.byKey(const ValueKey('sheet-drag-handle')),
                const Offset(0, -500),
              );
              await tester.pumpAndSettle();
            }
            final tabsRect = tester.getRect(tabs);
            final last = find.byKey(const ValueKey('notification-row-200'));
            await tester.scrollUntilVisible(
              last,
              500,
              scrollable: viewport,
              maxScrolls: 200,
            );
            await tester.pumpAndSettle();
            expect(last.hitTestable(), findsOneWidget);
            expect(tester.getRect(tabs), tabsRect);
            expect(
              find
                  .byType(NotificationRow, skipOffstage: false)
                  .evaluate()
                  .length,
              lessThan(40),
            );
            expect(
              find.byKey(
                const ValueKey('notification-row-1'),
                skipOffstage: false,
              ),
              findsNothing,
            );
            await tester.tap(last);
            await tester.pumpAndSettle();
            if (plugin) {
              expect(host.read, [200]);
              final footer = find.text('View all results');
              await tester.scrollUntilVisible(
                footer,
                200,
                scrollable: viewport,
              );
              await tester.pumpAndSettle();
              expect(footer.hitTestable(), findsOneWidget);
            } else {
              expect(
                shell.notificationsFor(_site).notifications.last.read,
                isTrue,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

final class _FeedModule implements PluginModule {
  const _FeedModule(this.host);
  final _FeedHost host;
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('list-audit'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(_FeedPlugin(host));
}

final class _FeedPlugin implements SitePlugin, UserMenuSectionPlugin {
  const _FeedPlugin(this.host);
  final _FeedHost host;
  @override
  String get name => 'list-audit';
  @override
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) =>
      [
        PluginUserMenuSection(
          id: const PluginUserMenuSectionId(
            owner: PluginId('list-audit'),
            name: 'feed',
          ),
          icon: DIcons.bell,
          label: 'Audit feed',
          builder: (_, actions) => PluginNotificationsSection(
            siteUrl: context.siteUrl,
            onOpened: actions.onDismiss,
            host: host,
            source: _source,
            viewAll: const PluginNotificationFeedLink(
              label: 'View all results',
              path: '/my/activity',
            ),
          ),
          sliverBuilder: (_, actions) => PluginNotificationsSection.sliver(
            siteUrl: context.siteUrl,
            onOpened: actions.onDismiss,
            host: host,
            source: _source,
            viewAll: const PluginNotificationFeedLink(
              label: 'View all results',
              path: '/my/activity',
            ),
          ),
        ),
      ];
}

final class _FeedHost extends ChangeNotifier
    implements PluginNotificationFeedHost {
  _FeedHost(this.feed);
  final NotificationFeed feed;
  final List<int> read = [];
  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) => this;
  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) => feed;
  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {}
  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {}
  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => read.add(notification.id);
  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      '$siteUrl$path';
  @override
  Future<bool> openPluginNotificationUrl(String url) async => true;
}
