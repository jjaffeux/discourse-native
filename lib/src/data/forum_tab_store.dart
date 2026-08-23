import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_workspace.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

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
/// and must never stop the shell from opening. What it must also never do is
/// save those fresh tabs over the ones it could not read — see [_unreadable].
class ForumTabStore {
  ForumTabStore({ForumTabPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesForumTabPersistence();

  ForumTabStore.memory() : _persistence = MemoryForumTabPersistence();

  static const String storageKey = 'discourse_native.forum_tabs';
  static const int formatVersion = 1;
  static final SerialOperationQueue _operations = SerialOperationQueue();

  final ForumTabPersistence _persistence;
  String? _pendingSave;
  Completer<void>? _pendingResult;
  bool _saving = false;

  /// Whether the stored document could not be read.
  ///
  /// A read that fails leaves the document intact and unknown, which is not
  /// the same as there being none. The shell cannot tell the two apart — both
  /// answer with no workspaces, and it opens fresh Topics tabs either way —
  /// and the first thing it does with a tab is save. So the distinction is
  /// kept here, and it is what stops one unreadable launch from replacing
  /// every forum's tabs and back stacks with what this session happened to
  /// fall back to. A later [load] that succeeds clears it.
  bool _unreadable = false;

  Future<List<ForumWorkspace>> load() async {
    final String? raw;
    try {
      raw = await _operations.run<String?>(
        owner: _persistence,
        key: storageKey,
        operation: _persistence.read,
      );
      _unreadable = false;
    } catch (error, stackTrace) {
      _unreadable = true;
      reportStorageFailure(error, stackTrace, 'forumTabs.load');
      return const [];
    }

    // Past here the document was read. Whatever it holds is either usable or
    // already lost, so a save over it is the repair rather than the damage.
    try {
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
      reportStorageFailure(error, stackTrace, 'forumTabs.decode');
      return const [];
    }
  }

  Future<void> save(Iterable<ForumWorkspace> workspaces) {
    if (_unreadable) return Future<void>.value();
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
          // The drain coalesces changes made through this store. The shared
          // queue additionally orders stores across shell replacement, where
          // an older in-flight snapshot must not finish after the new shell's
          // latest one and overwrite it.
          final saved = await _operations.run<bool>(
            owner: _persistence,
            key: storageKey,
            operation: () => _persistence.write(encoded),
          );
          if (!saved) throw StateError('Could not persist forum tabs.');
        } catch (error, stackTrace) {
          reportStorageFailure(error, stackTrace, 'forumTabs.save');
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
}
