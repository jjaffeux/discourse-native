import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';

/// Per-forum sidebar collapse-state persistence.
///
/// Site and section key encoding is an adapter detail. The store only sees the
/// optional collapse choice and the platform's durability result.
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

/// Remembers which sidebar sections a reader collapsed on each forum.
///
/// This is optional presentation state, so storage failures fall back to an
/// expanded section and never prevent the sidebar from being used.
final class SidebarSectionStore {
  const SidebarSectionStore({SidebarSectionPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesSidebarSectionPersistence();

  final SidebarSectionPersistence _persistence;

  Future<bool> read({
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
      _report(error, stackTrace, 'sidebarSections.readCollapsed');
      return false;
    }
  }

  Future<void> write({
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
      _report(error, stackTrace, 'sidebarSections.writeCollapsed');
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
