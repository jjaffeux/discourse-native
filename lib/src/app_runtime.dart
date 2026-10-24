import 'dart:async';
import 'dart:collection';

import 'data/app_settings_store.dart';
import 'data/authenticator.dart';
import 'data/destination_bookmarks_store.dart';
import 'data/discourse_api.dart';
import 'data/draft_store.dart';
import 'data/forum_settings_store.dart';
import 'data/forum_tab_store.dart';
import 'data/instance_store.dart';
import 'data/recent_destinations_store.dart';
import 'data/site_tracker.dart';
import 'data/update_store.dart';
import 'data/updater.dart';
import 'plugin_api/core_plugin_manifest.dart';
import 'plugin_api/plugin_runtime.dart';
import 'shell/shell_controller.dart';

part 'app_notification_ingress.dart';

final class AppRuntimeDependencies {
  const AppRuntimeDependencies({
    this.store,
    this.api,
    this.authenticator,
    this.appSettingsStore,
    this.forumSettingsStore,
    this.drafts,
    this.forumTabs,
    this.trackers,
    this.updater,
    this.updateStore,
    this.plugins,
    this.pluginManifest = corePluginManifest,
    this.initialRootMode = ShellRootMode.forum,
    this.forumTabsEnabled = false,
    this.mobileNavigationEnabled = false,
  });

  final InstanceStore? store;
  final ShellApiCapabilities? api;
  final Authenticator? authenticator;
  final AppSettingsStore? appSettingsStore;
  final ForumSettingsStore? forumSettingsStore;
  final DraftStore? drafts;
  final ForumTabStore? forumTabs;
  final SiteTrackerFactory? trackers;
  final Updater? updater;
  final UpdateStore? updateStore;
  final InstalledPlugins? plugins;
  final PluginManifest pluginManifest;
  final ShellRootMode initialRootMode;
  final bool forumTabsEnabled;
  final bool mobileNavigationEnabled;

  bool _hasSamePluginsAs(AppRuntimeDependencies other) =>
      identical(plugins, other.plugins) &&
      (plugins != null || pluginManifest == other.pluginManifest);

  bool _hasSameServicesAs(AppRuntimeDependencies other) =>
      identical(store, other.store) &&
      identical(api, other.api) &&
      identical(authenticator, other.authenticator) &&
      identical(appSettingsStore, other.appSettingsStore) &&
      identical(forumSettingsStore, other.forumSettingsStore) &&
      identical(drafts, other.drafts) &&
      identical(forumTabs, other.forumTabs) &&
      identical(trackers, other.trackers) &&
      identical(updater, other.updater) &&
      identical(updateStore, other.updateStore) &&
      _hasSamePluginsAs(other);
}

final class AppRuntime {
  AppRuntime({
    required AppRuntimeDependencies dependencies,
    required this._foreground,
    required this._lifecycleState,
  }) : _dependencies = dependencies {
    _plugins =
        dependencies.plugins ??
        PluginInstaller.install(dependencies.pluginManifest);
    _ownsPlugins = dependencies.plugins == null;
    _store = dependencies.store ?? InstanceStore(models: _plugins.models);
    _api = dependencies.api ?? DiscourseApi(models: _plugins.models);
    _authenticator = dependencies.authenticator ?? Authenticator();
    _appSettingsStore = dependencies.appSettingsStore ?? AppSettingsStore();
    _forumSettingsStore =
        dependencies.forumSettingsStore ?? ForumSettingsStore();
    _drafts = dependencies.drafts ?? DraftStore();
    _forumTabs = dependencies.forumTabs ?? ForumTabStore();
    _trackers = dependencies.trackers ?? SiteTracker.new;
    _updater = dependencies.updater ?? const UnsupportedUpdater();
    _updateStore = dependencies.updateStore ?? UpdateStore();
    _controller = _createController()..setForeground(_foreground);
  }

  static const Duration exitFlushTimeout = Duration(milliseconds: 1500);

  AppRuntimeDependencies _dependencies;
  late InstanceStore _store;
  late ShellApiCapabilities _api;
  late Authenticator _authenticator;
  late AppSettingsStore _appSettingsStore;
  late ForumSettingsStore _forumSettingsStore;
  late DraftStore _drafts;
  late ForumTabStore _forumTabs;
  final _recentDestinations = RecentDestinationsStore();
  final _destinationBookmarks = DestinationBookmarksStore();
  late SiteTrackerFactory _trackers;
  late Updater _updater;
  late UpdateStore _updateStore;
  late ShellController _controller;
  late InstalledPlugins _plugins;
  late bool _ownsPlugins;
  bool _foreground;
  String _lifecycleState;
  bool _disposed = false;
  final _notificationIngress = _NotificationIngress();

  ShellController get controller => _controller;

  ShellController _createController() => ShellController(
    instanceStore: _store,
    api: _api,
    authenticator: _authenticator,
    appSettingsStore: _appSettingsStore,
    forumSettingsStore: _forumSettingsStore,
    drafts: _drafts,
    forumTabs: _forumTabs,
    recentDestinations: _recentDestinations,
    destinationBookmarks: _destinationBookmarks,
    forumTabsEnabled: _dependencies.forumTabsEnabled,
    mobileNavigationEnabled: _dependencies.mobileNavigationEnabled,
    trackers: _trackers,
    updater: _updater,
    updateStore: _updateStore,
    plugins: _plugins,

    ownsApi: false,
    initialRootMode: _dependencies.mobileNavigationEnabled
        ? ShellRootMode.forum
        : _dependencies.initialRootMode,
  );

