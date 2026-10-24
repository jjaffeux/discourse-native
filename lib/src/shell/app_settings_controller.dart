import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;

import '../data/app_settings_store.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/app_settings.dart';

enum AppSettingsSaveStatus { unconfirmed, pending, saved, failed }

final class AppSettingsSaveState {
  const AppSettingsSaveState._(this.status, [this.failure]);

  static const unconfirmed = AppSettingsSaveState._(
    AppSettingsSaveStatus.unconfirmed,
  );
  static const pending = AppSettingsSaveState._(AppSettingsSaveStatus.pending);
  static const saved = AppSettingsSaveState._(AppSettingsSaveStatus.saved);

  final AppSettingsSaveStatus status;
  final AppSettingsWriteFailure? failure;
}

final class _SettingChoice<T extends Object> {
  T? value;
  Object? writeIdentity;
  Future<void>? pending;
  AppSettingsSaveState state = AppSettingsSaveState.unconfirmed;
}

final class AppSettingsController extends FrameSafeNotifier {
  AppSettingsController({AppSettingsStore? store})
    : store = store ?? AppSettingsStore();

  final AppSettingsStore store;

  AppSettings _settings = AppSettings.defaults;
  AppSettings get settings => _settings;
  bool get limitContentSize => _settings.limitContentSize;
  bool get disableGifAnimations => _settings.disableGifAnimations;
  bool? get reduceMotion => _settings.reduceMotion;
  bool get rawMarkdownComposers => _settings.rawMarkdownComposers;
  AppTextScale get textScale => _settings.textScale;
  AppThemeMode get themeMode => _settings.themeMode;
  TopicListDisplayMode get topicListMode => _settings.topicListMode;
  double get textScaleFactor => textScale.factor;

  bool _loaded = false;
  bool get loaded => _loaded;

  final _limitContentSize = _SettingChoice<bool>();
  final _disableGifAnimations = _SettingChoice<bool>();
  final _reduceMotion = _SettingChoice<bool>();
  final _rawMarkdownComposers = _SettingChoice<bool>();
  final _textScale = _SettingChoice<AppTextScale>();
  final _themeMode = _SettingChoice<AppThemeMode>();
  final _topicListMode = _SettingChoice<TopicListDisplayMode>();
  final _saveStates =
      FrameSafeValueNotifier<Map<AppSettingsField, AppSettingsSaveState>>(
        Map.unmodifiable({
          for (final field in AppSettingsField.values)
            field: AppSettingsSaveState.unconfirmed,
        }),
      );

