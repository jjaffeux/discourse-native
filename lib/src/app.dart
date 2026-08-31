import 'dart:async';
import 'dart:collection';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart'
    show PointerDownEvent, kBackMouseButton, kForwardMouseButton;
import 'package:flutter/material.dart';
import 'package:relative_time/relative_time.dart';

import 'data/app_settings_store.dart';
import 'data/authenticator.dart';
import 'data/discourse_api.dart';
import 'data/draft_store.dart';
import 'data/forum_tab_store.dart';
import 'data/instance_store.dart';
import 'data/notification_opens.dart';
import 'data/site_tracker.dart';
import 'data/update_store.dart';
import 'data/updater.dart';
import 'diagnostics/diagnostics.dart';
import 'foundation/timezone_environment.dart';
import 'models/site_appearance.dart';
import 'plugin_api/core_plugin_manifest.dart';
import 'plugin_api/plugin_runtime.dart';
import 'plugin_api/site_plugin_api.dart';
import 'shell/adaptive_shell.dart';
import 'shell/content_reading_lane.dart';
import 'shell/platform.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_scope.dart';
import 'theme/app_theme.dart';

class DiscourseApp extends StatefulWidget {
  const DiscourseApp({
    super.key,
    this.store,
    this.api,
    this.authenticator,
    this.appSettingsStore,
    this.drafts,
    this.forumTabs,
    this.trackers,
    this.updater,
    this.updateStore,
    this.diagnostics,
    this.plugins,
    this.pluginManifest = corePluginManifest,
    this.initialRootMode = ShellRootMode.aggregate,
    this.notificationOpenUrls,
  }) : assert(
         plugins == null || identical(pluginManifest, corePluginManifest),
         'Pass plugins or pluginManifest, not both.',
       );

  final InstanceStore? store;
  final ShellApiCapabilities? api;
  final Authenticator? authenticator;
  final AppSettingsStore? appSettingsStore;
  final DraftStore? drafts;
  final ForumTabStore? forumTabs;
  final SiteTrackerFactory? trackers;
  final Updater? updater;
  final UpdateStore? updateStore;
  final DiagnosticsController? diagnostics;
  final InstalledPlugins? plugins;
  final PluginManifest pluginManifest;
  final ShellRootMode initialRootMode;
  final Stream<String>? notificationOpenUrls;

  @override
  State<DiscourseApp> createState() => _DiscourseAppState();
}