  bool replace(AppRuntimeDependencies dependencies) {
    if (_disposed) return false;
    final previous = _dependencies;
    _dependencies = dependencies;
    if (dependencies._hasSameServicesAs(previous)) return false;

    _notificationIngress.unavailable();
    final previousController = _controller;
    final previousPlugins = _plugins;
    final previousOwnsPlugins = _ownsPlugins;
    previousController.dispose();
    final pluginsChanged = !dependencies._hasSamePluginsAs(previous);
    final previousTeardown = pluginsChanged && previousOwnsPlugins
        ? _closePlugins(
            previousPlugins,
            after: previousController.pluginTeardown,
          )
        : _settled(previousController.pluginTeardown);
    if (pluginsChanged) {
      _plugins =
          _dependencies.plugins ??
          PluginInstaller.install(_dependencies.pluginManifest);
      _ownsPlugins = _dependencies.plugins == null;
    }
    if (!identical(_dependencies.store, previous.store) ||
        (pluginsChanged && _dependencies.store == null)) {
      _store = _dependencies.store ?? InstanceStore(models: _plugins.models);
    }
    if (!identical(_dependencies.api, previous.api) ||
        (pluginsChanged && _dependencies.api == null)) {
      _closeApiAfter(_api, previousTeardown);
      _api = _dependencies.api ?? DiscourseApi(models: _plugins.models);
    }
    if (!identical(_dependencies.authenticator, previous.authenticator)) {
      _authenticator = _dependencies.authenticator ?? Authenticator();
    }
    if (!identical(_dependencies.appSettingsStore, previous.appSettingsStore)) {
      _appSettingsStore = _dependencies.appSettingsStore ?? AppSettingsStore();
    }
    if (!identical(
      _dependencies.forumSettingsStore,
      previous.forumSettingsStore,
    )) {
      _forumSettingsStore =
          _dependencies.forumSettingsStore ?? ForumSettingsStore();
    }
    if (!identical(_dependencies.drafts, previous.drafts)) {
      _drafts = _dependencies.drafts ?? DraftStore();
    }
    if (!identical(_dependencies.forumTabs, previous.forumTabs)) {
      _forumTabs = _dependencies.forumTabs ?? ForumTabStore();
    }
    if (!identical(_dependencies.trackers, previous.trackers)) {
      _trackers = _dependencies.trackers ?? SiteTracker.new;
    }
    if (!identical(_dependencies.updater, previous.updater)) {
      _updater = _dependencies.updater ?? const UnsupportedUpdater();
    }
    if (!identical(_dependencies.updateStore, previous.updateStore)) {
      _updateStore = _dependencies.updateStore ?? UpdateStore();
    }
    _controller = _createController()..setForeground(_foreground);
    return true;
  }

  Future<void> start(ShellController expectedController) async {
    if (!_isCurrent(expectedController)) return;
    final plugins = _plugins;
    final controller = expectedController;
    final _ = controller.pluginSession;
    var pluginsStarted = false;
    try {
      await plugins.startPhase(
        PluginStartupPhase.bootstrap,
        bindings: const PluginHostBindings.empty(),
      );
      if (!_isCurrent(controller)) return;
      await _observePluginAppState(plugins, _lifecycleState);
      pluginsStarted = true;
    } catch (_) {}
    if (!_isCurrent(controller)) return;
    try {
      await controller.load();
      if (!_isCurrent(controller)) return;
      _notificationIngress.ready(controller.openNotificationUrl);
      if (pluginsStarted) {
        await plugins.startPhase(
          PluginStartupPhase.appReady,
          bindings: const PluginHostBindings.empty(),
        );
      }
    } catch (_) {}
  }

  Future<void> _closePlugins(
    InstalledPlugins plugins, {
    required Future<void> after,
  }) => _settled(after)
      .then((_) => plugins.close())
      .onError((Object error, StackTrace stackTrace) {});

  /// Plugins leave the session over the API transport — Voice tells the site
  /// it left the room — so the transport stays open until they have, whether
  /// the app is going away or swapping the API underneath a new controller.
  void _closeApiAfter(ShellApiCapabilities api, Future<void> teardown) {
    unawaited(teardown.whenComplete(api.close));
  }

  static Future<void> _settled(Future<void> future) =>
      future.then<void>((_) {}, onError: (Object _, StackTrace _) {});

  bool _isCurrent(ShellController controller) =>
      !_disposed && identical(_controller, controller);

  void listenNotificationOpens(Stream<String> urls) {
    _notificationIngress.listen(urls);
  }

  void observeAppState(String state, {required bool foreground}) {
    if (_disposed) return;
    _lifecycleState = state;
    _foreground = foreground;
    unawaited(_observePluginAppState(_plugins, state));
    _controller.setForeground(foreground);
    if (!foreground) unawaited(_flushPlugins(_plugins));
  }

  Future<void> flushForExit() async {
    await Future.wait([
      _controller.flushForExit(),
      _flushPlugins(_plugins),
    ]).timeout(exitFlushTimeout, onTimeout: () => const []);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _notificationIngress.dispose();
    final controller = _controller;
    controller.dispose();
    final teardown = _ownsPlugins
        ? _closePlugins(_plugins, after: controller.pluginTeardown)
        : _settled(controller.pluginTeardown);
    _closeApiAfter(_api, teardown);
  }

  Future<void> _observePluginAppState(
    InstalledPlugins plugins,
    String state,
  ) async {
    try {
      await plugins.observeAppState(state, foreground: _foreground);
    } catch (_) {}
  }

  Future<void> _flushPlugins(InstalledPlugins plugins) async {
    try {
      await plugins.flush();
    } catch (_) {}
  }
}
