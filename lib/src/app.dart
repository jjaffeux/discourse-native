import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relative_time/relative_time.dart';

import 'data/authenticator.dart';
import 'data/discourse_api.dart';
import 'data/draft_store.dart';
import 'data/forum_tab_store.dart';
import 'data/instance_store.dart';
import 'data/site_tracker.dart';
import 'data/update_store.dart';
import 'data/updater.dart';
import 'diagnostics/diagnostics.dart';
import 'models/site_appearance.dart';
import 'plugins/local_dates/local_date_environment.dart';
import 'plugins/resenha/resenha_diagnostics.dart';
import 'shell/adaptive_shell.dart';
import 'shell/platform.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_scope.dart';
import 'theme/app_theme.dart';

/// Root of the application. Uses each site's resolved appearance, falling
/// back to the system light/dark setting when the site has not supplied one.
///
/// [store] and [api] exist so tests can supply fakes; production uses the real
/// implementations.
class DiscourseApp extends StatefulWidget {
  const DiscourseApp({
    super.key,
    this.store,
    this.api,
    this.authenticator,
    this.drafts,
    this.forumTabs,
    this.trackers,
    this.updater,
    this.updateStore,
    this.diagnostics,
    this.resenhaDiagnostics,
  });

  final InstanceStore? store;
  final DiscourseApi? api;
  final Authenticator? authenticator;
  final DraftStore? drafts;
  final ForumTabStore? forumTabs;
  final SiteTrackerFactory? trackers;
  final Updater? updater;
  final UpdateStore? updateStore;
  final DiagnosticsController? diagnostics;
  final ResenhaDiagnosticsController? resenhaDiagnostics;

  @override
  State<DiscourseApp> createState() => _DiscourseAppState();
}

