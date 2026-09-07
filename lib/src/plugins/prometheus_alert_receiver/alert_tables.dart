import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shell/open_link.dart';
import '../../shell/route_aware_selection_area.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'alert_data.dart';
import 'alert_links.dart';

class AlertTables extends StatelessWidget {
  const AlertTables({
    super.key,
    required this.data,
    required this.siteUrl,
    this.settings = const AlertLinkSettings(),
    this.onQuote,
  });

  final AlertData data;
  final String siteUrl;
  final AlertLinkSettings settings;
  final ValueChanged<PrometheusAlert>? onQuote;

  @override
  Widget build(BuildContext context) {
    return RouteAwareSelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < data.groups.length; index++) ...[
            if (index == 0 ||
                data.groups[index - 1].status != data.groups[index].status)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    data.groups[index].status.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            _AlertTable(
              key: ValueKey((
                data.groups[index].status,
                data.groups[index].datacenter,
              )),
              group: data.groups[index],
              siteUrl: siteUrl,
              settings: settings,
              onQuote: onQuote,
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertTable extends StatefulWidget {
  const _AlertTable({
    super.key,
    required this.group,
    required this.siteUrl,
    required this.settings,
    required this.onQuote,
  });

  final AlertGroup group;
  final String siteUrl;
  final AlertLinkSettings settings;
  final ValueChanged<PrometheusAlert>? onQuote;

  @override
  State<_AlertTable> createState() => _AlertTableState();
}

class _AlertTableState extends State<_AlertTable> {
  final _scroll = ScrollController();
  bool? _collapsed;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final collapsed = _collapsed ?? group.defaultCollapsed;
    final theme = Theme.of(context);
    final manager = alertWebUri(group.alerts.first.externalUrl);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DButton(
                  variant: DButtonVariant.transparent,
                  alignment: Alignment.centerLeft,
                  icon: DIcon(
                    collapsed ? DIcons.chevronRight : DIcons.chevronDown,
                    size: 12,
                  ),
                  label: Text('${group.heading} (${group.alerts.length})'),
                  tooltip:
                      '${collapsed ? 'Expand' : 'Collapse'} '
                      '${group.status.label}: ${group.heading}',
                  onPressed: () => setState(() => _collapsed = !collapsed),
                ),
              ),
              if (manager != null)
                _AlertLinkButton(
                  uri: manager,
                  siteUrl: widget.siteUrl,
                  label: 'Open Alertmanager',
                  icon: DIcons.list,
                ),
            ],
          ),
          if (!collapsed)
            LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: math.max(
                      constraints.maxWidth,
                      group.showDescription ? 680 : 460,
                    ),
                    child: Table(
                      defaultVerticalAlignment: TableCellVerticalAlignment.top,
                      columnWidths: {
                        0: const FlexColumnWidth(2),
                        1: const FlexColumnWidth(2),
                        if (group.showDescription) 2: const FlexColumnWidth(3),
                        group.showDescription ? 3 : 2: FixedColumnWidth(
                          widget.onQuote == null ? 48 : 96,
                        ),
                      },
                      border: TableBorder(
                        top: BorderSide(color: theme.dividerColor),
                        horizontalInside: BorderSide(color: theme.dividerColor),
                      ),
                      children: [
                        for (final alert in group.alerts) _row(context, alert),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  TableRow _row(BuildContext context, PrometheusAlert alert) {
    final now = DateTime.now();
    final graph = widget.settings.process(alert.generatorUrl, alert, now: now);
    final link = widget.settings.process(alert.linkUrl, alert, now: now);
    final theme = Theme.of(context);
    final identifier = Text(
      alert.identifier.isEmpty ? 'Alert' : alert.identifier,
    );
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (graph == null)
                identifier
              else
                LinkTarget(
                  url: graph.toString(),
                  siteUrl: widget.siteUrl,
                  child: Semantics(
                    link: true,
                    child: InkWell(
                      onTap: () => unawaited(
                        openLink(
                          context,
                          graph.toString(),
                          siteUrl: widget.siteUrl,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(color: theme.colorScheme.primary),
                          child: identifier,
                        ),
                      ),
                    ),
                  ),
                ),
              if (alert.wasRecentlySilenced(now))
                Tooltip(
                  message:
                      'Previously silenced on '
                      '${DateFormat.yMMMd().format(alert.lastSuppressedAt!.toLocal())}',
                  child: Text(
                    'Previously silenced',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(alertDateRange(alert)),
        ),
        if (widget.group.showDescription)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(alert.description),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (link != null)
              _AlertLinkButton(
                uri: link,
                siteUrl: widget.siteUrl,
                label: alert.linkText,
              ),
            if (widget.onQuote case final quote?)
              DButton.iconOnly(
                icon: const DIcon(DIcons.quoteLeft, size: 14),
                tooltip: 'Quote Alert',
                variant: DButtonVariant.flat,
                onPressed: () => quote(alert),
              ),
          ],
        ),
      ],
    );
  }
}

class _AlertLinkButton extends StatelessWidget {
  const _AlertLinkButton({
    required this.uri,
    required this.siteUrl,
    required this.label,
    this.icon = DIcons.upRightFromSquare,
  });

  final Uri uri;
  final String siteUrl;
  final String label;
  final DIconData icon;

  @override
  Widget build(BuildContext context) => LinkTarget(
    url: uri.toString(),
    siteUrl: siteUrl,
    child: DButton.iconOnly(
      icon: DIcon(icon, size: 14),
      tooltip: label,
      variant: DButtonVariant.flat,
      onPressed: () =>
          unawaited(openLink(context, uri.toString(), siteUrl: siteUrl)),
    ),
  );
}

String alertDateRange(PrometheusAlert alert) {
  final start = alert.start;
  final end = alert.end;
  if (start == null) return 'Unknown time';
  final startDate = DateFormat('yyyy-MM-dd HH:mm').format(start);
  if (end == null) return '$startDate UTC';
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final endDate = DateFormat(
    sameDay ? 'HH:mm' : 'yyyy-MM-dd HH:mm',
  ).format(end);
  return '$startDate – $endDate UTC';
}
