import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_route.dart';
import 'coalescing_snapshot_writer.dart';
import 'preference_storage_scope.dart';

abstract interface class RecentDestinationsPersistence {
  Future<String?> read();

  Future<bool> write(String value);
}

@PreferenceStorage.document(
  'RecentDestinationsStore.forgetSite removes visits before the next snapshot.',
)
final class SharedPreferencesRecentDestinationsPersistence
    implements RecentDestinationsPersistence {
  const SharedPreferencesRecentDestinationsPersistence();

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance())
      .getString(RecentDestinationsStore.storageKey);

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        RecentDestinationsStore.storageKey,
        value,
      );
}

final class MemoryRecentDestinationsPersistence
    implements RecentDestinationsPersistence {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    this.value = value;
    return true;
  }
}

/// Recent visits of each kind, scoped to a forum account.
class RecentDestinationsStore {
  RecentDestinationsStore({RecentDestinationsPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesRecentDestinationsPersistence();

  RecentDestinationsStore.memory()
    : _persistence = MemoryRecentDestinationsPersistence();

  static const storageKey = 'discourse_native.recent_destinations';
  static const formatVersion = 1;
  static const _limit = 5;

  final RecentDestinationsPersistence _persistence;
  late final CoalescingSnapshotWriter<List<_RecentDestinationsSnapshot>>
  _snapshots = CoalescingSnapshotWriter(
    owner: _persistence,
    key: storageKey,
    writeSnapshot: _persistSnapshot,
  );
  final Map<(String, String), _RecentDestinations> _entries = {};
  bool _unreadable = false;
  _RecentDestinationsHydration? _hydration;

  List<ContentRoute> categoriesFor(String siteUrl, String accountIdentity) =>
      List.unmodifiable(
        _entries[_accountKey(siteUrl, accountIdentity)]?.categories ?? const [],
      );

  List<ContentRoute> channelsFor(String siteUrl, String accountIdentity) =>
      List.unmodifiable(
        _entries[_accountKey(siteUrl, accountIdentity)]?.channels ?? const [],
      );

  List<ContentRoute> topicsFor(String siteUrl, String accountIdentity) =>
      List.unmodifiable(
        _entries[_accountKey(siteUrl, accountIdentity)]?.topics ?? const [],
      );

  bool hasVisits(String siteUrl, String accountIdentity) {
    final entry = _entries[_accountKey(siteUrl, accountIdentity)];
    return entry != null &&
        (entry.categories.isNotEmpty ||
            entry.channels.isNotEmpty ||
            entry.topics.isNotEmpty);
  }

  /// Returns whether visible history or a pending snapshot changed.
  bool remember(String siteUrl, String accountIdentity, ContentRoute route) {
    final kind = _kindOf(route);
    if (kind == null) return false;
    final pendingChanged =
        _hydration?.remember(siteUrl, accountIdentity, route, kind) ?? false;
    final entry = _entries.putIfAbsent(
      _accountKey(siteUrl, accountIdentity),
      () => _RecentDestinations(siteUrl, accountIdentity),
    );
    return entry.remember(route, kind) || pendingChanged;
  }

  /// Drops every account's visits to [siteUrl]. Returns whether history needs
  /// saving, including an exclusion of entries still being read from storage.
  bool forgetSite(String siteUrl) {
    final pendingChanged = _hydration?.forgetSite(siteUrl) ?? false;
    final held = _entries.length;
    _entries.removeWhere((_, entry) => entry.siteUrl == siteUrl);
    return _entries.length != held || pendingChanged;
  }

  /// Drops every account's visits outside [siteUrls]. Returns whether history
  /// needs saving, including exclusions from a pending storage snapshot.
  bool retainSites(Set<String> siteUrls) {
    final pendingChanged = _hydration?.retainSites(siteUrls) ?? false;
    final held = _entries.length;
    _entries.removeWhere((_, entry) => !siteUrls.contains(entry.siteUrl));
    return _entries.length != held || pendingChanged;
  }

  Future<void> load() {
    final hydration = _hydration ??= _RecentDestinationsHydration();
    final active = hydration.pending;
    if (active != null) return active.future;
    final result = Completer<void>();
    hydration.pending = result;
    unawaited(
      _load(hydration).then<void>(
        (_) {
          hydration.pending = null;
          result.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          hydration.pending = null;
          result.completeError(error, stackTrace);
        },
      ),
    );
    return result.future;
  }

  Future<void> _load(_RecentDestinationsHydration hydration) async {
    final String? raw;
    try {
      raw = await _snapshots.readShared(_persistence.read);
    } catch (_) {
      _unreadable = true;
      return;
    }
    final entries = <(String, String), _RecentDestinations>{};
    try {
      if (raw != null && raw.isNotEmpty) {
        final document = jsonDecode(raw);
        if (document is Map && document['version'] == formatVersion) {
          final values = document['entries'];
          if (values is List) {
            for (final value in values) {
              final entry = _RecentDestinations.tryFromJson(value);
              if (entry != null) {
                entries[_accountKey(entry.siteUrl, entry.accountIdentity)] =
                    entry;
              }
            }
          }
        }
      }
    } catch (_) {}
    hydration.applyTo(entries);
    _entries
      ..clear()
      ..addAll(entries);
    _unreadable = false;
    if (identical(_hydration, hydration)) _hydration = null;
  }

  Future<void> save() {
    final pending = _hydration?.pending;
    if (pending != null) {
      return pending.future.then((_) => save());
    }
    if (_unreadable) return Future<void>.value();
    return _snapshots.save([
      for (final entry in _entries.values) _RecentDestinationsSnapshot(entry),
    ]);
  }

  Future<void> _persistSnapshot(
    List<_RecentDestinationsSnapshot> entries,
  ) async {
    final encoded = jsonEncode({
      'version': formatVersion,
      'entries': [for (final entry in entries) entry.toJson()],
    });
    try {
      if (!await _persistence.write(encoded)) {
        throw StateError('Could not persist recent destinations.');
      }
    } catch (_) {}
  }
}

(String, String) _accountKey(String siteUrl, String accountIdentity) =>
    (siteUrl, accountIdentity);

/// Records only interactions accepted after this read began. Each visit list
/// remains bounded like the published list; removals also exclude unseen disk
/// entries, without preventing a later explicit visit from re-adding a site.
final class _RecentDestinationsHydration {
  Completer<void>? pending;
  final Map<(String, String), _RecentDestinations> _visits = {};
  final Set<String> _forgottenSites = {};
  Set<String>? _retainedSites;

  bool remember(
    String siteUrl,
    String accountIdentity,
    ContentRoute route,
    _RecentKind kind,
  ) {
    final visits = _visits.putIfAbsent(
      _accountKey(siteUrl, accountIdentity),
      () => _RecentDestinations(siteUrl, accountIdentity),
    );
    return visits.remember(route, kind);
  }

  bool forgetSite(String siteUrl) {
    final changed = _forgottenSites.add(siteUrl);
    final held = _visits.length;
    _visits.removeWhere((_, entry) => entry.siteUrl == siteUrl);
    return changed || _visits.length != held;
  }

  bool retainSites(Set<String> sites) {
    final retained = _retainedSites;
    final previousCount = retained?.length;
    final heldVisits = _visits.length;
    if (retained == null) {
      _retainedSites = Set.of(sites);
    } else {
      retained.removeWhere((site) => !sites.contains(site));
    }
    _visits.removeWhere((_, entry) => !sites.contains(entry.siteUrl));
    return previousCount != _retainedSites!.length ||
        _visits.length != heldVisits;
  }

  void applyTo(Map<(String, String), _RecentDestinations> entries) {
    entries.removeWhere(
      (_, entry) =>
          _forgottenSites.contains(entry.siteUrl) ||
          (_retainedSites != null && !_retainedSites!.contains(entry.siteUrl)),
    );
    for (final MapEntry(:key, :value) in _visits.entries) {
      final entry = entries.putIfAbsent(
        key,
        () => _RecentDestinations(value.siteUrl, value.accountIdentity),
      );
      for (final kind in _RecentKind.values) {
        for (final route in value.routesFor(kind).reversed) {
          entry.remember(route, kind);
        }
      }
    }
  }
}

enum _RecentKind { category, channel, topic }

_RecentKind? _kindOf(ContentRoute route) => switch (route) {
  _ when route.destination is TopicDestination => _RecentKind.topic,
  _
      when route.destination is FeedDestination &&
          (route.id.startsWith('category-') ||
              route.id.startsWith('list-/c/')) =>
    _RecentKind.category,
  _
      when route.destination is ExtensionDestination &&
          RegExp(r'^chat-c-[1-9][0-9]*$').hasMatch(route.id) =>
    _RecentKind.channel,
  _ => null,
};

/// The sidebar opens a category as `category-12` and a link opens it as
/// `list-/c/slug/12`; both are one visit, so a category is keyed by its id.
String _identityOf(ContentRoute route) {
  if (route.id.startsWith('category-')) {
    final id = int.tryParse(route.id.substring('category-'.length));
    if (id != null) return 'category:$id';
  }
  if (route.id.startsWith('list-/c/')) {
    final segments = Uri.tryParse(route.feedPath ?? '')?.pathSegments;
    final last = segments == null || segments.isEmpty ? null : segments.last;
    final id = last != null && last.endsWith('.json')
        ? int.tryParse(last.substring(0, last.length - '.json'.length))
        : null;
    if (id != null && id > 0) return 'category:$id';
  }
  return route.id;
}

final class _RecentDestinations {
  _RecentDestinations(this.siteUrl, this.accountIdentity);

  final String siteUrl;
  final String accountIdentity;
  final List<ContentRoute> categories = [];
  final List<ContentRoute> channels = [];
  final List<ContentRoute> topics = [];

  List<ContentRoute> routesFor(_RecentKind kind) => switch (kind) {
    _RecentKind.category => categories,
    _RecentKind.channel => channels,
    _RecentKind.topic => topics,
  };

  bool remember(ContentRoute route, _RecentKind kind) {
    final routes = routesFor(kind);
    if (routes.isNotEmpty && routes.first == route) return false;
    final identity = _identityOf(route);
    routes.removeWhere((item) => _identityOf(item) == identity);
    routes.insert(0, route);
    if (routes.length > RecentDestinationsStore._limit) routes.removeLast();
    return true;
  }

  static _RecentDestinations? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final siteUrl = value['site_url'];
    final accountIdentity = value['account_identity'];
    if (siteUrl is! String ||
        siteUrl.isEmpty ||
        accountIdentity is! String ||
        accountIdentity.isEmpty) {
      return null;
    }
    final entry = _RecentDestinations(siteUrl, accountIdentity);
    void read(String name, List<ContentRoute> target, _RecentKind kind) {
      final values = value[name];
      if (values is! List) return;
      for (final item in values) {
        try {
          if (item is! Map) continue;
          final route = ContentRoute.fromJson(Map<String, dynamic>.from(item));
          final identity = _identityOf(route);
          if (_kindOf(route) != kind ||
              target.any((r) => _identityOf(r) == identity)) {
            continue;
          }
          target.add(route);
          if (target.length == RecentDestinationsStore._limit) break;
        } catch (_) {
          // One invalid visit must not discard the other visits.
        }
      }
    }

    read('categories', entry.categories, _RecentKind.category);
    read('channels', entry.channels, _RecentKind.channel);
    read('topics', entry.topics, _RecentKind.topic);
    return entry;
  }
}

final class _RecentDestinationsSnapshot {
  _RecentDestinationsSnapshot(_RecentDestinations entry)
    : siteUrl = entry.siteUrl,
      accountIdentity = entry.accountIdentity,
      categories = List.unmodifiable(entry.categories),
      channels = List.unmodifiable(entry.channels),
      topics = List.unmodifiable(entry.topics);

  final String siteUrl;
  final String accountIdentity;
  final List<ContentRoute> categories;
  final List<ContentRoute> channels;
  final List<ContentRoute> topics;

  Map<String, Object?> toJson() => {
    'site_url': siteUrl,
    'account_identity': accountIdentity,
    'categories': [for (final route in categories) route.toJson()],
    'channels': [for (final route in channels) route.toJson()],
    'topics': [for (final route in topics) route.toJson()],
  };
}
