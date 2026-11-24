import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'event_calendar_data.dart';
import 'event_data.dart' show EventPerson, eventObject, eventText;

/// The agenda of one calendar day, formatted in the reader's timezone.
final class EventDayAgenda extends StatelessWidget {
  const EventDayAgenda({
    super.key,
    required this.day,
    required this.events,
    required this.formatTime,
    required this.onOpen,
    this.creatorAvatar,
  });

  final DateTime day;
  final List<EventCalendarEntry> events;
  final String Function(EventCalendarEntry) formatTime;
  final ValueChanged<EventCalendarEntry> onOpen;
  final Widget? Function(EventPerson)? creatorAvatar;

  @override
  Widget build(BuildContext context) {
    final gaps = eventAgendaGaps(events, day);
    return DScrollBar(
      showScrollbar: false,
      child: ListView.builder(
        primary: false,
        padding: EdgeInsets.fromLTRB(
          DSpacing.sm,
          0,
          DSpacing.sm,
          MediaQuery.paddingOf(context).bottom + DSpacing.sm,
        ),
        itemCount: math.max(1, events.length),
        itemBuilder: (context, index) => events.isEmpty
            ? const EventAgendaEmpty()
            : EventAgendaRow(
                event: events[index],
                day: day,
                creatorAvatar: creatorAvatar,
                time: formatTime(events[index]),
                gapAbove: gaps.contains(events[index].id),
                onOpen: () => onOpen(events[index]),
              ),
      ),
    );
  }
}

Set<String> eventAgendaGaps(List<EventCalendarEntry> events, DateTime day) {
  final gaps = <String>{};
  DateTime? latestEnd;
  for (final event in events) {
    if (event.isAllDay) continue;
    final previous = latestEnd;
    if (previous != null &&
        event.firstDay == day &&
        event.start.difference(previous) >= const Duration(hours: 2)) {
      gaps.add(event.id);
    }
    if (previous == null || event.end.isAfter(previous)) latestEnd = event.end;
  }
  return gaps;
}

class EventAgendaEmpty extends StatelessWidget {
  const EventAgendaEmpty({super.key});

  @override
  Widget build(BuildContext context) => DCard(
    border: false,
    borderRadius: BorderRadius.circular(14),
    spacing: 0,
    backgroundColor: DTokens.of(context).raisedBackground,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        context.l10n.nothingPlanned,
        style: TextStyle(color: DTokens.of(context).mutedForeground),
      ),
    ),
  );
}

class EventAgendaRow extends StatelessWidget {
  const EventAgendaRow({
    super.key,
    required this.event,
    required this.day,
    required this.creatorAvatar,
    required this.time,
    required this.gapAbove,
    required this.onOpen,
  });

  static const _railInset = 16.0;
  static const _timeTop = 16.0;

  final EventCalendarEntry event;
  final DateTime day;
  final Widget? Function(EventPerson)? creatorAvatar;
  final String time;
  final bool gapAbove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final color = event.color ?? tokens.primary;
    final creator = event.event.creator;
    final avatar = creator == null ? null : creatorAvatar?.call(creator);
    final host =
        creator?.name ??
        creator?.username ??
        eventText(eventObject(event.event.fields['post'])?['username']);
    final reading = Theme.of(context).textTheme.bodyLarge;
    final titleStyle = TextStyle(
      fontFamily: reading?.fontFamily,
      fontFamilyFallback: reading?.fontFamilyFallback,
    );
    final going = event.event.watching?.status == 'going';
    final timeStyle = TextStyle(
      fontSize: DiscourseTypography.xs,
      color: tokens.mutedForeground,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final fillsCard = event.isAllDay || event.spansDays;
    final durationHeight = fillsCard
        ? 12.0
        : math.max(
            12.0,
            (event.end.difference(event.start).inMinutes / 2).roundToDouble(),
          );
    final gap = gapAbove ? DSpacing.xs : 0.0;
    final marker = DSeparator(
      orientation: Axis.vertical,
      color: color,
      thickness: 4,
      radius: BorderRadius.circular(2),
      length: fillsCard ? null : durationHeight,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PositionedDirectional(
          top: 0,
          bottom: 0,
          end: 4,
          child: DSeparator(
            orientation: Axis.vertical,
            thickness: 2,
            color: tokens.mutedForeground.withValues(alpha: .3),
          ),
        ),
        if (gapAbove)
          PositionedDirectional(
            top: -4,
            end: 0,
            child: Transform.rotate(
              angle: -.35,
              child: Column(
                spacing: 2,
                children: [
                  for (var stroke = 0; stroke < 2; stroke++)
                    DSeparator(
                      length: 10,
                      thickness: 2,
                      color: tokens.mutedForeground.withValues(alpha: .6),
                    ),
                ],
              ),
            ),
          ),
        PositionedDirectional(
          top: _timeTop + gap,
          bottom: fillsCard ? _timeTop + DSpacing.sm : null,
          end: 3,
          child: marker,
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            end: _railInset,
            top: gap,
            bottom: DSpacing.sm,
          ),
          child: DCard(
            backgroundColor: Color.lerp(tokens.raisedBackground, color, .10),
            spacing: 0,
            border: false,
            borderRadius: BorderRadius.circular(14),
            child: DItem(
              shape: DItemShape.card,
              size: DItemSize.artwork,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onPressed: onOpen,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: durationHeight + 8),
                  child: DItemContent(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        spacing: DSpacing.sm,
                        children: [
                          Expanded(
                            child: DItemTitle(
                              maxLines: null,
                              child: going
                                  ? Text.rich(
                                      TextSpan(
                                        children: [
                                          WidgetSpan(
                                            alignment:
                                                PlaceholderAlignment.middle,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsetsDirectional.only(
                                                    end: 5,
                                                  ),
                                              child: DIcon(
                                                DIcons.circleCheck,
                                                size: 13,
                                                color: tokens.primary,
                                                semanticLabel:
                                                    context.l10n.going,
                                              ),
                                            ),
                                          ),
                                          TextSpan(text: event.title),
                                        ],
                                      ),
                                      style: titleStyle,
                                    )
                                  : Text(event.title, style: titleStyle),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Text(
                              time,
                              style: timeStyle,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                      if (event.categoryName != null ||
                          host != null ||
                          event.spansDays)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: DSpacing.sm,
                            children: [
                              Expanded(
                                child: DItemDescription(
                                  child: Wrap(
                                    spacing: DSpacing.sm,
                                    runSpacing: 2,
                                    children: [
                                      if (event.categoryName
                                          case final category?)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          spacing: 5,
                                          children: [
                                            DIcon(
                                              DNativeIcons.square,
                                              size: 8,
                                              color: color,
                                            ),
                                            Flexible(child: Text(category)),
                                          ],
                                        ),
                                      if (host != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          spacing: 5,
                                          children: [
                                            DAvatar(
                                              dimension: 16,
                                              decorative: true,
                                              fallback: DAvatarFallback(
                                                child: Text(
                                                  host.characters.first
                                                      .toUpperCase(),
                                                ),
                                              ),
                                              child: avatar,
                                            ),
                                            Flexible(child: Text(host)),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (event.spansDays)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 100,
                                  ),
                                  child: Text(
                                    context.l10n.dayOf(
                                      '${day.difference(event.firstDay).inDays + 1}',
                                      '${event.lastDay.difference(event.firstDay).inDays + 1}',
                                    ),
                                    style: timeStyle,
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
