import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

/// Diagnostics panel width persistence.
///
/// The boolean write result is deliberately preserved so the store can report
/// platform rejections while continuing with its built-in presentation
/// fallback.
abstract interface class DiagnosticsPanelWidthPersistence {
  Future<double?> readWidth();

  Future<bool> writeWidth(double width);
}

final class SharedPreferencesDiagnosticsPanelWidthPersistence
    implements DiagnosticsPanelWidthPersistence {
  const SharedPreferencesDiagnosticsPanelWidthPersistence();

  @override
  Future<double?> readWidth() async => (await SharedPreferences.getInstance())
      .getDouble(DiagnosticsPanelWidthStore.storageKey);

  @override
  Future<bool> writeWidth(double width) async =>
      (await SharedPreferences.getInstance()).setDouble(
        DiagnosticsPanelWidthStore.storageKey,
        width,
      );
}

/// Persists the preferred diagnostics panel width between app launches.
///
/// The preference is optional UI state: storage failures fall back to the
/// built-in width and must never keep the app from opening.
final class DiagnosticsPanelWidthStore {
  const DiagnosticsPanelWidthStore({
    DiagnosticsPanelWidthPersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesDiagnosticsPanelWidthPersistence();

  static const String storageKey = 'discourse_native.diagnostics_panel_width';
  static final SerialOperationQueue _operations = SerialOperationQueue();

  final DiagnosticsPanelWidthPersistence _persistence;

  Future<double?> read() =>
      _operations.run(owner: _persistence, key: storageKey, operation: _read);

  Future<double?> _read() async {
    try {
      return await _persistence.readWidth();
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'diagnosticsPanel.readWidth');
      return null;
    }
  }

  Future<void> write(double width) => _operations.run<void>(
    owner: _persistence,
    key: storageKey,
    operation: () => _persist(width),
  );

  Future<void> _persist(double width) async {
    try {
      if (!await _persistence.writeWidth(width)) {
        throw StateError('Could not persist the diagnostics panel width.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'diagnosticsPanel.writeWidth');
    }
  }
}
