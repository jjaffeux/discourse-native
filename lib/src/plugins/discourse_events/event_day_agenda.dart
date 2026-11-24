import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'event_calendar_data.dart';
import 'event_data.dart' show EventPerson;

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
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: DSpacing.md),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: DItem(
            variant: DItemVariant.muted,
            size: DItemSize.sm,
            children: [
              DItemContent(children: [Text(context.l10n.nothingPlanned)]),
            ],
          ),
        ),
      );
    }
    final gaps = <int>{};
    DateTime? latestEnd;
    for (final (index, event) in events.indexed) {
      if (event.isAllDay) continue;
      final previous = latestEnd;
      if (previous != null &&
          event.start.difference(previous) >= const Duration(hours: 2)) {
        gaps.add(index);
      }
      if (previous == null || event.end.isAfter(previous)) {
        latestEnd = event.end;
      }
    }
    return DScrollBar(
      showScrollbar: false,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          DSpacing.md,
          0,
          DSpacing.md,
          MediaQuery.paddingOf(context).bottom + DSpacing.sm,
        ),
        itemCount: events.length,
        itemBuilder: (context, index) => _EventAgendaRow(
          event: events[index],
          day: day,
          creatorAvatar: creatorAvatar,
          time: formatTime(events[index]),
          gapAbove: gaps.contains(index),
          onOpen: () => onOpen(events[index]),
        ),
      ),
    );
  }
}

class _EventAgendaRow extends StatelessWidget {
  const _EventAgendaRow({
    required this.event,
    required this.day,
    required this.creatorAvatar,
    required this.time,
    required this.gapAbove,
    required this.onOpen,
  });

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
    final host = creator?.name ?? creator?.username;
    final metadata = event.scheduleMetadata(day);
    final hasDetails = event.categoryName != null || host != null;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        const PositionedDirectional(
          top: 0,
          bottom: 0,
          end: 6,
          child: DSeparator(orientation: Axis.vertical, thickness: 2),
        ),
        if (gapAbove)
          const PositionedDirectional(
            top: 0,
            end: 1,
            child: Column(
              spacing: 2,
              children: [
                DSeparator(length: 12, thickness: 2),
                DSeparator(length: 12, thickness: 2),
              ],
            ),
          ),
        PositionedDirectional(
          top: 12 + (gapAbove ? 8 : 0),
          bottom: DSpacing.sm,
          end: 5,
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            child: DSeparator(
              orientation: Axis.vertical,
              color: color,
              thickness: 4,
              radius: const BorderRadius.all(Radius.circular(3)),
              length:
                  event.end
                      .difference(event.start)
                      .inMinutes
                      .clamp(12, 72)
                      .toDouble() /
                  2,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            end: 22,
            top: gapAbove ? 8 : 0,
            bottom: DSpacing.sm,
          ),
          child: DCard(
            backgroundColor: Color.lerp(tokens.raisedBackground, color, .12),
            spacing: 0,
            border: false,
            child: DItem(
              shape: DItemShape.card,
              size: DItemSize.sm,
              onPressed: onOpen,
              children: [
                DItemContent(
                  children: [
                    Row(
                      spacing: DSpacing.sm,
                      children: [
                        if (event.event.watching?.status == 'going')
                          DIcon(
                            DIcons.circleCheck,
                            color: tokens.primary,
                            semanticLabel: context.l10n.going,
                          ),
                        Expanded(
                          child: DItemTitle(
                            maxLines: null,
                            child: Text(event.title),
                          ),
                        ),
                        Text(time),
                      ],
                    ),
                    if (hasDetails)
                      DItemDescription(
                        child: Wrap(
                          spacing: DSpacing.sm,
                          runSpacing: DSpacing.xs,
                          children: [
                            if (event.categoryName case final category?)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: DSpacing.xs,
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
                                spacing: DSpacing.xs,
                                children: [
                                  DAvatar(
                                    dimension: 16,
                                    decorative: true,
                                    fallback: DAvatarFallback(
                                      child: Text(
                                        host.characters.first.toUpperCase(),
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
                    if ((!hasDetails || event.spansDays) && metadata.isNotEmpty)
                      DItemDescription(
                        child: Text(
                          hasDetails
                              ? context.l10n.dayOf(
                                  '${day.difference(event.firstDay).inDays + 1}',
                                  '${event.lastDay.difference(event.firstDay).inDays + 1}',
                                )
                              : metadata,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
