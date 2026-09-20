import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/discourse_typography.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_notifications.dart';
import 'event_time.dart';

/// Event dates sit below narrow titles and beside wide titles.
class EventTopicTitle extends StatelessWidget {
  const EventTopicTitle({
    super.key,
    required this.site,
    required this.topicTitle,
    required this.event,
    required this.controller,
    required this.child,
  });

  final String site;
  final String topicTitle;
  final EventTopicData event;
  final EventController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildTitle(context, mobile: constraints.maxWidth < 600),
  );

  Widget _buildTitle(
    BuildContext context, {
    required bool mobile,
  }) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final schedule = _schedule(context);
      if (!controller.settings(site).displayTopicDate || schedule == null) {
        return child;
      }
      final theme = Theme.of(context);
      return Flex(
        direction: mobile ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DSpacing.sm,
        children: [
          if (!mobile)
            ExcludeSemantics(
              child: IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 36),
                  child: DCard(
                    key: const ValueKey('event-calendar-stamp'),
                    size: DCardSize.small,
                    spacing: DSpacing.xs,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DSpacing.xs,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat.MMM(
                              schedule.locale,
                            ).format(schedule.start).toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: DTokens.of(context).mutedForeground,
                              height: 1.2,
                            ),
                          ),
                          Text(
                            DateFormat.d(
                              schedule.locale,
                            ).format(schedule.start),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: DiscourseTypography.lg,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Flexible(
            flex: mobile ? 0 : 1,
            fit: mobile ? FlexFit.loose : FlexFit.tight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                child,
                DButton(
                  key: const ValueKey('event-schedule-trigger'),
                  variant: DButtonVariant.inline,
                  size: DButtonSize.small,
                  alignment: AlignmentDirectional.centerStart,
                  icon: mobile
                      ? const DIcon(EventIcons.calendar, size: 14)
                      : null,
                  semanticLabel: 'View event schedule: ${schedule.description}',
                  tooltip: schedule.description,
                  label: Builder(
                    // Retain the button's typography while allowing long ranges
                    // to wrap naturally at narrow widths and large text sizes.
                    builder: (context) => DefaultTextStyle(
                      style: DefaultTextStyle.of(context).style,
                      child: Text(
                        schedule.summary(
                          controller.api.clock().year,
                          includeDate: mobile,
                        ),
                      ),
                    ),
                  ),
                  onPressed: () => showDDialog<void>(
                    context: context,
                    builder: (context, _) => ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => _EventScheduleDialog(
                        title: topicTitle,
                        schedule: _schedule(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  _EventSchedule? _schedule(BuildContext context) {
    DateTime? date(String? source) => eventDate(
      source,
      zones: controller.zones,
      timezone: event.timezone,
      allDay: event.allDay,
      showLocalTime: event.showLocalTime,
      accountTimezone: controller.accountTimezone(site),
    );
    final start = date(event.startsAt);
    if (start == null) return null;
    final end = date(event.endsAt);
    return _EventSchedule(
      start: start,
      end: end != null && !end.isBefore(start) ? end : null,
      allDay: event.allDay,
      zone: event.showLocalTime
          ? event.timezone
          : controller.zones.readerTimezone(controller.accountTimezone(site)),
      locale: Localizations.localeOf(context).toString(),
    );
  }
}

class _EventSchedule {
  _EventSchedule({
    required this.start,
    required this.end,
    required this.allDay,
    required this.zone,
    required this.locale,
  });

  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? zone;
  final String locale;

  // A list row uses the same description for its tooltip and semantics, and
  // the same formatters for both endpoints. Resolve each once per schedule.
  late final _fullDateFormat = DateFormat.yMMMMEEEEd(locale);
  late final _timeFormat = DateFormat.Hm(locale);

  bool get spansDays => end != null && _day(start) != _day(end!);
  DateTime _day(DateTime date) => DateTime.utc(date.year, date.month, date.day);

  String summary(int currentYear, {bool includeDate = false}) {
    final year =
        start.year != currentYear || (end?.year ?? start.year) != currentYear;
    if (spansDays) {
      final date = year ? DateFormat.yMMMd(locale) : DateFormat.MMMd(locale);
      final days = _day(end!).difference(_day(start)).inDays + 1;
      return '${date.format(start)} – ${date.format(end!)} · '
          '${allDay ? 'All day' : '$days days'}';
    }
    final date = year
        ? DateFormat.yMMMEd(locale)
        : includeDate
        ? DateFormat.MMMEd(locale)
        : DateFormat.E(locale);
    return '${date.format(start)} · '
        '${allDay ? 'All day' : _timeFormat.format(start)}';
  }

  String fullDate(DateTime date) =>
      '${_fullDateFormat.format(date)}'
      '${allDay ? ' · All day' : ' · ${_timeFormat.format(date)}'}';

  late final String description =
      '${fullDate(start)}'
      '${end == null ? '' : ' → ${fullDate(end!)}'}'
      '${allDay || zone == null ? '' : ' · $zone'}';
}

class _EventScheduleDialog extends StatelessWidget {
  const _EventScheduleDialog({required this.title, required this.schedule});
  final String title;
  final _EventSchedule? schedule;

  @override
  Widget build(BuildContext context) {
    Widget field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DSpacing.xs,
      children: [
        DLabel(child: Text(label)),
        Text(value),
      ],
    );
    final schedule = this.schedule;
    return DDialogContent(
      semanticLabel: 'Event schedule',
      maxWidth: 440,
      children: [
        const DDialogHeader(
          children: [DDialogTitle(child: Text('Event schedule'))],
        ),
        DDialogScrollArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.lg,
            children: [
              DDialogDescription(child: Text(title)),
              if (schedule == null)
                const Text('Date unavailable')
              else ...[
                field('Starts', schedule.fullDate(schedule.start)),
                if (schedule.end case final end?)
                  field('Ends', schedule.fullDate(end)),
                if (!schedule.allDay)
                  if (schedule.zone case final zone?) field('Timezone', zone),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
