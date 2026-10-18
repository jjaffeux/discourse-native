import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_route.dart';
import '../models/destination_bookmark.dart';
import 'coalescing_snapshot_writer.dart';
import 'preference_storage_scope.dart';
import 'serial_operation_queue.dart';

abstract interface class DestinationBookmarksPersistence {
  Future<String?> read();
  Future<bool> write(String value);
}

@PreferenceStorage.document(
  'DestinationBookmarksStore.forgetSite removes site entries from its aggregate document.',
)
final class SharedPreferencesDestinationBookmarksPersistence
    implements DestinationBookmarksPersistence {
  const SharedPreferencesDestinationBookmarksPersistence();

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance())
      .getString(DestinationBookmarksStore.storageKey);

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        DestinationBookmarksStore.storageKey,
        value,
      );
}

final class MemoryDestinationBookmarksPersistence
    implements DestinationBookmarksPersistence {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    this.value = value;
    return true;
  }
}

/// Mutations publish only after their complete account-scoped snapshot is durable.
final class DestinationBookmarksStore {
  DestinationBookmarksStore({DestinationBookmarksPersistence? persistence})
    : _persistence =
          persistence ??
          const SharedPreferencesDestinationBookmarksPersistence();

  DestinationBookmarksStore.memory()
    : _persistence = MemoryDestinationBookmarksPersistence();

  static const storageKey = 'discourse_native.destination_bookmarks';
  final DestinationBookmarksPersistence _persistence;
  final _operations = SerialOperationQueue();
  final Map<(String, String), List<DestinationBookmark>> _entries = {};
  bool _readable = false;
  late final _snapshots = CoalescingSnapshotWriter<String>(
    owner: _persistence,
    key: storageKey,
    writeSnapshot: (encoded) async {
      if (!await _persistence.write(encoded)) {
        throw StateError('Could not persist destination bookmarks.');
      }
    },
  );

  List<DestinationBookmark> entriesFor(
    String siteUrl,
    String accountIdentity,
  ) => List.unmodifiable(_entries[(siteUrl, accountIdentity)] ?? const []);

  Future<void> load() async {
    _readable = false;
    final raw = await _snapshots.read(_persistence.read);
    final entries = <(String, String), List<DestinationBookmark>>{};
    if (raw != null && raw.isNotEmpty) {
      final document = jsonDecode(raw);
      if (document is! Map ||
          document['version'] != 1 ||
          document['entries'] is! List) {
        throw const FormatException('Invalid destination bookmarks.');
      }
      for (final value in document['entries'] as List) {
        if (value is! Map ||
            value['site_url'] is! String ||
            value['account_identity'] is! String ||
            value['routes'] is! List) {
          continue;
        }
        final site = value['site_url'] as String;
        final account = value['account_identity'] as String;
        if (site.isEmpty || account.isEmpty) continue;
        final routes = entries.putIfAbsent((site, account), () => []);
        for (final json in value['routes'] as List) {
          try {
            if (json is! Map) continue;
            final bookmark = DestinationBookmark.fromRoute(
              ContentRoute.fromJson(Map<String, dynamic>.from(json)),
            );
            if (bookmark != null &&
                !routes.any((entry) => entry.identity == bookmark.identity)) {
              routes.add(bookmark);
            }
          } on FormatException {
            continue;
          } on TypeError {
            continue;
          }
        }
      }
    }
    _entries
      ..clear()
      ..addAll(entries);
    _readable = true;
  }

  Future<bool> set(
    String siteUrl,
    String accountIdentity,
    DestinationBookmark bookmark, {
    required bool bookmarked,
    bool Function()? isCurrent,
  }) => _operations.run(
    owner: this,
    key: storageKey,
    operation: () async {
      if (!_readable) {
        throw StateError('Destination bookmarks could not be loaded.');
      }
      if (isCurrent?.call() == false) return false;
      final key = (siteUrl, accountIdentity);
      final held = _entries[key] ?? const <DestinationBookmark>[];
      if (held.any((entry) => entry.identity == bookmark.identity) ==
          bookmarked) {
        return false;
      }
      final next = {
        ..._entries,
        key: [
          if (bookmarked) bookmark,
          ...held.where((entry) => entry.identity != bookmark.identity),
        ],
      };
      await _snapshots.save(_encode(next));
      _entries
        ..clear()
        ..addAll(next);
      return true;
    },
  );

  Future<void> forgetSite(String siteUrl) => _operations.run(
    owner: this,
    key: storageKey,
    operation: () async {
      if (!_readable) {
        throw StateError('Destination bookmarks could not be loaded.');
      }
      final next = {..._entries}..removeWhere((key, _) => key.$1 == siteUrl);
      if (next.length == _entries.length) return;
      await _snapshots.save(_encode(next));
      _entries
        ..clear()
        ..addAll(next);
    },
  );

  Future<void> flush() =>
      _operations.run(owner: this, key: storageKey, operation: () async {});

  String _encode(Map<(String, String), List<DestinationBookmark>> entries) =>
      jsonEncode({
        'version': 1,
        'entries': [
          for (final entry in entries.entries)
            {
              'site_url': entry.key.$1,
              'account_identity': entry.key.$2,
              'routes': [
                for (final bookmark in entry.value) bookmark.route.toJson(),
              ],
            },
        ],
      });
}
