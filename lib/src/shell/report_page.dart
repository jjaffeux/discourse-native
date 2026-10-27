import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../models/dashboard.dart';
import '../models/report.dart';
import 'dashboard_page.dart' show dashboardPeriodLabel;
import 'report_controller.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.controller, required this.onBack});
  final ReportController controller;
  final VoidCallback onBack;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  bool _table = false;
  final Set<String> _hidden = {};
  ReportController get owner => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: owner,
    builder: (context, _) {
      final details = owner.details;
      final result = details?.result;
      final hasChart =
          details?.chart == true &&
          result != null &&
          (result.points.isNotEmpty || result.series.isNotEmpty);
      return DPageSurface.headed(
        title: Text(
          details?.title.isNotEmpty == true
              ? details!.title
              : owner.report.title,
        ),
        controls: DControlWrap(
          children: [
            DButton(
              variant: DButtonVariant.ghost,
              label: Text(context.l10n.reportBackToDashboard),
              onPressed: widget.onBack,
            ),
            if (details?.datesFiltering != false) ...[
              DSelect<DashboardPeriod>(
                value: null,
                placeholder: context.l10n.reportDateRange,
                semanticLabel: context.l10n.reportDateRange,
                entries: [
                  for (final period in DashboardPeriod.values)
                    DSelectItem(
                      value: period,
                      textValue: dashboardPeriodLabel(period),
                      child: Text(dashboardPeriodLabel(period)),
                    ),
                ],
                onChanged: (period) {
                  if (period != null) {
                    unawaited(
                      owner.selectRange(period.rangeAt(DateTime.now())),
                    );
                  }
                },
              ),
              DDatePicker.controlled(
                value: DCalendarDate(
                  owner.range.start.year,
                  owner.range.start.month,
                  owner.range.start.day,
                ),
                semanticLabel: context.l10n.reportStartDate,
                width: 150,
                closeBehavior: DDatePickerCloseBehavior.onSelection,
                disabled: (date) => date.dateTimeUtc.isAfter(
                  DateTime.utc(
                    owner.range.end.year,
                    owner.range.end.month,
                    owner.range.end.day,
                  ),
                ),
                onChanged: (date) {
                  if (date != null) {
                    unawaited(
                      owner.selectRange(
                        DashboardRange(
                          DateTime(date.year, date.month, date.day),
                          owner.range.end,
                        ),
                      ),
                    );
                  }
                },
              ),
              DDatePicker.controlled(
                value: DCalendarDate(
                  owner.range.end.year,
                  owner.range.end.month,
                  owner.range.end.day,
                ),
                semanticLabel: context.l10n.reportEndDate,
                width: 150,
                closeBehavior: DDatePickerCloseBehavior.onSelection,
                disabled: (date) => date.dateTimeUtc.isBefore(
                  DateTime.utc(
                    owner.range.start.year,
                    owner.range.start.month,
                    owner.range.start.day,
                  ),
                ),
                onChanged: (date) {
                  if (date != null) {
                    unawaited(
                      owner.selectRange(
                        DashboardRange(
                          owner.range.start,
                          DateTime(date.year, date.month, date.day),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
            DButton(
              variant: DButtonVariant.outline,
              label: Text(context.l10n.refresh),
              onPressed: owner.loading ? null : owner.refresh,
            ),
            if (hasChart)
              DToggleGroup<bool>(
                values: [_table],
                allowEmptySelection: false,
                items: [
                  DToggleGroupItem(
                    value: false,
                    child: Text(context.l10n.reportChart),
                  ),
                  DToggleGroupItem(
                    value: true,
                    child: Text(context.l10n.table),
                  ),
                ],
                onChanged: (values) => setState(() => _table = values.single),
              ),
          ],
        ),
        bodyBuilder: (context, header) => DPullToRefresh(
          onRefresh: owner.loading ? null : owner.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              header.spacer,
              if ((details?.description ?? owner.report.description).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    details?.description.isNotEmpty == true
                        ? details!.description
                        : owner.report.description,
                  ),
                ),
              if (details?.filters.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DControlWrap(
                    children: [
                      for (final filter in details!.filters) _filter(filter),
                    ],
                  ),
                ),
              if (owner.loading)
                DProgress(semanticsLabel: context.l10n.loading),
              if (owner.error)
                DAlert(
                  description: DAlertDescription(
                    child: Text(context.l10n.reportLoadError),
                  ),
                ),
              if (!owner.loading && !owner.error && result != null)
                if (result.unsupported)
                  DEmpty(
                    children: [
                      DEmptyDescription(
                        context.l10n.dashboardSectionUnsupported,
                      ),
                    ],
                  )
                else if (result.rows.isEmpty && !hasChart)
                  DEmpty(
                    children: [DEmptyDescription(context.l10n.dashboardNoData)],
                  )
                else if (hasChart && !_table)
                  _chart(result)
                else
                  _rows(result),
            ],
          ),
        ),
      );
    },
  );

  Widget _filter(ReportFilter filter) {
    final label = switch (filter.id) {
      'category' => context.l10n.category,
      'category_list' => context.l10n.categories,
      'group' => context.l10n.group,
      'groups' => context.l10n.groups,
      'include_subcategories' => context.l10n.includeSubcategories,
      _ => filter.id.replaceAll('_', ' '),
    };
    if (filter.type == 'bool') {
      return DToggle(
        pressed: filter.value == true,
        onPressedChanged: filter.disabled
            ? null
            : (value) => owner.filter(filter.id, value),
        child: Text(label),
      );
    }
    final options = [
      if (!filter.multiple && filter.allowAny)
        DComboboxOption(value: '', label: context.l10n.all),
      for (final choice in filter.choices.entries)
        DComboboxOption(value: choice.key, label: choice.value),
    ];
    final anchor = DComboboxInput<String>(
      semanticLabel: label,
      placeholder: label,
    );
    final content = DComboboxContent(
      semanticLabel: label,
      children: const [DComboboxList<String>()],
    );
    return SizedBox(
      width: 220,
      child: filter.multiple
          ? DCombobox<String>.multipleControlled(
              value: filter.value is List
                  ? (filter.value as List)
                        .map((value) => value.toString())
                        .toList()
                  : const [],
              options: options,
              anchor: anchor,
              content: content,
              enabled: !filter.disabled,
              onValuesChanged: (values, _) => owner.filter(filter.id, values),
            )
          : DCombobox<String>.controlled(
              value: filter.value?.toString(),
              options: options,
              anchor: anchor,
              content: content,
              enabled: !filter.disabled,
              onChanged: (value, _) =>
                  owner.filter(filter.id, value == '' ? null : value),
            ),
    );
  }

  List<DashboardSeries> _series(DashboardReportResult result) =>
      result.series.isEmpty
      ? [DashboardSeries('value', owner.report.title, result.points)]
      : result.series;

  List<MapEntry<String, Map<String, num?>>> _data(
    List<DashboardSeries> series,
  ) {
    if (owner.details?.fillMissingDates != true && series.length == 1) {
      return [
        for (final point in series.single.points)
          MapEntry(point.label, {series.single.id: point.value}),
      ];
    }
    final data = <String, Map<String, num?>>{};
    for (final item in series) {
      for (final point in item.points) {
        (data[point.label] ??= {})[item.id] = point.value;
      }
    }
    // Core charts fill unreported calendar days with zero before plotting.
    // Query results can be categorical and keep exactly the returned rows.
    if (owner.details?.fillMissingDates == true &&
        data.keys.every((key) => DateTime.tryParse(key) != null)) {
      var day = DateTime.utc(
        owner.range.start.year,
        owner.range.start.month,
        owner.range.start.day,
      );
      final end = DateTime.utc(
        owner.range.end.year,
        owner.range.end.month,
        owner.range.end.day,
      );
      while (!day.isAfter(end)) {
        final values = data[DateFormat('yyyy-MM-dd').format(day)] ??= {};
        for (final item in series) {
          values.putIfAbsent(item.id, () => 0);
        }
        day = day.add(const Duration(days: 1));
      }
    }
    final entries = data.entries.toList();
    if (owner.details?.fillMissingDates == true) {
      entries.sort((a, b) => a.key.compareTo(b.key));
    }
    return entries;
  }

  Widget _chart(DashboardReportResult result) {
    final series = _series(result);
    final visible = series.where((item) => !_hidden.contains(item.id)).toList();
    return DChartContainer(
      config: {
        for (var i = 0; i < series.length; i++)
          series[i].id: DChartConfigEntry(
            label: series[i].label,
            color: (context) => DChartColors.series(context, i),
          ),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          DCartesianChart<MapEntry<String, Map<String, num?>>>(
            data: _data(visible),
            series: [
              for (final item in visible)
                DChartSeries(key: item.id, value: (row) => row.value[item.id]),
            ],
            label: (row) => _date(row.key),
            semanticLabel: owner.report.title,
            plot: DChartPlot.line,
            axis: true,
            valueAxis: true,
            grid: true,
            height: 300,
            valueFormatter: (value) =>
                result.percent ? '${_number(value)}%' : _number(value),
          ),
          if (series.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in series)
                  DToggle(
                    pressed: !_hidden.contains(item.id),
                    onPressedChanged: (pressed) => setState(() {
                      if (pressed) {
                        _hidden.remove(item.id);
                      } else {
                        _hidden.add(item.id);
                      }
                    }),
                    child: DChartLegendContent(
                      items: [DChartItem(key: item.id)],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _number(num? value) => value == null
      ? '—'
      : NumberFormat.decimalPattern(context.l10n.localeName).format(value);
  String _date(String value) {
    final date = DateTime.tryParse(value);
    return date == null
        ? value
        : DateFormat.yMMMd(context.l10n.localeName).format(date);
  }

  Widget _rows(DashboardReportResult result) {
    final series = _series(result);
    final headings = result.series.isNotEmpty
        ? [context.l10n.date, ...series.map((item) => item.label)]
        : result.headings;
    final rows = result.series.isNotEmpty
        ? [
            for (final row in _data(series))
              [
                _date(row.key),
                for (final item in series) _number(row.value[item.id]),
              ],
          ]
        : result.rows;
    return DTable(
      semanticLabel: owner.report.title,
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
          for (final row in rows)
            DTableRow(
              cells: [for (final cell in row) DTableCell(child: Text(cell))],
            ),
        ],
      ),
    );
  }
}
