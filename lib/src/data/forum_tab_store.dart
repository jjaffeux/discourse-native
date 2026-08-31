import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_workspace.dart';
import 'coalescing_snapshot_writer.dart';
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
  final ForumTabPersistence _persistence;
  late final CoalescingSnapshotWriter<String> _snapshots =
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: storageKey,
        writeSnapshot: _persistSnapshot,
      );

  /// Distinguishes an intact but unreadable document from an absent one so the
  /// fallback workspace cannot overwrite unknown stored tabs. A successful
  /// later [load] clears it.
  bool _unreadable = false;

  Future<List<ForumWorkspace>> load() async {
    final String? raw;
    try {
      raw = await _snapshots.read(_persistence.read);
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
    final encoded = jsonEncode({
      'version': formatVersion,
      'workspaces': [for (final workspace in workspaces) workspace.toJson()],
    });
    return _snapshots.save(encoded);
  }

  Future<void> _persistSnapshot(String encoded) async {
    try {
      final saved = await _persistence.write(encoded);
      if (!saved) throw StateError('Could not persist forum tabs.');
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'forumTabs.save');
    }
  }
}
