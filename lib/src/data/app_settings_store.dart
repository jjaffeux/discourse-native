import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import 'preference_storage_scope.dart';
import 'serial_operation_queue.dart';

abstract interface class AppSettingsPersistence {
  Future<bool?> readLimitContentSize();

  Future<bool> writeLimitContentSize(bool value);

  Future<bool?> readDisableGifAnimations();

  Future<bool?> readReduceMotion();

  Future<bool> writeReduceMotion(bool value);

  Future<bool?> readRawMarkdownComposers();

  Future<bool> writeDisableGifAnimations(bool value);

  Future<bool> writeRawMarkdownComposers(bool value);

  Future<String?> readTextScale();

  Future<bool> writeTextScale(String value);

  Future<String?> readThemeMode();

  Future<bool> writeThemeMode(String value);

  Future<String?> readTopicListMode();

  Future<bool> writeTopicListMode(String value);
}

@PreferenceStorage.device('Device application settings survive forum removal.')
final class SharedPreferencesAppSettingsPersistence
    implements AppSettingsPersistence {
  const SharedPreferencesAppSettingsPersistence();

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
  Future<bool?> readLimitContentSize() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.limitContentSizeKey,
      );

  @override
  Future<bool> writeLimitContentSize(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.limitContentSizeKey,
        value,
      );

  @override
  Future<bool?> readDisableGifAnimations() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.disableGifAnimationsKey,
      );

  @override
  Future<bool?> readReduceMotion() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.reduceMotionKey,
      );

  @override
  Future<bool> writeReduceMotion(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.reduceMotionKey,
        value,
      );

  @override
  Future<bool?> readRawMarkdownComposers() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.rawMarkdownComposersKey,
      );

  @override
  Future<bool> writeDisableGifAnimations(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.disableGifAnimationsKey,
        value,
      );

  @override
  Future<bool> writeRawMarkdownComposers(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.rawMarkdownComposersKey,
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
    this.limitContentSize,
    this.disableGifAnimations,
    this.reduceMotion,
    this.rawMarkdownComposers,
    this.textScale,
    this.themeMode,
    this.topicListMode,
  });

  bool? limitContentSize;
  bool? disableGifAnimations;
  bool? reduceMotion;
  bool? rawMarkdownComposers;
  String? textScale;
  String? themeMode;
  String? topicListMode;

  @override
  Future<String?> readTopicListMode() async => topicListMode;

  @override
  Future<bool> writeTopicListMode(String value) async {
    topicListMode = value;
    return true;
  }

  @override
  Future<bool?> readLimitContentSize() async => limitContentSize;

  @override
  Future<bool> writeLimitContentSize(bool value) async {
    limitContentSize = value;
    return true;
  }

  @override
  Future<bool?> readDisableGifAnimations() async => disableGifAnimations;

  @override
  Future<bool?> readReduceMotion() async => reduceMotion;

  @override
  Future<bool> writeReduceMotion(bool value) async {
    reduceMotion = value;
    return true;
  }

  @override
  Future<bool?> readRawMarkdownComposers() async => rawMarkdownComposers;

  @override
  Future<bool> writeDisableGifAnimations(bool value) async {
    disableGifAnimations = value;
    return true;
  }

  @override
  Future<bool> writeRawMarkdownComposers(bool value) async {
    rawMarkdownComposers = value;
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

  static const String limitContentSizeKey =
      'discourse_native.limit_content_size';
  static const String disableGifAnimationsKey =
      'discourse_native.disable_gif_animations';
  static const String reduceMotionKey = 'discourse_native.reduce_motion';
  static const String rawMarkdownComposersKey =
      'discourse_native.raw_markdown_composers';
  static const String textScaleKey = 'discourse_native.text_scale';
  static const String themeModeKey = 'discourse_native.theme_mode';
  static const String topicListModeKey = 'discourse_native.topic_list_mode';
  static const String _operationKey = 'discourse_native.app_settings';
  static const AppSettingsPersistence _defaultPersistence =
      SharedPreferencesAppSettingsPersistence();
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  final AppSettingsPersistence _persistence;
  bool? _sessionLimitContentSize;
  bool? _sessionDisableGifAnimations;
  bool? _sessionReduceMotion;
  bool? _sessionRawMarkdownComposers;
  AppTextScale? _sessionTextScale;
  AppThemeMode? _sessionThemeMode;
  TopicListDisplayMode? _sessionTopicListMode;
  AppSettings? _lastReadSettings;

  bool get _hasSessionChanges =>
      _sessionLimitContentSize != null ||
      _sessionDisableGifAnimations != null ||
      _sessionReduceMotion != null ||
      _sessionRawMarkdownComposers != null ||
      _sessionTextScale != null ||
      _sessionThemeMode != null ||
      _sessionTopicListMode != null;

  Future<AppSettings> read() async {
    final known = _lastReadSettings;
    if (_hasSessionChanges && known != null) {
      return _withSessionSettings(known);
    }
    if (_sessionLimitContentSize != null &&
        _sessionDisableGifAnimations != null &&
        _sessionReduceMotion != null &&
        _sessionRawMarkdownComposers != null &&
        _sessionTextScale != null &&
        _sessionThemeMode != null &&
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
    limitContentSize: _sessionLimitContentSize,
    disableGifAnimations: _sessionDisableGifAnimations,
    reduceMotion: _sessionReduceMotion,
    rawMarkdownComposers: _sessionRawMarkdownComposers,
    textScale: _sessionTextScale,
    themeMode: _sessionThemeMode,
    topicListMode: _sessionTopicListMode,
  );

  Future<AppSettings> _read() async {
    var limitContentSize = AppSettings.defaults.limitContentSize;
    var disableGifAnimations = false;
    bool? reduceMotion;
    var rawMarkdownComposers = false;
    var textScale = AppTextScale.percent100;
    var themeMode = AppThemeMode.system;
    var topicListMode = TopicListDisplayMode.card;
    try {
      limitContentSize =
          await _persistence.readLimitContentSize() ??
          AppSettings.defaults.limitContentSize;
    } catch (error) {}
    try {
      disableGifAnimations =
          await _persistence.readDisableGifAnimations() ?? false;
    } catch (error) {}
    try {
      reduceMotion = await _persistence.readReduceMotion();
    } catch (error) {}
    try {
      rawMarkdownComposers =
          await _persistence.readRawMarkdownComposers() ?? false;
    } catch (error) {}
    try {
      final stored = await _persistence.readTextScale();
      textScale = _appTextScaleByName(stored);
    } catch (error) {}
    try {
      final stored = await _persistence.readThemeMode();
      themeMode = AppThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => AppThemeMode.system,
      );
    } catch (error) {}
    try {
      final stored = await _persistence.readTopicListMode();
      topicListMode = TopicListDisplayMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => TopicListDisplayMode.card,
      );
    } catch (error) {}
    return AppSettings(
      limitContentSize: limitContentSize,
      disableGifAnimations: disableGifAnimations,
      reduceMotion: reduceMotion,
      rawMarkdownComposers: rawMarkdownComposers,
      textScale: textScale,
      themeMode: themeMode,
      topicListMode: topicListMode,
    );
  }

  Future<void> write(AppSettings settings) => update(
    limitContentSize: settings.limitContentSize,
    disableGifAnimations: settings.disableGifAnimations,
    reduceMotion: settings.reduceMotion,
    rawMarkdownComposers: settings.rawMarkdownComposers,
    textScale: settings.textScale,
    themeMode: settings.themeMode,
    topicListMode: settings.topicListMode,
  );

  /// Saves explicit choices without replacing preferences still being read.
  /// Session choices also override late reads when persistence fails.
  Future<void> update({
    bool? limitContentSize,
    bool? disableGifAnimations,
    bool? reduceMotion,
    bool? rawMarkdownComposers,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    TopicListDisplayMode? topicListMode,
  }) {
    _sessionLimitContentSize = limitContentSize ?? _sessionLimitContentSize;
    _sessionDisableGifAnimations =
        disableGifAnimations ?? _sessionDisableGifAnimations;
    _sessionReduceMotion = reduceMotion ?? _sessionReduceMotion;
    _sessionRawMarkdownComposers =
        rawMarkdownComposers ?? _sessionRawMarkdownComposers;
    _sessionTextScale = textScale ?? _sessionTextScale;
    _sessionThemeMode = themeMode ?? _sessionThemeMode;
    _sessionTopicListMode = topicListMode ?? _sessionTopicListMode;
    return _operations.write<void>(
      owner: _persistence,
      key: _operationKey,
      operation: () => _persist(
        limitContentSize: limitContentSize,
        disableGifAnimations: disableGifAnimations,
        reduceMotion: reduceMotion,
        rawMarkdownComposers: rawMarkdownComposers,
        textScale: textScale,
        themeMode: themeMode,
        topicListMode: topicListMode,
      ),
    );
  }

  Future<void> _persist({
    bool? limitContentSize,
    bool? disableGifAnimations,
    bool? reduceMotion,
    bool? rawMarkdownComposers,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    TopicListDisplayMode? topicListMode,
  }) async {
    try {
      if (limitContentSize != null &&
          !await _persistence.writeLimitContentSize(limitContentSize)) {
        throw StateError('Could not persist the content size limit.');
      }
    } catch (error) {}
    try {
      if (disableGifAnimations != null &&
          !await _persistence.writeDisableGifAnimations(disableGifAnimations)) {
        throw StateError('Could not persist the GIF animation preference.');
      }
    } catch (error) {}
    try {
      if (reduceMotion != null &&
          !await _persistence.writeReduceMotion(reduceMotion)) {
        throw StateError('Could not persist the reduced motion preference.');
      }
    } catch (error) {}
    try {
      if (rawMarkdownComposers != null &&
          !await _persistence.writeRawMarkdownComposers(rawMarkdownComposers)) {
        throw StateError(
          'Could not persist the raw Markdown composer preference.',
        );
      }
    } catch (error) {}
    try {
      if (textScale != null &&
          !await _persistence.writeTextScale(textScale.name)) {
        throw StateError('Could not persist the app text scale.');
      }
    } catch (error) {}
    try {
      if (themeMode != null &&
          !await _persistence.writeThemeMode(themeMode.name)) {
        throw StateError('Could not persist the app theme mode.');
      }
    } catch (error) {}
    try {
      if (topicListMode != null &&
          !await _persistence.writeTopicListMode(topicListMode.name)) {
        throw StateError('Could not persist the topic list mode.');
      }
    } catch (error) {}
  }
}

AppTextScale _appTextScaleByName(String? name) {
  for (final scale in AppTextScale.values) {
    if (scale.name == name) return scale;
  }
  return AppTextScale.percent100;
}
