// ignore_for_file: prefer_initializing_formals

import '../../models/content_route.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/site_url.dart';
import '../../theme/d_icons.dart';
import 'assigned_group_link.dart';

typedef AssignGroupRoutePermission = bool Function(String siteUrl);

/// Assign-owned link routing for the current shell session.
final class AssignShellService implements PluginLinkHandler {
  const AssignShellService({
    required PluginRouteNavigationHost host,
    required PluginTopicListNavigationHost topicLists,
    required AssignGroupRoutePermission canOpenGroupAssignments,
  }) : _host = host,
       _topicLists = topicLists,
       _canOpenGroupAssignments = canOpenGroupAssignments;

  final PluginRouteNavigationHost _host;
  final PluginTopicListNavigationHost _topicLists;
  final AssignGroupRoutePermission _canOpenGroupAssignments;

  @override
  Future<bool> openPluginUrl(String url) async {
    final absolute = resolveSiteUrl(url, _host.currentSite?.url);
    final link = AssignedGroupLink.parse(absolute);
    if (link == null) return false;

    final index = _host.sites.indexWhere((site) => site.serves(link.uri));
    if (index < 0 || !_host.sites[index].isConnected) return false;
    final site = _host.sites[index];
    if (!_canOpenGroupAssignments(site.url)) return false;

    if (_host.currentSite?.url != site.url) _host.selectInstance(index);
    _topicLists.openTopicList(
      ContentRoute(
        id: 'assign-group-${Uri.encodeComponent(link.groupName)}',
        title: 'Assigned to ${link.groupName}',
        icon: DIcons.userPlus,
        feedPath: link.feedPath,
      ),
    );
    return true;
  }
}
