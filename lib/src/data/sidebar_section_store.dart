import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class SidebarSectionPersistence {
  Future<bool?> readCollapsed({
    required String siteUrl,
    required String sectionId,
  });

  Future<bool> writeCollapsed({
    required String siteUrl,
    required String sectionId,
    required bool collapsed,
  });
}

final class SharedPreferencesSidebarSectionPersistence
    implements SidebarSectionPersistence {
  const SharedPreferencesSidebarSectionPersistence();

  static const String _keyPrefix = 'discourse_native.sidebar_section_collapsed';

  @override
  Future<bool?> readCollapsed({
    required String siteUrl,
    required String sectionId,
  }) async =>
      (await SharedPreferences.getInstance()).getBool(_key(siteUrl, sectionId));

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required String sectionId,
    required bool collapsed,
  }) async => (await SharedPreferences.getInstance()).setBool(
    _key(siteUrl, sectionId),
    collapsed,
  );

  static String _key(String siteUrl, String sectionId) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}.'
      '${Uri.encodeComponent(sectionId)}';
}

final class SidebarSectionStore {
  const SidebarSectionStore({SidebarSectionPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesSidebarSectionPersistence();

  final SidebarSectionPersistence _persistence;
  static final SerialOperationQueue _operations = SerialOperationQueue();

  Future<bool> read({required String siteUrl, required String sectionId}) =>
      _operations.run(
        owner: _persistence,
        key: (siteUrl, sectionId),
        operation: () => _read(siteUrl: siteUrl, sectionId: sectionId),
      );

  Future<bool> _read({
    required String siteUrl,
    required String sectionId,
  }) async {
    try {
      return await _persistence.readCollapsed(
            siteUrl: siteUrl,
            sectionId: sectionId,
          ) ??
          false;
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'sidebarSections.readCollapsed');
      return false;
    }
  }

  Future<void> write({
    required String siteUrl,
    required String sectionId,
    required bool collapsed,
  }) async {
    await _operations.run<void>(
      owner: _persistence,
      key: (siteUrl, sectionId),
      operation: () => _persist(
        siteUrl: siteUrl,
        sectionId: sectionId,
        collapsed: collapsed,
      ),
    );
  }

  Future<void> _persist({
    required String siteUrl,
    required String sectionId,
    required bool collapsed,
  }) async {
    try {
      final saved = await _persistence.writeCollapsed(
        siteUrl: siteUrl,
        sectionId: sectionId,
        collapsed: collapsed,
      );
      if (!saved) throw StateError('Could not persist sidebar section state.');
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'sidebarSections.writeCollapsed');
    }
  }
}
