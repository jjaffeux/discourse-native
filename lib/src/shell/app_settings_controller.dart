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
  ContentAlignment get contentAlignment => _settings.contentAlignment;
  bool get disableGifAnimations => _settings.disableGifAnimations;
  AppTextScale get textScale => _settings.textScale;
  double get textScaleFactor => textScale.factor;

  bool _loaded = false;
  bool get loaded => _loaded;

  ContentAlignment? _selectedContentAlignment;
  bool? _selectedDisableGifAnimations;
  AppTextScale? _selectedTextScale;
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
      contentAlignment: _selectedContentAlignment,
      disableGifAnimations: _selectedDisableGifAnimations,
      textScale: _selectedTextScale,
    );
    _loaded = true;
    notifySafely();
  }

  Future<void> setContentAlignment(ContentAlignment alignment) {
    if (isDisposed ||
        ((_loaded || _selectedContentAlignment != null) &&
            alignment == contentAlignment)) {
      return Future<void>.value();
    }

    _selectedContentAlignment = alignment;
    _settings = _settings.copyWith(contentAlignment: alignment);
    final saving = store.update(contentAlignment: alignment);
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
