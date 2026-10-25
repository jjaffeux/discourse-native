import 'dart:async';
import 'dart:ui' show AppExitResponse, PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart'
    show PointerDownEvent, kBackMouseButton, kForwardMouseButton;
import 'package:flutter/material.dart';
import 'package:relative_time/relative_time.dart';

import 'app_runtime.dart';
import 'data/app_settings_store.dart';
import 'data/authenticator.dart';
import 'data/discourse_api.dart';
import 'data/draft_store.dart';
import 'data/forum_settings_store.dart';
import 'data/forum_tab_store.dart';
import 'data/instance_store.dart';
import 'data/notification_opens.dart';
import 'data/site_tracker.dart';
import 'data/update_store.dart';
import 'data/updater.dart';

import 'foundation/bounded_lru_cache.dart';
import 'foundation/foreground_lifecycle.dart';
import 'foundation/timezone_environment.dart';
import 'models/app_settings.dart';
import 'models/forum_background.dart';
import 'models/site_appearance.dart';
import 'plugin_api/core_plugin_manifest.dart';
import 'plugin_api/plugin_runtime.dart';
import 'shell/adaptive_shell.dart';
import 'shell/app_motion.dart';
import 'shell/app_text_scale.dart';
import 'shell/content_reading_lane.dart';
import 'shell/forum_settings_controller.dart';
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
    this.forumSettingsStore,
    this.drafts,
    this.forumTabs,
    this.trackers,
    this.updater,
    this.updateStore,

    this.plugins,
    this.pluginManifest = corePluginManifest,
    this.initialRootMode = ShellRootMode.forum,
    this.notificationOpenUrls,
  }) : assert(
         plugins == null || identical(pluginManifest, corePluginManifest),
         'Pass plugins or pluginManifest, not both.',
       );

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
  final Stream<String>? notificationOpenUrls;

  /// How long a quit waits for local state to be written before it goes
  /// ahead regardless; storage that cannot answer must not hold the app open.
  static const Duration exitFlushTimeout = AppRuntime.exitFlushTimeout;

  @override
  State<DiscourseApp> createState() => _DiscourseAppState();
}

