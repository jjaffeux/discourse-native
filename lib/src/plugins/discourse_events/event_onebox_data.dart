import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:html/dom.dart' as dom;

import 'event_cooked_visibility.dart';

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
