import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/discourse_instance.dart';
import 'coalescing_snapshot_writer.dart';
import 'store_diagnostics.dart';

abstract interface class AggregatePreferencesPersistence {
  Future<String?> read();

  Future<bool> write(String value);
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

/// Versioned app-wide selection for the cross-forum Aggregate feed.
///
/// Exclusions are persisted instead of inclusions so a newly connected forum
/// participates by default. The values are canonical site origins already
/// owned by [DiscourseInstance]; malformed or stale entries are harmless and
/// are pruned by the controller when it next saves.
final class AggregatePreferencesStore {
  AggregatePreferencesStore({AggregatePreferencesPersistence? persistence})
    : _persistence =
          persistence ??
          const SharedPreferencesAggregatePreferencesPersistence();

  AggregatePreferencesStore.memory()
    : _persistence = MemoryAggregatePreferencesPersistence();

  static const storageKey = 'discourse_native.aggregate_preferences';
  static const formatVersion = 1;

  final AggregatePreferencesPersistence _persistence;
  late final CoalescingSnapshotWriter<String> _snapshots =
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: storageKey,
        writeSnapshot: _persist,
      );

  Future<Set<String>> load() async {
    try {
      final raw = await _snapshots.read(_persistence.read);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != formatVersion) {
        return const {};
      }
      final excluded = decoded['excluded_forums'];
      if (excluded is! List) return const {};
      return {
        for (final value in excluded)
          if (value is String && _isOrigin(value)) value,
      };
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'aggregatePreferences.load');
      return const {};
    }
  }

  Future<void> save(Set<String> excludedForums) {
    final encoded = jsonEncode({
      'version': formatVersion,
      'excluded_forums': excludedForums.toList()..sort(),
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
}
