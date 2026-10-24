import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/discourse_instance.dart';
import '../plugin_api/discourse_model_codec.dart';
import 'coalescing_snapshot_writer.dart';
import 'preference_storage_scope.dart';

import 'stored_forum_base.dart';

abstract interface class InstancePersistence {
  Future<String?> read();

  Future<void> write(String value);
}

@PreferenceStorage.document(
  'InstanceStore.save commits the durable forum rail and removal boundary.',
)
final class SharedPreferencesInstancePersistence
    implements InstancePersistence {
  const SharedPreferencesInstancePersistence();

  static const String storageKey = 'discourse_native.instances';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(storageKey);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(storageKey, value);
    if (!saved) throw StateError('Could not persist connected sites.');
  }
}

class InstanceStore {
  InstanceStore({InstancePersistence? persistence, DiscourseModelCodec? models})
    : _persistence =
          persistence ?? const SharedPreferencesInstancePersistence(),
      _models = models ?? const DiscourseModelCodec.core();

  final InstancePersistence _persistence;
  final DiscourseModelCodec _models;
  Map<DiscourseInstance, String> _encodedInstances = Map.identity();
  late final CoalescingSnapshotWriter<List<DiscourseInstance>> _snapshots =
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: SharedPreferencesInstancePersistence.storageKey,
        writeSnapshot: _persistSnapshot,
      );

  Future<List<DiscourseInstance>> load() async {
    final raw = await _snapshots.read(_persistence.read);
    if (raw == null || raw.isEmpty) return const [];

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      return const [];
    }
    if (decoded is! List<dynamic>) return const [];

    final instances = <DiscourseInstance>[];
    final seenUrls = <String>{};
    for (final entry in decoded) {
      try {
        if (entry is! Map<String, dynamic>) continue;
        // Persistence is an untrusted boundary: old or damaged preferences
        // must not revive a plaintext remote endpoint or leave a relative URL
        // that crashes a later `DiscourseInstance.host` read during startup.
        final instance = _models.storedInstance({
          ...entry,
          'url': requireStoredForumBase(entry['url']),
        });
        if (seenUrls.add(instance.url)) instances.add(instance);
      } catch (_) {
        // A stale or damaged entry must not erase the other connected sites.
      }
    }
    return instances;
  }

  Future<void> save(List<DiscourseInstance> instances) {
    return _snapshots.save(List<DiscourseInstance>.unmodifiable(instances));
  }

  Future<void> _persistSnapshot(List<DiscourseInstance> instances) async {
    // Instances are immutable, but equality compares URLs rather than revisions.
    // Keep encodings with this store's codec and discard removed identities even
    // if conversion or persistence of the replacement snapshot fails.
    final retained = Map<DiscourseInstance, String>.identity();
    for (final instance in instances) {
      if (_encodedInstances[instance] case final encoded?) {
        retained[instance] = encoded;
      }
    }
    _encodedInstances = retained;

    final entries = [
      for (final instance in instances)
        _encodedInstances.putIfAbsent(
          instance,
          () => jsonEncode(_models.storeInstance(instance)),
        ),
    ];
    await _persistence.write('[${entries.join(',')}]');
  }
}
