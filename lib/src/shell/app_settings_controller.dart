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

  int _mutationRevision = 0;
  Future<void>? _loadTask;

  Future<void> load() {
    if (isDisposed) return Future<void>.value();
    final active = _loadTask;
    if (active != null) return active;
    if (_loaded) return Future<void>.value();

    final revision = _mutationRevision;
    late final Future<void> task;
    task = _load(revision).whenComplete(() {
      if (identical(_loadTask, task)) _loadTask = null;
    });
    _loadTask = task;
    return task;
  }

  Future<void> _load(int revision) async {
    final loaded = await store.read();
    if (isDisposed || revision != _mutationRevision) return;
    _settings = loaded;
    _loaded = true;
    notifySafely();
  }

  Future<void> setContentAlignment(ContentAlignment alignment) {
    if (isDisposed || (_loaded && alignment == contentAlignment)) {
      return Future<void>.value();
    }

    _mutationRevision++;
    _settings = _settings.copyWith(contentAlignment: alignment);
    _loaded = true;
    notifySafely();
    return store.write(_settings);
  }

  Future<void> setDisableGifAnimations(bool disabled) {
    if (isDisposed || (_loaded && disabled == disableGifAnimations)) {
      return Future<void>.value();
    }

    _mutationRevision++;
    _settings = _settings.copyWith(disableGifAnimations: disabled);
    _loaded = true;
    notifySafely();
    return store.write(_settings);
  }

  Future<void> setTextScale(AppTextScale scale) {
    if (isDisposed || (_loaded && scale == textScale)) {
      return Future<void>.value();
    }

    _mutationRevision++;
    _settings = _settings.copyWith(textScale: scale);
    _loaded = true;
    notifySafely();
    return store.write(_settings);
  }

  Future<void> increaseTextScale() {
    if (!_loaded) return _changeTextScaleAfterLoad(increaseTextScale);
    final index = textScale.index;
    if (index == AppTextScale.values.length - 1) {
      return Future<void>.value();
    }
    return setTextScale(AppTextScale.values[index + 1]);
  }

  Future<void> decreaseTextScale() {
    if (!_loaded) return _changeTextScaleAfterLoad(decreaseTextScale);
    final index = textScale.index;
    if (index == 0) return Future<void>.value();
    return setTextScale(AppTextScale.values[index - 1]);
  }

  Future<void> resetTextScale() {
    if (!_loaded) return _changeTextScaleAfterLoad(resetTextScale);
    return setTextScale(AppTextScale.percent100);
  }

  Future<void> _changeTextScaleAfterLoad(Future<void> Function() change) async {
    await load();
    if (isDisposed) return;
    await change();
  }
}
