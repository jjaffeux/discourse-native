import 'dart:async';
import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'cakeday_api.dart';
import 'cakeday_data.dart';

const cakedayControllerKey = PluginServiceKey<CakedayController>(
  owner: cakedayPluginId,
  name: 'controller',
);

enum CakedayFailure { request, forbidden, unavailable }

final class CakedayDirectoryState {
  const CakedayDirectoryState({
    this.members = const [],
    this.total = 0,
    this.loaded = false,
    this.loading = false,
    this.loadingMore = false,
    this.failure,
    this.nextPage,
    this.failedPage,
  });
  final List<CakedayMember> members;
  final int total;
  final bool loaded, loading, loadingMore;
  final CakedayFailure? failure;
  final int? nextPage, failedPage;
}

final class CakedayController extends FrameSafeNotifier
    implements
        PluginSiteActivator,
        PluginCurrentUserObserver,
        PluginRouteHydrator {
  CakedayController({
    required this.api,
    required this.requests,
    required this.siteState,
    required this.timezone,
    required this.emoji,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    timezone.changes.addListener(_timeChanged);
  }
  final CakedayApi api;
  final PluginRequestHost requests;
  final PluginSiteStateHost siteState;
  final PluginTimezoneHost timezone;
  final PluginEmojiHost emoji;
  final DateTime Function() _clock;
  final _states = <(String, CakedayQuery), CakedayDirectoryState>{};
  final _tokens = <(String, CakedayQuery), Object>{};
  final _observedSites = <String>{};
  final _settingsListeners = <String, (Listenable, VoidCallback)>{};
  final _revisions = <String, int>{};
  final _forbidden = <String>{};
  final _unavailable = <(String, CakedayKind)>{};
  final _visible = <(String, CakedayQuery), int>{};
  final _siteDays = <String, DateTime>{};
  Timer? _timer;
  bool _foreground = true;
  DateTime? _day;
  DateTime get now => _clock();
  int revision(String site) => _revisions[site] ?? 0;
  CakedaySettings settings(String site) =>
      siteState.siteConfigFor(site).plugins.get(cakedaySettingsKey) ??
      const CakedaySettings();
  bool enabled(String site, [CakedayKind? kind]) =>
      !isDisposed &&
      !_forbidden.contains(site) &&
      (kind == null || !_unavailable.contains((site, kind))) &&
      siteState.currentUserFor(site) != null &&
      settings(site).enabled &&
      (kind != CakedayKind.birthdays || settings(site).birthdays);
  List<CakedayKind> celebrations(String site, CakedayDates dates) => [
    if (enabled(site, CakedayKind.birthdays) && dates.celebratesBirthday(now))
      CakedayKind.birthdays,
    if (enabled(site, CakedayKind.anniversaries) &&
        dates.celebratesAnniversary(now))
      CakedayKind.anniversaries,
  ];

  DateTime viewerToday(String site) {
    final zone = timezone.readerTimezone(
      siteState.currentUserFor(site)?.timezone,
    );
    final location = timezone.location(zone);
    final date = location == null
        ? now.toUtc()
        : tz.TZDateTime.from(now, location);
    return DateTime.utc(date.year, date.month, date.day);
  }

  CakedayDirectoryState state(String site, CakedayQuery query) =>
      enabled(site, query.kind)
      ? _states[(site, query)] ?? const CakedayDirectoryState()
      : const CakedayDirectoryState(failure: CakedayFailure.unavailable);
  void retain(String site, CakedayQuery query) {
    _observe(site);
    final key = (site, query);
    _visible[key] = (_visible[key] ?? 0) + 1;
    _schedule();
    unawaited(load(site, query, refresh: true));
  }

  void release(String site, CakedayQuery query) {
    final key = (site, query), count = _visible[(site, query)] ?? 0;
    if (count <= 1) {
      _visible.remove(key);
    } else {
      _visible[key] = count - 1;
    }
  }

  Future<void> load(
    String site,
    CakedayQuery query, {
    bool refresh = false,
    bool more = false,
  }) async {
    _observe(site);
    if (!enabled(site, query.kind)) return;
    final key = (site, query), held = state(site, query);
    if (_tokens.containsKey(key)) return;
    if (more && (!held.loaded || held.nextPage == null)) return;
    if (!refresh && !more && held.loaded) return;
    final page = more ? held.nextPage! : 0;
    final token = Object(),
        lease = requests.capture(site),
        epoch = revision(site);
    _tokens[key] = token;
    bool current() =>
        !isDisposed &&
        lease.isCurrent &&
        epoch == revision(site) &&
        identical(_tokens[key], token) &&
        enabled(site, query.kind);
    _states[key] = CakedayDirectoryState(
      members: held.members,
      total: held.total,
      loaded: held.loaded,
      loading: !more,
      loadingMore: more,
      nextPage: held.nextPage,
    );
    notifySafely();
    try {
      final credentials = await requests.credentialsFor(site);
      if (!current()) return;
      if (credentials.apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final result = await credentials.run(
        () => api.load(site, query, page, credentials),
      );
      if (!current()) return;
      lease.commit(() {
        final rows = <int, CakedayMember>{
          for (final member in more ? held.members : const <CakedayMember>[])
            member.id: member,
        };
        for (final member in result.members) {
          rows[member.id] = member;
        }
        _states[key] = CakedayDirectoryState(
          members: List.unmodifiable(rows.values),
          total: result.total,
          loaded: true,
          nextPage:
              rows.length >= result.total ||
                  result.members.isEmpty ||
                  (more && rows.length == held.members.length)
              ? null
              : result.nextPage,
        );
      });
    } catch (error) {
      if (!current()) return;
      final status = switch (error) {
        SiteLookupException(:final statusCode) => statusCode,
        WriteException(:final statusCode) => statusCode,
        _ => null,
      };
      final forbidden =
          status == 401 ||
          status == 403 ||
          (error is WriteException && error.failure == WriteFailure.forbidden);
      final unavailable = status == 404;
      if (forbidden || unavailable) {
        if (forbidden) {
          _forbidden.add(site);
        } else {
          _unavailable.add((site, query.kind));
        }
        _states.removeWhere(
          (key, _) =>
              key.$1 == site && (forbidden || key.$2.kind == query.kind),
        );
      } else {
        _states[key] = CakedayDirectoryState(
          members: held.members,
          total: held.total,
          loaded: held.loaded,
          nextPage: held.nextPage,
          failure: CakedayFailure.request,
          failedPage: page,
        );
      }
    } finally {
      if (identical(_tokens[key], token)) {
        _tokens.remove(key);
      }
      if (!isDisposed && epoch == revision(site)) notifySafely();
    }
  }

  void _observe(String site) {
    if (isDisposed) return;
    if (_observedSites.add(site)) _siteDays[site] = viewerToday(site);
    if (_settingsListeners.containsKey(site)) return;
    final source = siteState.siteConfigListenableFor?.call(site);
    if (source != null) {
      void callback() {
        _revisions[site] = revision(site) + 1;
        _tokens.removeWhere((key, _) => key.$1 == site);
        _states.removeWhere((key, _) => key.$1 == site);
        _forbidden.remove(site);
        _unavailable.removeWhere((key) => key.$1 == site);
        _schedule();
        notifySafely();
        for (final key in _visible.keys.toList()) {
          if (key.$1 == site) unawaited(load(site, key.$2, refresh: true));
        }
      }

      _settingsListeners[site] = (source, callback);
      source.addListener(callback);
    }
    _schedule();
  }

  void observeDecorations(String site) => _observe(site);
  void _schedule() {
    if (!_foreground || isDisposed || !_observedSites.any(enabled)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _rememberDays();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_deviceDay() != _day ||
          _observedSites.any((site) => viewerToday(site) != _siteDays[site])) {
        _timeChanged();
      }
    });
  }

  DateTime _deviceDay() {
    final date = now;
    return DateTime.utc(date.year, date.month, date.day);
  }

  void _rememberDays() {
    _day = _deviceDay();
    for (final site in _observedSites) {
      _siteDays[site] = viewerToday(site);
    }
  }

  void _timeChanged() {
    if (isDisposed) return;
    _rememberDays();
    for (final site in _visible.keys.map((key) => key.$1).toSet()) {
      _revisions[site] = revision(site) + 1;
      _tokens.removeWhere((key, _) => key.$1 == site);
      _states.removeWhere((key, _) => key.$1 == site);
    }
    for (final key in _visible.keys.toList()) {
      unawaited(load(key.$1, key.$2, refresh: true));
    }
    notifySafely();
  }

  @override
  void activatePluginSite(String siteUrl, {required bool connected}) {
    _observe(siteUrl);
    notifySafely();
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    forget(siteUrl);
    _observe(siteUrl);
    for (final key in _visible.keys.toList()) {
      if (key.$1 == siteUrl) unawaited(load(siteUrl, key.$2, refresh: true));
    }
  }

  @override
  bool handlesPluginRoute(String routeId) =>
      CakedayQuery.parse(routeId) != null;
  @override
  Future<void> hydratePluginRoute(
    String siteUrl,
    String routeId, {
    bool force = false,
  }) async {
    final query = CakedayQuery.parse(routeId);
    if (query != null) await load(siteUrl, query, refresh: force);
  }

  void forget(String site) {
    _observedSites.remove(site);
    _siteDays.remove(site);
    _revisions[site] = revision(site) + 1;
    _states.removeWhere((key, _) => key.$1 == site);
    _tokens.removeWhere((key, _) => key.$1 == site);
    _forbidden.remove(site);
    _unavailable.removeWhere((key) => key.$1 == site);
    final listener = _settingsListeners.remove(site);
    if (listener != null) listener.$1.removeListener(listener.$2);
    _schedule();
    notifySafely();
  }

  void setForeground(bool value) {
    _foreground = value;
    _timer?.cancel();
    _timer = null;
    if (value) {
      _schedule();
      _timeChanged();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    timezone.changes.removeListener(_timeChanged);
    for (final listener in _settingsListeners.values) {
      listener.$1.removeListener(listener.$2);
    }
    _observedSites.clear();
    _siteDays.clear();
    _settingsListeners.clear();
    _states.clear();
    _tokens.clear();
    _visible.clear();
    super.dispose();
  }
}
