import 'package:shared_preferences/shared_preferences.dart';

import 'preference_snapshots.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class TopicSidebarPersistence {
  Future<bool?> readCollapsed({required String siteUrl});

  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  });
}

final class SharedPreferencesTopicSidebarPersistence
    implements TopicSidebarPersistence {
  const SharedPreferencesTopicSidebarPersistence();

  // Keep the earlier recommendations-panel key: that panel became this
  // sidebar, so an existing reader's visibility choice still means the same
  // thing after the surface grows topic properties and actions.
  static const String _keyPrefix =
      'discourse_native.topic_recommendations_panel_collapsed';

  @override
  Future<bool?> readCollapsed({required String siteUrl}) async =>
      (await SharedPreferences.getInstance()).getBool(_key(siteUrl));

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  }) async =>
      (await SharedPreferences.getInstance()).setBool(_key(siteUrl), collapsed);

  static String _key(String siteUrl) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}';
}

final class TopicSidebarStore {
  TopicSidebarStore({TopicSidebarPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesTopicSidebarPersistence();

  final TopicSidebarPersistence _persistence;
  final _snapshots = PreferenceSnapshots<String, bool>();
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  bool? collapsedFor(String siteUrl) => _snapshots.peek(siteUrl);

  Future<bool> ensure({required String siteUrl}) =>
      _snapshots.ensure(siteUrl, () => read(siteUrl: siteUrl));

  Future<bool> read({required String siteUrl}) => _operations.read(
    owner: _persistence,
    key: siteUrl,
    operation: () => _read(siteUrl),
  );

  Future<bool> _read(String siteUrl) async {
    try {
      return await _persistence.readCollapsed(siteUrl: siteUrl) ?? false;
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'topicSidebar.readCollapsed');
      return false;
    }
  }

  Future<void> write({required String siteUrl, required bool collapsed}) {
    _snapshots.remember(siteUrl, collapsed);
    return _operations.write<void>(
      owner: _persistence,
      key: siteUrl,
      operation: () => _persist(siteUrl: siteUrl, collapsed: collapsed),
    );
  }

  Future<void> _persist({
    required String siteUrl,
    required bool collapsed,
  }) async {
    try {
      final saved = await _persistence.writeCollapsed(
        siteUrl: siteUrl,
        collapsed: collapsed,
      );
      if (!saved) {
        throw StateError('Could not persist topic sidebar state.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'topicSidebar.writeCollapsed');
    }
  }
}
