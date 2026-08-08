import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../models/discourse_instance.dart';

abstract interface class InstancePersistence {
  Future<String?> read();

  Future<void> write(String value);
}

final class SharedPreferencesInstancePersistence
    implements InstancePersistence {
  static const String _key = 'discourse_native.instances';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key, value);
    if (!saved) throw StateError('Could not persist connected sites.');
  }
}

/// Persists the connected sites between launches.
///
/// Site metadata and the connected account's public profile live here. API
/// keys and other credentials live in the keychain.
class InstanceStore {
  InstanceStore({InstancePersistence? persistence})
    : _persistence = persistence ?? SharedPreferencesInstancePersistence();

  final InstancePersistence _persistence;
  String? _pendingSave;
  Completer<void>? _pendingSaveResult;
  bool _saving = false;

  Future<List<DiscourseInstance>> load() async {
    final raw = await _persistence.read();
    if (raw == null || raw.isEmpty) return const [];

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'instances.decode');
      return const [];
    }
    if (decoded is! List<dynamic>) return const [];

    final instances = <DiscourseInstance>[];
    final seenUrls = <String>{};
    for (final entry in decoded) {
      try {
        if (entry is! Map<String, dynamic>) continue;
        final instance = DiscourseInstance.fromJson(entry);
        if (seenUrls.add(instance.url)) instances.add(instance);
      } catch (error, stackTrace) {
        _report(error, stackTrace, 'instances.decodeEntry');
        // A stale or damaged entry must not erase the other connected sites.
      }
    }
    return instances;
  }

  static void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    DiagnosticSeverity severity = DiagnosticSeverity.warning,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'storage',
      severity: severity,
      handled: true,
      degraded: true,
    );
  }

  Future<void> save(List<DiscourseInstance> instances) {
    _pendingSave = jsonEncode(instances.map((i) => i.toJson()).toList());
    // Every caller waiting behind the active write is waiting for the same
    // thing: the newest queued snapshot. Sharing its completion keeps a burst
    // of rail updates at one retained future rather than one per update.
    final result = _pendingSaveResult ??= Completer<void>();
    if (!_saving) {
      _saving = true;
      unawaited(_drainSaves());
    }
    return result.future;
  }

  Future<void> _drainSaves() async {
    try {
      while (_pendingSave != null) {
        final encoded = _pendingSave!;
        final result = _pendingSaveResult!;
        _pendingSave = null;
        _pendingSaveResult = null;

        try {
          await _persistence.write(encoded);
        } catch (error, stackTrace) {
          _report(
            error,
            stackTrace,
            'instances.save',
            severity: DiagnosticSeverity.error,
          );
          result.completeError(error, stackTrace);
          continue;
        }

        result.complete();
      }
    } finally {
      _saving = false;
      if (_pendingSave != null) {
        _saving = true;
        unawaited(_drainSaves());
      }
    }
  }
}
