import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../../plugin_api/site_plugin_api.dart';
import 'lazy_youtube.dart';

/// Native renderers for cooked markup owned by discourse-lazy-videos.
final class DiscourseLazyVideosPlugin
    implements SitePlugin, CookedElementPlugin {
  const DiscourseLazyVideosPlugin();

  @override
  String get name => 'discourse-lazy-videos';

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      lazyYoutubeVideoWidgetBuilder(element, siteUrl: siteUrl);
}
