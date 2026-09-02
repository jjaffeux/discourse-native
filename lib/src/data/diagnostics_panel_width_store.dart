import 'scalar_preference_repository.dart';

abstract interface class DiagnosticsPanelWidthPersistence {
  Future<double?> readWidth();

  Future<bool> writeWidth(double width);
}

final class SharedPreferencesDiagnosticsPanelWidthPersistence
    implements DiagnosticsPanelWidthPersistence {
  const SharedPreferencesDiagnosticsPanelWidthPersistence();

  static const _preferences = SharedPreferencesDoublePreferencePersistence();

  @override
  Future<double?> readWidth() =>
      _preferences.read(DiagnosticsPanelWidthStore.storageKey);

  @override
  Future<bool> writeWidth(double width) =>
      _preferences.write(DiagnosticsPanelWidthStore.storageKey, width);
}

final class DiagnosticsPanelWidthStore {
  const DiagnosticsPanelWidthStore({
    DiagnosticsPanelWidthPersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesDiagnosticsPanelWidthPersistence();

  static const String storageKey = 'discourse_native.diagnostics_panel_width';

  final DiagnosticsPanelWidthPersistence _persistence;

  ScalarPreferenceRepository<double> get _repository =>
      ScalarPreferenceRepository<double>(
        persistence: _DiagnosticsPanelWidthScalarPersistence(_persistence),
        owner: _persistence,
        key: storageKey,
        readOperation: 'diagnosticsPanel.readWidth',
        writeOperation: 'diagnosticsPanel.writeWidth',
        writeFailureMessage: 'Could not persist the diagnostics panel width.',
      );

  Future<double?> read() => _repository.read();

  Future<void> write(double width) => _repository.write(width);
}

final class _DiagnosticsPanelWidthScalarPersistence
    implements ScalarPreferencePersistence<double> {
  const _DiagnosticsPanelWidthScalarPersistence(this._persistence);

  final DiagnosticsPanelWidthPersistence _persistence;

  @override
  Future<double?> read(String key) => _persistence.readWidth();

  @override
  Future<bool> write(String key, double value) =>
      _persistence.writeWidth(value);
}