class _DiscourseAppState extends State<DiscourseApp>
    with WidgetsBindingObserver {
  late InstanceStore _store;
  late ShellApiCapabilities _api;
  late Authenticator _authenticator;
  late AppSettingsStore _appSettingsStore;
  late DraftStore _drafts;
  late ForumTabStore _forumTabs;
  late SiteTrackerFactory _trackers;
  late Updater _updater;
  late UpdateStore _updateStore;
  DiagnosticsController? _pluginDiagnosticsSink;
  late final PluginDiagnosticsReporter _pluginDiagnosticsReporter;
  late ShellController _controller;
  late InstalledPlugins _plugins;
  late bool _ownsPlugins;
  late bool _foreground;
  late final PlatformNotificationOpens _platformNotificationOpens;
  StreamSubscription<String>? _notificationOpenSubscription;
  final Queue<String> _pendingNotificationUrls = Queue<String>();
  ShellController? _notificationNavigationController;
  bool _drainingNotificationUrls = false;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  static const _maximumPendingNotificationUrls = 16;

  ShellController _createController() => ShellController(
    instanceStore: _store,
    api: _api,
    authenticator: _authenticator,
    appSettingsStore: _appSettingsStore,
    drafts: _drafts,
    forumTabs: _forumTabs,
    forumTabsEnabled: forumTabsEnabledForCurrentPlatform,
    trackers: _trackers,
    // Linux is updated by apt and cannot replace its own /usr installation.
    updater: _updater,
    updateStore: _updateStore,
    plugins: _plugins,
    pluginDiagnosticsReporter: _pluginDiagnosticsReporter,
    ownsApi: false,
    initialRootMode: widget.initialRootMode,
  );

  @override
  void initState() {
    super.initState();
    _plugins = widget.plugins ?? PluginInstaller.install(widget.pluginManifest);
    _ownsPlugins = widget.plugins == null;
    _store = widget.store ?? InstanceStore(models: _plugins.models);
    _api = widget.api ?? DiscourseApi(models: _plugins.models);
    _authenticator = widget.authenticator ?? Authenticator();
    _appSettingsStore = widget.appSettingsStore ?? AppSettingsStore();
    _drafts = widget.drafts ?? DraftStore();
    _forumTabs = widget.forumTabs ?? ForumTabStore();
    _trackers = widget.trackers ?? SiteTracker.new;
    _updater = widget.updater ?? const UnsupportedUpdater();
    _updateStore = widget.updateStore ?? UpdateStore();
    _pluginDiagnosticsSink = widget.diagnostics;
    _pluginDiagnosticsReporter = PluginDiagnosticsReporter.resolving(
      () => _pluginDiagnosticsSink,
    );
    _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
    _controller = _createController()..setForeground(_foreground);
    _platformNotificationOpens = PlatformNotificationOpens();
    _listenToNotificationOpens(
      widget.notificationOpenUrls ?? _platformNotificationOpens.urls,
    );
    WidgetsBinding.instance.addObserver(this);
    _startAfterFirstFrame(_controller, _plugins);
  }

  @override
  void didUpdateWidget(DiscourseApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      widget.notificationOpenUrls,
      oldWidget.notificationOpenUrls,
    )) {
      _listenToNotificationOpens(
        widget.notificationOpenUrls ?? _platformNotificationOpens.urls,
      );
    }
    if (!identical(widget.diagnostics, oldWidget.diagnostics)) {
      // Repoint the stable, already-injected capability before releasing the
      // old recorder. Existing plugin lifecycles and sessions therefore cannot
      // write into a controller the app has begun closing.
      _pluginDiagnosticsSink = widget.diagnostics;
      _releaseDiagnostics(oldWidget.diagnostics);
    }
    if (!_dependenciesChanged(oldWidget)) return;

    _notificationNavigationController = null;
    final previousController = _controller;
    final previousPlugins = _plugins;
    final previousOwnsPlugins = _ownsPlugins;
    previousController.dispose();
    final pluginsChanged = _pluginsChanged(oldWidget);
    if (pluginsChanged && previousOwnsPlugins) {
      _closePlugins(previousPlugins, after: previousController.pluginTeardown);
    }
    _updateDependencies(oldWidget);
    _controller = _createController()..setForeground(_foreground);
    _startAfterFirstFrame(_controller, _plugins);
  }

  void _startAfterFirstFrame(
    ShellController controller,
    InstalledPlugins plugins,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_controller, controller)) return;
      unawaited(_start(controller, plugins));
    });
  }

  bool _dependenciesChanged(DiscourseApp oldWidget) =>
      !identical(widget.store, oldWidget.store) ||
      !identical(widget.api, oldWidget.api) ||
      !identical(widget.authenticator, oldWidget.authenticator) ||
      !identical(widget.appSettingsStore, oldWidget.appSettingsStore) ||
      !identical(widget.drafts, oldWidget.drafts) ||
      !identical(widget.forumTabs, oldWidget.forumTabs) ||
      !identical(widget.trackers, oldWidget.trackers) ||
      !identical(widget.updater, oldWidget.updater) ||
      !identical(widget.updateStore, oldWidget.updateStore) ||
      !identical(widget.plugins, oldWidget.plugins) ||
      (widget.plugins == null &&
          widget.pluginManifest != oldWidget.pluginManifest);

  bool _pluginsChanged(DiscourseApp oldWidget) =>
      !identical(widget.plugins, oldWidget.plugins) ||
      (widget.plugins == null &&
          widget.pluginManifest != oldWidget.pluginManifest);

  void _updateDependencies(DiscourseApp oldWidget) {
    final pluginsChanged = _pluginsChanged(oldWidget);
    if (pluginsChanged) {
      _plugins =
          widget.plugins ?? PluginInstaller.install(widget.pluginManifest);
      _ownsPlugins = widget.plugins == null;
    }
    if (!identical(widget.store, oldWidget.store) ||
        (pluginsChanged && widget.store == null)) {
      _store = widget.store ?? InstanceStore(models: _plugins.models);
    }
    if (!identical(widget.api, oldWidget.api) ||
        (pluginsChanged && widget.api == null)) {
      _api.close();
      _api = widget.api ?? DiscourseApi(models: _plugins.models);
    }
    if (!identical(widget.authenticator, oldWidget.authenticator)) {
      _authenticator = widget.authenticator ?? Authenticator();
    }
    if (!identical(widget.appSettingsStore, oldWidget.appSettingsStore)) {
      _appSettingsStore = widget.appSettingsStore ?? AppSettingsStore();
    }
    if (!identical(widget.drafts, oldWidget.drafts)) {
      _drafts = widget.drafts ?? DraftStore();
    }
    if (!identical(widget.forumTabs, oldWidget.forumTabs)) {
      _forumTabs = widget.forumTabs ?? ForumTabStore();
    }
    if (!identical(widget.trackers, oldWidget.trackers)) {
      _trackers = widget.trackers ?? SiteTracker.new;
    }
    if (!identical(widget.updater, oldWidget.updater)) {
      _updater = widget.updater ?? const UnsupportedUpdater();
    }
    if (!identical(widget.updateStore, oldWidget.updateStore)) {
      _updateStore = widget.updateStore ?? UpdateStore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notificationOpenSubscription?.cancel());
    final controller = _controller;
    controller.dispose();
    _api.close();
    if (_ownsPlugins) {
      _closePlugins(_plugins, after: controller.pluginTeardown);
    }
    _pluginDiagnosticsSink = null;
    _releaseDiagnostics(widget.diagnostics);
    super.dispose();
  }

  Future<void> _start(
    ShellController controller,
    InstalledPlugins plugins,
  ) async {
    try {
      await plugins.startPhase(
        PluginStartupPhase.bootstrap,
        bindings: _pluginHostBindings,
      );
      if (!mounted || !identical(_controller, controller)) return;
      await _observePluginAppState(
        plugins,
        WidgetsBinding.instance.lifecycleState?.name ?? 'unknown',
      );
      await controller.load();
      if (!mounted || !identical(_controller, controller)) return;
      _notificationNavigationController = controller;
      _drainNotificationUrls();
      await plugins.startPhase(
        PluginStartupPhase.appReady,
        bindings: _pluginHostBindings,
      );
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'app.plugins.start',
        source: 'plugins',
        severity: DiagnosticSeverity.error,
        handled: true,
        degraded: true,
      );
    }
  }

  void _listenToNotificationOpens(Stream<String> urls) {
    unawaited(_notificationOpenSubscription?.cancel());
    _notificationOpenSubscription = urls.listen(
      _queueNotificationUrl,
      onError: (Object error, StackTrace stackTrace) {
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'push.notificationOpens',
          source: 'push',
          severity: DiagnosticSeverity.warning,
          handled: true,
          degraded: false,
        );
      },
    );
  }

  void _queueNotificationUrl(String url) {
    if (url.isEmpty) return;
    _pendingNotificationUrls.addLast(url);
    if (_pendingNotificationUrls.length > _maximumPendingNotificationUrls) {
      _pendingNotificationUrls.removeFirst();
    }
    _drainNotificationUrls();
  }

  void _drainNotificationUrls() {
    final controller = _controller;
    if (_drainingNotificationUrls ||
        _pendingNotificationUrls.isEmpty ||
        !identical(_notificationNavigationController, controller)) {
      return;
    }
    _drainingNotificationUrls = true;
    unawaited(_drainNotificationUrlsWith(controller));
  }

  Future<void> _drainNotificationUrlsWith(ShellController controller) async {
    try {
      while (mounted &&
          identical(_controller, controller) &&
          _pendingNotificationUrls.isNotEmpty) {
        final url = _pendingNotificationUrls.first;
        try {
          await controller.openNotificationUrl(url);
        } catch (error, stackTrace) {
          DiagnosticsSink.current.reportError(
            error,
            stackTrace,
            operation: 'push.openNotification',
            source: 'push',
            severity: DiagnosticSeverity.warning,
            handled: true,
            degraded: false,
          );
        }
        if (!mounted || !identical(_controller, controller)) return;
        _pendingNotificationUrls.removeFirst();
      }
    } finally {
      _drainingNotificationUrls = false;
      if (mounted) _drainNotificationUrls();
    }
  }

  void _closePlugins(InstalledPlugins plugins, {Future<void>? after}) {
    unawaited(
      _closePluginsAfterSession(plugins, after).onError((
        Object error,
        StackTrace stackTrace,
      ) {
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'app.plugins.close',
          source: 'plugins',
          severity: DiagnosticSeverity.warning,
          handled: true,
          degraded: true,
        );
      }),
    );
  }

  Future<void> _closePluginsAfterSession(
    InstalledPlugins plugins,
    Future<void>? sessionTeardown,
  ) async {
    if (sessionTeardown != null) {
      try {
        await sessionTeardown;
      } on Object {
        // ShellController already observes session teardown failures. App
        // lifecycle cleanup must still close the installed runtime.
      }
    }
    await plugins.close();
  }

  void _releaseDiagnostics(DiagnosticsController? diagnostics) {
    if (diagnostics == null) return;
    unawaited(
      diagnostics.close().onError((Object error, StackTrace stackTrace) {
        // The app cannot await teardown from a widget lifecycle callback, but
        // a persistence-close failure must still be observed rather than
        // escaping as an unhandled asynchronous error.
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'app.diagnostics.close',
          source: 'diagnostics',
          severity: DiagnosticSeverity.warning,
          handled: true,
          degraded: false,
        );
      }),
    );
  }

  /// `inactive` is transient (for example, a system dialog), so only hidden,
  /// paused, and detached states pace down the live connection.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    unawaited(_observePluginAppState(_plugins, state.name));
    _controller.setForeground(_foreground);
    if (state == AppLifecycleState.resumed) {
      unawaited(
        TimezoneEnvironment.instance.refreshDeviceTimezone(forceNotify: true),
      );
    }
    if (!_foreground) {
      unawaited(widget.diagnostics?.flush());
      unawaited(_flushPlugins(_plugins));
    }
  }

  static bool _isForeground(AppLifecycleState? state) =>
      state != AppLifecycleState.hidden &&
      state != AppLifecycleState.paused &&
      state != AppLifecycleState.detached;

  @override
  Widget build(BuildContext context) {
    // Above MaterialApp so that sheets and dialogs, which build under its
    // Navigator, can still reach the controller.
    final app = ShellScope(
      controller: _controller,
      child: ContentAlignmentScope(
        controller: _controller.appSettings,
        child: ShellSelector<_AppThemeSelection>(
          select: _AppThemeSelection.from,
          builder: (context, selection, _) {
            final appearance = selection.appearance;
            final base = appearance?.base ?? appearance?.alternate;
            if (appearance == null || base == null) {
              return _materialApp(
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: ThemeMode.system,
              );
            }

            final baseTheme = AppTheme.fromPalette(base);
            final alternate = appearance.alternate;
            final alternateTheme = AppTheme.fromPalette(
              alternate ?? appearance.base ?? base,
            );
            final themeMode = switch (appearance.mode) {
              SiteAppearanceMode.followSystem when alternate != null =>
                ThemeMode.system,
              SiteAppearanceMode.alternate when alternate != null =>
                ThemeMode.dark,
              SiteAppearanceMode.followSystem ||
              SiteAppearanceMode.base ||
              SiteAppearanceMode.alternate => ThemeMode.light,
            };
            return _materialApp(
              theme: baseTheme,
              darkTheme: alternateTheme,
              themeMode: themeMode,
            );
          },
        ),
      ),
    );
    final diagnostics = widget.diagnostics;
    return diagnostics == null
        ? app
        : DiagnosticsScope(
            controller: diagnostics,
            plugins: _diagnosticsPlugins,
            child: app,
          );
  }

  PluginHostBindings get _pluginHostBindings => PluginHostBindings([
    PluginHostPort<Object>(
      pluginDiagnosticsReporterPort,
      _pluginDiagnosticsReporter,
    ),
  ]);

  Future<void> _observePluginAppState(
    InstalledPlugins plugins,
    String state,
  ) async {
    try {
      await plugins.observeAppState(state, foreground: _foreground);
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'app.plugins.observeAppState',
        source: 'plugins',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
    }
  }

  Future<void> _flushPlugins(InstalledPlugins plugins) async {
    try {
      await plugins.flush();
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'app.plugins.flush',
        source: 'plugins',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
    }
  }

  List<DiagnosticsPlugin> get _diagnosticsPlugins =>
      _plugins.registry.diagnosticsPlugins;

  Widget _materialApp({
    required ThemeData theme,
    required ThemeData darkTheme,
    required ThemeMode themeMode,
  }) => MaterialApp(
    navigatorKey: _navigatorKey,
    title: 'Discourse',
    debugShowCheckedModeBanner: false,
    theme: theme,
    darkTheme: darkTheme,
    themeMode: themeMode,
    localizationsDelegates: RelativeTimeLocalizations.localizationsDelegates,
    supportedLocales: RelativeTimeLocalizations.supportedLocales,
    builder: (context, child) => _MouseNavigationRegion(
      navigatorKey: _navigatorKey,
      child: child ?? const SizedBox.shrink(),
    ),
    home: const AdaptiveShell(),
  );
}

