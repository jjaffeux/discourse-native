import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';

/// Persists the preferred diagnostics panel width between app launches.
///
/// The preference is optional UI state: storage failures fall back to the
/// built-in width and must never keep the app from opening.
final class DiagnosticsPanelWidthStore {
  static const String storageKey = 'discourse_native.diagnostics_panel_width';

  Future<double?> read() async {
    try {
      return (await SharedPreferences.getInstance()).getDouble(storageKey);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'diagnosticsPanel.readWidth');
      return null;
    }
  }

  Future<void> write(double width) async {
    try {
      await (await SharedPreferences.getInstance()).setDouble(
        storageKey,
        width,
      );
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'diagnosticsPanel.writeWidth');
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
