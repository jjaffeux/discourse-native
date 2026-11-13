import 'dart:async';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../models/discourse_instance.dart';
import '../models/notification.dart';
import '../models/notification_type_counts.dart';

final class NotificationFeedRefreshOwner {
  NotificationFeedRefreshOwner({
    required this.siteNotificationTypes,
    required this.credentials,
    required this.lifecycle,
    required this.loadOther,
    required this.markAllRead,
    required this.applyLiveState,
    required this.hasTrackedPluginNotifications,
    required this.refreshLoadedPluginNotifications,
    required this.instanceFor,
    required this.claimedTypes,
    required this.groupedAuthorityAdvanced,
    required this.refreshDebounce,
  }) : assert(refreshDebounce >= Duration.zero);

  final Future<List<NotificationWireType>> Function({
    required String siteUrl,
    required String apiKey,
  })
  siteNotificationTypes;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final Future<void> Function(
    DiscourseInstance instance,
    Future<List<NotificationTypeName>> Function(String apiKey) resolveTypes,
  )
  loadOther;
  final Future<void> Function(
    DiscourseInstance instance,
    List<NotificationWireType> types,
  )
  markAllRead;
  final void Function(String siteUrl, Object? data) applyLiveState;
  final bool Function(String siteUrl) hasTrackedPluginNotifications;
  final Future<void> Function(DiscourseInstance instance)
  refreshLoadedPluginNotifications;
  final DiscourseInstance? Function(String siteUrl) instanceFor;
  final Set<NotificationTypeName> Function(DiscourseInstance instance)
  claimedTypes;
  final void Function(String siteUrl) groupedAuthorityAdvanced;
  final Duration refreshDebounce;
  final Map<String, _NotificationFeedAccount> _accounts = {};
  bool _disposed = false;

  _NotificationFeedAccount? _account(String siteUrl, {SiteLease? lease}) {
    if (_disposed || (lease != null && !lifecycle.owns(siteUrl, lease))) {
      return null;
    }
    final currentLease = lease ?? lifecycle.capture(siteUrl);
    if (!currentLease.isCurrent) return null;
    final held = _accounts[siteUrl];
    if (held != null &&
        held.isCurrent &&
        identical(held.lease.session, currentLease.session)) {
      return held;
    }
    held?.retire();
    final account = _NotificationFeedAccount(siteUrl, currentLease);
    _accounts[siteUrl] = account;
    account.detach = currentLease.onRetire(() {
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
      account.retire();
    });
    return account;
  }

  bool _owns(_NotificationFeedAccount account) =>
      !_disposed &&
      account.isCurrent &&
      identical(_accounts[account.siteUrl], account);

  Future<void> loadOtherNotifications(String siteUrl) async {
    final instance = instanceFor(siteUrl);
    if (instance == null) return;
    final account = _account(siteUrl);
    if (account == null) return;
    await loadOther(instance, (_) async {
      if (!_owns(account)) return const [];
      final types = await _siteTypes(account);
      if (types == null || !_owns(account)) return const [];
      final current = instanceFor(siteUrl);
      if (current == null) return const [];
      final claimed = claimedTypes(current);
      return List<NotificationTypeName>.unmodifiable([
        for (final type in types)
          if (!claimed.contains(NotificationTypeName(type.wireName)))
            NotificationTypeName(type.wireName),
      ]);
    });
  }

  Future<void> markAllNotificationsRead(String siteUrl) async {
    final instance = instanceFor(siteUrl);
    if (instance == null || !instance.isConnected) return;
    final account = _account(siteUrl);
    if (account == null) return;
    final retired = Completer<void>();
    account.credentialWaiters.add(retired);
    final AccountRequestCredentials? credential;
    try {
      credential = await Future.any<AccountRequestCredentials?>([
        AccountRequestSession(
          siteUrl,
          account.lease,
        ).keyCredentials(credentials),
        retired.future.then((_) {
          if (!account.lease.isCurrent) {
            throw const AccountRequestRetiredException();
          }
          return null;
        }),
      ]);
    } finally {
      account.credentialWaiters.remove(retired);
    }
    if (!_owns(account) || credential?.apiKey == null) return;
    final types = await _siteTypes(account, credential: credential);
    if (types == null || !_owns(account)) return;
    await markAllRead(instance, types);
  }

