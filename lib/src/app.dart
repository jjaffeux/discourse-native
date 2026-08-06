import 'package:flutter/material.dart';

import 'data/authenticator.dart';
import 'data/discourse_api.dart';
import 'data/draft_store.dart';
import 'data/instance_store.dart';
import 'data/site_tracker.dart';
import 'data/update_store.dart';
import 'data/updater.dart';
import 'shell/adaptive_shell.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_scope.dart';
import 'theme/app_theme.dart';

/// Root of the application. Follows the system light/dark setting.
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
    this.trackers,
    this.updater,
    this.updateStore,
  });

  final InstanceStore? store;
  final DiscourseApi? api;
  final Authenticator? authenticator;
  final DraftStore? drafts;
  final SiteTrackerFactory? trackers;
  final Updater? updater;
  final UpdateStore? updateStore;

  @override
  State<DiscourseApp> createState() => _DiscourseAppState();
}

class _DiscourseAppState extends State<DiscourseApp>
    with WidgetsBindingObserver {
  late final ShellController _controller = ShellController(
    instanceStore: widget.store ?? InstanceStore(),
    api: widget.api ?? DiscourseApi(),
    authenticator: widget.authenticator ?? Authenticator(),
    drafts: widget.drafts ?? DraftStore(),
    trackers: widget.trackers ?? SiteTracker.new,
    // Swapped for DesktopUpdaterAdapter once that lands. Until then this is
    // also the honest answer everywhere but Linux.
    updater: widget.updater ?? const UnsupportedUpdater(),
    updateStore: widget.updateStore ?? UpdateStore(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// Only `paused` and `detached` count as being in the background, and the
  /// distinction matters because the live connection is paced off it.
  /// `inactive` fires for anything transient — the app switcher, a system
  /// dialog, a notification pulled down — and dropping the connection every
  /// time the user glanced away would cost more than it saves.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setForeground(
      state != AppLifecycleState.paused && state != AppLifecycleState.detached,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Above MaterialApp so that sheets and dialogs, which build under its
    // Navigator, can still reach the controller.
    return ShellScope(
      controller: _controller,
      child: MaterialApp(
        title: 'Discourse',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const AdaptiveShell(),
      ),
    );
  }
}
