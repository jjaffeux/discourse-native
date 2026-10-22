import 'package:shared_preferences/shared_preferences.dart';

import 'preference_storage_scope.dart';
import 'serial_operation_queue.dart';

abstract interface class ScalarPreferencePersistence<T extends Object> {
  Future<T?> read(String key);

  Future<bool> write(String key, T value);
}

@PreferenceStorage.adapter(
  'ScalarPreferenceRepository uses the device or site key declared by its domain store.',
)
abstract base class SharedPreferencesScalarPreferencePersistence<
  T extends Object
>
    implements ScalarPreferencePersistence<T> {
  const SharedPreferencesScalarPreferencePersistence();

  T? readValue(SharedPreferences preferences, String key);

  Future<bool> writeValue(SharedPreferences preferences, String key, T value);

  @override
  Future<T?> read(String key) async =>
      readValue(await SharedPreferences.getInstance(), key);

  @override
  Future<bool> write(String key, T value) async =>
      writeValue(await SharedPreferences.getInstance(), key, value);
}

@PreferenceStorage.adapter(
  'ScalarPreferenceRepository supplies the owning device or site key.',
)
final class SharedPreferencesDoublePreferencePersistence
    extends SharedPreferencesScalarPreferencePersistence<double> {
  const SharedPreferencesDoublePreferencePersistence();

  @override
  double? readValue(SharedPreferences preferences, String key) =>
      preferences.getDouble(key);

  @override
  Future<bool> writeValue(
    SharedPreferences preferences,
    String key,
    double value,
  ) => preferences.setDouble(key, value);
}

final class ScalarPreferenceRepository<T extends Object> {
  const ScalarPreferenceRepository({
    required this.persistence,
    required this.key,

    this.isCurrent,
    Object? owner,
  }) : owner = owner ?? persistence;

  static final SerialOperationQueue _operations = SerialOperationQueue();

  final ScalarPreferencePersistence<T> persistence;
  final Object owner;
  final String key;

  final bool Function()? isCurrent;

  Future<T?> read() =>
      _operations.run(owner: owner, key: key, operation: _read);

  Future<T?> _read() async {
    if (isCurrent?.call() == false) return null;
    try {
      final value = await persistence.read(key);
      return isCurrent?.call() == false ? null : value;
    } catch (error) {
      return null;
    }
  }

  Future<void> write(T value) => _operations.run<void>(
    owner: owner,
    key: key,
    operation: () => _write(value),
  );

  Future<void> _write(T value) async {
    if (isCurrent?.call() == false) return;
    try {
      await persistence.write(key, value);
    } catch (_) {}
  }
}
