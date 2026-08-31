import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _assigned = NotificationWireType(34, 'assigned');
const _testAlert = NotificationWireType(901, 'test_alert');

String _dismissConfirmation(int unreadCount) => 'Dismiss $unreadCount alerts?';

const _testAlertFeed = PluginNotificationFeedSource(
  id: PluginNotificationFeedId(owner: PluginId('test-alerts'), name: 'alerts'),
  filterByTypes: [NotificationTypeName('test_alert')],
  reconnectMessage: 'Reconnect.',
  failureMessage: 'Failed.',
  emptyMessage: 'No alerts.',
  dismissal: PluginNotificationFeedDismissal(
    notificationTypes: [_testAlert],
    buttonLabel: 'Dismiss',
    buttonTooltip: 'Dismiss test alerts',
    confirmationMessage: _dismissConfirmation,
  ),
);

void main() {
  test(
    'a stale current-user response cannot replace newer live grouped counts',
    () async {
      final staleUser = DiscourseUser(
        id: 7,
        username: 'reader',
        groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
          '34': 1,
        }),
      );
      final api = _GatedCurrentUserApi(staleUser);
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await api.started.future;
      for (
        var attempt = 0;
        attempt < 20 && FakeSiteTracker.built.isEmpty;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      final tracker = FakeSiteTracker.built.single;

      tracker.deliverNotification(const {
        'grouped_unread_notifications': {'34': 7},
      });
      expect(
        shell.accountActivity
            .totalsFor(_siteUrl)!
            .groupedUnreadNotifications
            .count(_assigned),
        7,
      );

      api.release.complete();
      await api.returned.future;
      await pumpEventQueue();

      expect(
        shell.accountActivity
            .totalsFor(_siteUrl)!
            .groupedUnreadNotifications
            .count(_assigned),
        7,
      );
    },
  );

  test(
    'an aggregate-only live update does not suppress current-user grouped counts',
    () async {
      final user = DiscourseUser(
        id: 7,
        username: 'reader',
        groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
          '34': 4,
        }),
      );
      final api = _GatedCurrentUserApi(user);
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await api.started.future;
      for (
        var attempt = 0;
        attempt < 20 && FakeSiteTracker.built.isEmpty;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      FakeSiteTracker.built.single.deliverNotification(const {
        'all_unread_notifications_count': 2,
      });
      api.release.complete();
      await api.returned.future;
      await pumpEventQueue();

      expect(
        shell.accountActivity
            .totalsFor(_siteUrl)!
            .groupedUnreadNotifications
            .count(_assigned),
        4,
      );
    },
  );

  test(
    'a stale current-user response cannot resurrect a successfully read type at zero',
    () async {
      final staleUser = DiscourseUser(
        id: 7,
        username: 'reader',
        groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
          '2': 1,
        }),
      );
      final api = _GatedCurrentUserApi(staleUser);
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(
            user: const DiscourseUser(id: 7, username: 'reader'),
            notificationTotals: const NotificationTotals(
              groupedUnreadNotifications: NotificationTypeCounts.empty,
            ),
          ),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await api.started.future;
      shell.readNotification(
        _siteUrl,
        const DiscourseNotification.test(id: 41, typeId: NotificationTypeId(2)),
      );
      await pumpEventQueue();

      expect(api.markedRead, [41]);
      expect(
        shell.accountActivity
            .totalsFor(_siteUrl)!
            .groupedUnreadNotifications
            .count(CoreNotificationTypes.replied),
        0,
      );

      api.release.complete();
      await api.returned.future;
      await pumpEventQueue();

      expect(
        shell.accountActivity
            .totalsFor(_siteUrl)!
            .groupedUnreadNotifications
            .count(CoreNotificationTypes.replied),
        0,
      );
    },
  );

  test(
    'a stale current-user response cannot resurrect a successfully dismissed type at zero',
    () async {
      final staleUser = DiscourseUser(
        id: 7,
        username: 'reader',
        groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
          '901': 3,
        }),
      );
      final api = _GatedCurrentUserApi(staleUser);
      final plugins = PluginInstaller.install(
        const PluginManifest([_TestAlertModule()]),
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(
            user: const DiscourseUser(id: 7, username: 'reader'),
            notificationTotals: const NotificationTotals(
              groupedUnreadNotifications: NotificationTypeCounts.empty,
            ),
          ),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        plugins: plugins,
      );
      addTearDown(() async {
        shell.dispose();
        await plugins.close();
      });

      await shell.load();
      await api.started.future;
      await shell.dismissPluginNotifications(
        _siteUrl,
        plugins.registry.notificationFeed(_testAlertFeed.id)!,
      );

      expect(api.markedTypesRead, const [
        [NotificationTypeName('test_alert')],
      ]);
      expect(
        shell.accountActivity
            .totalsFor(_siteUrl)!
            .groupedUnreadNotifications
            .count(_testAlert),
        0,
      );

      api.release.complete();
      await api.returned.future;
      await pumpEventQueue();

      expect(
        shell.accountActivity
            .totalsFor(_siteUrl)!
            .groupedUnreadNotifications
            .count(_testAlert),
        0,
      );
    },
  );

  test(
    'stored user counts seed unavailable totals before a stale response and dismissal',
    () async {
      final storedUser = DiscourseUser(
        id: 7,
        username: 'reader',
        groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
          '901': 3,
        }),
      );
      final staleUser = DiscourseUser(
        id: 7,
        username: 'reader',
        groupedUnreadNotifications: NotificationTypeCounts.fromWire(const {
          '901': 9,
        }),
      );
      final api = _GatedCurrentUserApi(staleUser);
      final plugins = PluginInstaller.install(
        const PluginManifest([_TestAlertModule()]),
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: storedUser),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        plugins: plugins,
      );
      addTearDown(() async {
        shell.dispose();
        await plugins.close();
      });

      await shell.load();
      await api.started.future;
      final seeded = shell.accountActivity.totalsFor(_siteUrl)!;
      expect(seeded.groupedUnreadNotifications.isAvailable, isTrue);
      expect(seeded.groupedUnreadNotifications.count(_testAlert), 3);

      await shell.dismissPluginNotifications(
        _siteUrl,
        plugins.registry.notificationFeed(_testAlertFeed.id)!,
      );
      api.release.complete();
      await api.returned.future;
      await pumpEventQueue();

      final user = shell.instanceFor(_siteUrl)!.user!;
      final totals = shell.accountActivity.totalsFor(_siteUrl);
      expect(user.groupedUnreadNotifications.count(_testAlert), 3);
      expect(
        PluginUserMenuContext(
          siteUrl: _siteUrl,
          user: user,
          totals: totals,
        ).unreadCountFor(_testAlert),
        0,
      );
    },
  );
}

