import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class AppSettingsPersistence {
  Future<String?> readContentAlignment();

  Future<bool> writeContentAlignment(String value);

  Future<bool?> readDisableGifAnimations();

  Future<bool> writeDisableGifAnimations(bool value);

  Future<String?> readTextScale();

  Future<bool> writeTextScale(String value);
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

  @override
  Future<bool?> readDisableGifAnimations() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.disableGifAnimationsKey,
      );

  @override
  Future<bool> writeDisableGifAnimations(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.disableGifAnimationsKey,
        value,
      );

  @override
  Future<String?> readTextScale() async =>
      (await SharedPreferences.getInstance()).getString(
        AppSettingsStore.textScaleKey,
      );

  @override
  Future<bool> writeTextScale(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        AppSettingsStore.textScaleKey,
        value,
      );
}

final class MemoryAppSettingsPersistence implements AppSettingsPersistence {
  MemoryAppSettingsPersistence({
    this.contentAlignment,
    this.disableGifAnimations,
    this.textScale,
  });

  String? contentAlignment;
  bool? disableGifAnimations;
  String? textScale;

  @override
  Future<String?> readContentAlignment() async => contentAlignment;

  @override
  Future<bool> writeContentAlignment(String value) async {
    contentAlignment = value;
    return true;
  }

  @override
  Future<bool?> readDisableGifAnimations() async => disableGifAnimations;

  @override
  Future<bool> writeDisableGifAnimations(bool value) async {
    disableGifAnimations = value;
    return true;
  }

  @override
  Future<String?> readTextScale() async => textScale;

  @override
  Future<bool> writeTextScale(String value) async {
    textScale = value;
    return true;
  }
}

final class AppSettingsStore {
  AppSettingsStore({AppSettingsPersistence? persistence})
    : _persistence = persistence ?? _defaultPersistence;

  static const String contentAlignmentKey =
      'discourse_native.content_alignment';
  static const String disableGifAnimationsKey =
      'discourse_native.disable_gif_animations';
  static const String textScaleKey = 'discourse_native.text_scale';
  static const String _operationKey = 'discourse_native.app_settings';
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
      key: _operationKey,
      operation: _read,
    );
    return _sessionSettings ?? persisted;
  }

  Future<AppSettings> _read() async {
    var contentAlignment = ContentAlignment.center;
    var disableGifAnimations = false;
    var textScale = AppTextScale.percent100;
    try {
      final stored = await _persistence.readContentAlignment();
      contentAlignment = _contentAlignmentByName(stored);
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readContentAlignment',
      );
    }
    try {
      disableGifAnimations =
          await _persistence.readDisableGifAnimations() ?? false;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readDisableGifAnimations',
      );
    }
    try {
      final stored = await _persistence.readTextScale();
      textScale = _appTextScaleByName(stored);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'appSettings.readTextScale');
    }
    return AppSettings(
      contentAlignment: contentAlignment,
      disableGifAnimations: disableGifAnimations,
      textScale: textScale,
    );
  }

  Future<void> write(AppSettings settings) {
    _sessionSettings = settings;
    return _operations.write<void>(
      owner: _persistence,
      key: _operationKey,
      operation: () => _persist(settings),
    );
  }

  Future<void> _persist(AppSettings settings) async {
    try {
      if (!await _persistence.writeContentAlignment(
        settings.contentAlignment.name,
      )) {
        throw StateError('Could not persist the app content alignment.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeContentAlignment',
      );
    }
    try {
      if (!await _persistence.writeDisableGifAnimations(
        settings.disableGifAnimations,
      )) {
        throw StateError('Could not persist the GIF animation preference.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeDisableGifAnimations',
      );
    }
    try {
      if (!await _persistence.writeTextScale(settings.textScale.name)) {
        throw StateError('Could not persist the app text scale.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'appSettings.writeTextScale');
    }
  }
}

ContentAlignment _contentAlignmentByName(String? name) {
  for (final alignment in ContentAlignment.values) {
    if (alignment.name == name) return alignment;
  }
  return ContentAlignment.center;
}

AppTextScale _appTextScaleByName(String? name) {
  for (final scale in AppTextScale.values) {
    if (scale.name == name) return scale;
  }
  return AppTextScale.percent100;
}
