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

  Future<String?> readThemeMode();

  Future<bool> writeThemeMode(String value);

  Future<bool?> readTopicListLargerText();

  Future<bool> writeTopicListLargerText(bool value);

  Future<String?> readTopicListMode();

  Future<bool> writeTopicListMode(String value);
}

final class SharedPreferencesAppSettingsPersistence
    implements AppSettingsPersistence {
  const SharedPreferencesAppSettingsPersistence();

  @override
  Future<bool?> readTopicListLargerText() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.topicListLargerTextKey,
      );

  @override
  Future<bool> writeTopicListLargerText(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.topicListLargerTextKey,
        value,
      );

  @override
  Future<String?> readTopicListMode() async =>
      (await SharedPreferences.getInstance()).getString(
        AppSettingsStore.topicListModeKey,
      );

  @override
  Future<bool> writeTopicListMode(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        AppSettingsStore.topicListModeKey,
        value,
      );

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

  @override
  Future<String?> readThemeMode() async =>
      (await SharedPreferences.getInstance()).getString(
        AppSettingsStore.themeModeKey,
      );

  @override
  Future<bool> writeThemeMode(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        AppSettingsStore.themeModeKey,
        value,
      );
}

final class MemoryAppSettingsPersistence implements AppSettingsPersistence {
  MemoryAppSettingsPersistence({
    this.contentAlignment,
    this.disableGifAnimations,
    this.textScale,
    this.themeMode,
    this.topicListLargerText,
    this.topicListMode,
  });

  String? contentAlignment;
  bool? disableGifAnimations;
  String? textScale;
  String? themeMode;
  bool? topicListLargerText;
  String? topicListMode;

  @override
  Future<bool?> readTopicListLargerText() async => topicListLargerText;

  @override
  Future<bool> writeTopicListLargerText(bool value) async {
    topicListLargerText = value;
    return true;
  }

  @override
  Future<String?> readTopicListMode() async => topicListMode;

  @override
  Future<bool> writeTopicListMode(String value) async {
    topicListMode = value;
    return true;
  }

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

  @override
  Future<String?> readThemeMode() async => themeMode;

  @override
  Future<bool> writeThemeMode(String value) async {
    themeMode = value;
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
  static const String themeModeKey = 'discourse_native.theme_mode';
  static const String topicListLargerTextKey =
      'discourse_native.topic_list_larger_text';
  static const String topicListModeKey = 'discourse_native.topic_list_mode';
  static const String _operationKey = 'discourse_native.app_settings';
  static const AppSettingsPersistence _defaultPersistence =
      SharedPreferencesAppSettingsPersistence();
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  final AppSettingsPersistence _persistence;
  ContentAlignment? _sessionContentAlignment;
  bool? _sessionDisableGifAnimations;
  AppTextScale? _sessionTextScale;
  AppThemeMode? _sessionThemeMode;
  bool? _sessionTopicListLargerText;
  TopicListDisplayMode? _sessionTopicListMode;
  AppSettings? _lastReadSettings;

  bool get _hasSessionChanges =>
      _sessionContentAlignment != null ||
      _sessionDisableGifAnimations != null ||
      _sessionTextScale != null ||
      _sessionThemeMode != null ||
      _sessionTopicListLargerText != null ||
      _sessionTopicListMode != null;

  Future<AppSettings> read() async {
    final known = _lastReadSettings;
    if (_hasSessionChanges && known != null) {
      return _withSessionSettings(known);
    }
    if (_sessionContentAlignment != null &&
        _sessionDisableGifAnimations != null &&
        _sessionTextScale != null &&
        _sessionThemeMode != null &&
        _sessionTopicListLargerText != null &&
        _sessionTopicListMode != null) {
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
    themeMode: _sessionThemeMode,
    topicListLargerText: _sessionTopicListLargerText,
    topicListMode: _sessionTopicListMode,
  );

  Future<AppSettings> _read() async {
    var contentAlignment = ContentAlignment.center;
    var disableGifAnimations = false;
    var textScale = AppTextScale.percent100;
    var themeMode = AppThemeMode.system;
    var topicListLargerText = false;
    var topicListMode = TopicListDisplayMode.card;
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
    try {
      final stored = await _persistence.readThemeMode();
      themeMode = AppThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => AppThemeMode.system,
      );
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'appSettings.readThemeMode');
    }
    try {
      final stored = await _persistence.readTopicListMode();
      topicListMode = TopicListDisplayMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => TopicListDisplayMode.card,
      );
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'appSettings.readTopicListMode');
    }
    try {
      topicListLargerText =
          await _persistence.readTopicListLargerText() ?? false;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readTopicListLargerText',
      );
    }
    return AppSettings(
      contentAlignment: contentAlignment,
      disableGifAnimations: disableGifAnimations,
      textScale: textScale,
      themeMode: themeMode,
      topicListLargerText: topicListLargerText,
      topicListMode: topicListMode,
    );
  }

  Future<void> write(AppSettings settings) => update(
    contentAlignment: settings.contentAlignment,
    disableGifAnimations: settings.disableGifAnimations,
    textScale: settings.textScale,
    themeMode: settings.themeMode,
    topicListLargerText: settings.topicListLargerText,
    topicListMode: settings.topicListMode,
  );

  /// Saves explicit choices without replacing preferences still being read.
  /// Session choices also override late reads when persistence fails.
  Future<void> update({
    ContentAlignment? contentAlignment,
    bool? disableGifAnimations,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    bool? topicListLargerText,
    TopicListDisplayMode? topicListMode,
  }) {
    _sessionContentAlignment = contentAlignment ?? _sessionContentAlignment;
    _sessionDisableGifAnimations =
        disableGifAnimations ?? _sessionDisableGifAnimations;
    _sessionTextScale = textScale ?? _sessionTextScale;
    _sessionThemeMode = themeMode ?? _sessionThemeMode;
    _sessionTopicListLargerText =
        topicListLargerText ?? _sessionTopicListLargerText;
    _sessionTopicListMode = topicListMode ?? _sessionTopicListMode;
    return _operations.write<void>(
      owner: _persistence,
      key: _operationKey,
      operation: () => _persist(
        contentAlignment: contentAlignment,
        disableGifAnimations: disableGifAnimations,
        textScale: textScale,
        themeMode: themeMode,
        topicListLargerText: topicListLargerText,
        topicListMode: topicListMode,
      ),
    );
  }

  Future<void> _persist({
    ContentAlignment? contentAlignment,
    bool? disableGifAnimations,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    bool? topicListLargerText,
    TopicListDisplayMode? topicListMode,
  }) async {
    try {
      if (topicListLargerText != null &&
          !await _persistence.writeTopicListLargerText(topicListLargerText)) {
        throw StateError('Could not persist topicListLargerText.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeTopicListLargerText',
      );
    }
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
    try {
      if (themeMode != null &&
          !await _persistence.writeThemeMode(themeMode.name)) {
        throw StateError('Could not persist the app theme mode.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'appSettings.writeThemeMode');
    }
    try {
      if (topicListMode != null &&
          !await _persistence.writeTopicListMode(topicListMode.name)) {
        throw StateError('Could not persist the topic list mode.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'appSettings.writeTopicListMode');
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
