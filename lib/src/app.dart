import 'package:flutter/material.dart';

import 'data/authenticator.dart';
import 'data/discourse_api.dart';
import 'data/instance_store.dart';
import 'shell/adaptive_shell.dart';
import 'shell/shell_controller.dart';
import 'shell/shell_scope.dart';
import 'theme/app_theme.dart';

/// Root of the application. Follows the system light/dark setting.
///
/// [store] and [api] exist so tests can supply fakes; production uses the real
/// implementations.
class DiscourseApp extends StatefulWidget {
  const DiscourseApp({super.key, this.store, this.api, this.authenticator});

  final InstanceStore? store;
  final DiscourseApi? api;
  final Authenticator? authenticator;

  @override
  State<DiscourseApp> createState() => _DiscourseAppState();
}

class _DiscourseAppState extends State<DiscourseApp> {
  late final ShellController _controller = ShellController(
    store: widget.store ?? InstanceStore(),
    api: widget.api ?? DiscourseApi(),
    authenticator: widget.authenticator ?? Authenticator(),
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
