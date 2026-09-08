import '../../models/content_route.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/external_link.dart';
import '../../shell/site_url.dart';
import 'event_calendar_data.dart';
import 'event_controller.dart';
import 'event_data.dart';
import 'event_notifications.dart';

const eventNavigationKey = PluginServiceKey<EventNavigation>(
  owner: eventsPluginId,
  name: 'navigation',
);

final class EventNavigation implements PluginLinkHandler {
  const EventNavigation({
    required this.host,
    required this.editor,
    required this.controller,
  });
  final PluginRouteNavigationHost host;
  final PluginPostEditorHost editor;
  final EventController controller;

  void openEvent(String site, PostEvent event) {
    if (event.topicId case final topicId?) {
      host.openTopicPost(
        siteUrl: site,
        topicId: topicId,
        postNumber:
            eventInt(eventObject(event.fields['post'])?['post_number']) ?? 1,
      );
    }
  }

  void edit(String site, PostEvent event) {
    if (!editor.open(site, event.id, focusText: '[event')) {
      openEvent(site, event);
    }
  }

  Future<bool> openWeb(String site, PostEvent event) {
    final serverPath = eventText(eventObject(event.fields['post'])?['url']);
    return openExternalLink(
      serverPath == null
          ? resolveSitePath(site, event.topicPath.substring(1))
          : resolveSiteUrl(serverPath, site),
    );
  }

  void openDirectory({
    bool mine = false,
    EventCalendarPage? page,
    bool replace = false,
  }) {
    final route = ContentRoute(
      id: page?.routeId(mine) ?? (mine ? 'events-mine' : 'events-upcoming'),
      title: mine ? 'My events' : 'Upcoming events',
      icon: EventIcons.calendar,
    );
    if (host.currentContent?.id == route.id) return;
    if (replace) {
      host.replaceCurrentContent(route);
    } else {
      host.pushContent(route);
    }
  }

  void rememberDirectory({
    required bool mine,
    required EventCalendarPage page,
  }) {
    if (EventCalendarPage.readRoute(host.currentContent?.id ?? '') == null) {
      return;
    }
    openDirectory(mine: mine, page: page, replace: true);
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null) return false;
    final index = host.sites.indexWhere((site) => site.serves(target));
    if (index < 0) return false;
    final site = host.sites[index];
    final path = site.pathWithin(target);
    if (path == null || !path.startsWith('/upcoming-events')) return false;
    final route = EventCalendarPage.readRoute(
      path.startsWith('/upcoming-events/mine')
          ? path.replaceFirst('/upcoming-events/mine', 'events-mine')
          : path.replaceFirst('/upcoming-events', 'events-upcoming'),
    );
    if (route == null) return false;
    if (!controller.settings(site.url).enabled) return false;
    if (route.mine && !site.isConnected) return false;
    if (host.currentSite?.url != site.url) host.selectInstance(index);
    openDirectory(mine: route.mine, page: route.page);
    return true;
  }
}
