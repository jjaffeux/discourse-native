import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:intl/intl.dart';

import '../../models/content_route.dart';
import '../../models/post.dart';
import '../../models/sidebar.dart';
import '../../models/topic.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import 'event_calendar_data.dart';
import 'event_card.dart';
import 'event_composer.dart';
import 'event_composer_parser.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_directory.dart';
import 'event_navigation.dart';
import 'event_notifications.dart';
import 'event_time.dart';

final class DiscourseEventsPlugin
    implements
        SitePlugin,
        IconCatalogPlugin,
        SiteSettingsPlugin<EventSettings>,
        CurrentUserPlugin<EventUserPermissions>,
        PostRecordPlugin<EventPostData>,
        PostBodyPlugin,
        CookedElementPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        NotificationTypePlugin,
        CommunitySidebarPlugin,
        ContentPlugin {
  const DiscourseEventsPlugin();
  @override
  String get name => 'discourse-events';
  @override
  PluginIconCatalog get iconCatalog => eventIconCatalog;
  @override
  List<PluginNotificationType> get notificationTypes => eventNotificationTypes;
  @override
  PluginDataKey<EventPostData> get record => eventPostKey;
  @override
  EventPostData? readPost(Map<String, dynamic> json, String siteUrl) =>
      EventPostData.decode(json);
  @override
  EventPostData? mergeAfterPostEdit(
    EventPostData? held,
    EventPostData? incoming,
  ) => incoming;
  @override
  PluginDataPersistenceCodec<EventSettings> get siteSettingsCodec =>
      const EventSettingsCodec();
  @override
  EventSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      EventSettings.decode(json);
  @override
  PluginDataPersistenceCodec<EventUserPermissions> get currentUserCodec =>
      const EventUserCodec();
  @override
  EventUserPermissions? readCurrentUser(
    Map<String, dynamic> json,
    String siteUrl,
  ) => EventUserPermissions.decode(json);
  @override
  ComposerSyntaxKind get composerSyntaxKind => eventSyntaxKind;
  @override
  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  ) => EventSyntaxPolicy(context);

  @override
  Widget? postBodyElement(PluginPostBodyContext context, dom.Element element) {
    PostEvent? event;
    final record = context.post.plugins.get(eventPostKey);
    if (element.classes.contains('discourse-post-event')) {
      for (
        var parent = element.parent;
        parent != null;
        parent = parent.parent
      ) {
        if (parent.localName == 'blockquote' ||
            parent.localName == 'pre' ||
            parent.localName == 'aside') {
          return EventCookedFallback(element: element);
        }
      }
      event = record?.event;
      if (event == null ||
          event.id != context.post.id ||
          context.post.postNumber != 1) {
        return EventCookedFallback(element: element);
      }
    } else if (element.localName == 'aside' &&
        element.classes.contains('quote') &&
        element.attributes['data-post'] == '1' &&
        !element.attributes.containsKey('data-username')) {
      event = record
          ?.oneboxes[int.tryParse(element.attributes['data-topic'] ?? '')];
      if (event == null) return null;
    } else {
      return null;
    }
    final controller = PluginUiScope.maybe(
      context.buildContext,
      eventControllerKey,
    );
    final navigation = PluginUiScope.maybe(
      context.buildContext,
      eventNavigationKey,
    );
    if (controller == null || navigation == null) {
      return EventCookedFallback(element: element);
    }
    return PostEventCard(
      site: context.siteUrl,
      event: event,
      controller: controller,
      navigation: navigation,
    );
  }

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      element.classes.contains('discourse-post-event')
      ? EventCookedFallback(element: element)
      : null;

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerEditorHost editor,
  ) {
    final policy = editor.syntaxPolicy<EventSyntaxPolicy>(eventSyntaxKind);
    if (policy == null ||
        !policy.canAuthor ||
        !editor.isCurrent ||
        editor.loadingBody) {
      return const [];
    }
    final blocks = parseEventBlocks(editor.value.text);
    if (blocks.length > 1) return const [];
    if (blocks.isEmpty && hasEventMarkup(editor.value.text)) return const [];
    return [
      ComposerToolbarContribution(
        icon: EventIcons.calendar,
        label: blocks.isEmpty ? 'Add event' : 'Edit event',
        onInvoke: () => unawaited(
          openEventComposer(context, editor, policy, block: blocks.firstOrNull),
        ),
      ),
    ];
  }

  @override
  Listenable? communitySidebarListenable(BuildContext context) =>
      PluginUiScope.maybe(context, eventControllerKey);
  @override
  List<SidebarDestination> communitySidebarDestinations(BuildContext context) {
    final controller = PluginUiScope.require(context, eventControllerKey);
    final navigation = PluginUiScope.require(context, eventNavigationKey);
    final site = navigation.host.currentSite;
    if (site == null) return const [];
    final settings = controller.settings(site.url);
    if (!settings.enabled || !settings.showUpcomingEvents) return const [];
    return const [
      SidebarDestination(
        id: 'events-upcoming',
        label: 'Upcoming events',
        icon: EventIcons.calendar,
      ),
    ];
  }

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final calendarRoute = EventCalendarPage.readRoute(route.id);
    if (calendarRoute == null) return null;
    final navigation = PluginUiScope.require(context, eventNavigationKey);
    final site = navigation.host.currentSite;
    if (site == null) return null;
    return EventDirectory(
      site: site.url,
      mine: calendarRoute.mine,
      page: calendarRoute.page,
      navigation: navigation,
      controller: PluginUiScope.require(context, eventControllerKey),
    );
  }
}

/// Topic and post records have separate keys, while retaining one owner.
final class EventTopicPlugin
    implements
        SitePlugin,
        TopicRecordPlugin<EventTopicData>,
        TopicListMetadataPlugin,
        TopicPropertiesPlugin {
  const EventTopicPlugin();
  @override
  String get name => 'discourse-events';
  @override
  PluginDataKey<EventTopicData> get record => eventTopicKey;
  @override
  EventTopicData? readTopic(Map<String, dynamic> json, String siteUrl) =>
      EventTopicData.decode(json);

  Widget? _date(BuildContext context, String site, EventTopicData? event) {
    if (event == null) return null;
    final controller = PluginUiScope.maybe(context, eventControllerKey);
    if (controller == null || !controller.settings(site).displayTopicDate) {
      return null;
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) {
        final date = eventDate(
          event.startsAt,
          zones: controller.zones,
          timezone: event.timezone,
          allDay: event.allDay,
          showLocalTime: event.showLocalTime,
          accountTimezone: controller.accountTimezone(site),
        );
        return date == null
            ? const SizedBox.shrink()
            : Text(
                event.allDay
                    ? DateFormat.yMMMd().format(date)
                    : DateFormat.yMMMd().add_Hm().format(date),
              );
      },
    );
  }

  @override
  List<Widget> topicListMetadata(
    BuildContext context,
    String siteUrl,
    Topic topic,
  ) => [?_date(context, siteUrl, topic.plugins.get(eventTopicKey))];
  @override
  List<TopicPropertySection> topicProperties(
    BuildContext context,
    String siteUrl,
    TopicDetail topic,
  ) => [
    if (_date(context, siteUrl, topic.plugins.get(eventTopicKey))
        case final widget?)
      TopicPropertySection(
        label: 'Event',
        values: [widget],
        header: (context, showDetails) =>
            InkWell(onTap: showDetails, child: widget),
      ),
  ];
}
