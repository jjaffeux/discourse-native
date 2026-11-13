import 'package:discourse_native/discourse_plugin_sdk.dart' show YoutubeVideo;
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import 'lazy_youtube_parser.dart';

Widget? lazyYoutubeVideoWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final data = parseLazyYoutubeVideo(element);
  return data == null ? null : YoutubeVideo(data: data, siteUrl: siteUrl);
}