  ValueListenable<Map<AppSettingsField, AppSettingsSaveState>> get saveStates =>
      _saveStates;

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
      limitContentSize: _limitContentSize.value,
      disableGifAnimations: _disableGifAnimations.value,
      reduceMotion: _reduceMotion.value,
      rawMarkdownComposers: _rawMarkdownComposers.value,
      textScale: _textScale.value,
      themeMode: _themeMode.value,
      topicListMode: _topicListMode.value,
    );
    _loaded = true;
    notifySafely();
  }

  Future<void> setLimitContentSize(bool value) => _select(
    _limitContentSize,
    AppSettingsField.limitContentSize,
    value,
    current: limitContentSize,
    apply: () => _settings = _settings.copyWith(limitContentSize: value),
    persist: () => store.update(limitContentSize: value),
  );

  Future<void> setDisableGifAnimations(bool value) => _select(
    _disableGifAnimations,
    AppSettingsField.disableGifAnimations,
    value,
    current: disableGifAnimations,
    apply: () => _settings = _settings.copyWith(disableGifAnimations: value),
    persist: () => store.update(disableGifAnimations: value),
  );

  Future<void> setReduceMotion(bool value) => _select(
    _reduceMotion,
    AppSettingsField.reduceMotion,
    value,
    current: reduceMotion,
    apply: () => _settings = _settings.copyWith(reduceMotion: value),
    persist: () => store.update(reduceMotion: value),
  );

  Future<void> setRawMarkdownComposers(bool value) => _select(
    _rawMarkdownComposers,
    AppSettingsField.rawMarkdownComposers,
    value,
    current: rawMarkdownComposers,
    apply: () => _settings = _settings.copyWith(rawMarkdownComposers: value),
    persist: () => store.update(rawMarkdownComposers: value),
  );

  Future<void> setTextScale(AppTextScale value) => _select(
    _textScale,
    AppSettingsField.textScale,
    value,
    current: textScale,
    apply: () => _settings = _settings.copyWith(textScale: value),
    persist: () => store.update(textScale: value),
  );

  Future<void> setThemeMode(AppThemeMode value) => _select(
    _themeMode,
    AppSettingsField.themeMode,
    value,
    current: themeMode,
    apply: () => _settings = _settings.copyWith(themeMode: value),
    persist: () => store.update(themeMode: value),
  );

  Future<void> setTopicListMode(TopicListDisplayMode value) => _select(
    _topicListMode,
    AppSettingsField.topicListMode,
    value,
    current: topicListMode,
    apply: () => _settings = _settings.copyWith(topicListMode: value),
    persist: () => store.update(topicListMode: value),
  );

  Future<void> _select<T extends Object>(
    _SettingChoice<T> choice,
    AppSettingsField field,
    T value, {
    required T? current,
    required void Function() apply,
    required Future<AppSettingsWriteResult> Function() persist,
  }) {
    if (isDisposed) return Future<void>.value();
    if (choice.value == value) {
      final pending = choice.pending;
      if (pending != null) return pending;
      if (choice.state.status == AppSettingsSaveStatus.saved) {
        return Future<void>.value();
      }
    }

    final settingsChanged =
        choice.value != value && (!_loaded || current != value);
    choice.value = value;
    final identity = Object();
    choice.writeIdentity = identity;
    choice.state = AppSettingsSaveState.pending;
    apply();
    final saving = _save(choice, field, identity, persist);
    choice.pending = saving;
    unawaited(load());
    _publishSaveStates();
    if (settingsChanged) notifySafely();
    return saving;
  }

  Future<void> _save<T extends Object>(
    _SettingChoice<T> choice,
    AppSettingsField field,
    Object identity,
    Future<AppSettingsWriteResult> Function() persist,
  ) async {
    AppSettingsWriteFailure? failure;
    try {
      final result = await persist();
      failure = result.failures[field];
      if (failure == null && !result.saved.contains(field)) {
        throw StateError('Missing persistence outcome for ${field.name}.');
      }
    } catch (error, stackTrace) {
      failure = AppSettingsWriteFailure(error, stackTrace);
    }
    if (isDisposed || !identical(choice.writeIdentity, identity)) return;
    choice.pending = null;
    choice.state = failure == null
        ? AppSettingsSaveState.saved
        : AppSettingsSaveState._(AppSettingsSaveStatus.failed, failure);
    _publishSaveStates();
  }

  void _publishSaveStates() {
    _saveStates.value = Map.unmodifiable({
      AppSettingsField.limitContentSize: _limitContentSize.state,
      AppSettingsField.disableGifAnimations: _disableGifAnimations.state,
      AppSettingsField.reduceMotion: _reduceMotion.state,
      AppSettingsField.rawMarkdownComposers: _rawMarkdownComposers.state,
      AppSettingsField.textScale: _textScale.state,
      AppSettingsField.themeMode: _themeMode.state,
      AppSettingsField.topicListMode: _topicListMode.state,
    });
  }

  @override
  void dispose() {
    _saveStates.dispose();
    super.dispose();
  }

  Future<void> increaseTextScale() {
    if (!_loaded && _textScale.value == null) {
      return _changeTextScaleAfterLoad(increaseTextScale);
    }
    final index = textScale.index;
    if (index == AppTextScale.values.length - 1) {
      return Future<void>.value();
    }
    return setTextScale(AppTextScale.values[index + 1]);
  }

  Future<void> decreaseTextScale() {
    if (!_loaded && _textScale.value == null) {
      return _changeTextScaleAfterLoad(decreaseTextScale);
    }
    final index = textScale.index;
    if (index == 0) return Future<void>.value();
    return setTextScale(AppTextScale.values[index - 1]);
  }

  Future<void> resetTextScale() {
    if (!_loaded && _textScale.value == null) {
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
