import 'dart:ui' show Color;

import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import 'site_url.dart';

typedef ResolvedCoreLink = ({ContentRoute route, String siteUrl});

final class CoreLinkTarget {
  CoreLinkTarget._(this._target, this.instance);

  static CoreLinkTarget? match(
    String url, {
    required String? currentSiteUrl,
    required List<DiscourseInstance> instances,
  }) {
    final target = Uri.tryParse(resolveSiteUrl(url, currentSiteUrl));
    if (target == null) return null;
    final instance = mostSpecificServingForum(
      instances,
      target,
      siteUrl: (site) => site.url,
    )?.forum;
    return instance == null ? null : CoreLinkTarget._(target, instance);
  }

  final Uri _target;
  final DiscourseInstance instance;

  bool get isHomepage =>
      const {'', '/'}.contains(instance.pathWithin(_target)) &&
      !_target.hasQuery &&
      !_target.hasFragment;

  ContentRoute? decode({
    required SiteConfig config,
    ContentRoute? homepage,
    String? title,
    String? specializedTitle,
  }) {
    if (isHomepage) {
      return homepage ??
          ContentRoute.homepage(config, connected: instance.isConnected);
    }
    final decoded = ContentRouteCodec.fromUrl(
      _target.toString(),
      instance: instance,
      config: config,
      defaultTopPeriod: TopPeriod.fromQueryValue(config.topPageDefaultPeriod),
      title: title,
    );
    return decoded != null &&
            (decoded.destination is BadgeDestination || decoded.isTaxonomyList)
        ? decoded.withDisplay(title: specializedTitle)
        : decoded;
  }

  ResolvedCoreLink enrich(
    ContentRoute decoded, {
    required TopicCategory? category,
    required Iterable<TopicCategory> filterCategories,
  }) => (
    route:
        (category == null
                ? decoded
                : decoded.withDisplay(color: Color(category.colorValue)))
            .resolveCategoryLink(filterCategories),
    siteUrl: instance.url,
  );
}
