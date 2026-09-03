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
}
