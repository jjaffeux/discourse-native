import 'scalar_preference_repository.dart';

abstract interface class SidebarWidthPersistence {
  Future<double?> readWidth();

  Future<bool> writeWidth(double width);
}

final class SharedPreferencesSidebarWidthPersistence
    implements SidebarWidthPersistence {
  const SharedPreferencesSidebarWidthPersistence();

  static const _preferences = SharedPreferencesDoublePreferencePersistence();

  @override
  Future<double?> readWidth() =>
      _preferences.read(SidebarWidthStore.storageKey);

  @override
  Future<bool> writeWidth(double width) =>
      _preferences.write(SidebarWidthStore.storageKey, width);
}

final class SidebarWidthStore {
  const SidebarWidthStore({SidebarWidthPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesSidebarWidthPersistence();

  static const String storageKey = 'discourse_native.sidebar_width';

  final SidebarWidthPersistence _persistence;

  ScalarPreferenceRepository<double> get _repository =>
      ScalarPreferenceRepository<double>(
        persistence: _SidebarWidthScalarPersistence(_persistence),
        owner: _persistence,
        key: storageKey,
        readOperation: 'sidebar.readWidth',
        writeOperation: 'sidebar.writeWidth',
        writeFailureMessage: 'Could not persist the sidebar width.',
      );

  Future<double?> read() => _repository.read();

  Future<void> write(double width) => _repository.write(width);
}

final class _SidebarWidthScalarPersistence
    implements ScalarPreferencePersistence<double> {
  const _SidebarWidthScalarPersistence(this._persistence);

  final SidebarWidthPersistence _persistence;

  @override
  Future<double?> read(String key) => _persistence.readWidth();

  @override
  Future<bool> write(String key, double value) =>
      _persistence.writeWidth(value);
}