class _MouseNavigationRegion extends StatelessWidget {
  const _MouseNavigationRegion({
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  void _handlePointerDown(BuildContext context, PointerDownEvent event) {
    if (kIsWeb || event.kind != PointerDeviceKind.mouse) return;
    final backPressed = (event.buttons & kBackMouseButton) != 0;
    final forwardPressed = (event.buttons & kForwardMouseButton) != 0;
    if (!backPressed && !forwardPressed) return;

    final navigator = navigatorKey.currentState;
    if (navigator?.canPop() ?? false) {
      if (backPressed) unawaited(navigator!.maybePop());
      return;
    }

    final controller = ShellScope.read(context);
    if (backPressed && controller.rootMode == ShellRootMode.settings) {
      controller.handleBack(canReturnToSidebar: false);
      return;
    }

    final diagnostics = DiagnosticsScope.maybeRead(context);
    if (diagnostics?.isPanelOpen ?? false) {
      if (backPressed) diagnostics!.closePanel();
      return;
    }

    if (backPressed) {
      if (controller.rootMode == ShellRootMode.forum &&
          controller.canPopContent) {
        controller.handleBack(canReturnToSidebar: false);
      }
    } else {
      controller.handleForward();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => _handlePointerDown(context, event),
    child: child,
  );
}

@immutable
final class _AppThemeSelection {
  const _AppThemeSelection(this.siteUrl, this.appearance);

  factory _AppThemeSelection.from(ShellController controller) {
    // App-owned surfaces do not inherit whichever forum happened to be
    // selected last. The empty selection also rebuilds MaterialApp when the
    // root changes even though the underlying instance stays unchanged.
    if (controller.rootMode != ShellRootMode.forum) {
      return const _AppThemeSelection(null, null);
    }
    return _AppThemeSelection(
      controller.currentInstance?.url,
      controller.currentSiteAppearance,
    );
  }

  final String? siteUrl;
  final SiteAppearance? appearance;

  @override
  bool operator ==(Object other) =>
      other is _AppThemeSelection &&
      other.siteUrl == siteUrl &&
      other.appearance == appearance;

  @override
  int get hashCode => Object.hash(siteUrl, appearance);
}
