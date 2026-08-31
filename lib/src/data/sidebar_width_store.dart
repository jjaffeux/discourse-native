import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class SidebarWidthPersistence {
  Future<double?> readWidth();

  Future<bool> writeWidth(double width);
}

final class SharedPreferencesSidebarWidthPersistence
    implements SidebarWidthPersistence {
  const SharedPreferencesSidebarWidthPersistence();

  @override
  Future<double?> readWidth() async => (await SharedPreferences.getInstance())
      .getDouble(SidebarWidthStore.storageKey);

  @override
  Future<bool> writeWidth(double width) async =>
      (await SharedPreferences.getInstance()).setDouble(
        SidebarWidthStore.storageKey,
        width,
      );
}

final class SidebarWidthStore {
  const SidebarWidthStore({SidebarWidthPersistence? persistence})
    : _persistence =
          persistence ?? const SharedPreferencesSidebarWidthPersistence();

  static const String storageKey = 'discourse_native.sidebar_width';
  static final SerialOperationQueue _operations = SerialOperationQueue();

  final SidebarWidthPersistence _persistence;

  Future<double?> read() =>
      _operations.run(owner: _persistence, key: storageKey, operation: _read);

  Future<double?> _read() async {
    try {
      return await _persistence.readWidth();
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'sidebar.readWidth');
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
        throw StateError('Could not persist the sidebar width.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'sidebar.writeWidth');
    }
  }
}
