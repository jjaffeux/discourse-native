import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/notification_type_counts.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart'
    show PluginId, PluginInstallationException;
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/user_menu_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _owner = PluginId('test');
const _alertType = NotificationWireType(901, 'custom_alert');
const _pluginLikeType = NotificationWireType(902, 'custom_like');
const _feedId = PluginNotificationFeedId(owner: _owner, name: 'alerts');
const _alertName = NotificationTypeName('custom_alert');

String _confirm(int count) => 'Dismiss $count?';

const _dismissal = PluginNotificationFeedDismissal(
  notificationTypes: [_alertType],
  buttonLabel: 'Dismiss',
  buttonTooltip: 'Dismiss alerts',
  confirmationMessage: _confirm,
);
const _installed = PluginNotificationFeedSource(
  id: _feedId,
  filterByTypes: [_alertName],
  reconnectMessage: 'Reconnect',
  failureMessage: 'Failed',
  emptyMessage: 'Empty',
  dismissal: _dismissal,
);
const _impostor = PluginNotificationFeedSource(
  id: _feedId,
  filterByTypes: [NotificationTypeName('replied')],
  reconnectMessage: 'Reconnect',
  failureMessage: 'Failed',
  emptyMessage: 'Empty',
  dismissal: _dismissal,
);

void main() {
  test('load admits only the feed the registry installed', () async {
    final h = _Harness();
    addTearDown(h.activity.dispose);

    await expectLater(
      h.notifications.loadPluginNotificationFeed(_site, _impostor),
      throwsStateError,
    );
    expect(h.api.feedFilters, isEmpty);

    await h.notifications.loadPluginNotificationFeed(_site, _installed);
    expect(h.api.feedFilters, [
      [_alertName],
    ]);
  });

  test('dismissal admits only the feed the registry installed', () async {
    final h = _Harness();
    addTearDown(h.activity.dispose);

    await expectLater(
      h.notifications.dismissPluginNotifications(_site, _impostor),
      throwsStateError,
    );
    expect(h.api.markedTypesRead, isEmpty);

    await h.notifications.dismissPluginNotifications(_site, _installed);
    expect(h.api.markedTypesRead, [
      [_alertName],
    ]);
  });

  test('section counts follow the types each section claims', () {
    final h = _Harness();
    addTearDown(h.activity.dispose);

    expect(h.notifications.replyUnreadCount(_site), 2);
    expect(h.notifications.messageUnreadCount(_site), 4);
    expect(h.notifications.allUnreadCount(_site), 14);
    expect(
      h.notifications.otherUnreadCount(_site),
      3,
      reason:
          'Replies, messages and likes have tabs; the plugin alert does not.',
    );
    expect(h.notifications.likeUnreadCount(_site), 5);
  });

  test('a site without a stored instance loads and counts nothing', () async {
    final h = _Harness()..current = null;
    addTearDown(h.activity.dispose);

    await h.notifications.loadPluginNotificationFeed(_site, _installed);

    expect(h.api.feedFilters, isEmpty);
    expect(h.notifications.allUnreadCount(_site), 0);
    expect(h.notifications.otherUnreadCount(_site), 0);
  });

  test('a scoped host refuses a feed its consumer did not declare', () {
    final h = _Harness();
    addTearDown(h.activity.dispose);

    expect(
      () => h.notifications
          .scopedTo(const PluginId('other'))
          .notificationFeedFor(_feedId, _site),
      throwsA(isA<PluginInstallationException>()),
    );
    expect(
      h.notifications.scopedTo(_owner).notificationFeedFor(_feedId, _site),
      same(h.activity.pluginNotificationsFor(_feedId, _site)),
    );
  });
}

final class _Harness {
  _Harness() {
    credentials.keys[_site] = 'key';
    activity = AccountActivityController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
    );
    notifications = UserMenuNotifications(
      registry: const PluginRegistry([_AlertsPlugin()]),
      activity: activity,
      instanceFor: (_) => current,
      openUrl: (_) async => false,
    );
  }

  final api = _Api();
  final credentials = FakeApiCredentialReader();
  late final AccountActivityController activity;
  late final UserMenuNotifications notifications;
  DiscourseInstance? current = instance('meta.discourse.org').copyWith(
    user: DiscourseUser(
      id: 7,
      username: 'reader',
      groupedUnreadNotifications: NotificationTypeCounts.fromWire({
        CoreNotificationTypes.replied.wireId: 2,
        CoreNotificationTypes.privateMessage.wireId: 4,
        _alertType.wireId: 3,
        _pluginLikeType.wireId: 5,
      }),
    ),
  );
}

final class _Api extends FakeDiscourseApi {
  _Api() : super(totals: const NotificationTotals());

  final feedFilters = <List<NotificationTypeName>>[];

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async {
    feedFilters.add(filterByTypes);
    return const [];
  }
}

ResolvedNotification? _decodeNothing(
  String siteUrl,
  DiscourseNotification notification,
) => null;

final class _AlertsPlugin
    implements SitePlugin, NotificationFeedPlugin, NotificationTypePlugin {
  const _AlertsPlugin();

  @override
  String get name => _owner.value;

  @override
  List<PluginNotificationFeedSource> get notificationFeeds => const [
    _installed,
  ];

  @override
  List<PluginNotificationType> get notificationTypes => const [
    PluginNotificationType(
      id: PluginNotificationTypeId(owner: _owner, name: 'like'),
      wireType: _pluginLikeType,
      decode: _decodeNothing,
      coreMenuSection: CoreNotificationMenuSection.likes,
    ),
  ];
}
