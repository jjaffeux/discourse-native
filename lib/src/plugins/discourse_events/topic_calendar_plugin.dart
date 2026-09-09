import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/external_link.dart';
import '../../shell/site_url.dart';
import 'event_controller.dart';
import 'event_navigation.dart';
import 'topic_calendar.dart';
import 'topic_calendar_data.dart';

final class TopicCalendarPlugin
    implements
        SitePlugin,
        PostRecordPlugin<TopicCalendarData>,
        SiteSettingsPlugin<TopicCalendarSettings>,
        PostBodyPlugin,
        CookedElementPlugin,
        TopicLiveReloadPlugin {
  const TopicCalendarPlugin();
  @override
  String get name => 'discourse-events';
  @override
  PluginDataKey<TopicCalendarData> get record => topicCalendarKey;
  @override
  TopicCalendarData? readPost(Map<String, dynamic> json, String siteUrl) =>
      TopicCalendarData.decode(json);
  @override
  TopicCalendarData? mergeAfterPostEdit(
    TopicCalendarData? held,
    TopicCalendarData? incoming,
  ) => incoming;
  @override
  PluginDataPersistenceCodec<TopicCalendarSettings> get siteSettingsCodec =>
      const TopicCalendarSettingsCodec();
  @override
  TopicCalendarSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => TopicCalendarSettings.decode(json);

  dom.Element? _calendar(dom.Element element) {
    if (element.localName != 'div') return null;
    if (element.classes.contains('calendar')) return element;
    if (element.classes.contains('discourse-calendar-wrap')) {
      // Own the wrapper as well to discard the legacy empty timezone header.
      final calendars = element.querySelectorAll('div.calendar');
      if (calendars.length == 1) return calendars.single;
    }
    return null;
  }

  @override
  Widget? postBodyElement(PluginPostBodyContext context, dom.Element element) {
    final calendar = _calendar(element);
    if (calendar == null) return null;
    final data = context.post.plugins.get(topicCalendarKey);
    final topicId = data?.topicId ?? context.topic?.id;
    void openWeb() {
      if (topicId != null) {
        unawaited(
          openExternalLink(resolveSitePath(context.siteUrl, 't/$topicId/1')),
        );
      }
    }

    Widget fallback() => TopicCalendarFallback(
      text: calendar.text.trim(),
      onOpenWeb: topicId == null ? null : openWeb,
    );
    for (var parent = element.parent; parent != null; parent = parent.parent) {
      if (const {
        'blockquote',
        'pre',
        'code',
        'aside',
      }.contains(parent.localName)) {
        return fallback();
      }
    }
    final options = TopicCalendarOptions.fromElement(calendar);
    if (context.post.postNumber != 1 ||
        data == null ||
        options.type != 'dynamic') {
      return fallback();
    }
    final controller = PluginUiScope.maybe(
      context.buildContext,
      eventControllerKey,
    );
    final navigation = PluginUiScope.maybe(
      context.buildContext,
      eventNavigationKey,
    );
    if (controller == null || navigation == null) return fallback();
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) => TopicCalendar(
        key: ValueKey((context.siteUrl, context.post.id)),
        data: data,
        options: options,
        zones: controller.zones,
        settings:
            controller.siteState
                .siteConfigFor(context.siteUrl)
                .plugins
                .get(topicCalendarSettingsKey) ??
            const TopicCalendarSettings(),
        accountTimezone: controller.accountTimezone(context.siteUrl),
        onOpenReply: (number) => navigation.host.openTopicPost(
          siteUrl: context.siteUrl,
          topicId: data.topicId,
          postNumber: number,
          highlight: true,
        ),
        onOpenWeb: openWeb,
      ),
    );
  }

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    final calendar = _calendar(element);
    return calendar == null
        ? null
        : TopicCalendarFallback(text: calendar.text.trim());
  }

  @override
  bool staleTopic(int topicId, String channel, Object? data) =>
      channel == '/topic/$topicId' &&
      data is Map &&
      const {'calendar_change', 'deleted', 'recovered'}.contains(data['type']);
}

final class TopicCalendarFallback extends StatelessWidget {
  const TopicCalendarFallback({super.key, required this.text, this.onOpenWeb});
  final String text;
  final VoidCallback? onOpenWeb;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Topic calendar'),
        if (text.isNotEmpty) Text(text),
        if (onOpenWeb != null)
          DButton(
            variant: DButtonVariant.transparentPrimary,
            onPressed: onOpenWeb,
            label: const Text('Open web calendar'),
          )
        else
          const Text('Open the original topic to view this calendar.'),
      ],
    ),
  );
}
