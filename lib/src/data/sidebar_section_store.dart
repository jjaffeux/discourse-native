import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';

/// Remembers which sidebar sections a reader collapsed on each forum.
///
/// This is optional presentation state, so storage failures fall back to an
/// expanded section and never prevent the sidebar from being used.
final class SidebarSectionStore {
  const SidebarSectionStore();

  static const String _keyPrefix = 'discourse_native.sidebar_section_collapsed';

  Future<bool> read({
    required String siteUrl,
    required String sectionId,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_key(siteUrl, sectionId)) ?? false;
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
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_key(siteUrl, sectionId), collapsed);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'sidebarSections.writeCollapsed');
    }
  }

  static String _key(String siteUrl, String sectionId) =>
      '$_keyPrefix.${Uri.encodeComponent(siteUrl)}.'
      '${Uri.encodeComponent(sectionId)}';

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
