import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_workspace.dart';
import 'coalescing_snapshot_writer.dart';
import 'preference_storage_scope.dart';

abstract interface class ForumTabPersistence {
  Future<String?> read();

  Future<bool> write(String value);
}

@PreferenceStorage.document(
  'Shell workspace snapshots omit forums after durable removal.',
)
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
  static final _reads = Expando<Future<String?>>();
  late final CoalescingSnapshotWriter<ForumTabSnapshot> _snapshots =
      CoalescingSnapshotWriter(
        owner: _persistence,
        key: storageKey,
        writeSnapshot: _persistSnapshot,
      );

  /// Distinguishes an intact but unreadable document from an absent one so the
  /// fallback workspace cannot overwrite unknown stored tabs. A successful
  /// later [load] clears it.
  bool _unreadable = false;

  Future<ForumTabSnapshot> load() async {
    final String? raw;
    try {
      raw = await _readShared();
      _unreadable = false;
    } catch (error) {
      _unreadable = true;

      return const ForumTabSnapshot.empty();
    }

    try {
      if (raw == null || raw.isEmpty) return const ForumTabSnapshot.empty();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ForumTabSnapshot.empty();
      final version = decoded['version'];
      if (version != formatVersion) {
        _unreadable = version is int && version > formatVersion;
        return const ForumTabSnapshot.empty();
      }
      final selected = decoded['selectedSiteUrl'];
      final selectedSiteUrl = selected is String && selected.isNotEmpty
          ? selected
          : null;
      final entries = decoded['workspaces'];
      if (entries is! List) {
        return ForumTabSnapshot(const [], selectedSiteUrl: selectedSiteUrl);
      }

      final workspaces = <ForumWorkspace>[];
      final seenSites = <String>{};
      for (final entry in entries) {
        final workspace = ForumWorkspace.tryFromJson(entry);
        if (workspace != null && seenSites.add(workspace.siteUrl)) {
          workspaces.add(workspace);
        }
      }
      return ForumTabSnapshot(workspaces, selectedSiteUrl: selectedSiteUrl);
    } catch (error) {
      return const ForumTabSnapshot.empty();
    }
  }

  Future<String?> _readShared() {
    if (_reads[_persistence] case final pending?) return pending;
    late final Future<String?> read;
    read = _snapshots.read(_persistence.read).whenComplete(() {
      if (identical(_reads[_persistence], read)) _reads[_persistence] = null;
    });
    return _reads[_persistence] = read;
  }

  /// Completes once these workspaces, or newer ones saved before their write
  /// started, are written, or once that write's failure has been reported.
  Future<void> save(
    Iterable<ForumWorkspace> workspaces, {
    String? selectedSiteUrl,
  }) {
    if (_unreadable) return Future<void>.value();
    _reads[_persistence] = null;
    // Workspaces are immutable, so copying the list captures the snapshot.
    // It is encoded only when its write starts: navigation and scrolling save
    // far more often than a write completes, and a snapshot superseded before
    // then is never encoded at all.
    return _snapshots.save(
      ForumTabSnapshot(workspaces, selectedSiteUrl: selectedSiteUrl),
    );
  }

  /// Byte for byte the `jsonEncode` of the versioned document holding each
  /// workspace's `toJson()`, assembled from the encodings its unchanged tabs
  /// and history entries already hold.
  static String encode(
    Iterable<ForumWorkspace> workspaces, {
    String? selectedSiteUrl,
  }) {
    final out = StringBuffer('{"version":$formatVersion');
    if (selectedSiteUrl != null) {
      out.write(',"selectedSiteUrl":${jsonEncode(selectedSiteUrl)}');
    }
    out.write(',"workspaces":[');
    var first = true;
    for (final workspace in workspaces) {
      if (!first) out.write(',');
      first = false;
      workspace.writeJson(out);
    }
    out.write(']}');
    return out.toString();
  }

  Future<void> _persistSnapshot(ForumTabSnapshot snapshot) async {
    try {
      final saved = await _persistence.write(
        encode(snapshot.workspaces, selectedSiteUrl: snapshot.selectedSiteUrl),
      );
      if (!saved) throw StateError('Could not persist forum tabs.');
    } catch (_) {}
  }
}

/// One workspace document, including the selection captured with its tabs.
final class ForumTabSnapshot {
  ForumTabSnapshot(Iterable<ForumWorkspace> workspaces, {this.selectedSiteUrl})
    : workspaces = List.unmodifiable(workspaces);

  const ForumTabSnapshot.empty()
    : workspaces = const [],
      selectedSiteUrl = null;

  final List<ForumWorkspace> workspaces;
  final String? selectedSiteUrl;
}