class _DiscourseAppState extends State<DiscourseApp>
    with WidgetsBindingObserver {
  late final AppRuntime _runtime;
  late final PlatformNotificationOpens _platformNotificationOpens;

  ShellController get _controller => _runtime.controller;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  // Theme construction includes Material's seed-color calculation. Keep recent
  // immutable palettes across forum switches, while bounding retained themes
  // when appearances change or forums are removed. Platform affects ThemeData
  // defaults, including typography and tap targets.
  final _themes =
      BoundedLruCache<
        (
          ResolvedSitePalette?,
          Brightness,
          TargetPlatform,
          String?,
          String?,
          ForumBackground,
        ),
        ThemeData
      >(32);

  ThemeData _themeFor(
    SiteAppearance? appearance,
    Brightness brightness,
    String? fontFamily,
    String? readingFontFamily,
    ForumBackground effects,
  ) {
    final palette = appearance?.paletteForBrightness(brightness);
    final key = (
      palette,
      brightness,
      defaultTargetPlatform,
      fontFamily,
      readingFontFamily,
      effects,
    );
    final cached = _themes.read(key);
    if (cached != null) return cached;
    final theme = palette != null
        ? AppTheme.fromPalette(
            palette,
            fontFamily: fontFamily,
            readingFontFamily: readingFontFamily,
          )
        : AppTheme.forBrightness(
            brightness,
            fontFamily: fontFamily,
            readingFontFamily: readingFontFamily,
            background: effects,
          );
    _themes.put(key, theme);
    return theme;
  }

  AppRuntimeDependencies get _dependencies => AppRuntimeDependencies(
    store: widget.store,
    api: widget.api,
    authenticator: widget.authenticator,
    appSettingsStore: widget.appSettingsStore,
    forumSettingsStore: widget.forumSettingsStore,
    drafts: widget.drafts,
    forumTabs: widget.forumTabs,
    trackers: widget.trackers,
    updater: widget.updater,
    updateStore: widget.updateStore,
    plugins: widget.plugins,
    pluginManifest: widget.pluginManifest,
    initialRootMode: widget.initialRootMode,
    forumTabsEnabled: forumTabsEnabledForCurrentPlatform,
    mobileNavigationEnabled: usesMobileNavigation(defaultTargetPlatform),
  );

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _runtime = AppRuntime(
      dependencies: _dependencies,
      foreground: isForegroundLifecycle(state),
      lifecycleState: state?.name ?? 'unknown',
    );
    _platformNotificationOpens = PlatformNotificationOpens();
    _runtime.listenNotificationOpens(
      widget.notificationOpenUrls ?? _platformNotificationOpens.urls,
    );
    WidgetsBinding.instance.addObserver(this);
    _startAfterFirstFrame(_controller);
  }

  @override
  void didUpdateWidget(DiscourseApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      widget.notificationOpenUrls,
      oldWidget.notificationOpenUrls,
    )) {
      _runtime.listenNotificationOpens(
        widget.notificationOpenUrls ?? _platformNotificationOpens.urls,
      );
    }
    if (_runtime.replace(_dependencies)) _startAfterFirstFrame(_controller);
  }

  void _startAfterFirstFrame(ShellController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_controller, controller)) return;
      unawaited(_runtime.start(controller));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtime.dispose();
    super.dispose();
  }

  /// `inactive` is transient (for example, a system dialog), so only hidden,
  /// paused, and detached states pace down the live connection.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _runtime.observeAppState(
      state.name,
      foreground: isForegroundLifecycle(state),
    );
    if (state == AppLifecycleState.resumed) {
      unawaited(
        TimezoneEnvironment.instance.refreshDeviceTimezone(forceNotify: true),
      );
    }
  }

  /// Quitting on desktop can end the process without a lifecycle change.
  /// The platform waits for this answer before it shuts the engine down.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _runtime.flushForExit();
    return AppExitResponse.exit;
  }

  /// The app has no URL routes. Any page can open the `discourse` scheme that
  /// sign-in names as its callback, and [WidgetsApp] pushes each URL the
  /// platform opens as a named route: a second shell, or a missing-generator
  /// error once it carries a query. This observer is registered before the
  /// [MaterialApp] below it builds, so claiming the push here keeps it from
  /// that navigator, and from being relayed back to the system, which would
  /// only route the scheme to this app again.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) =>
      Future.value(true);

  @override
  Widget build(BuildContext context) {
    // Above MaterialApp so that sheets and dialogs, which build under its
    // Navigator, can still reach the controller.
    final app = ShellScope(
      controller: _controller,
      child: ContentSettingsScope(
        controller: _controller.appSettings,
        child: ShellSelector<_AppThemeSelection>(
          select: _AppThemeSelection.from,
          builder: (context, selection, _) {
            return ListenableBuilder(
              listenable: _controller.forumSettings,
              builder: (context, _) {
                final appearance = _controller.forumSettings.appearanceFor(
                  selection.siteUrl ?? ForumSettingsController.homeSite,
                  selection.appearance,
                );
                final fontFamily =
                    _controller.forumSettings.shared.interfaceFont.family;
                final effects = _controller.forumSettings.shared.effects;
                final lightTheme = _themeFor(
                  appearance,
                  Brightness.light,
                  fontFamily,
                  _controller.forumSettings.shared.readingFamily,
                  effects,
                );
                final darkTheme = _themeFor(
                  appearance,
                  Brightness.dark,
                  fontFamily,
                  _controller.forumSettings.shared.readingFamily,
                  effects,
                );

                final shown = _controller.forumSettings.previewBrightnessFor(
                  selection.siteUrl ?? ForumSettingsController.homeSite,
                );
                return DIconSetScope(
                  iconSet: _controller.forumSettings.shared.iconSet,
                  child: _materialApp(
                    theme: lightTheme,
                    darkTheme: darkTheme,
                    themeMode: switch (shown) {
                      Brightness.light => ThemeMode.light,
                      Brightness.dark => ThemeMode.dark,
                      null => switch (_controller.forumSettings.themeModeFor(
                        selection.siteUrl ?? ForumSettingsController.homeSite,
                      )) {
                        AppThemeMode.system => ThemeMode.system,
                        AppThemeMode.light => ThemeMode.light,
                        AppThemeMode.dark => ThemeMode.dark,
                      },
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    return app;
  }

  Widget _materialApp({
    required ThemeData theme,
    required ThemeData darkTheme,
    required ThemeMode themeMode,
  }) => MaterialApp(
    navigatorKey: _navigatorKey,
    onGenerateTitle: (context) => context.l10n.discourse,
    debugShowCheckedModeBanner: false,
    theme: theme,
    darkTheme: darkTheme,
    themeMode: themeMode,
    scrollBehavior: const DScrollBehavior(),
    // Forum switches replace the whole palette. Animating that change makes
    // every theme-dependent subtree rebuild on each tick, including cooked
    // HTML.
    themeAnimationStyle: AnimationStyle.noAnimation,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      RelativeTimeLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: resolveAppLocale,
    home: const AdaptiveShell(),
    builder: (context, child) => AppMotionRegion(
      controller: _controller.appSettings,
      child: DFocusHighlight(
        child: DToaster(
          key: ObjectKey(_controller),
          child: AppTextScaleRegion(
            controller: _controller.appSettings,
            child: _MouseNavigationRegion(
              navigatorKey: _navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
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
