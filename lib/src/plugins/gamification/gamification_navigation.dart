import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'gamification_controller.dart';
import 'gamification_models.dart';
import 'gamification_route.dart';

const gamificationNavigationKey = PluginServiceKey<GamificationNavigation>(
  owner: gamificationPluginId,
  name: 'navigation',
);
const gamificationIcon = DIcons.star;

final class GamificationNavigation
    implements PluginLinkHandler, PluginMobileBackPath {
  const GamificationNavigation({required this.host, required this.controller});
  final PluginRouteNavigationHost host;
  final GamificationController controller;

  @override
  List<ContentRoute> mobileBackPath(ContentRoute route) {
    final target = GamificationRoute.parse(route.id);
    if (target == null ||
        !target.admin ||
        (!target.create && target.boardId == null)) {
      return const [];
    }
    return [_contentRoute(const GamificationRoute(admin: true))];
  }

  ContentRoute _contentRoute(GamificationRoute route) => ContentRoute(
    destination: ExtensionDestination(route.id),
    title: appL10n.gamificationTitle,
    icon: gamificationIcon,
  );

  void open([GamificationRoute route = const GamificationRoute()]) {
    final site = host.currentSite;
    if (site != null) openForSite(site.url, route);
  }

  void openForSite(
    String site,
    GamificationRoute route, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) {
    final index = host.sites.indexWhere((entry) => entry.url == site);
    if (index < 0 ||
        !(route.admin
            ? controller.canManage(site)
            : controller.enabled(site))) {
      return;
    }
    host.pushContent(
      _contentRoute(route),
      siteUrl: site,
      origin: origin,
      onNavigated: onNavigated,
    );
  }

  void updatePeriod(String site, GamificationQuery query) {
    final route = GamificationRoute.parse(host.currentContent?.id ?? '');
    if (host.currentSite?.url != site ||
        route == null ||
        route.admin ||
        route.boardId != query.target.id) {
      return;
    }
    host.replaceCurrentContent(
      ContentRoute(
        destination: ExtensionDestination(
          GamificationRoute(boardId: query.target.id, period: query.period).id,
        ),
        title: host.currentContent!.title,
        icon: gamificationIcon,
      ),
    );
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null) return false;
    final owner = mostSpecificServingForum(
      host.sites,
      target,
      siteUrl: (site) => site.url,
    );
    if (owner == null) return false;
    final path = owner.forum.pathWithin(target);
    if (path == null) return false;
    final GamificationRoute? route;
    try {
      route = GamificationRoute.web(path, target.queryParameters);
    } on FormatException {
      return false;
    }
    if (route == null ||
        !(route.admin
            ? controller.canManage(owner.forum.url)
            : controller.enabled(owner.forum.url))) {
      return false;
    }
    openForSite(
      owner.forum.url,
      route,
      origin: origin,
      onNavigated: onNavigated,
    );
    return true;
  }
}
