import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/dashboard_api.dart';
import '../data/site_lifecycle.dart';
import '../models/dashboard.dart';
import '../models/discourse_instance.dart';
import 'dashboard_controller.dart';
import 'dashboard_page.dart';
import 'external_link.dart';
import 'open_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_url.dart';

String dashboardLinkUrl(String siteUrl, DashboardLink link) =>
    switch (link.origin) {
      DashboardLinkOrigin.server => resolveSiteUrl(link.value, siteUrl),
      DashboardLinkOrigin.app => resolveSiteRootPath(siteUrl, link.value),
    };

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
              onOpenUrl: (link) {
                final url = dashboardLinkUrl(widget.siteUrl, link);
                final target = Uri.tryParse(url);
                final site = Uri.parse(widget.siteUrl);
                final path =
                    target != null &&
                        (target.scheme == 'http' || target.scheme == 'https') &&
                        target.hasAuthority &&
                        target.origin == site.origin
                    ? DiscourseInstance.pathWithinUrl(widget.siteUrl, target)
                    : null;
                if (path == '/admin' || path?.startsWith('/admin/') == true) {
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
