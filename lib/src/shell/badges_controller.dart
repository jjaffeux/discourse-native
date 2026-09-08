import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/badges_api.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
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

typedef _BadgeKey = ({String siteUrl, BadgeRoute route});

final class BadgesController extends FrameSafeNotifier {
  BadgesController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final BadgesApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final Map<_BadgeKey, BadgesState> _states = {};
  final Map<_BadgeKey, Object> _requests = {};
  final Map<_BadgeKey, SiteLease> _leases = {};

  BadgesState stateFor(String siteUrl, BadgeRoute route) {
    final key = (siteUrl: siteUrl, route: route);
    return _leases[key]?.isCurrent == true
        ? _states[key] ?? const BadgesState()
        : const BadgesState();
  }

  Future<void> load(
    DiscourseInstance instance,
    BadgeRoute route, {
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed || !instance.config.badgesEnabled) return;
    final key = (siteUrl: instance.url, route: route);
    if (_leases[key]?.isCurrent == false) _remove(key);
    final held = stateFor(instance.url, route);
    if (_requests.containsKey(key) ||
        (!refresh && !more && held.loaded) ||
        (more &&
            (held.badge == null ||
                (!held.hasMore && held.recipientsError == null)))) {
      return;
    }

    final lease = lifecycle.capture(instance.url);
    final token = Object();
    _leases[key] = lease;
    _requests[key] = token;
    _states.remove(key);
    _states[key] = held.copyWith(loading: !more, loadingMore: more);
    final keys = _states.keys
        .where((entry) => entry.siteUrl == instance.url)
        .toList();
    for (final oldest in keys.take((keys.length - 16).clamp(0, keys.length))) {
      _remove(oldest);
    }
    notifySafely();

    bool current() =>
        !isDisposed && lease.isCurrent && identical(_requests[key], token);
    var fetchingRecipients = more;
    try {
      final apiKey = instance.isConnected
          ? await credentials.apiKeyFor(instance.url)
          : null;
      if (!current()) return;
      if (instance.isConnected && apiKey == null) {
        throw StateError('Missing account credentials');
      }
      final clientId = instance.isConnected
          ? await credentials.clientId()
          : null;
      if (!current()) return;
      if (route.isDirectory) {
        final catalog = await api.catalog(
          siteUrl: instance.url,
          apiKey: apiKey,
          clientId: clientId,
        );
        if (!current()) return;
        _states[key] = BadgesState(catalog: catalog, loaded: true);
      } else {
        if (!more) {
          final badge = await api.badge(
            siteUrl: instance.url,
            id: route.badgeId!,
            apiKey: apiKey,
            clientId: clientId,
          );
          if (!current()) return;
          _states[key] = BadgesState(badge: badge, loading: true, loaded: true);
          notifySafely();
        }
        fetchingRecipients = true;
        final offset = more ? held.nextOffset : 0;
        final page = await api.grants(
          siteUrl: instance.url,
          route: route,
          offset: offset,
          apiKey: apiKey,
          clientId: clientId,
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
        _states[key] = _states[key]!.copyWith(
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
    } catch (error, stackTrace) {
      if (!current()) return;
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: fetchingRecipients ? 'badges.recipients' : 'badges.load',
        source: 'badges',
        handled: true,
        degraded: true,
      );
      _states[key] = _states[key]!.copyWith(
        loading: false,
        loadingMore: false,
        loaded: true,
        error: fetchingRecipients
            ? null
            : "Couldn't load ${route.isDirectory ? 'badges' : 'this badge'}.",
        recipientsError: fetchingRecipients
            ? "Couldn't load badge recipients."
            : null,
      );
      notifySafely();
    } finally {
      if (identical(_requests[key], token)) _requests.remove(key);
    }
  }

  void _remove(_BadgeKey key) {
    _states.remove(key);
    _requests.remove(key);
    _leases.remove(key);
  }

  void forget(String siteUrl) {
    for (final key
        in _states.keys.where((key) => key.siteUrl == siteUrl).toList()) {
      _remove(key);
    }
    notifySafely();
  }

  @override
  void dispose() {
    _states.clear();
    _requests.clear();
    _leases.clear();
    super.dispose();
  }
}
