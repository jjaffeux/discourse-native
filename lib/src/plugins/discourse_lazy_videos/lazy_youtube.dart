import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

YoutubeVideoData? parseLazyYoutubeVideo(dom.Element element) {
  if (element.localName != 'div' ||
      !element.classes.contains('lazy-video-container') ||
      !element.classes.contains('youtube-onebox') ||
      element.attributes['data-provider-name'] != 'youtube') {
    return null;
  }

  final link = element.querySelector('a[href]');
  final fromUrl = link == null
      ? null
      : YoutubeVideoData.tryParseUrl(link.attributes['href'] ?? '');
  final videoId =
      sanitizeYoutubeId(element.attributes['data-video-id']) ??
      fromUrl?.videoId;
  final listId =
      sanitizeYoutubeId(element.attributes['data-video-list-id']) ??
      fromUrl?.listId;
  if (videoId == null && listId == null) return null;

  final image = element.querySelector('img');
  final title =
      element.attributes['data-video-title']?.trim().nullIfEmpty ??
      image?.attributes['title']?.trim().nullIfEmpty ??
      (videoId == null ? appL10n.youTubePlaylist : appL10n.youTubeVideo);

  return YoutubeVideoData(
    videoId: videoId,
    listId: listId,
    title: title,
    thumbnailUrl:
        image?.attributes['src']?.trim().nullIfEmpty ?? fromUrl?.thumbnailUrl,
    startSeconds:
        parseYoutubeTime(element.attributes['data-video-start-time']) ??
        fromUrl?.startSeconds,
    endSeconds: fromUrl?.endSeconds,
    loop: fromUrl?.loop ?? false,
  );
}

Widget? lazyYoutubeVideoWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final data = parseLazyYoutubeVideo(element);
  return data == null ? null : YoutubeVideo(data: data, siteUrl: siteUrl);
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
