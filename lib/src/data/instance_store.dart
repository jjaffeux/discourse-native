import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../models/discourse_instance.dart';
import 'http_transport.dart';
import 'serial_operation_queue.dart';

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

/// Persists the connected sites between launches.
///
/// Site metadata and the connected account's public profile live here. API
/// keys and other credentials live in platform-private storage.
class InstanceStore {
  InstanceStore({InstancePersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesInstancePersistence();

  static final SerialOperationQueue _operations = SerialOperationQueue();

  final InstancePersistence _persistence;
  String? _pendingSave;
  Completer<void>? _pendingSaveResult;
  bool _saving = false;

  Future<List<DiscourseInstance>> load() async {
    final raw = await _operations.run<String?>(
      owner: _persistence,
      key: SharedPreferencesInstancePersistence.storageKey,
      operation: _persistence.read,
    );
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
        // Persistence is an untrusted boundary: old or damaged preferences
        // must not revive a plaintext remote endpoint or leave a relative URL
        // that crashes a later `DiscourseInstance.host` read during startup.
        final instance = DiscourseInstance.fromJson({
          ...entry,
          'url': _safeStoredOrigin(entry['url']),
        });
        if (seenUrls.add(instance.url)) instances.add(instance);
      } catch (error, stackTrace) {
        _report(error, stackTrace, 'instances.decodeEntry');
        // A stale or damaged entry must not erase the other connected sites.
      }
    }
    return instances;
  }

  static String _safeStoredOrigin(Object? value) {
    if (value is! String) {
      throw const FormatException('Invalid stored forum origin.');
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(value);
    } on FormatException {
      // Uri.parse's exception retains its source. Do not put a damaged value
      // (which may contain credentials) into diagnostics.
      throw const FormatException('Invalid stored forum origin.');
    }

    final safe = requireSafeHttpUrl(parsed);
    if ((safe.path.isNotEmpty && safe.path != '/') ||
        safe.hasQuery ||
        safe.hasFragment) {
      throw UnsafeHttpTransportException(safe);
    }

    // `DiscourseInstance.url` is both identity and base URL. Keep one stable
    // spelling even when an older entry persisted the origin's root slash.
    return safe.origin;
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
          // Coalescing above owns this store's burst. The shared queue also
          // covers app dependency replacement: an older store's in-flight
          // rail must never complete after its replacement's newer snapshot.
          await _operations.run<void>(
            owner: _persistence,
            key: SharedPreferencesInstancePersistence.storageKey,
            operation: () => _persistence.write(encoded),
          );
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
