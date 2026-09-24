import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_route.dart';
import 'coalescing_snapshot_writer.dart';
import 'store_diagnostics.dart';

abstract interface class RecentDestinationsPersistence {
  Future<String?> read();

  Future<bool> write(String value);
}

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

/// The Start page's last five visits of each kind, scoped to a forum account.
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
  late final CoalescingSnapshotWriter<String> _snapshots =
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: storageKey,
        writeSnapshot: _persistSnapshot,
      );
  final Map<String, _RecentDestinations> _entries = {};
  bool _unreadable = false;

  String _key(String siteUrl, String accountIdentity) =>
      '$siteUrl\u0000$accountIdentity';

  List<ContentRoute> categoriesFor(String siteUrl, String accountIdentity) =>
      List.unmodifiable(
        _entries[_key(siteUrl, accountIdentity)]?.categories ?? const [],
      );

  List<ContentRoute> channelsFor(String siteUrl, String accountIdentity) =>
      List.unmodifiable(
        _entries[_key(siteUrl, accountIdentity)]?.channels ?? const [],
      );

  List<ContentRoute> topicsFor(String siteUrl, String accountIdentity) =>
      List.unmodifiable(
        _entries[_key(siteUrl, accountIdentity)]?.topics ?? const [],
      );

  bool hasVisits(String siteUrl, String accountIdentity) {
    final entry = _entries[_key(siteUrl, accountIdentity)];
    return entry != null &&
        (entry.categories.isNotEmpty ||
            entry.channels.isNotEmpty ||
            entry.topics.isNotEmpty);
  }

  /// Returns whether the visible order or metadata changed.
  bool remember(String siteUrl, String accountIdentity, ContentRoute route) {
    final kind = _kindOf(route);
    if (kind == null) return false;
    final entry = _entries.putIfAbsent(
      _key(siteUrl, accountIdentity),
      () => _RecentDestinations(siteUrl, accountIdentity),
    );
    final routes = switch (kind) {
      _RecentKind.category => entry.categories,
      _RecentKind.channel => entry.channels,
      _RecentKind.topic => entry.topics,
    };
    if (routes.isNotEmpty && routes.first == route) return false;
    routes.removeWhere((item) => item.id == route.id);
    routes.insert(0, route);
    if (routes.length > _limit) routes.removeLast();
    return true;
  }

  Future<void> load() async {
    final String? raw;
    try {
      raw = await _snapshots.read(_persistence.read);
      _unreadable = false;
    } catch (error, stackTrace) {
      _unreadable = true;
      reportStorageFailure(error, stackTrace, 'recentDestinations.load');
      return;
    }
    _entries.clear();
    try {
      if (raw == null || raw.isEmpty) return;
      final document = jsonDecode(raw);
      if (document is! Map || document['version'] != formatVersion) return;
      final entries = document['entries'];
      if (entries is! List) return;
      for (final value in entries) {
        final entry = _RecentDestinations.tryFromJson(value);
        if (entry != null) {
          _entries[_key(entry.siteUrl, entry.accountIdentity)] = entry;
        }
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'recentDestinations.decode');
    }
  }

  Future<void> save() {
    if (_unreadable) return Future<void>.value();
    return _snapshots.save(
      jsonEncode({
        'version': formatVersion,
        'entries': [for (final entry in _entries.values) entry.toJson()],
      }),
    );
  }

  Future<void> _persistSnapshot(String encoded) async {
    try {
      if (!await _persistence.write(encoded)) {
        throw StateError('Could not persist recent destinations.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'recentDestinations.save');
    }
  }
}

enum _RecentKind { category, channel, topic }

_RecentKind? _kindOf(ContentRoute route) => switch (route) {
  _ when route.topicId != null => _RecentKind.topic,
  _ when route.id.startsWith('category-') || route.id.startsWith('list-/c/') =>
    _RecentKind.category,
  _ when RegExp(r'^chat-channel-[1-9][0-9]*$').hasMatch(route.id) =>
    _RecentKind.channel,
  _ => null,
};

final class _RecentDestinations {
  _RecentDestinations(this.siteUrl, this.accountIdentity);

  final String siteUrl;
  final String accountIdentity;
  final List<ContentRoute> categories = [];
  final List<ContentRoute> channels = [];
  final List<ContentRoute> topics = [];

  Map<String, Object?> toJson() => {
    'site_url': siteUrl,
    'account_identity': accountIdentity,
    'categories': [for (final route in categories) route.toJson()],
    'channels': [for (final route in channels) route.toJson()],
    'topics': [for (final route in topics) route.toJson()],
  };

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
          if (_kindOf(route) != kind || target.any((r) => r.id == route.id)) {
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
