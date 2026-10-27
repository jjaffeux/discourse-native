import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../models/dashboard.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'dashboard_controller.dart';
import 'skeleton_fill.dart';

String dashboardSectionLabel(String id) => switch (id) {
  'highlights' => appL10n.dashboardHighlights,
  'reports' => appL10n.dashboardReports,
  'traffic' => appL10n.dashboardTraffic,
  'engagement' => appL10n.dashboardEngagement,
  'search' => appL10n.dashboardSearch,
  'system' => appL10n.dashboardSystem,
  _ => id,
};
String dashboardPeriodLabel(DashboardPeriod period) => switch (period) {
  DashboardPeriod.last7Days => appL10n.dashboardLast7Days,
  DashboardPeriod.last30Days => appL10n.dashboardLast30Days,
  DashboardPeriod.last3Months => appL10n.dashboardLast3Months,
  DashboardPeriod.last6Months => appL10n.dashboardLast6Months,
  DashboardPeriod.lastYear => appL10n.dashboardLastYear,
};
String _metricLabel(String id) => switch (id) {
  'new_signups' => appL10n.dashboardNewSignups,
  'dau_mau' => appL10n.dashboardStickiness,
  'new_contributors' => appL10n.dashboardNewContributors,
  'daily_engaged_users' => appL10n.dashboardDailyEngaged,
  'browser_pageviews' => appL10n.dashboardBrowserPageviews,
  'logged_in_share' => appL10n.dashboardLoggedInShare,
  'direct_traffic' => appL10n.dashboardDirectTraffic,
  'bounce_rate' => appL10n.dashboardBounceRate,
  'average_session_duration_seconds' => appL10n.dashboardSessionDuration,
  'total_searches' => appL10n.dashboardTotalSearches,
  'no_result_rate' => appL10n.dashboardNoResultRate,
  _ => id,
};
String _number(num? value) => value == null
    ? '—'
    : NumberFormat.decimalPattern(appL10n.localeName).format(value);
String _decimal(num? value) => value == null
    ? '—'
    : NumberFormat.decimalPatternDigits(
        locale: appL10n.localeName,
        decimalDigits: 1,
      ).format(value);
String _percent(num? value) {
  if (value == null) return '—';
  final format = NumberFormat.percentPattern(appL10n.localeName)
    ..maximumFractionDigits = 1;
  return format.format(value / 100);
}

