import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'gamification_controller.dart';
import 'gamification_models.dart';

const gamificationNavigationKey = PluginServiceKey<GamificationNavigation>(
  owner: gamificationPluginId,
  name: 'navigation',
);
const gamificationIcon = DIcons.star;

final class GamificationRoute {
  const GamificationRoute({
    this.boardId,
    this.period,
    this.admin = false,
    this.create = false,
  });
  final int? boardId;
  final GamificationPeriod? period;
  final bool admin, create;
  GamificationQuery get query => GamificationQuery(
    target: boardId == null
        ? const DefaultLeaderboard()
        : LeaderboardById(boardId!),
    period: period,
  );
  String get id {
    final path = admin
        ? 'gamification/admin${create
              ? '/new'
              : boardId == null
              ? ''
              : '/$boardId'}'
        : 'gamification${boardId == null ? '' : '/$boardId'}';
    return '$path${period == null || admin ? '' : '?period=${period!.wire}'}';
  }

  static GamificationRoute? parse(String id) {
    final uri = Uri.tryParse(id);
    if (uri == null) return null;
    final admin = RegExp(
      r'^gamification/admin(?:/(new|[1-9][0-9]*))?$',
    ).firstMatch(uri.path);
    if (admin != null) {
      return GamificationRoute(
        admin: true,
        create: admin[1] == 'new',
        boardId: int.tryParse(admin[1] ?? ''),
      );
    }
    final match = RegExp(
      r'^gamification(?:/([1-9][0-9]*))?$',
    ).firstMatch(uri.path);
    if (match == null) return null;
    try {
      final period = uri.queryParameters['period'];
      return GamificationRoute(
        boardId: int.tryParse(match[1] ?? ''),
        period: period == null ? null : GamificationPeriod.decode(period),
      );
    } on FormatException {
      return null;
    } on GamificationUnsupportedResponse {
      return null;
    }
  }

  static GamificationRoute? web(String path, Map<String, String> params) {
    final admin = RegExp(
      r'^/admin/plugins/discourse-gamification(?:/leaderboards(?:/(new|[1-9][0-9]*)(?:/edit)?)?)?(?:\.json)?/?$',
    ).firstMatch(path);
    if (admin != null) {
      return GamificationRoute(
        admin: true,
        create: admin[1] == 'new',
        boardId: int.tryParse(admin[1] ?? ''),
      );
    }
    if (RegExp(r'^/admin/plugins/gamification(?:\.json)?/?$').hasMatch(path)) {
      return const GamificationRoute(admin: true);
    }
    final match = RegExp(
      r'^/leaderboard(?:/([1-9][0-9]*))?(?:\.json)?/?$',
    ).firstMatch(path);
    if (match == null) return null;
    try {
      return GamificationRoute(
        boardId: int.tryParse(match[1] ?? ''),
        period: params['period'] == null
            ? null
            : GamificationPeriod.decode(params['period']),
      );
    } on GamificationUnsupportedResponse {
      return null;
    }
  }
}

final class GamificationNavigation implements PluginLinkHandler {
  const GamificationNavigation({required this.host, required this.controller});
  final PluginRouteNavigationHost host;
  final GamificationController controller;
  void open([GamificationRoute route = const GamificationRoute()]) {
    final site = host.currentSite;
    if (site != null) openForSite(site.url, route);
  }

  void openForSite(String site, GamificationRoute route) {
    final index = host.sites.indexWhere((entry) => entry.url == site);
    if (index < 0 ||
        !(route.admin
            ? controller.canManage(site)
            : controller.enabled(site))) {
      return;
    }
    if (host.currentSite?.url != site) host.selectInstance(index);
    host.pushContent(
      ContentRoute(
        destination: ExtensionDestination(route.id),
        title: appL10n.gamificationTitle,
        icon: gamificationIcon,
      ),
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
    if (host.currentSite?.url != owner.forum.url) {
      host.selectInstance(owner.index);
    }
    open(route);
    onNavigated?.call();
    return true;
  }
}
