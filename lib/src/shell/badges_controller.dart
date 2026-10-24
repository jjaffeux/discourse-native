import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/badges_api.dart';
import '../data/site_lifecycle.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/badge.dart';
import '../models/badge_route.dart';
import '../models/discourse_instance.dart';

@immutable
final class BadgesState {
  const BadgesState({
    this.catalog,
    this.badge,
    this.grants = const [],
    this.totalGrants,
    this.nextOffset = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.recipientsError,
  });

  final BadgeCatalog? catalog;
  final DiscourseBadge? badge;
  final List<BadgeGrant> grants;
  final int? totalGrants;
  final int nextOffset;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final String? recipientsError;

  BadgesState copyWith({
    BadgeCatalog? catalog,
    DiscourseBadge? badge,
    List<BadgeGrant>? grants,
    int? totalGrants,
    int? nextOffset,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    bool? loaded,
    String? error,
    String? recipientsError,
  }) => BadgesState(
    catalog: catalog ?? this.catalog,
    badge: badge ?? this.badge,
    grants: grants == null ? this.grants : List.unmodifiable(grants),
    totalGrants: totalGrants ?? this.totalGrants,
    nextOffset: nextOffset ?? this.nextOffset,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    loaded: loaded ?? this.loaded,
    error: error,
    recipientsError: recipientsError,
  );
}

final class _BadgeAccount {
  _BadgeAccount(this.lease);

  final SiteLease lease;
  final Map<BadgeRoute, BadgesState> states = {};
  final Map<BadgeRoute, Object> requests = {};
  void Function()? detach;

  void trim() {
    for (final route
        in states.keys
            .take((states.length - 16).clamp(0, states.length))
            .toList()) {
      states.remove(route);
      requests.remove(route);
    }
  }

  void dispose() {
    detach?.call();
    detach = null;
    states.clear();
    requests.clear();
  }
}

final class BadgesController extends FrameSafeNotifier {
  BadgesController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final BadgesApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Map<String, _BadgeAccount> _accounts = {};

  _BadgeAccount? _accountFor(String siteUrl) {
    final account = _accounts[siteUrl];
    return account?.lease.isCurrent == true ? account : null;
  }

  _BadgeAccount _ensureAccount(String siteUrl) {
    final held = _accountFor(siteUrl);
    if (held != null) return held;
    final account = _BadgeAccount(lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      final owned = identical(_accounts[siteUrl], account);
      if (owned) _accounts.remove(siteUrl);
      account.dispose();
      if (owned) notifySafely();
    });
    return account;
  }

  BadgesState stateFor(String siteUrl, BadgeRoute route) =>
      _accountFor(siteUrl)?.states[route] ?? const BadgesState();

  Future<void> load(
    DiscourseInstance instance,
    BadgeRoute route, {
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed || !instance.config.badgesEnabled) return;
    final account = _ensureAccount(instance.url);
    final held = account.states[route] ?? const BadgesState();
    if (account.requests.containsKey(route) ||
        (!refresh && !more && held.loaded) ||
        (more &&
            (held.badge == null ||
                (!held.hasMore && held.recipientsError == null)))) {
      return;
    }

    final lease = account.lease;
    final token = Object();
    account.requests[route] = token;
    account.states.remove(route);
    account.states[route] = held.copyWith(loading: !more, loadingMore: more);
    account.trim();
    notifySafely();

    bool current() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_accounts[instance.url], account) &&
        identical(account.requests[route], token);
    var fetchingRecipients = more;
    try {
      final session = AccountRequestSession(instance.url, lease);
      final auth = instance.isConnected
          ? await session.credentials(credentials)
          : session.anonymousCredentials();
      if (!current()) return;
      if (instance.isConnected && auth.apiKey == null) {
        throw StateError('Missing account credentials');
      }
      final apiKey = auth.apiKey;
      final clientId = apiKey == null ? null : auth.clientId;
      if (route.isDirectory) {
        final catalog = await auth.run(
          () => api.catalog(
            siteUrl: instance.url,
            apiKey: apiKey,
            clientId: clientId,
          ),
        );
        if (!current()) return;
        account.states[route] = BadgesState(catalog: catalog, loaded: true);
      } else {
        if (!more) {
          final badge = await auth.run(
            () => api.badge(
              siteUrl: instance.url,
              id: route.badgeId!,
              apiKey: apiKey,
              clientId: clientId,
            ),
          );
          if (!current()) return;
          account.states[route] = BadgesState(
            badge: badge,
            loading: true,
            loaded: true,
          );
          notifySafely();
          if (!current()) return;
        }
        fetchingRecipients = true;
        final offset = more ? held.nextOffset : 0;
        final page = await auth.run(
          () => api.grants(
            siteUrl: instance.url,
            route: route,
            offset: offset,
            apiKey: apiKey,
            clientId: clientId,
          ),
        );
        if (!current()) return;
        final rows = more ? [...held.grants] : <BadgeGrant>[];
        final seen = {for (final row in rows) row.id};
        var added = 0;
        for (final row in page.grants) {
          if (seen.add(row.id)) {
            rows.add(row);
            added++;
          }
        }
        final nextOffset = offset + page.rawCount;
        account.states[route] = account.states[route]!.copyWith(
          grants: rows,
          totalGrants: page.total,
          nextOffset: nextOffset,
          hasMore:
              page.rawCount >= BadgesApi.pageSize &&
              added > 0 &&
              (page.total == null || nextOffset < page.total!),
          loading: false,
          loadingMore: false,
          loaded: true,
        );
      }
      notifySafely();
    } catch (error) {
      if (!current()) return;

      account.states[route] = account.states[route]!.copyWith(
        loading: false,
        loadingMore: false,
        loaded: true,
        error: fetchingRecipients
            ? null
            : appL10n.couldnTLoad((route.isDirectory).toString()),
        recipientsError: fetchingRecipients
            ? appL10n.couldnTLoadBadgeRecipients
            : null,
      );
      notifySafely();
    } finally {
      if (identical(account.requests[route], token)) {
        account.requests.remove(route);
      }
    }
  }

  void forget(String siteUrl) {
    _accounts.remove(siteUrl)?.dispose();
    notifySafely();
  }

  @override
  void dispose() {
    for (final account in _accounts.values) {
      account.dispose();
    }
    _accounts.clear();
    super.dispose();
  }
}