String _signed(num value) => '${value > 0 ? '+' : ''}${_decimal(value)}';
String _bytes(num value) => appL10n.dashboardMegabytes(
  NumberFormat.decimalPatternDigits(
    locale: appL10n.localeName,
    decimalDigits: 1,
  ).format(value / 1024 / 1024),
);

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.state,
    required this.staff,
    required this.admin,
    required this.onRefresh,
    required this.onPeriodChanged,
    required this.onConfigure,
    required this.onRefreshProblems,
    required this.onDismissProblem,
    required this.onOpenUrl,
    required this.onOpenReport,
  });
  final DashboardState state;
  final bool staff;
  final bool admin;
  final Future<void> Function() onRefresh;
  final ValueChanged<DashboardPeriod> onPeriodChanged;
  final ValueChanged<List<DashboardConfiguration>> onConfigure;
  final VoidCallback onRefreshProblems;
  final ValueChanged<DashboardProblem> onDismissProblem;
  final ValueChanged<DashboardLink> onOpenUrl;
  final ValueChanged<DashboardReport> onOpenReport;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final Set<String> _trafficOff = {'page_view_crawler'};
  DashboardState get state => widget.state;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = state.snapshot;
    return DPageSurface.headed(
      title: Text(l10n.dashboardTitle),
      controls: !widget.staff
          ? null
          : DControlWrap(
              children: [
                DSelect<DashboardPeriod>(
                  value: state.period,
                  semanticLabel: l10n.dashboardTitle,
                  entries: [
                    for (final period in DashboardPeriod.values)
                      DSelectItem(
                        value: period,
                        textValue: dashboardPeriodLabel(period),
                        child: Text(dashboardPeriodLabel(period)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) widget.onPeriodChanged(value);
                  },
                ),
                if (widget.admin && snapshot?.configuration != null)
                  _configure(snapshot!.configuration!),
              ],
            ),
      bodyBuilder: (context, header) => DPullToRefresh(
        onRefresh: widget.staff && !state.loading ? widget.onRefresh : null,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
          children: [
            header.spacer,
            if (!widget.staff)
              _empty(l10n.dashboardStaffOnly)
            else ...[
              if (state.error) _error(l10n.dashboardLoadError),
              if (state.mutationError) _error(l10n.dashboardMutationError),
              // The host's first refresh starts after the first frame, so an
              // absent snapshot, not `loading`, is what marks the page as
              // loading.
              if (snapshot == null && !state.error) _skeleton(),
              if (snapshot != null && !snapshot.supported) ...[
                _empty(l10n.dashboardUnsupported),
                _openDashboard(),
              ],
              if (snapshot?.supported == true) ...[
                if (snapshot!.problems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    child: _advice(snapshot.problems),
                  ),
                if (snapshot.sections.isEmpty) _empty(l10n.dashboardNoSections),
                for (final section in snapshot.sections)
                  _sectionFrame(
                    Text(
                      dashboardSectionLabel(section.id),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    _section(section),
                    key: ValueKey('dashboard-section-${section.id}'),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionFrame(Widget heading, Widget content, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [heading, const SizedBox(height: 12), content],
    ),
  );

  Widget _skeleton() {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    Widget line(TextStyle? style, double width) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: DSkeleton(
        width: width,
        height: scaler.scale(style?.fontSize ?? DiscourseTypography.sm),
      ),
    );
    return DSkeletonRegion(
      semanticsLabel: context.l10n.dashboardLoading,
      color: skeletonFill(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionFrame(
            line(text.titleMedium, 96),
            _grid([
              for (var i = 0; i < 3; i++)
                _cardFrame([
                  line(text.titleSmall, 120),
                  line(text.headlineSmall, 72),
                  line(text.bodySmall, 40),
                ]),
            ], maximumColumns: 3),
          ),
          _sectionFrame(
            line(text.titleMedium, 80),
            _grid([
              for (var i = 0; i < 4; i++)
                _cardFrame([
                  line(text.titleSmall, 140),
                  line(text.bodySmall, 220),
                  line(text.headlineSmall, 64),
                  const DSkeleton(height: 140),
                  line(text.bodySmall, 96),
                ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _configure(List<DashboardConfiguration> sections) => DDropdownMenu(
    content: DDropdownMenuContent(
      width: 220,
      semanticLabel: context.l10n.dashboardConfigure,
      children: [
        for (final section in sections)
          DDropdownMenuCheckboxItem(
            checked: section.visible,
            onChanged: state.mutating
                ? null
                : (visible) => widget.onConfigure([
                    for (final item in sections)
                      DashboardConfiguration(
                        item.id,
                        item.id == section.id ? visible : item.visible,
                      ),
                  ]),
            child: Text(dashboardSectionLabel(section.id)),
          ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, trigger) => DButton(
        label: Text(context.l10n.dashboardConfigure),
        icon: const DIcon(DIcons.gear),
        variant: DButtonVariant.outline,
        expanded: trigger.open,
        hasPopup: true,
        focusNode: trigger.focusNode,
        onPressed: state.mutating ? null : trigger.toggle,
      ),
    ),
  );

  Widget _advice(List<DashboardProblem> problems) => _card(
    context.l10n.dashboardAdvice,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final problem in problems)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(problem.message),
              if (widget.admin)
                DButton(
                  variant: DButtonVariant.outline,
                  label: Text(context.l10n.dashboardDismiss),
                  onPressed: state.mutating
                      ? null
                      : () => widget.onDismissProblem(problem),
                ),
            ],
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            variant: DButtonVariant.ghost,
            icon: const DIcon(DIcons.arrowsRotate),
            label: Text(context.l10n.refresh),
            onPressed: state.mutating ? null : widget.onRefreshProblems,
          ),
        ),
      ],
    ),
  );

  Widget _section(DashboardSection section) => switch (section) {
    DashboardHighlights(:final metrics) => _metrics(metrics),
    DashboardReports(:final items) =>
      items.isEmpty
          ? _empty(context.l10n.dashboardNoReports)
          : _grid([
              for (final item in items) _report(item, state.reports[item.key]),
            ]),
    DashboardTraffic() => _traffic(section),
    DashboardEngagement(:final metrics, :final breakdowns) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        _metrics(metrics),
        _grid([for (final breakdown in breakdowns) _breakdown(breakdown)]),
      ],
    ),
    DashboardSearch(:final loggingEnabled, :final metrics, :final breakdowns) =>
      !loggingEnabled
          ? _empty(context.l10n.dashboardSearchDisabled)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _metrics(metrics),
                _grid([
                  for (final breakdown in breakdowns) _breakdown(breakdown),
                ]),
              ],
            ),
    DashboardSystem() => _system(section),
    DashboardUnavailableSection(:final failed) => _card(
      dashboardSectionLabel(section.id),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            failed
                ? context.l10n.dashboardSectionError
                : context.l10n.dashboardSectionUnsupported,
          ),
          _openDashboard(),
        ],
      ),
    ),
  };

  Widget _metrics(List<DashboardMetric> metrics) => metrics.isEmpty
      ? _empty(context.l10n.dashboardNoData)
      : _grid([
          for (final metric in metrics)
            _card(
              _metricLabel(metric.type),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    _metricValue(metric),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                  if (metric.change != null)
                    _delta(
                      metric.change!,
                      lowerIsBetter: metric.type == 'bounce_rate',
                    ),
                  if (metric.pointChange != null)
                    Text(
                      context.l10n.dashboardPercentagePoints(
                        _signed(metric.pointChange!),
                      ),
                      style: _muted,
                    ),
                ],
              ),
            ),
        ], maximumColumns: metrics.length == 3 ? 3 : 2);

  String _metricValue(DashboardMetric metric) => switch (metric.type) {
    'dau_mau' ||
    'logged_in_share' ||
    'direct_traffic' ||
    'bounce_rate' ||
    'no_result_rate' => _percent(metric.value),
    'average_session_duration_seconds' =>
      metric.value == null
          ? '—'
          : context.l10n.dashboardDurationSeconds(_number(metric.value)),
    _ => _number(metric.value),
  };
  TextStyle? get _muted => Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: DTokens.of(context).mutedForeground);
  Widget _delta(num value, {bool lowerIsBetter = false}) => Text(
    '${_signed(value)}%',
    style: _muted?.copyWith(
      color: (lowerIsBetter ? value <= 0 : value >= 0)
          ? DTokens.of(context).success
          : DTokens.of(context).destructive,
    ),
  );

  Widget _report(DashboardReport report, DashboardReportResult? result) =>
      _card(
        report.title,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (report.description.isNotEmpty)
              Text(report.description, style: _muted),
            if (result == null || result.error)
              Text(context.l10n.dashboardSectionError)
            else if (result.unsupported)
              Text(context.l10n.dashboardSectionUnsupported)
            else if (result.points.isNotEmpty) ...[
              Text(
                result.percent
                    ? _percent(result.value)
                    : report.identifier == 'time_to_first_response' &&
                          result.value != null
                    ? context.l10n.dashboardDurationHours(
                        _decimal(result.value),
                      )
                    : _decimal(result.value),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              _line(report.title, result.points),
            ] else if (result.rows.isNotEmpty && result.headings.isNotEmpty)
              _table(result.headings, result.rows)
            else
              Text(context.l10n.dashboardNoData, style: _muted),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DButton(
                label: Text(context.l10n.dashboardOpenReport),
                variant: DButtonVariant.link,
                onPressed: () => widget.onOpenReport(report),
              ),
            ),
          ],
        ),
      );

  Widget _line(String title, List<DashboardPoint> points) => DChartContainer(
    config: {'value': DChartConfigEntry(label: title)},
    child: DCartesianChart<DashboardPoint>(
      plot: DChartPlot.line,
      data: points,
      series: [DChartSeries(key: 'value', value: (point) => point.value)],
      label: (point) => _dateLabel(point.label),
      semanticLabel: title,
      height: 140,
    ),
  );
  String _dateLabel(String value) {
    final date = DateTime.tryParse(value);
    return date == null
        ? value
        : DateFormat.MMMd(context.l10n.localeName).format(date);
  }

  Widget _traffic(DashboardTraffic traffic) {
    final shown = traffic.series
        .where((series) => !_trafficOff.contains(series.id))
        .toList();
    final dates = <String, Map<String, num?>>{};
    for (final series in shown) {
      for (final point in series.points) {
        (dates[point.label] ??= {})[series.id] = point.value;
      }
    }
    final data = dates.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final missing = data.any(
      (day) => shown.any((series) => day.value[series.id] == null),
    );
    final total = data.fold<num>(
      0,
      (sum, day) =>
          sum +
          day.value.values.fold<num>(0, (sum, value) => sum + (value ?? 0)),
    );
    return DChartContainer(
      config: {
        for (var i = 0; i < traffic.series.length; i++)
          traffic.series[i].id: DChartConfigEntry(
            label: traffic.series[i].label,
            color: (context) => DChartColors.series(context, i),
          ),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          _metrics(traffic.metrics),
          _card(
            context.l10n.dashboardSelectedPageviews,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Text(
                  data.isEmpty || missing ? '—' : _number(total),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(context.l10n.dashboardTrafficHelp, style: _muted),
                DCartesianChart<MapEntry<String, Map<String, num?>>>(
                  plot: DChartPlot.stackedArea,
                  data: data,
                  series: [
                    for (final series in shown)
                      DChartSeries(
                        key: series.id,
                        value: (day) => day.value[series.id],
                      ),
                  ],
                  label: (day) => _dateLabel(day.key),
                  semanticLabel: context.l10n.dashboardTraffic,
                  grid: true,
                  axis: true,
                  height: 230,
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < traffic.series.length; i++)
                      DToggle(
                        pressed: !_trafficOff.contains(traffic.series[i].id),
                        onPressedChanged: (pressed) => setState(() {
                          if (pressed) {
                            _trafficOff.remove(traffic.series[i].id);
                          } else {
                            _trafficOff.add(traffic.series[i].id);
                          }
                        }),
                        child: DChartLegendContent(
                          items: [DChartItem(key: traffic.series[i].id)],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.admin)
            _grid([
              for (final ranking in traffic.rankings) _breakdown(ranking),
            ]),
        ],
      ),
    );
  }

  Widget _breakdown(DashboardBreakdown breakdown) {
    final category = breakdown.rows.any((row) => row.posts != null);
    if (category) {
      return _card(
        breakdown.title,
        _table(
          [
            context.l10n.dashboardName,
            context.l10n.dashboardTopics,
            context.l10n.dashboardPosts,
            context.l10n.dashboardViews,
            context.l10n.dashboardShare,
            context.l10n.dashboardChange,
          ],
          [
            for (final row in breakdown.rows)
              [
                row.label,
                _number(row.topics),
                _number(row.posts),
                _number(row.views),
                _percent(row.share),
                row.change == null ? '—' : '${_signed(row.change!)}%',
              ],
          ],
          firstCellPaths: breakdown.rows.map((row) => row.link).toList(),
        ),
      );
    }
    final maxCount = breakdown.rows.fold<num>(
      0,
      (max, row) => (row.count ?? 0) > max ? row.count! : max,
    );
    return _card(
      breakdown.title,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          if (breakdown.error)
            Text(context.l10n.dashboardSectionError)
          else if (breakdown.rows.isEmpty)
            Text(context.l10n.dashboardNoData, style: _muted)
          else
            for (final row in breakdown.rows)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: row.link == null
                            ? Text(row.label)
                            : Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: DButton(
                                  variant: DButtonVariant.link,
                                  label: Text(
                                    row.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () => widget.onOpenUrl(row.link!),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Text(_number(row.count)),
                    ],
                  ),
                  if (row.share != null || row.count != null)
                    DProgress(
                      value:
                          (row.share ??
                                  (maxCount == 0
                                      ? 0
                                      : (row.count ?? 0) / maxCount * 100))
                              .toDouble(),
                      semanticsLabel: row.label,
                    ),
                  if (row.share != null)
                    Text(_percent(row.share), style: _muted),
                  if (row.promoted != null || row.demoted != null)
                    Text(
                      '${context.l10n.dashboardPromoted} ${_number(row.promoted)} · ${context.l10n.dashboardDemoted} ${_number(row.demoted)}',
                      style: _muted,
                    ),
                  if (row.status != null)
                    Text(
                      row.status == 'no_match'
                          ? context.l10n.dashboardNoMatch
                          : context.l10n.dashboardPoorMatch,
                      style: _muted,
                    ),
                ],
              ),
        ],
      ),
    );
  }

  Widget _system(DashboardSystem system) {
    final storage = system.storage
        .where((store) => widget.admin || store.name != 'backups')
        .toList();
    final local = storage.where((store) => !store.remote).toList();
    final used = local.fold<num>(0, (sum, store) => sum + (store.used ?? 0));
    final free = local.map((store) => store.free).nonNulls.firstOrNull;
    return _grid([
      _card(
        context.l10n.dashboardVersion,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              system.version ?? '—',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (system.checkFailed)
              Text(context.l10n.dashboardVersionCheckFailed, style: _muted),
            if (system.latestVersion != null)
              Text(
                '${context.l10n.dashboardLatestVersion} ${system.latestVersion}',
                style: _muted,
              ),
            if (system.commits != null &&
                RegExp(r'^[a-fA-F0-9]{7,40}$').hasMatch(system.commits!))
              DButton(
                label: Text(context.l10n.dashboardViewGithub),
                variant: DButtonVariant.link,
                onPressed: () => widget.onOpenUrl(
                  DashboardLink.server(
                    'https://github.com/discourse/discourse/commits/${system.commits}',
                  ),
                ),
              ),
          ],
        ),
      ),
      _card(
        context.l10n.dashboardStorage,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            if (storage.isEmpty)
              Text(context.l10n.dashboardNoData, style: _muted),
            if (free != null) ...[
              Text(context.l10n.dashboardUsedSpace(_bytes(used))),
              DProgress(
                value: used + free <= 0 ? 0 : used / (used + free) * 100,
                semanticsLabel: context.l10n.dashboardStorage,
              ),
              Text(
                context.l10n.dashboardFreeSpace(_bytes(free)),
                style: _muted,
              ),
            ],
            for (final store in storage)
              Text(
                '${store.name == 'backups' ? context.l10n.dashboardBackups : context.l10n.dashboardUploads} · ${store.used == null ? '—' : _bytes(store.used!)}${store.remote ? ' · ${context.l10n.dashboardRemoteStorage}' : ''}',
                style: _muted,
              ),
          ],
        ),
      ),
      _card(
        context.l10n.dashboardStatus,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            if (system.discourseUpdatedAt != null)
              Text(
                context.l10n.dashboardDiscourseUpdated(
                  DateFormat.yMMMd(
                    context.l10n.localeName,
                  ).format(system.discourseUpdatedAt!),
                ),
                style: _muted,
              ),
            if (system.dashboardUpdatedAt != null)
              Text(
                context.l10n.dashboardUpdated(
                  DateFormat.yMMMd(
                    context.l10n.localeName,
                  ).add_jm().format(system.dashboardUpdatedAt!),
                ),
                style: _muted,
              ),
            DButton(
              label: Text(context.l10n.dashboardWhatsNew),
              variant: DButtonVariant.link,
              onPressed: () =>
                  widget.onOpenUrl(const DashboardLink.app('/admin/whats-new')),
            ),
          ],
        ),
      ),
    ], maximumColumns: 3);
  }

  Widget _table(
    List<String> headings,
    List<List<String>> rows, {
    List<DashboardLink?>? firstCellPaths,
  }) => DTable(
    header: DTableHeader(
      rows: [
        DTableRow(
          cells: [
            for (final heading in headings) DTableHead(child: Text(heading)),
          ],
        ),
      ],
    ),
    body: DTableBody(
      rows: [
        for (var i = 0; i < rows.length; i++)
          DTableRow(
            cells: [
              for (var j = 0; j < rows[i].length; j++)
                DTableCell(
                  child: j == 0 && firstCellPaths?[i] != null
                      ? DButton(
                          variant: DButtonVariant.link,
                          label: Text(rows[i][j]),
                          onPressed: () =>
                              widget.onOpenUrl(firstCellPaths![i]!),
                        )
                      : Text(rows[i][j]),
                ),
            ],
          ),
      ],
    ),
  );
  Widget _grid(List<Widget> children, {int maximumColumns = 2}) =>
      LayoutBuilder(
        builder: (context, bounds) {
          final columns = bounds.maxWidth >= 900
              ? maximumColumns
              : bounds.maxWidth >= 600
              ? maximumColumns.clamp(1, 2)
              : 1;
          final width = (bounds.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );
  Widget _card(String title, Widget content) => _cardFrame([
    Text(title, style: Theme.of(context).textTheme.titleSmall),
    content,
  ]);
  Widget _cardFrame(List<Widget> children) => DCard(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: children,
      ),
    ),
  );
  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: DEmpty(children: [DEmptyDescription(text)]),
  );
  Widget _error(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DAlert(description: DAlertDescription(child: Text(text))),
  );
  Widget _openDashboard() => Align(
    alignment: AlignmentDirectional.centerStart,
    child: DButton(
      label: Text(context.l10n.dashboardOpenBrowser),
      variant: DButtonVariant.outline,
      onPressed: () =>
          widget.onOpenUrl(const DashboardLink.app('/admin/dashboard')),
    ),
  );
}
