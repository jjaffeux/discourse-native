import 'dart:async';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../models/discourse_instance.dart';
import '../models/notification.dart';
import '../models/notification_type_counts.dart';
import 'account_activity_controller.dart';

final class NotificationFeedRefreshOwner {
  NotificationFeedRefreshOwner({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.activity,
    required this.instanceFor,
    required this.claimedTypes,
    required this.groupedAuthorityAdvanced,
    required this.refreshDebounce,
  }) : assert(refreshDebounce >= Duration.zero);

  final ShellSiteApi api;
  final SiteApiKeyReader credentials;
  final SiteLifecycle lifecycle;
  final AccountActivityController activity;
  final DiscourseInstance? Function(String siteUrl) instanceFor;
  final Set<NotificationTypeName> Function(DiscourseInstance instance)
  claimedTypes;
  final void Function(String siteUrl) groupedAuthorityAdvanced;
  final Duration refreshDebounce;
  final Map<String, _NotificationFeedAccount> _accounts = {};
  bool _disposed = false;

  _NotificationFeedAccount? _account(String siteUrl, {SiteLease? lease}) {
    if (_disposed) return null;
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
    await activity.loadOtherNotifications(instance, (_) async {
      if (!_owns(account)) return const [];
      final types = await _siteTypes(account);
      if (!_owns(account)) return const [];
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
    final credential = await AccountRequestSession(
      siteUrl,
      account.lease,
    ).keyCredentials(credentials);
    if (!_owns(account) || credential.apiKey == null) return;
    final types = await _siteTypes(account, credential: credential);
    if (!_owns(account)) return;
    await activity.markAllNotificationsRead(instance, types);
  }

  Future<List<NotificationWireType>> _siteTypes(
    _NotificationFeedAccount account, {
    AccountRequestCredentials? credential,
  }) {
    final cached = account.catalog;
    if (cached != null) return Future.value(cached);
    final active = account.request;
    if (active != null) return active;
    final result = Completer<List<NotificationWireType>>();
    account.request = result.future;
    unawaited(
      _loadTypes(
        account,
        result.future,
        credential,
      ).then(result.complete, onError: result.completeError),
    );
    return result.future;
  }

  Future<List<NotificationWireType>> _loadTypes(
    _NotificationFeedAccount account,
    Future<List<NotificationWireType>> request,
    AccountRequestCredentials? credential,
  ) async {
    try {
      final auth =
          credential ??
          await AccountRequestSession(
            account.siteUrl,
            account.lease,
          ).keyCredentials(credentials);
      if (!_owns(account)) throw const AccountRequestRetiredException();
      final types = await auth.run(
        () => api.siteNotificationTypes(
          siteUrl: account.siteUrl,
          apiKey: auth.apiKey!,
        ),
      );
      final immutable = List<NotificationWireType>.unmodifiable(types);
      if (_owns(account)) account.catalog = immutable;
      return immutable;
    } finally {
      if (identical(account.request, request)) account.request = null;
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
    activity.applyLiveNotificationState(siteUrl, data);
    if (!_owns(account) || !activity.hasTrackedPluginNotifications(siteUrl)) {
      return;
    }
    account.timer?.cancel();
    late final Timer timer;
    timer = Timer(refreshDebounce, () {
      if (!_owns(account) || !identical(account.timer, timer)) return;
      account.timer = null;
      final instance = instanceFor(siteUrl);
      if (instance?.isConnected != true) return;
      activity.refreshLoadedPluginNotifications(instance!).ignore();
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
  List<NotificationWireType>? catalog;
  Future<List<NotificationWireType>>? request;
  Timer? timer;
  void Function()? detach;
  bool _retired = false;

  bool get isCurrent => !_retired && lease.isCurrent;

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
    timer?.cancel();
    timer = null;
    request?.ignore();
    request = null;
    catalog = null;
  }
}
