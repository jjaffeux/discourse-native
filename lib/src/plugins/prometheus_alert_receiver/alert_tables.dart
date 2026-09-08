import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shell/cooked_html.dart';
import '../../shell/emoji.dart';
import '../../shell/open_link.dart';
import '../../shell/platform.dart';
import '../../shell/route_aware_selection_area.dart';
import '../../theme/app_theme.dart';
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
    this.emojiUrl,
  });

  final AlertData data;
  final String siteUrl;
  final AlertLinkSettings settings;
  final ValueChanged<PrometheusAlert>? onQuote;
  final String Function(String name)? emojiUrl;

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
                padding: EdgeInsets.only(top: index == 0 ? 0 : 12, bottom: 6),
                child: Semantics(
                  header: true,
                  child: _AlertHeading(
                    status: data.groups[index].status,
                    emojiUrl: emojiUrl,
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

class _AlertHeading extends StatelessWidget {
  const _AlertHeading({required this.status, required this.emojiUrl});

  final AlertStatus status;
  final String Function(String name)? emojiUrl;

  @override
  Widget build(BuildContext context) {
    final emoji = switch (status) {
      AlertStatus.firing => (name: 'fire', fallback: '🔥'),
      AlertStatus.suppressed => (name: 'shushing_face', fallback: '🤫'),
      _ => null,
    };
    final style = Theme.of(context).textTheme.titleLarge;
    return Row(
      children: [
        if (emoji != null) ...[
          ExcludeSemantics(
            child: emojiUrl == null
                ? Text(emoji.fallback, style: style)
                : EmojiImage(
                    url: emojiUrl!(emoji.name),
                    size: MediaQuery.textScalerOf(
                      context,
                    ).scale(DiscourseTypography.xl),
                    alt: emoji.fallback,
                    style: style,
                  ),
          ),
          const SizedBox(width: 4),
        ],
        Flexible(child: Text(status.label, style: style)),
      ],
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
    final textScale =
        MediaQuery.textScalerOf(context).scale(DiscourseTypography.base) /
        DiscourseTypography.base;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: Size(0, _actionSize(context)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: theme.colorScheme.onSurface,
                    textStyle: theme.textTheme.bodyMedium,
                    alignment: Alignment.centerLeft,
                    shape: const RoundedRectangleBorder(),
                  ),
                  onPressed: () => setState(() => _collapsed = !collapsed),
                  child: Row(
                    children: [
                      DIcon(
                        collapsed ? DIcons.chevronRight : DIcons.chevronDown,
                        size: 10,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${group.heading} (${group.alerts.length})',
                          semanticsLabel:
                              '${collapsed ? 'Expand' : 'Collapse'} '
                              '${group.status.label}: ${group.heading} (${group.alerts.length})',
                        ),
                      ),
                    ],
                  ),
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
              builder: (context, constraints) {
                final width = math.max(
                  constraints.maxWidth,
                  (group.showDescription ? 620 : 460) * textScale,
                );
                return Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(
                      bottom: width > constraints.maxWidth ? 6 : 0,
                    ),
                    child: SizedBox(
                      width: width,
                      child: Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        columnWidths: {
                          0: const FlexColumnWidth(2),
                          1: FixedColumnWidth(180 * textScale),
                          if (group.showDescription)
                            2: const FlexColumnWidth(3),
                          group.showDescription ? 3 : 2: FixedColumnWidth(
                            _actionSize(context) *
                                (widget.onQuote == null ? 1 : 2),
                          ),
                        },
                        border: TableBorder(
                          top: BorderSide(color: theme.dividerColor),
                          horizontalInside: BorderSide(
                            color: theme.dividerColor,
                          ),
                        ),
                        children: [
                          for (final alert in group.alerts)
                            _row(context, alert),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
          padding: const EdgeInsets.fromLTRB(8, 3, 3, 3),
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
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: theme.colorScheme.primary),
                        child: identifier,
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
          padding: const EdgeInsets.fromLTRB(8, 3, 3, 3),
          child: CookedHtml(
            html: _alertDateRangeHtml(alert),
            siteUrl: widget.siteUrl,
          ),
        ),
        if (widget.group.showDescription)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 3, 3),
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
              _AlertActionButton(
                icon: DIcons.quoteLeft,
                label: 'Quote Alert',
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
    child: _AlertActionButton(
      icon: icon,
      label: label,
      onPressed: () =>
          unawaited(openLink(context, uri.toString(), siteUrl: siteUrl)),
    ),
  );
}

double _actionSize(BuildContext context) => context.isTouch ? 40 : 28;

class _AlertActionButton extends StatelessWidget {
  const _AlertActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final DIconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: DIcon(icon, size: 14),
    tooltip: label,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      minimumSize: Size.square(_actionSize(context)),
      maximumSize: Size.square(_actionSize(context)),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
  );
}

String _alertDateRangeHtml(PrometheusAlert alert) {
  final start = alert.start;
  final end = alert.end;
  if (start == null) return 'Unknown time';
  final startDate = _dateHtml(start);
  if (end == null) return startDate;
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return '$startDate – ${_dateHtml(end, hideDate: sameDay)}';
}

String _dateHtml(DateTime time, {bool hideDate = false}) {
  final format = hideDate ? 'HH:mm' : 'YYYY-MM-DD HH:mm';
  final fallback = DateFormat(
    hideDate ? 'HH:mm' : 'yyyy-MM-dd HH:mm',
  ).format(time);
  return '<span class="discourse-local-date" '
      'data-date="${DateFormat('yyyy-MM-dd').format(time)}" '
      'data-time="${DateFormat('HH:mm:ss').format(time)}" '
      'data-timezone="UTC" data-displayed-timezone="UTC" '
      'data-format="$format" data-calendar="off">$fallback (UTC)</span>';
}
