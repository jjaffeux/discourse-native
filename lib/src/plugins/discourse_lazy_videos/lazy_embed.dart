import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import 'lazy_embed_parser.dart';

Widget? lazyEmbeddedVideoWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final iframe = parseLazyEmbeddedVideo(element);
  if (iframe == null) return null;
  return embeddedOneboxWidgetBuilder(iframe, siteUrl: siteUrl);
}
