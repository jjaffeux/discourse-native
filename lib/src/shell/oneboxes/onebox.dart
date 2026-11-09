import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../cooked_html.dart';
import '../image_decode.dart';
import '../site_image.dart';
import 'audio.dart';
import 'discourse/category/block.dart';
import 'discourse/topic/block.dart';
import 'discourse/user/block.dart';
import 'embedded.dart';
import 'forum_theme.dart';
import 'onebox_card.dart';
import 'reddit.dart';
import 'twitter.dart';

final List<OneboxEngine> _engines = [
  twitterBlock,
  discourseTopicBlock,
  discourseUserBlock,
  discourseCategoryBlock,
];

Widget? oneboxWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final theme = forumThemeOneboxWidgetBuilder(element, siteUrl: siteUrl);
  if (theme != null) return theme;
  final audio = audioOneboxWidgetBuilder(element, siteUrl: siteUrl);
  if (audio != null) return audio;
  if (element.localName == 'iframe') {
    if (element.classes.contains('reddit-onebox')) {
      return redditOneboxWidgetBuilder(element, siteUrl: siteUrl);
    }
    return embeddedOneboxWidgetBuilder(element, siteUrl: siteUrl);
  }
  if (element.localName == 'script') {
    return embeddedOneboxWidgetBuilder(element, siteUrl: siteUrl);
  }
  if (element.localName != 'aside') return null;
  if (!element.classes.contains('onebox')) return null;

  final envelope = OneboxData.from(element);
  for (final engine in _engines) {
    if (engine.matches(element)) {
      return engine.build(element, envelope, siteUrl);
    }
  }
  return genericOneboxCard(envelope, siteUrl: siteUrl);
}

/// A card for a site with no engine of its own: the envelope's thumbnail,
/// title, and cooked excerpt, read as one link to the whole card.
OneboxCard genericOneboxCard(OneboxData data, {String? siteUrl}) => OneboxCard(
  data: data,
  siteUrl: siteUrl,
  readsAsOneLink: true,
  child: _GenericOneboxBody(data: data, siteUrl: siteUrl),
);

class _GenericOneboxBody extends StatelessWidget {
  const _GenericOneboxBody({required this.data, required this.siteUrl});

  final OneboxData data;
  final String? siteUrl;

  static const double _thumbnailWidth = 88;
  static const double _avatarSize = 44;

  @override
  Widget build(BuildContext context) {
    final thumbnail = data.thumbnail;
    final text = _genericText(context);

    if (thumbnail == null) return text;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Thumbnail(
          thumbnail: thumbnail,
          width: thumbnail.isAvatar ? _avatarSize : _thumbnailWidth,
          siteUrl: siteUrl,
        ),
        const SizedBox(width: 12),
        Expanded(child: text),
      ],
    );
  }

  Widget _genericText(BuildContext context) {
    final theme = Theme.of(context);
    final title = data.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        if (title != null && data.bodyHtml.isNotEmpty)
          const SizedBox(height: 4),
        if (data.bodyHtml.isNotEmpty)
          CookedHtml(
            html: data.bodyHtml,
            textStyle: theme.textTheme.bodyLarge?.copyWith(
              height: theme.textTheme.bodyMedium?.height,
            ),
            siteUrl: siteUrl,
          ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.thumbnail,
    required this.width,
    required this.siteUrl,
  });

  final OneboxThumbnail thumbnail;
  final double width;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    // Reserve the slot from the ratio the markup declared so the text does not
    // reflow when the image lands.
    final image = DAspectRatio(
      ratio: thumbnail.aspectRatio ?? 1,
      child: SiteImage(
        url: thumbnail.src,
        siteUrl: siteUrl,
        fit: BoxFit.cover,
        cacheWidth: imagePhysicalPixels(context, width),
        gifPlaybackControls: true,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox();
        },
      ),
    );

    return SizedBox(
      width: width,
      child: thumbnail.isAvatar
          ? DAvatar.frame(child: image)
          : ClipRRect(borderRadius: BorderRadius.circular(4), child: image),
    );
  }
}
