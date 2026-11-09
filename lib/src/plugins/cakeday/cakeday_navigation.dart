import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'cakeday_controller.dart';
import 'cakeday_data.dart';

const cakedayNavigationKey = PluginServiceKey<CakedayNavigation>(
  owner: cakedayPluginId,
  name: 'navigation',
);

final class CakedayNavigation implements PluginLinkHandler {
  const CakedayNavigation(this.host, this.controller);
  final PluginRouteNavigationHost host;
  final CakedayController controller;
  void open(
    CakedayQuery query, {
    bool replace = false,
    String? siteUrl,
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) {
    final site = siteUrl ?? host.currentSite?.url;
    if (site == null || !controller.enabled(site, query.kind)) return;
    final route = ContentRoute(
      destination: ExtensionDestination(query.id),
      title: query.kind == CakedayKind.birthdays
          ? appL10n.cakedayBirthdays
          : appL10n.cakedayAnniversaries,
      icon: DIcons.cakeCandles,
    );
    if (replace) {
      host.replaceCurrentContent(route);
    } else {
      host.pushContent(
        route,
        siteUrl: site,
        origin: origin,
        onNavigated: onNavigated,
      );
    }
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
    final clean = path.replaceAll(RegExp(r'^/|/$'), '');
    var query = CakedayQuery.parse(
      clean,
      today: controller.viewerToday(owner.forum.url),
    );
    if (query?.period == CakedayPeriod.month) {
      final Map<String, String> parameters;
      try {
        parameters = target.queryParameters;
      } on FormatException {
        return false;
      }
      if (parameters['month'] case final value?) {
        final month = int.tryParse(value);
        if (month == null || month < 1 || month > 12) return false;
        query = CakedayQuery(query!.kind, CakedayPeriod.month, month: month);
      }
    }
    if (query == null || !controller.enabled(owner.forum.url, query.kind)) {
      return false;
    }
    open(
      query,
      siteUrl: owner.forum.url,
      origin: origin,
      onNavigated: onNavigated,
    );
    return true;
  }
}