final class _GatedCurrentUserApi extends FakeDiscourseApi {
  _GatedCurrentUserApi(this.response)
    : super(
        totals: const NotificationTotals(),
        notificationList: const [],
        feeds: const {'/latest.json': []},
      );

  final DiscourseUser response;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  final Completer<void> returned = Completer<void>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    if (!returned.isCompleted) returned.complete();
    return response;
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async {
    notificationFilters.add(List.unmodifiable(filterByTypes));
    return const [];
  }
}

final class _TestAlertModule implements PluginModule {
  const _TestAlertModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('test-alerts'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const _TestAlertPlugin());
  }
}

final class _TestAlertPlugin
    implements SitePlugin, NotificationFeedPlugin, NotificationTypePlugin {
  const _TestAlertPlugin();

  @override
  String get name => 'test-alerts';

  @override
  List<PluginNotificationFeedSource> get notificationFeeds => const [
    _testAlertFeed,
  ];

  @override
  List<PluginNotificationType> get notificationTypes => const [
    PluginNotificationType(
      id: PluginNotificationTypeId(
        owner: PluginId('test-alerts'),
        name: 'test-alert',
      ),
      wireType: _testAlert,
      decode: _ignoreNotification,
    ),
  ];
}

ResolvedNotification? _ignoreNotification(DiscourseNotification notification) =>
    null;