class _DiscourseAppState extends State<DiscourseApp>
    with WidgetsBindingObserver {
  late InstanceStore _store;
  late DiscourseApi _api;
  late Authenticator _authenticator;
  late DraftStore _drafts;
  late ForumTabStore _forumTabs;
  late SiteTrackerFactory _trackers;
  late Updater _updater;
  late UpdateStore _updateStore;
  late ShellController _controller;
  late bool _foreground;

  ShellController _createController() => ShellController(
    instanceStore: _store,
    api: _api,
    authenticator: _authenticator,
    drafts: _drafts,
    forumTabs: _forumTabs,
    forumTabsEnabled: forumTabsEnabledForCurrentPlatform,
    trackers: _trackers,
    // Nothing updates itself. Linux ships as a .deb from an apt repository, so
    // updates arrive with `apt upgrade` the way the rest of the system does,
    // and the app is installed under /usr where it could not replace itself
    // anyway. [DesktopUpdaterAdapter] is kept for the platform that gets an
    // in-app updater next; wiring it here would put an update button in front
    // of users whose package manager already owns the job.
    updater: _updater,
    updateStore: _updateStore,
    resenhaDiagnostics:
        widget.resenhaDiagnostics ?? const NoopResenhaDiagnosticsRecorder(),
    ownsApi: false,
  );

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? InstanceStore();
    _api = widget.api ?? DiscourseApi();
    _authenticator = widget.authenticator ?? Authenticator();
    _drafts = widget.drafts ?? DraftStore();
    _forumTabs = widget.forumTabs ?? ForumTabStore();
    _trackers = widget.trackers ?? SiteTracker.new;
    _updater = widget.updater ?? const UnsupportedUpdater();
    _updateStore = widget.updateStore ?? UpdateStore();
    _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
    widget.resenhaDiagnostics?.record(
      'app.lifecycle.initial',
      component: 'app',
      data: {
        'state': WidgetsBinding.instance.lifecycleState?.name ?? 'unknown',
        'foreground': _foreground,
      },
    );
    _controller = _createController()..setForeground(_foreground);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.load());
  }

  @override
  void didUpdateWidget(DiscourseApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dependenciesChanged(oldWidget)) return;

    _controller.dispose();
    if (!identical(widget.resenhaDiagnostics, oldWidget.resenhaDiagnostics)) {
      // DiscourseApp owns the injected diagnostics controller for the same
      // lifetime as the ordinary diagnostics controller. A replacement must
      // release an active SDK bridge as well as the final widget disposal does.
      unawaited(oldWidget.resenhaDiagnostics?.close());
    }
    _updateDependencies(oldWidget);
    _controller = _createController()..setForeground(_foreground);
    unawaited(_controller.load());
  }

  bool _dependenciesChanged(DiscourseApp oldWidget) =>
      !identical(widget.store, oldWidget.store) ||
      !identical(widget.api, oldWidget.api) ||
      !identical(widget.authenticator, oldWidget.authenticator) ||
      !identical(widget.drafts, oldWidget.drafts) ||
      !identical(widget.forumTabs, oldWidget.forumTabs) ||
      !identical(widget.trackers, oldWidget.trackers) ||
      !identical(widget.updater, oldWidget.updater) ||
      !identical(widget.updateStore, oldWidget.updateStore) ||
      !identical(widget.resenhaDiagnostics, oldWidget.resenhaDiagnostics);

  void _updateDependencies(DiscourseApp oldWidget) {
    if (!identical(widget.store, oldWidget.store)) {
      _store = widget.store ?? InstanceStore();
    }
    if (!identical(widget.api, oldWidget.api)) {
      _api.close();
      _api = widget.api ?? DiscourseApi();
    }
    if (!identical(widget.authenticator, oldWidget.authenticator)) {
      _authenticator = widget.authenticator ?? Authenticator();
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
    _controller.dispose();
    _api.close();
    unawaited(widget.diagnostics?.close());
    unawaited(widget.resenhaDiagnostics?.close());
    super.dispose();
  }

  /// Only `hidden`, `paused` and `detached` count as being in the background,
  /// and the distinction matters because the live connection is paced off it.
  /// `inactive` fires for anything transient — the app switcher, a system
  /// dialog, a notification pulled down — and dropping the connection every
  /// time the user glanced away would cost more than it saves. `hidden` is
  /// different: every view is gone from the screen, so nothing is being
  /// glanced at, and the poll would only be held open for an app nobody is
  /// looking at.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    widget.resenhaDiagnostics?.record(
      'app.lifecycle.changed',
      component: 'app',
      data: {'state': state.name, 'foreground': _foreground},
    );
    _controller.setForeground(_foreground);
    if (state == AppLifecycleState.resumed) {
      unawaited(
        LocalDateEnvironment.instance.refreshDeviceTimezone(forceNotify: true),
      );
    }
    if (!_foreground) {
      unawaited(widget.diagnostics?.flush());
      unawaited(widget.resenhaDiagnostics?.flush());
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
    );
    final diagnostics = widget.diagnostics;
    return diagnostics == null
        ? app
        : DiagnosticsScope(
            controller: diagnostics,
            resenhaController: widget.resenhaDiagnostics,
            child: app,
          );
  }

  static Widget _materialApp({
    required ThemeData theme,
    required ThemeData darkTheme,
    required ThemeMode themeMode,
  }) => MaterialApp(
    title: 'Discourse',
    debugShowCheckedModeBanner: false,
    theme: theme,
    darkTheme: darkTheme,
    themeMode: themeMode,
    localizationsDelegates: RelativeTimeLocalizations.localizationsDelegates,
    supportedLocales: RelativeTimeLocalizations.supportedLocales,
    home: const AdaptiveShell(),
  );
}

@immutable
final class _AppThemeSelection {
  const _AppThemeSelection(this.siteUrl, this.appearance);

  factory _AppThemeSelection.from(ShellController controller) =>
      _AppThemeSelection(
        controller.currentInstance?.url,
        controller.currentSiteAppearance,
      );

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
