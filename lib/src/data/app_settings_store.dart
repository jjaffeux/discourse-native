import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class AppSettingsPersistence {
  Future<String?> readContentAlignment();

  Future<bool> writeContentAlignment(String value);
}

final class SharedPreferencesAppSettingsPersistence
    implements AppSettingsPersistence {
  const SharedPreferencesAppSettingsPersistence();

  @override
  Future<String?> readContentAlignment() async =>
      (await SharedPreferences.getInstance()).getString(
        AppSettingsStore.contentAlignmentKey,
      );

  @override
  Future<bool> writeContentAlignment(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        AppSettingsStore.contentAlignmentKey,
        value,
      );
}

final class MemoryAppSettingsPersistence implements AppSettingsPersistence {
  MemoryAppSettingsPersistence({this.contentAlignment});

  String? contentAlignment;

  @override
  Future<String?> readContentAlignment() async => contentAlignment;

  @override
  Future<bool> writeContentAlignment(String value) async {
    contentAlignment = value;
    return true;
  }
}

final class AppSettingsStore {
  AppSettingsStore({AppSettingsPersistence? persistence})
    : _persistence = persistence ?? _defaultPersistence;

  static const String contentAlignmentKey =
      'discourse_native.content_alignment';
  static const AppSettingsPersistence _defaultPersistence =
      SharedPreferencesAppSettingsPersistence();
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  final AppSettingsPersistence _persistence;
  AppSettings? _sessionSettings;

  Future<AppSettings> read() async {
    final sessionSettings = _sessionSettings;
    if (sessionSettings != null) return sessionSettings;
    final persisted = await _operations.read(
      owner: _persistence,
      key: contentAlignmentKey,
      operation: _read,
    );
    return _sessionSettings ?? persisted;
  }

  Future<AppSettings> _read() async {
    try {
      final stored = await _persistence.readContentAlignment();
      return AppSettings(contentAlignment: _contentAlignmentByName(stored));
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readContentAlignment',
      );
      return AppSettings.defaults;
    }
  }

  Future<void> write(AppSettings settings) {
    _sessionSettings = settings;
    return _operations.write<void>(
      owner: _persistence,
      key: contentAlignmentKey,
      operation: () => _persist(settings.contentAlignment),
    );
  }

  Future<void> _persist(ContentAlignment alignment) async {
    try {
      if (!await _persistence.writeContentAlignment(alignment.name)) {
        throw StateError('Could not persist the app content alignment.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeContentAlignment',
      );
    }
  }
}

ContentAlignment _contentAlignmentByName(String? name) {
  for (final alignment in ContentAlignment.values) {
    if (alignment.name == name) return alignment;
  }
  return ContentAlignment.center;
}
