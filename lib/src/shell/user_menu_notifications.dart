import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show Listenable;

import '../models/discourse_instance.dart';
import '../models/notification.dart';
import '../models/notification_type_counts.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_runtime.dart';
import '../plugin_api/site_plugin_api.dart';
import 'account_activity_controller.dart';
import 'site_url.dart';

/// Decides which unread notifications each user-menu section counts, and which
/// plugin feeds a notification host admits. Canonical feeds and totals stay in
/// [AccountActivityController]; this owner holds no account state of its own.
final class UserMenuNotifications implements PluginNotificationFeedHost {
  const UserMenuNotifications({
    required this._registry,
    required this._activity,
    required this._instanceFor,
    required this._openUrl,
  });

  final PluginRegistry _registry;
  final AccountActivityController _activity;
  final DiscourseInstance? Function(String siteUrl) _instanceFor;
  final Future<bool> Function(String url) _openUrl;

  int likeUnreadCount(String siteUrl) =>
      _groupedUnreadCountOf(siteUrl, _registry.likeNotificationTypes);

  /// The menu counts unread rows even after opening the bell marks them seen.
  int allUnreadCount(String siteUrl) =>
      _groupedUnreadCountsFor(siteUrl)?.totalExcluding(const []) ??
      _activity.totalsFor(siteUrl)?.coreBadge ??
      0;

  // The Replies, Messages and Bookmarks tabs count unread notifications of
  // their own types, as Discourse's menu does. The seen-scoped
  // `new_personal_messages_notifications_count` is not a Messages count: the
  // Notifications tab's non-silent fetch bumps the seen marker, and core then
  // publishes it as zero while those notifications are still unread.
  int replyUnreadCount(String siteUrl) =>
      _groupedUnreadCountOf(siteUrl, userMenuReplyNotificationTypes);

  int messageUnreadCount(String siteUrl) {
    final counts = _groupedUnreadCountsFor(siteUrl);
    return counts?.count(CoreNotificationTypes.privateMessage) ?? 0;
  }

  int bookmarkReminderUnreadCount(String siteUrl) {
    final counts = _groupedUnreadCountsFor(siteUrl);
    return counts?.count(CoreNotificationTypes.bookmarkReminder) ?? 0;
  }

  int otherUnreadCount(
    String siteUrl, {
    List<PluginUserMenuSection>? pluginSections,
  }) {
    final instance = _instanceFor(siteUrl);
    final counts = _groupedUnreadCountsFor(siteUrl);
    if (counts == null) return 0;

    final claimedNames = _claimedTypes(
      pluginSections ?? _pluginSectionsFor(instance),
    );
    final claimedIds = <NotificationTypeId>{
      for (final definition in _registeredTypes)
        if (claimedNames.contains(NotificationTypeName(definition.wireName)))
          NotificationTypeId(definition.wireId),
    };
    return counts.totalExcluding(claimedIds);
  }

  /// Notification types a dedicated section shows, which Other leaves out.
  Set<NotificationTypeName> claimedTypesFor(DiscourseInstance instance) =>
      _claimedTypes(_pluginSectionsFor(instance));

