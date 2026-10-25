import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/dashboard_api.dart';
import '../data/site_lifecycle.dart';
import 'dashboard_controller.dart';
import 'dashboard_page.dart';
import 'external_link.dart';
import 'open_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_url.dart';

class DashboardHost extends StatefulWidget {
  const DashboardHost({super.key, required this.siteUrl});
  final String siteUrl;
  @override
  State<DashboardHost> createState() => DashboardHostState();
}

class DashboardHostState extends State<DashboardHost> {
  DashboardController? _controller;
  Object? _identity;

  Future<void> refresh() => _controller?.refresh() ?? Future.value();

  @override
  Widget build(BuildContext context) =>
      ShellSelector<
        ({
          ShellController shell,
          Object session,
          String? username,
          bool staff,
          bool admin,
        })
      >(
        select: (shell) {
          final instance = shell.instanceFor(widget.siteUrl);
          return (
            shell: shell,
            session: shell.lifecycle.capture(widget.siteUrl).session,
            username: instance?.user?.username,
            staff: instance?.user?.staff == true,
            admin: instance?.user?.admin == true,
          );
        },
        builder: (context, owner, _) {
          final identity = (
            widget.siteUrl,
            owner.shell,
            owner.session,
            owner.username,
            owner.staff,
            owner.admin,
          );
          if (_identity != identity) {
            _controller?.dispose();
            _identity = identity;
            final SiteLease lease = owner.shell.lifecycle.capture(
              widget.siteUrl,
            );
            final controller = DashboardController(
              api: DiscourseDashboardApi(owner.shell.api.pluginTransport),
              credentials: owner.shell.credentials,
              lease: lease,
              siteUrl: widget.siteUrl,
              staff: owner.staff,
              admin: owner.admin,
            );
            _controller = controller;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && identical(_controller, controller)) {
                unawaited(controller.refresh());
              }
            });
          }
          final controller = _controller!;
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) => DashboardPage(
              key: ValueKey(identity),
              state: controller.state,
              staff: owner.staff,
              admin: owner.admin,
              onRefresh: controller.refresh,
              onPeriodChanged: (period) =>
                  unawaited(controller.selectPeriod(period)),
              onConfigure: (sections) =>
                  unawaited(controller.configure(sections)),
              onRefreshProblems: () => unawaited(controller.refreshProblems()),
              onDismissProblem: (problem) =>
                  unawaited(controller.dismissProblem(problem)),
              onOpenUrl: (path) {
                final url = path.startsWith('/')
                    ? resolveSitePath(widget.siteUrl, path.substring(1))
                    : path;
                if (Uri.tryParse(path)?.path.startsWith('/admin') == true ||
                    !path.startsWith('/')) {
                  unawaited(openExternalLink(url));
                } else {
                  unawaited(openLink(context, url, siteUrl: widget.siteUrl));
                }
              },
            ),
          );
        },
      );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
