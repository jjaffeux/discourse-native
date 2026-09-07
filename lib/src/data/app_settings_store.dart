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
  ContentAlignment? _sessionContentAlignment;
  bool? _sessionDisableGifAnimations;
  AppTextScale? _sessionTextScale;
  AppSettings? _lastReadSettings;

  bool get _hasSessionChanges =>
      _sessionContentAlignment != null ||
      _sessionDisableGifAnimations != null ||
      _sessionTextScale != null;

  Future<AppSettings> read() async {
    final known = _lastReadSettings;
    if (_hasSessionChanges && known != null) {
      return _withSessionSettings(known);
    }
    if (_sessionContentAlignment != null &&
        _sessionDisableGifAnimations != null &&
        _sessionTextScale != null) {
      return _withSessionSettings(AppSettings.defaults);
    }
    final persisted = await _operations.read(
      owner: _persistence,
      key: _operationKey,
      operation: _read,
    );
    // Retain known preferences with session edits if storage later fails.
    // An older read must not replace a session another read already hydrated.
    final settings = _hasSessionChanges
        ? _lastReadSettings ?? persisted
        : persisted;
    _lastReadSettings = settings;
    return _withSessionSettings(settings);
  }

  AppSettings _withSessionSettings(AppSettings settings) => settings.copyWith(
    contentAlignment: _sessionContentAlignment,
    disableGifAnimations: _sessionDisableGifAnimations,
    textScale: _sessionTextScale,
  );

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

  Future<void> write(AppSettings settings) => update(
    contentAlignment: settings.contentAlignment,
    disableGifAnimations: settings.disableGifAnimations,
    textScale: settings.textScale,
  );

  /// Saves explicit choices without replacing preferences still being read.
  /// Session choices also override late reads when persistence fails.
  Future<void> update({
    ContentAlignment? contentAlignment,
    bool? disableGifAnimations,
    AppTextScale? textScale,
  }) {
    _sessionContentAlignment = contentAlignment ?? _sessionContentAlignment;
    _sessionDisableGifAnimations =
        disableGifAnimations ?? _sessionDisableGifAnimations;
    _sessionTextScale = textScale ?? _sessionTextScale;
    return _operations.write<void>(
      owner: _persistence,
      key: _operationKey,
      operation: () => _persist(
        contentAlignment: contentAlignment,
        disableGifAnimations: disableGifAnimations,
        textScale: textScale,
      ),
    );
  }

  Future<void> _persist({
    ContentAlignment? contentAlignment,
    bool? disableGifAnimations,
    AppTextScale? textScale,
  }) async {
    try {
      if (contentAlignment != null &&
          !await _persistence.writeContentAlignment(contentAlignment.name)) {
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
      if (disableGifAnimations != null &&
          !await _persistence.writeDisableGifAnimations(disableGifAnimations)) {
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
      if (textScale != null &&
          !await _persistence.writeTextScale(textScale.name)) {
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