  /// The host a plugin receives, limited to the feeds that plugin declared.
  PluginNotificationFeedHost scopedTo(PluginId consumer) =>
      _ScopedPluginNotificationFeedHost(this, consumer, {
        for (final source in _registry.notificationFeeds)
          if (source.id.owner == consumer) source.id: source,
      });

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) =>
      _activity.pluginNotificationsListenable(id);

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) => _activity.pluginNotificationsFor(id, siteUrl);

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {
    final registered = _registry.notificationFeed(source.id);
    if (registered != source) {
      throw StateError(
        'Notification feed ${source.id.id} is not installed in this build.',
      );
    }
    final instance = _instanceFor(siteUrl);
    if (instance != null) {
      await _activity.loadPluginNotifications(instance, registered!);
    }
  }

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) async {
    final registered = _registry.notificationFeed(source.id);
    if (registered != source) {
      throw StateError(
        'Notification feed ${source.id.id} is not installed in this build.',
      );
    }
    if (registered!.dismissal == null) {
      throw StateError(
        'Notification feed ${source.id.id} does not support dismissal.',
      );
    }
    final instance = _instanceFor(siteUrl);
    if (instance == null) {
      throw StateError('No forum is registered for $siteUrl.');
    }
    await _activity.dismissPluginNotifications(instance, registered);
  }

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) {
    final instance = _instanceFor(siteUrl);
    if (instance != null) _activity.readNotification(instance, notification);
  }

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      resolveSiteRootPath(siteUrl, path);

  @override
  Future<bool> openPluginNotificationUrl(String url) => _openUrl(url);

  int _groupedUnreadCountOf(
    String siteUrl,
    Iterable<NotificationTypeName> types,
  ) {
    final counts = _groupedUnreadCountsFor(siteUrl);
    if (counts == null) return 0;
    final names = types.toSet();
    return _registeredTypes
        .where((type) => names.contains(NotificationTypeName(type.wireName)))
        .fold(0, (total, type) => total + counts.count(type));
  }

  NotificationTypeCounts? _groupedUnreadCountsFor(String siteUrl) {
    final instance = _instanceFor(siteUrl);
    final live = _activity.totalsFor(siteUrl)?.groupedUnreadNotifications;
    final counts = live?.isAvailable == true
        ? live!
        : instance?.user?.groupedUnreadNotifications;
    return counts?.isAvailable == true ? counts : null;
  }

  Iterable<NotificationWireType> get _registeredTypes sync* {
    yield* CoreNotificationTypes.values;
    for (final type in _registry.notificationTypes) {
      yield type.wireType;
    }
  }

  Set<NotificationTypeName> _claimedTypes(
    Iterable<PluginUserMenuSection> pluginSections,
  ) => {
    ...userMenuDedicatedNotificationTypes,
    ..._registry.likeNotificationTypes,
    for (final section in pluginSections) ...section.notificationTypes,
  };

  List<PluginUserMenuSection> _pluginSectionsFor(DiscourseInstance? instance) {
    final user = instance?.user;
    if (instance == null || user == null) return const [];
    return _registry.userMenuSections(
      PluginUserMenuContext(
        siteUrl: instance.url,
        user: user,
        totals: _activity.totalsFor(instance.url),
      ),
    );
  }
}

final class _ScopedPluginNotificationFeedHost
    implements PluginNotificationFeedHost {
  const _ScopedPluginNotificationFeedHost(
    this._host,
    this._consumer,
    this._sources,
  );

  final PluginNotificationFeedHost _host;
  final PluginId _consumer;
  final Map<PluginNotificationFeedId, PluginNotificationFeedSource> _sources;

  PluginNotificationFeedSource _requireDeclared(PluginNotificationFeedId id) {
    final source = _sources[id];
    if (source != null) return source;
    final reason = id.owner == _consumer
        ? appL10n.didNotRegisterNotificationFeed
        : appL10n.cannotAccessNotificationFeed;
    throw PluginInstallationException(
      appL10n.plugin(
        (_consumer).toString(),
        (reason).toString(),
        (id.id).toString(),
      ),
    );
  }

  @override
  Listenable notificationFeedListenable(PluginNotificationFeedId id) {
    _requireDeclared(id);
    return _host.notificationFeedListenable(id);
  }

  @override
  NotificationFeed notificationFeedFor(
    PluginNotificationFeedId id,
    String siteUrl,
  ) {
    _requireDeclared(id);
    return _host.notificationFeedFor(id, siteUrl);
  }

  @override
  Future<void> loadPluginNotificationFeed(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) {
    final registered = _requireDeclared(source.id);
    if (registered != source) {
      throw PluginInstallationException(
        appL10n.pluginMustUseItsRegisteredNotificationFeed(
          (_consumer).toString(),
          (source.id.id).toString(),
        ),
      );
    }
    return _host.loadPluginNotificationFeed(siteUrl, registered);
  }

  @override
  Future<void> dismissPluginNotifications(
    String siteUrl,
    PluginNotificationFeedSource source,
  ) {
    final registered = _requireDeclared(source.id);
    if (registered != source) {
      throw PluginInstallationException(
        appL10n.pluginMustUseItsRegisteredNotificationFeed(
          (_consumer).toString(),
          (source.id.id).toString(),
        ),
      );
    }
    if (registered.dismissal == null) {
      throw PluginInstallationException(
        appL10n.pluginDidNotRegisterDismissalForNotificationFeed(
          (_consumer).toString(),
          (source.id.id).toString(),
        ),
      );
    }
    return _host.dismissPluginNotifications(siteUrl, registered);
  }

  @override
  void readPluginNotification(
    String siteUrl,
    DiscourseNotification notification,
  ) => _host.readPluginNotification(siteUrl, notification);

  @override
  String pluginAbsoluteUrl(String path, {required String siteUrl}) =>
      _host.pluginAbsoluteUrl(path, siteUrl: siteUrl);

  @override
  Future<bool> openPluginNotificationUrl(String url) =>
      _host.openPluginNotificationUrl(url);
}
