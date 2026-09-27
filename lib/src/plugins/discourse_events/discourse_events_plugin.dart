import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import 'event_calendar_data.dart';
import 'event_card.dart';
import 'event_composer.dart';
import 'event_composer_parser.dart';
import 'event_controller.dart';
import 'event_cooked_visibility.dart';
import 'event_data.dart';
import 'event_directory.dart';
import 'event_navigation.dart';
import 'event_notifications.dart';
import 'event_topic_title.dart';

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
        ContentPlugin,
        ContentChromePlugin {
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
    final hidden = eventHiddenCookedElement(element);
    if (hidden != null) return hidden;
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
          return EventCookedFallback(
            element: element,
            siteUrl: context.siteUrl,
          );
        }
      }
      event = record?.event;
      if (event == null ||
          event.id != context.post.id ||
          context.post.postNumber != 1) {
        return EventCookedFallback(element: element, siteUrl: context.siteUrl);
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
      return EventCookedFallback(element: element, siteUrl: context.siteUrl);
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
      eventHiddenCookedElement(element) ??
      (element.classes.contains('discourse-post-event')
          ? EventCookedFallback(element: element, siteUrl: siteUrl)
          : null);

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

  // The link reads only the current site and its settings, and the shell
  // redraws the sidebar when either changes. The controller notifies for every
  // event's load and write, none of which the link reads.
  @override
  Listenable? communitySidebarListenable(BuildContext context) => null;
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
        mobileNavigationLabel: 'Events',
        icon: EventIcons.calendar,
      ),
    ];
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      EventCalendarPage.readRoute(route.id) != null;

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
        TopicListTitlePlugin {
  const EventTopicPlugin();
  @override
  String get name => 'discourse-events';
  @override
  PluginDataKey<EventTopicData> get record => eventTopicKey;
  @override
  EventTopicData? readTopic(Map<String, dynamic> json, String siteUrl) =>
      EventTopicData.decode(json);

  @override
  Widget? decorateTopicListTitle(
    BuildContext context,
    String siteUrl,
    Topic topic,
    Widget title,
  ) {
    final event = topic.plugins.get(eventTopicKey);
    final controller = PluginUiScope.maybe(context, eventControllerKey);
    if (event == null || controller == null) return null;
    return EventTopicTitle(
      site: siteUrl,
      topicTitle: topic.title,
      event: event,
      controller: controller,
      child: title,
    );
  }
}
