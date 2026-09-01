// ignore_for_file: prefer_initializing_formals

import '../../models/content_route.dart';
import '../../models/group_route.dart';
import '../../models/topic.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/site_url.dart';
import 'assigned_group.dart';
import 'assigned_group_link.dart';

typedef AssignGroupRoutePermission = bool Function(String siteUrl);

final class AssignShellService implements PluginLinkHandler {
  const AssignShellService({
    required PluginRouteNavigationHost host,
    required AssignGroupRoutePermission canOpenGroupAssignments,
  }) : _host = host,
       _canOpenGroupAssignments = canOpenGroupAssignments;

  final PluginRouteNavigationHost _host;
  final AssignGroupRoutePermission _canOpenGroupAssignments;

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
    if (_host.currentContent?.id != route.id) {
      _host.replaceCurrentContent(route);
    }
  }

  void openTopic(Topic topic) {
    _host.pushContent(
      ContentRoute.topic(
        topicId: topic.id,
        slug: topic.slug,
        title: topic.title,
        postNumber: topic.lastUnreadPostNumber,
      ),
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
    );
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) async {
    final absolute = resolveSiteUrl(url, _host.currentSite?.url);
    final link = AssignedGroupLink.parse(absolute);
    if (link == null) return false;

    final index = _host.sites.indexWhere((site) => site.serves(link.uri));
    if (index < 0 || !_host.sites[index].isConnected) return false;
    final site = _host.sites[index];
    if (!_canOpenGroupAssignments(site.url)) return false;

    if (_host.currentSite?.url != site.url) _host.selectInstance(index);
    final route = ContentRoute.group(
      GroupRoute.plugin(
        groupName: link.groupName,
        owner: 'discourse-assign',
        section: 'assigned',
        subsection: link.filter.routeSegment(link.groupName),
      ),
      title: link.groupName,
    );
    if (_host.currentContent?.id == route.id) return true;
    _host.pushContent(route);
    return true;
  }
}
