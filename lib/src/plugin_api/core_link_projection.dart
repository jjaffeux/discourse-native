import '../models/content_route.dart';
import 'plugin_manifest.dart';

/// Adds plugin-owned context to a link that core has already decoded.
///
/// Projections do not navigate. Core retains the serving forum and applies its
/// normal tab, panel, history, and capacity behavior to the returned route.
abstract interface class PluginCoreLinkProjection
    implements PluginSessionCapability {
  /// Returns a replacement route, or null when this plugin has no context to
  /// add. The first non-null projection is used. [url] is the resolved absolute
  /// link, and [siteUrl] is the forum serving it and [route].
  ContentRoute? projectCoreLink({
    required String siteUrl,
    required String url,
    required ContentRoute route,
  });
}
