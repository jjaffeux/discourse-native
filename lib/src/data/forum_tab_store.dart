import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../models/forum_workspace.dart';

abstract interface class ForumTabPersistence {
  Future<String?> read();

  Future<bool> write(String value);
}

final class SharedPreferencesForumTabPersistence
    implements ForumTabPersistence {
  const SharedPreferencesForumTabPersistence();

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance())
      .getString(ForumTabStore.storageKey);

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        ForumTabStore.storageKey,
        value,
      );
}

final class MemoryForumTabPersistence implements ForumTabPersistence {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    this.value = value;
    return true;
  }
}

/// Versioned persistence for local, forum-scoped workspaces.
///
/// This is presentation state: a storage failure degrades to fresh Topics tabs
/// and must never stop the shell from opening.
class ForumTabStore {
  ForumTabStore({ForumTabPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesForumTabPersistence();

  ForumTabStore.memory() : _persistence = MemoryForumTabPersistence();

  static const String storageKey = 'discourse_native.forum_tabs';
  static const int formatVersion = 1;

  final ForumTabPersistence _persistence;
  String? _pendingSave;
  Completer<void>? _pendingResult;
  bool _saving = false;

  Future<List<ForumWorkspace>> load() async {
    try {
      final raw = await _persistence.read();
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != formatVersion) {
        return const [];
      }
      final entries = decoded['workspaces'];
      if (entries is! List) return const [];

      final workspaces = <ForumWorkspace>[];
      final seenSites = <String>{};
      for (final entry in entries) {
        final workspace = ForumWorkspace.tryFromJson(entry);
        if (workspace != null && seenSites.add(workspace.siteUrl)) {
          workspaces.add(workspace);
        }
      }
      return workspaces;
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'forumTabs.load');
      return const [];
    }
  }

  Future<void> save(Iterable<ForumWorkspace> workspaces) {
    _pendingSave = jsonEncode({
      'version': formatVersion,
      'workspaces': [for (final workspace in workspaces) workspace.toJson()],
    });
    final result = _pendingResult ??= Completer<void>();
    if (!_saving) {
      _saving = true;
      unawaited(_drain());
    }
    return result.future;
  }

  Future<void> _drain() async {
    try {
      while (_pendingSave != null) {
        final encoded = _pendingSave!;
        final result = _pendingResult!;
        _pendingSave = null;
        _pendingResult = null;
        try {
          final saved = await _persistence.write(encoded);
          if (!saved) throw StateError('Could not persist forum tabs.');
        } catch (error, stackTrace) {
          _report(error, stackTrace, 'forumTabs.save');
        }
        if (!result.isCompleted) result.complete();
      }
    } finally {
      _saving = false;
      if (_pendingSave != null) {
        _saving = true;
        unawaited(_drain());
      }
    }
  }

  static void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'storage',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }
}
