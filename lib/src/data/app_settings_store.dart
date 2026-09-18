import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';

abstract interface class AppSettingsPersistence {
  Future<bool?> readLimitContentSize();

  Future<bool> writeLimitContentSize(bool value);

  Future<bool?> readDisableGifAnimations();

  Future<bool> writeDisableGifAnimations(bool value);

  Future<String?> readTextScale();

  Future<bool> writeTextScale(String value);

  Future<String?> readThemeMode();

  Future<bool> writeThemeMode(String value);

  Future<bool?> readTopicListLargerText();
  Future<bool?> readTopicListShowTags();
  Future<bool?> readTopicListShowLastPoster();
  Future<bool?> readTopicListShowAssignments();

  Future<bool> writeTopicListLargerText(bool value);
  Future<bool> writeTopicListShowTags(bool value);
  Future<bool> writeTopicListShowLastPoster(bool value);
  Future<bool> writeTopicListShowAssignments(bool value);

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
  Future<bool?> readTopicListShowTags() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.topicListShowTagsKey,
      );
  @override
  Future<bool?> readTopicListShowLastPoster() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.topicListShowLastPosterKey,
      );

  @override
  Future<bool> writeTopicListShowTags(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.topicListShowTagsKey,
        value,
      );
  @override
  Future<bool> writeTopicListShowLastPoster(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.topicListShowLastPosterKey,
        value,
      );

  @override
  Future<bool?> readTopicListShowAssignments() async =>
      (await SharedPreferences.getInstance()).getBool(
        AppSettingsStore.topicListShowAssignmentsKey,
      );

  @override
  Future<bool> writeTopicListShowAssignments(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        AppSettingsStore.topicListShowAssignmentsKey,
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
    this.limitContentSize,
    this.disableGifAnimations,
    this.textScale,
    this.themeMode,
    this.topicListLargerText,
    this.topicListShowTags,
    this.topicListShowLastPoster,
    this.topicListShowAssignments,
    this.topicListMode,
  });

  bool? limitContentSize;
  bool? disableGifAnimations;
  String? textScale;
  String? themeMode;
  bool? topicListLargerText;
  bool? topicListShowTags;
  bool? topicListShowLastPoster;
  bool? topicListShowAssignments;
  String? topicListMode;

  @override
  Future<bool?> readTopicListLargerText() async => topicListLargerText;
  @override
  Future<bool?> readTopicListShowTags() async => topicListShowTags;
  @override
  Future<bool?> readTopicListShowLastPoster() async => topicListShowLastPoster;
  @override
  Future<bool?> readTopicListShowAssignments() async =>
      topicListShowAssignments;

  @override
  Future<bool> writeTopicListLargerText(bool value) async {
    topicListLargerText = value;
    return true;
  }

  @override
  Future<bool> writeTopicListShowTags(bool value) async {
    topicListShowTags = value;
    return true;
  }

  @override
  Future<bool> writeTopicListShowLastPoster(bool value) async {
    topicListShowLastPoster = value;
    return true;
  }

  @override
  Future<bool> writeTopicListShowAssignments(bool value) async {
    topicListShowAssignments = value;
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
  Future<bool?> readLimitContentSize() async => limitContentSize;

  @override
  Future<bool> writeLimitContentSize(bool value) async {
    limitContentSize = value;
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

  static const String limitContentSizeKey =
      'discourse_native.limit_content_size';
  static const String disableGifAnimationsKey =
      'discourse_native.disable_gif_animations';
  static const String textScaleKey = 'discourse_native.text_scale';
  static const String themeModeKey = 'discourse_native.theme_mode';
  static const String topicListLargerTextKey =
      'discourse_native.topic_list_larger_text';
  static const String topicListShowTagsKey =
      'discourse_native.topic_list_show_tags';
  static const String topicListShowLastPosterKey =
      'discourse_native.topic_list_show_last_poster';
  static const String topicListShowAssignmentsKey =
      'discourse_native.topic_list_show_assignments';
  static const String topicListModeKey = 'discourse_native.topic_list_mode';
  static const String _operationKey = 'discourse_native.app_settings';
  static const AppSettingsPersistence _defaultPersistence =
      SharedPreferencesAppSettingsPersistence();
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();

  final AppSettingsPersistence _persistence;
  bool? _sessionLimitContentSize;
  bool? _sessionDisableGifAnimations;
  AppTextScale? _sessionTextScale;
  AppThemeMode? _sessionThemeMode;
  bool? _sessionTopicListLargerText;
  bool? _sessionTopicListShowTags;
  bool? _sessionTopicListShowLastPoster;
  bool? _sessionTopicListShowAssignments;
  TopicListDisplayMode? _sessionTopicListMode;
  AppSettings? _lastReadSettings;

  bool get _hasSessionChanges =>
      _sessionLimitContentSize != null ||
      _sessionDisableGifAnimations != null ||
      _sessionTextScale != null ||
      _sessionThemeMode != null ||
      _sessionTopicListLargerText != null ||
      _sessionTopicListShowTags != null ||
      _sessionTopicListShowLastPoster != null ||
      _sessionTopicListShowAssignments != null ||
      _sessionTopicListMode != null;

  Future<AppSettings> read() async {
    final known = _lastReadSettings;
    if (_hasSessionChanges && known != null) {
      return _withSessionSettings(known);
    }
    if (_sessionLimitContentSize != null &&
        _sessionDisableGifAnimations != null &&
        _sessionTextScale != null &&
        _sessionThemeMode != null &&
        _sessionTopicListLargerText != null &&
        _sessionTopicListShowTags != null &&
        _sessionTopicListShowLastPoster != null &&
        _sessionTopicListShowAssignments != null &&
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
    textScale: _sessionTextScale,
    themeMode: _sessionThemeMode,
    topicListLargerText: _sessionTopicListLargerText,
    topicListShowTags: _sessionTopicListShowTags,
    topicListShowLastPoster: _sessionTopicListShowLastPoster,
    topicListShowAssignments: _sessionTopicListShowAssignments,
    topicListMode: _sessionTopicListMode,
  );

  Future<AppSettings> _read() async {
    var limitContentSize = false;
    var disableGifAnimations = false;
    var textScale = AppTextScale.percent100;
    var themeMode = AppThemeMode.system;
    var topicListLargerText = false;
    var topicListShowTags = true;
    var topicListShowLastPoster = true;
    var topicListShowAssignments = true;
    var topicListMode = TopicListDisplayMode.card;
    try {
      limitContentSize = await _persistence.readLimitContentSize() ?? false;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readLimitContentSize',
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
    try {
      topicListShowTags = await _persistence.readTopicListShowTags() ?? true;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readTopicListShowTags',
      );
    }
    try {
      topicListShowLastPoster =
          await _persistence.readTopicListShowLastPoster() ?? true;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readTopicListShowLastPoster',
      );
    }
    try {
      topicListShowAssignments =
          await _persistence.readTopicListShowAssignments() ?? true;
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.readTopicListShowAssignments',
      );
    }
    return AppSettings(
      limitContentSize: limitContentSize,
      disableGifAnimations: disableGifAnimations,
      textScale: textScale,
      themeMode: themeMode,
      topicListLargerText: topicListLargerText,
      topicListShowTags: topicListShowTags,
      topicListShowLastPoster: topicListShowLastPoster,
      topicListShowAssignments: topicListShowAssignments,
      topicListMode: topicListMode,
    );
  }

  Future<void> write(AppSettings settings) => update(
    limitContentSize: settings.limitContentSize,
    disableGifAnimations: settings.disableGifAnimations,
    textScale: settings.textScale,
    themeMode: settings.themeMode,
    topicListLargerText: settings.topicListLargerText,
    topicListShowTags: settings.topicListShowTags,
    topicListShowLastPoster: settings.topicListShowLastPoster,
    topicListShowAssignments: settings.topicListShowAssignments,
    topicListMode: settings.topicListMode,
  );

  /// Saves explicit choices without replacing preferences still being read.
  /// Session choices also override late reads when persistence fails.
  Future<void> update({
    bool? limitContentSize,
    bool? disableGifAnimations,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    bool? topicListLargerText,
    bool? topicListShowTags,
    bool? topicListShowLastPoster,
    bool? topicListShowAssignments,
    TopicListDisplayMode? topicListMode,
  }) {
    _sessionLimitContentSize = limitContentSize ?? _sessionLimitContentSize;
    _sessionDisableGifAnimations =
        disableGifAnimations ?? _sessionDisableGifAnimations;
    _sessionTextScale = textScale ?? _sessionTextScale;
    _sessionThemeMode = themeMode ?? _sessionThemeMode;
    _sessionTopicListLargerText =
        topicListLargerText ?? _sessionTopicListLargerText;
    _sessionTopicListShowTags = topicListShowTags ?? _sessionTopicListShowTags;
    _sessionTopicListShowLastPoster =
        topicListShowLastPoster ?? _sessionTopicListShowLastPoster;
    _sessionTopicListShowAssignments =
        topicListShowAssignments ?? _sessionTopicListShowAssignments;
    _sessionTopicListMode = topicListMode ?? _sessionTopicListMode;
    return _operations.write<void>(
      owner: _persistence,
      key: _operationKey,
      operation: () => _persist(
        limitContentSize: limitContentSize,
        disableGifAnimations: disableGifAnimations,
        textScale: textScale,
        themeMode: themeMode,
        topicListLargerText: topicListLargerText,
        topicListShowTags: topicListShowTags,
        topicListShowLastPoster: topicListShowLastPoster,
        topicListShowAssignments: topicListShowAssignments,
        topicListMode: topicListMode,
      ),
    );
  }

  Future<void> _persist({
    bool? limitContentSize,
    bool? disableGifAnimations,
    AppTextScale? textScale,
    AppThemeMode? themeMode,
    bool? topicListLargerText,
    bool? topicListShowTags,
    bool? topicListShowLastPoster,
    bool? topicListShowAssignments,
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
      if (topicListShowTags != null &&
          !await _persistence.writeTopicListShowTags(topicListShowTags)) {
        throw StateError('Could not persist topicListShowTags.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeTopicListShowTags',
      );
    }
    try {
      if (topicListShowLastPoster != null &&
          !await _persistence.writeTopicListShowLastPoster(
            topicListShowLastPoster,
          )) {
        throw StateError('Could not persist topicListShowLastPoster.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeTopicListShowLastPoster',
      );
    }
    try {
      if (topicListShowAssignments != null &&
          !await _persistence.writeTopicListShowAssignments(
            topicListShowAssignments,
          )) {
        throw StateError('Could not persist topicListShowAssignments.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeTopicListShowAssignments',
      );
    }
    try {
      if (limitContentSize != null &&
          !await _persistence.writeLimitContentSize(limitContentSize)) {
        throw StateError('Could not persist the content size limit.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'appSettings.writeLimitContentSize',
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

AppTextScale _appTextScaleByName(String? name) {
  for (final scale in AppTextScale.values) {
    if (scale.name == name) return scale;
  }
  return AppTextScale.percent100;
}
