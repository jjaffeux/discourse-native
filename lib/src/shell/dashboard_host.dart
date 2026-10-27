import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/dashboard_api.dart';
import '../data/report_api.dart';
import '../data/site_lifecycle.dart';
import '../models/dashboard.dart';
import '../models/discourse_instance.dart';
import '../plugin_api/dashboard_report_source.dart';
import 'dashboard_controller.dart';
import 'dashboard_page.dart';
import 'external_link.dart';
import 'open_link.dart';
import 'report_controller.dart';
import 'report_page.dart';
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
  ReportController? _report;

  Future<void> refresh() =>
      _report?.refresh() ?? _controller?.refresh() ?? Future.value();

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
            _report?.dispose();
            _report = null;
            _controller?.dispose();
            _identity = identity;
            final SiteLease lease = owner.shell.lifecycle.capture(
              widget.siteUrl,
            );
            final controller = DashboardController(
              api: DiscourseDashboardApi(
                owner.shell.api.pluginTransport,
                sources: owner.shell.plugins
                    .capabilities<DashboardReportSource>(),
              ),
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
          final report = _report;
          if (report != null) {
            return ReportPage(
              key: ValueKey((identity, report.report.key)),
              controller: report,
              onBack: () => setState(() {
                _report?.dispose();
                _report = null;
              }),
            );
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
              onOpenReport: (report) {
                if (!owner.staff) return;
                final detail = ReportController(
                  api: DiscourseReportApi(
                    owner.shell.api.pluginTransport,
                    sources: owner.shell.plugins
                        .capabilities<DashboardReportSource>(),
                  ),
                  credentials: owner.shell.credentials,
                  lease: owner.shell.lifecycle.capture(widget.siteUrl),
                  siteUrl: widget.siteUrl,
                  report: report,
                  range: controller.state.period.rangeAt(DateTime.now()),
                );
                setState(() => _report = detail);
                unawaited(detail.refresh());
              },
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
    _report?.dispose();
    _controller?.dispose();
    super.dispose();
  }
}
