import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/discourse_instance.dart';
import 'coalescing_snapshot_writer.dart';
import 'store_diagnostics.dart';

abstract interface class AggregatePreferencesPersistence {
  Future<String?> read();

  Future<bool> write(String value);
}

final class AggregatePreferences {
  AggregatePreferences({
    Set<String>? excludedForums,
    Map<String, String>? queries,
  }) : excludedForums = Set.unmodifiable(excludedForums ?? const {}),
       queries = Map.unmodifiable(queries ?? const {});

  final Set<String> excludedForums;
  final Map<String, String> queries;
}

final class SharedPreferencesAggregatePreferencesPersistence
    implements AggregatePreferencesPersistence {
  const SharedPreferencesAggregatePreferencesPersistence();

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance())
      .getString(AggregatePreferencesStore.storageKey);

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        AggregatePreferencesStore.storageKey,
        value,
      );
}

final class MemoryAggregatePreferencesPersistence
    implements AggregatePreferencesPersistence {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    this.value = value;
    return true;
  }
}

/// Versioned app-wide configuration for the cross-forum Aggregate feed.
///
/// Exclusions are persisted instead of inclusions so a newly connected forum
/// participates by default. A query is stored only when it is non-empty; an
/// included forum without one asks Discourse for its default topic filter.
/// Origins are already owned by [DiscourseInstance], and malformed or stale
/// entries are pruned by the controller when it next saves.
final class AggregatePreferencesStore {
  AggregatePreferencesStore({AggregatePreferencesPersistence? persistence})
    : _persistence =
          persistence ??
          const SharedPreferencesAggregatePreferencesPersistence();

  AggregatePreferencesStore.memory()
    : _persistence = MemoryAggregatePreferencesPersistence();

  static const storageKey = 'discourse_native.aggregate_preferences';
  static const formatVersion = 2;
  static const maximumQueryLength = 2048;

  final AggregatePreferencesPersistence _persistence;
  late final CoalescingSnapshotWriter<String> _snapshots =
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: storageKey,
        writeSnapshot: _persist,
      );

  Future<AggregatePreferences> load() async {
    try {
      final raw = await _snapshots.read(_persistence.read);
      if (raw == null || raw.isEmpty) return AggregatePreferences();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return AggregatePreferences();
      final version = decoded['version'];
      if (version != 1 && version != formatVersion) {
        return AggregatePreferences();
      }
      final excluded = decoded['excluded_forums'];
      final queries = decoded['queries'];
      return AggregatePreferences(
        excludedForums: {
          if (excluded is List)
            for (final value in excluded)
              if (value is String && _isOrigin(value)) value,
        },
        queries: {
          if (version == formatVersion && queries is Map)
            for (final MapEntry(key: siteUrl, value: query) in queries.entries)
              if (siteUrl is String &&
                  query is String &&
                  _isOrigin(siteUrl) &&
                  _normalizeQuery(query).isNotEmpty)
                siteUrl: _normalizeQuery(query),
        },
      );
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aggregatePreferences.load');
      return AggregatePreferences();
    }
  }

  Future<void> save({
    required Set<String> excludedForums,
    required Map<String, String> queries,
  }) {
    final encoded = jsonEncode({
      'version': formatVersion,
      'excluded_forums': excludedForums.toList()..sort(),
      'queries': Map.fromEntries(
        [
          for (final MapEntry(:key, :value) in queries.entries)
            if (_isOrigin(key) && _normalizeQuery(value).isNotEmpty)
              MapEntry(key, _normalizeQuery(value)),
        ]..sort((left, right) => left.key.compareTo(right.key)),
      ),
    });
    return _snapshots.save(encoded);
  }

  Future<void> _persist(String encoded) async {
    try {
      if (!await _persistence.write(encoded)) {
        throw StateError('Could not persist Aggregate forum preferences.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aggregatePreferences.save');
    }
  }

  static bool _isOrigin(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static String _normalizeQuery(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= maximumQueryLength) return trimmed;
    return trimmed.substring(0, maximumQueryLength);
  }
}