  Future<List<NotificationWireType>?> _siteTypes(
    _NotificationFeedAccount account, {
    AccountRequestCredentials? credential,
  }) {
    final cached = account.catalog;
    if (cached != null) return Future.value(cached);
    final active = account.request;
    if (active != null) return active.future;
    final result = Completer<List<NotificationWireType>?>();
    account.request = result;
    unawaited(_loadTypes(account, result, credential));
    return result.future;
  }

  Future<void> _loadTypes(
    _NotificationFeedAccount account,
    Completer<List<NotificationWireType>?> request,
    AccountRequestCredentials? credential,
  ) async {
    try {
      final auth =
          credential ??
          await AccountRequestSession(
            account.siteUrl,
            account.lease,
          ).keyCredentials(credentials);
      if (request.isCompleted) return;
      if (!_owns(account)) throw const AccountRequestRetiredException();
      final types = await auth.run(
        () => siteNotificationTypes(
          siteUrl: account.siteUrl,
          apiKey: auth.apiKey!,
        ),
      );
      if (request.isCompleted) return;
      final immutable = List<NotificationWireType>.unmodifiable(types);
      if (_owns(account)) account.catalog = immutable;
      request.complete(immutable);
    } catch (error, stackTrace) {
      if (!request.isCompleted) request.completeError(error, stackTrace);
    } finally {
      if (identical(account.request, request)) account.request = null;
    }
  }

  /// Adopts the catalog carried by a `/site.json` read [lease] already made.
  /// An empty one settles nothing, so the first reader still fetches its own.
  void seedSiteTypes(
    String siteUrl,
    List<NotificationWireType> types,
    SiteLease lease,
  ) {
    if (types.isEmpty) return;
    final account = _account(siteUrl, lease: lease);
    if (account != null && _owns(account)) {
      final catalog = account.catalog ??=
          List<NotificationWireType>.unmodifiable(types);
      final request = account.request;
      account.request = null;
      request?.complete(catalog);
    }
  }

  void acceptLiveState(String siteUrl, Object? data, SiteLease lease) {
    final account = _account(siteUrl, lease: lease);
    if (account == null) return;
    final grouped = data is Map
        ? NotificationTypeCounts.fromWire(data['grouped_unread_notifications'])
        : NotificationTypeCounts.unavailable;
    if (grouped.isAvailable) groupedAuthorityAdvanced(siteUrl);
    if (!_owns(account)) return;
    applyLiveState(siteUrl, data);
    if (!_owns(account) || !hasTrackedPluginNotifications(siteUrl)) {
      return;
    }
    account.timer?.cancel();
    late final Timer timer;
    timer = Timer(refreshDebounce, () {
      if (!_owns(account) || !identical(account.timer, timer)) return;
      account.timer = null;
      final instance = instanceFor(siteUrl);
      if (instance?.isConnected != true) return;
      refreshLoadedPluginNotifications(instance!).ignore();
    });
    account.timer = timer;
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?.retire();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final accounts = _accounts.values.toList();
    _accounts.clear();
    for (final account in accounts) {
      account.retire();
    }
  }
}

final class _NotificationFeedAccount {
  _NotificationFeedAccount(this.siteUrl, this.lease);

  final String siteUrl;
  final SiteLease lease;
  final credentialWaiters = <Completer<void>>{};
  List<NotificationWireType>? catalog;
  Completer<List<NotificationWireType>?>? request;
  Timer? timer;
  void Function()? detach;
  bool _retired = false;

  bool get isCurrent => !_retired && lease.isCurrent;

  void retire() {
    if (_retired) return;
    _retired = true;
    for (final waiter in credentialWaiters) {
      waiter.complete();
    }
    credentialWaiters.clear();
    detach?.call();
    detach = null;
    timer?.cancel();
    timer = null;
    final pending = request;
    request = null;
    pending?.complete(null);
    catalog = null;
  }
}
