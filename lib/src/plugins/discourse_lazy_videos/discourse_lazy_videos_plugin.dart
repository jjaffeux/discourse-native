import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import 'lazy_youtube.dart';

final class DiscourseLazyVideosPlugin
    implements SitePlugin, CookedElementPlugin {
  const DiscourseLazyVideosPlugin();

  @override
  String get name => 'discourse-lazy-videos';

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      lazyYoutubeVideoWidgetBuilder(element, siteUrl: siteUrl);
}
