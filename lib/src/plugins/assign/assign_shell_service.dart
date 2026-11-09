// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'assigned_group.dart';
import 'assigned_group_link.dart';

typedef AssignGroupRoutePermission = bool Function(String siteUrl);
typedef AssignTopicOpeningPost = int? Function(String siteUrl, Topic topic);

final class AssignShellService implements PluginLinkHandler {
  const AssignShellService({
    required PluginRouteNavigationHost host,
    required AssignGroupRoutePermission canOpenGroupAssignments,
    required AssignTopicOpeningPost openingPostFor,
  }) : _host = host,
       _canOpenGroupAssignments = canOpenGroupAssignments,
       _openingPostFor = openingPostFor;

  final PluginRouteNavigationHost _host;
  final AssignGroupRoutePermission _canOpenGroupAssignments;
  final AssignTopicOpeningPost _openingPostFor;

  void selectGroupFilter(String groupName, AssignedGroupFilter filter) {
    final route = ContentRoute.group(
      GroupRoute.plugin(
        groupName: groupName,
        owner: 'discourse-assign',
        section: 'assigned',
        subsection: filter.routeSegment(groupName),
      ),
      title: groupName,
    );
    if (!route.sameDestinationAs(_host.currentContent)) {
      _host.replaceCurrentContent(route);
    }
  }

  void openTopic(Topic topic) {
    final siteUrl = _host.currentSite?.url;
    if (siteUrl == null) return;
    final postNumber = _openingPostFor(siteUrl, topic);
    _host.pushContent(
      ContentRoute.topic(
        topicId: topic.id,
        slug: topic.slug,
        title: topic.displayTitle,
        postNumber: postNumber,
      ),
    );
    _host.openTopicPost(
      siteUrl: siteUrl,
      topicId: topic.id,
      postNumber: postNumber ?? 1,
    );
  }

  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  }) {
    _host.openTopicPost(
      siteUrl: siteUrl,
      topicId: topicId,
      postNumber: postNumber,
      highlight: true,
    );
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) async {
    final absolute = resolveSiteUrl(url, _host.currentSite?.url);
    final target = Uri.tryParse(absolute);
    if (target == null) return false;
    final sites = _host.sites;
    final owner = mostSpecificServingForum(
      sites,
      target,
      siteUrl: (site) => site.url,
    );
    if (owner == null || !owner.forum.isConnected) return false;
    final site = owner.forum;
    final link = AssignedGroupLink.parse(absolute, siteUrl: site.url);
    if (link == null) return false;
    if (!_canOpenGroupAssignments(site.url)) return false;

    final route = ContentRoute.group(
      GroupRoute.plugin(
        groupName: link.groupName,
        owner: 'discourse-assign',
        section: 'assigned',
        subsection: link.filter.routeSegment(link.groupName),
      ),
      title: link.groupName,
    );
    if ((origin == PluginLinkOrigin.direct ||
            origin == PluginLinkOrigin.inApp) &&
        _host.currentSite?.url == site.url &&
        route.sameDestinationAs(_host.currentContent)) {
      onNavigated?.call();
    } else {
      _host.pushContent(
        route,
        siteUrl: site.url,
        origin: origin,
        onNavigated: onNavigated,
      );
    }
    return true;
  }
}
