import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../models/discourse_instance.dart';
import '../plugin_api/discourse_model_codec.dart';
import 'coalescing_snapshot_writer.dart';
import 'http_transport.dart';
import 'store_diagnostics.dart';

abstract interface class InstancePersistence {
  Future<String?> read();

  Future<void> write(String value);
}

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
  late final CoalescingSnapshotWriter<String> _snapshots =
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
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'instances.decode');
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
          'url': _safeStoredBase(entry['url']),
        });
        if (seenUrls.add(instance.url)) instances.add(instance);
      } catch (error, stackTrace) {
        reportStorageFailure(error, stackTrace, 'instances.decodeEntry');
        // A stale or damaged entry must not erase the other connected sites.
      }
    }
    return instances;
  }

  static String _safeStoredBase(Object? value) {
    if (value is! String) {
      throw const FormatException('Invalid stored forum base URL.');
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(value);
    } on FormatException {
      // Uri.parse's exception retains its source. Do not put a damaged value
      // (which may contain credentials) into diagnostics.
      throw const FormatException('Invalid stored forum base URL.');
    }

    final safe = requireSafeHttpUrl(parsed);
    if (safe.hasQuery || safe.hasFragment) {
      throw UnsafeHttpTransportException(safe);
    }

    // `DiscourseInstance.url` is both identity and base URL, and a forum can
    // be served from a subfolder. Keep one stable spelling — no trailing
    // slash — even when an older entry persisted the root slash.
    final path = safe.path.replaceFirst(RegExp(r'/+$'), '');
    return '${safe.origin}$path';
  }

  Future<void> save(List<DiscourseInstance> instances) {
    final encoded = jsonEncode(instances.map(_models.storeInstance).toList());
    return _snapshots.save(encoded);
  }

  Future<void> _persistSnapshot(String encoded) async {
    try {
      await _persistence.write(encoded);
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'instances.save',
        severity: DiagnosticSeverity.error,
      );
      rethrow;
    }
  }
}
