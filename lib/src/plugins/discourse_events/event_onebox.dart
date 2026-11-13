import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'event_card.dart';
import 'event_controller.dart';
import 'event_date_stamp.dart';
import 'event_navigation.dart';
import 'event_onebox_data.dart';
import 'event_time.dart';

class EventOnebox extends StatelessWidget {
  const EventOnebox({super.key, required this.data, this.siteUrl});
  final EventOneboxData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final controller = PluginUiScope.maybe(context, eventControllerKey);
    final navigation = PluginUiScope.maybe(context, eventNavigationKey);
    final site = siteUrl;
    if (controller == null || navigation == null || site == null) {
      return _PublishedEventOnebox(data: data, siteUrl: siteUrl);
    }
    return ListenableBuilder(
      listenable: controller.readerChanges,
      builder: (context, _) {
        final topicId = data.topicId;
        final fallback = _PublishedEventOnebox(
          data: data,
          siteUrl: site,
          controller: controller,
        );
        if (topicId == null) return fallback;
        return FutureBuilder(
          key: ValueKey((
            controller,
            site,
            topicId,
            controller.accountRevision(site),
          )),
          future: controller.eventForTopic(site, topicId),
          builder: (context, snapshot) => switch (snapshot.data) {
            final event? => PostEventCard(
              site: site,
              event: event,
              controller: controller,
              navigation: navigation,
            ),
            null => fallback,
          },
        );
      },
    );
  }
}

class _PublishedEventOnebox extends StatelessWidget {
  const _PublishedEventOnebox({
    required this.data,
    this.siteUrl,
    this.controller,
  });
  final EventOneboxData data;
  final String? siteUrl;
  final EventController? controller;

  @override
  Widget build(BuildContext context) {
    if (data.fallbackHtml case final html?) {
      return DCard(
        size: DCardSize.small,
        children: [
          DCardContent(
            child: CookedHtml(html: html, siteUrl: siteUrl),
          ),
        ],
      );
    }
    final zones = controller?.zones;
    final date = zones == null
        ? null
        : eventDate(
            data.startsAt,
            zones: zones,
            timezone: data.timezone,
            accountTimezone: siteUrl == null
                ? null
                : controller?.accountTimezone(siteUrl!),
            allDay: data.allDay,
          );
    final end = zones == null
        ? null
        : eventDate(
            data.endsAt,
            zones: zones,
            timezone: data.timezone,
            accountTimezone: siteUrl == null
                ? null
                : controller?.accountTimezone(siteUrl!),
            allDay: data.allDay,
          );
    String label(DateTime value) => data.allDay
        ? DateFormat.yMMMd().format(value)
        : '${DateFormat.yMMMd().format(value)} ${clockTimeLabel(context, value)}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 690),
      child: DCard(
        size: DCardSize.small,
        children: [
          DCardHeader(
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.sm,
              children: [
                if (date != null) EventDateStamp(date: date),
                Expanded(
                  child: LinkTarget(
                    url: data.url,
                    siteUrl: siteUrl,
                    child: DButton(
                      variant: DButtonVariant.inline,
                      alignment: AlignmentDirectional.centerStart,
                      isLink: true,
                      label: Text(
                        data.title,
                        softWrap: true,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      onPressed: () => unawaited(
                        openLink(context, data.url, siteUrl: siteUrl),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          DCardContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.sm,
              children: [
                if (data.image case final image?)
                  SiteImage(
                    url: image,
                    siteUrl: siteUrl,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.contain,
                    // One bound keeps the aspect ratio; contain never draws taller.
                    cacheHeight: imagePhysicalPixels(context, 180),
                  ),
                if (date != null)
                  Text(
                    data.allDay
                        ? end == null || DateUtils.isSameDay(date, end)
                              ? context.l10n.allDayEventtime(label(date))
                              : context.l10n.allDayEventtimeValue(
                                  label(date),
                                  label(end),
                                )
                        : end == null
                        ? label(date)
                        : '${label(date)} → ${label(end)}',
                  )
                else if (data.startsAt case final start?)
                  Text(start),
                if (data.recurrence case final recurrence?) Text(recurrence),
                if (data.description case final description?) Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
