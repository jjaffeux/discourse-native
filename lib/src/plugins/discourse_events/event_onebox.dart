import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:intl/intl.dart';

import 'event_card.dart';
import 'event_controller.dart';
import 'event_cooked_visibility.dart';
import 'event_date_stamp.dart';
import 'event_navigation.dart';
import 'event_time.dart';

final class EventOneboxData {
  const EventOneboxData({
    required this.title,
    required this.url,
    this.topicId,
    this.startsAt,
    this.endsAt,
    this.timezone,
    this.allDay = false,
    this.image,
    this.description,
    this.recurrence,
    this.fallbackHtml,
  });

  final String title, url;
  final int? topicId;
  final String? startsAt, endsAt, timezone, image, description, recurrence;
  final bool allDay;
  final String? fallbackHtml;

  static EventOneboxData? from(dom.Element element, String? siteUrl) {
    if (!element.classes.contains('discourse-event-onebox') &&
        !(element.localName == 'aside' &&
            (element.classes.contains('onebox') ||
                element.classes.contains('quote')))) {
      return null;
    }
    final visible = eventVisibleCookedElement(element);
    final event = visible.classes.contains('discourse-event-onebox')
        ? visible
        : visible.querySelector('.discourse-event-onebox');
    if (event == null) {
      if (siteUrl == null ||
          visible.localName != 'aside' ||
          !visible.classes.contains('quote') ||
          visible.attributes['data-post'] != '1' ||
          visible.attributes.containsKey('data-username')) {
        return null;
      }
      final topicId = int.tryParse(visible.attributes['data-topic'] ?? '');
      if (topicId == null || topicId <= 0) return null;
      return EventOneboxData(
        title: visible.querySelector('.title')?.text.trim() ?? '',
        url: resolveSitePath(siteUrl, 't/$topicId/1'),
        topicId: topicId,
        fallbackHtml: visible.innerHtml,
      );
    }
    final link = event.querySelector('h3 a');
    final rawUrl = link?.attributes['href'];
    if (rawUrl == null) return null;
    final uri = Uri.tryParse(
      siteUrl == null ? rawUrl : resolveSiteUrl(rawUrl, siteUrl),
    );
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final title = link!.text.trim();
    if (title.isEmpty) return null;
    int? topicId;
    if (siteUrl != null && DiscourseInstance.urlServes(siteUrl, uri)) {
      final target = TopicLink.parse(uri.toString(), siteUrl: siteUrl);
      if (target != null && (target.postNumber ?? 1) == 1) {
        topicId = target.topicId;
      }
    }
    return EventOneboxData(
      title: title,
      url: uri.toString(),
      topicId: topicId,
      startsAt: event.attributes['data-event-starts-at'],
      endsAt: event.attributes['data-event-ends-at'],
      timezone: event.attributes['data-event-timezone'],
      allDay: event.attributes['data-event-all-day'] == 'true',
      image: _imageUrl(
        event
            .querySelector('.discourse-event-onebox__image')
            ?.attributes['src'],
        uri,
      ),
      description: event
          .querySelector('.discourse-event-onebox__description')
          ?.text
          .trim(),
      recurrence: event
          .querySelector('.discourse-event-onebox__recurrence-text')
          ?.text
          .trim(),
    );
  }

  static String? _imageUrl(String? source, Uri eventUrl) {
    final trimmed = source?.trim();
    final reference = trimmed == null || trimmed.isEmpty
        ? null
        : Uri.tryParse(trimmed);
    if (reference == null) return null;
    final url = eventUrl.resolveUri(reference);
    return const {'http', 'https'}.contains(url.scheme) &&
            url.host.isNotEmpty &&
            url.userInfo.isEmpty
        ? url.toString()
        : null;
  }
}

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
