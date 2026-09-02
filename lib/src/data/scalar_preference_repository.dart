import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class ScalarPreferencePersistence<T extends Object> {
  Future<T?> read(String key);

  Future<bool> write(String key, T value);
}

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
    required this.readOperation,
    required this.writeOperation,
    required this.writeFailureMessage,
    Object? owner,
  }) : owner = owner ?? persistence;

  static final SerialOperationQueue _operations = SerialOperationQueue();

  final ScalarPreferencePersistence<T> persistence;
  final Object owner;
  final String key;
  final String readOperation;
  final String writeOperation;
  final String writeFailureMessage;

  Future<T?> read() =>
      _operations.run(owner: owner, key: key, operation: _read);

  Future<T?> _read() async {
    try {
      return await persistence.read(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, readOperation);
      return null;
    }
  }

  Future<void> write(T value) => _operations.run<void>(
    owner: owner,
    key: key,
    operation: () => _write(value),
  );

  Future<void> _write(T value) async {
    try {
      if (!await persistence.write(key, value)) {
        throw StateError(writeFailureMessage);
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, writeOperation);
    }
  }
}
