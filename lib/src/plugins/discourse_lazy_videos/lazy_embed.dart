import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

Widget? lazyEmbeddedVideoWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (element.localName != 'div' ||
      !element.classes.contains('lazy-video-container')) {
    return null;
  }
  final provider = element.attributes['data-provider-name'];
  final id = element.attributes['data-video-id'] ?? '';
  final String source;
  if (provider == 'vimeo' &&
      element.classes.contains('vimeo-onebox') &&
      RegExp(r'^\d+(?:\?[^\s#]*)?$').hasMatch(id)) {
    // Unlisted Vimeo videos include the provider's private h query parameter.
    source = 'https://player.vimeo.com/video/$id';
  } else if (provider == 'tiktok' &&
      element.classes.contains('tiktok-onebox') &&
      RegExp(r'^\d+$').hasMatch(id)) {
    source = 'https://www.tiktok.com/embed/v2/$id';
  } else {
    return null;
  }
  final iframe = dom.Element.tag('iframe')..attributes['src'] = source;
  final title = element.attributes['data-video-title'];
  if (title != null) iframe.attributes['title'] = title;
  final link = element.querySelector('a[href]')?.attributes['href'];
  if (link != null) iframe.attributes['data-original-href'] = link;
  if (provider == 'tiktok') iframe.attributes['height'] = '560';
  return embeddedOneboxWidgetBuilder(iframe, siteUrl: siteUrl);
}
