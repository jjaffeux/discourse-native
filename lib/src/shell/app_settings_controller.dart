import 'dart:async';

import '../data/app_settings_store.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/app_settings.dart';

final class AppSettingsController extends FrameSafeNotifier {
  AppSettingsController({AppSettingsStore? store})
    : store = store ?? AppSettingsStore();

  final AppSettingsStore store;

  AppSettings _settings = AppSettings.defaults;
  AppSettings get settings => _settings;
  bool get limitContentSize => _settings.limitContentSize;
  bool get disableGifAnimations => _settings.disableGifAnimations;
  AppTextScale get textScale => _settings.textScale;
  AppThemeMode get themeMode => _settings.themeMode;
  bool get topicListLargerText => _settings.topicListLargerText;
  bool get topicListShowTags => _settings.topicListShowTags;
  bool get topicListShowLastPoster => _settings.topicListShowLastPoster;
  bool get topicListShowAssignments => _settings.topicListShowAssignments;
  TopicListDisplayMode get topicListMode => _settings.topicListMode;
  double get textScaleFactor => textScale.factor;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool? _selectedLimitContentSize;
  bool? _selectedDisableGifAnimations;
  AppTextScale? _selectedTextScale;
  AppThemeMode? _selectedThemeMode;
  bool? _selectedTopicListLargerText;
  bool? _selectedTopicListShowTags;
  bool? _selectedTopicListShowLastPoster;
  bool? _selectedTopicListShowAssignments;
  TopicListDisplayMode? _selectedTopicListMode;
  Future<void>? _loadTask;

  Future<void> load() {
    if (isDisposed) return Future<void>.value();
    final active = _loadTask;
    if (active != null) return active;
    if (_loaded) return Future<void>.value();

    late final Future<void> task;
    task = _load().whenComplete(() {
      if (identical(_loadTask, task)) _loadTask = null;
    });
    _loadTask = task;
    return task;
  }

  Future<void> _load() async {
    final loaded = await store.read();
    if (isDisposed) return;
    // A choice can arrive even after the store's read future has completed.
    _settings = loaded.copyWith(
      limitContentSize: _selectedLimitContentSize,
      disableGifAnimations: _selectedDisableGifAnimations,
      textScale: _selectedTextScale,
      themeMode: _selectedThemeMode,
      topicListLargerText: _selectedTopicListLargerText,
      topicListShowTags: _selectedTopicListShowTags,
      topicListShowLastPoster: _selectedTopicListShowLastPoster,
      topicListShowAssignments: _selectedTopicListShowAssignments,
      topicListMode: _selectedTopicListMode,
    );
    _loaded = true;
    notifySafely();
  }

  Future<void> setLimitContentSize(bool enabled) {
    if (isDisposed ||
        ((_loaded || _selectedLimitContentSize != null) &&
            enabled == limitContentSize)) {
      return Future<void>.value();
    }

    _selectedLimitContentSize = enabled;
    _settings = _settings.copyWith(limitContentSize: enabled);
    final saving = store.update(limitContentSize: enabled);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setDisableGifAnimations(bool disabled) {
    if (isDisposed ||
        ((_loaded || _selectedDisableGifAnimations != null) &&
            disabled == disableGifAnimations)) {
      return Future<void>.value();
    }

    _selectedDisableGifAnimations = disabled;
    _settings = _settings.copyWith(disableGifAnimations: disabled);
    final saving = store.update(disableGifAnimations: disabled);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setTextScale(AppTextScale scale) {
    if (isDisposed ||
        ((_loaded || _selectedTextScale != null) && scale == textScale)) {
      return Future<void>.value();
    }

    _selectedTextScale = scale;
    _settings = _settings.copyWith(textScale: scale);
    final saving = store.update(textScale: scale);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setThemeMode(AppThemeMode mode) {
    if (isDisposed ||
        ((_loaded || _selectedThemeMode != null) && mode == themeMode)) {
      return Future<void>.value();
    }

    _selectedThemeMode = mode;
    _settings = _settings.copyWith(themeMode: mode);
    final saving = store.update(themeMode: mode);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setTopicListLargerText(bool value) {
    if (isDisposed ||
        ((_loaded || _selectedTopicListLargerText != null) &&
            value == topicListLargerText)) {
      return Future<void>.value();
    }
    _selectedTopicListLargerText = value;
    _settings = _settings.copyWith(topicListLargerText: value);
    final saving = store.update(topicListLargerText: value);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setTopicListShowTags(bool value) {
    if (isDisposed ||
        ((_loaded || _selectedTopicListShowTags != null) &&
            value == topicListShowTags)) {
      return Future<void>.value();
    }
    _selectedTopicListShowTags = value;
    _settings = _settings.copyWith(topicListShowTags: value);
    final saving = store.update(topicListShowTags: value);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setTopicListShowLastPoster(bool value) {
    if (isDisposed ||
        ((_loaded || _selectedTopicListShowLastPoster != null) &&
            value == topicListShowLastPoster)) {
      return Future<void>.value();
    }
    _selectedTopicListShowLastPoster = value;
    _settings = _settings.copyWith(topicListShowLastPoster: value);
    final saving = store.update(topicListShowLastPoster: value);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setTopicListShowAssignments(bool value) {
    if (isDisposed ||
        ((_loaded || _selectedTopicListShowAssignments != null) &&
            value == topicListShowAssignments)) {
      return Future<void>.value();
    }
    _selectedTopicListShowAssignments = value;
    _settings = _settings.copyWith(topicListShowAssignments: value);
    final saving = store.update(topicListShowAssignments: value);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> setTopicListMode(TopicListDisplayMode mode) {
    if (isDisposed ||
        ((_loaded || _selectedTopicListMode != null) &&
            mode == topicListMode)) {
      return Future<void>.value();
    }
    _selectedTopicListMode = mode;
    _settings = _settings.copyWith(topicListMode: mode);
    final saving = store.update(topicListMode: mode);
    unawaited(load());
    notifySafely();
    return saving;
  }

  Future<void> increaseTextScale() {
    if (!_loaded && _selectedTextScale == null) {
      return _changeTextScaleAfterLoad(increaseTextScale);
    }
    final index = textScale.index;
    if (index == AppTextScale.values.length - 1) {
      return Future<void>.value();
    }
    return setTextScale(AppTextScale.values[index + 1]);
  }

  Future<void> decreaseTextScale() {
    if (!_loaded && _selectedTextScale == null) {
      return _changeTextScaleAfterLoad(decreaseTextScale);
    }
    final index = textScale.index;
    if (index == 0) return Future<void>.value();
    return setTextScale(AppTextScale.values[index - 1]);
  }

  Future<void> resetTextScale() {
    if (!_loaded && _selectedTextScale == null) {
      return _changeTextScaleAfterLoad(resetTextScale);
    }
    return setTextScale(AppTextScale.percent100);
  }

  Future<void> _changeTextScaleAfterLoad(Future<void> Function() change) async {
    await load();
    if (isDisposed) return;
    await change();
  }
}
