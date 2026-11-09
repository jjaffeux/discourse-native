import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../theme/app_theme.dart';
import '../cooked_dom.dart';
import '../image_decode.dart';
import '../open_link.dart';
import '../site_image.dart';
import 'markup.dart';

class OneboxData {
  const OneboxData({
    required this.url,
    required this.siteIcon,
    required this.siteName,
    required this.title,
    required this.titleUrl,
    required this.thumbnail,
    required this.bodyHtml,
  });

  final String? url;

  final String? siteIcon;

  final String? siteName;

  final String? title;
  final String? titleUrl;
  final OneboxThumbnail? thumbnail;

  final String bodyHtml;

  static OneboxData from(dom.Element aside) {
    final header = descendantWhere(aside, (e) => e.localName == 'header');
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;

    final iconImg = header == null
        ? null
        : descendantWhere(
            header,
            (e) => e.localName == 'img' && e.classes.contains('site-icon'),
          );
    final siteLink = header == null
        ? null
        : descendantWhere(header, (e) => e.localName == 'a');

    final titleEl = descendantWhere(
      article,
      (e) => const {'h1', 'h2', 'h3', 'h4'}.contains(e.localName),
    );
    final titleLink = titleEl == null
        ? null
        : descendantWhere(titleEl, (e) => e.localName == 'a');

    final thumbImg = descendantWhere(article, _isThumbnail);
    final thumbnail = thumbImg == null ? null : OneboxThumbnail.from(thumbImg);

    // Remove only the extracted nodes from a clone. Several core templates
    // put the title, image and description in one shared wrapper.
    final body = article.clone(true);
    final originalElements = article.querySelectorAll('*');
    final clonedElements = body.querySelectorAll('*');
    for (final claimed in [titleEl, if (thumbnail != null) thumbImg]) {
      if (claimed == null) continue;
      final index = originalElements.indexOf(claimed);
      if (index < 0) continue;
      dom.Element node = clonedElements[index];
      while (node.parent != body &&
          node.parent is dom.Element &&
          (node.parent!).children.length == 1 &&
          node.parent!.nodes.whereType<dom.Text>().every(
            (text) => text.text.trim().isEmpty,
          )) {
        node = node.parent!;
      }
      node.remove();
    }
    final metadata = aside.children.where(
      (element) => element.classes.contains('onebox-metadata'),
    );
    final bodyHtml = [
      body.innerHtml,
      ...metadata.map((e) => e.outerHtml),
    ].join().trim();

    return OneboxData(
      url:
          aside.attributes['data-onebox-src'] ??
          titleLink?.attributes['href'] ??
          siteLink?.attributes['href'],
      siteIcon: iconImg?.attributes['src'],
      siteName: siteLink?.text.trim().nullIfEmpty,
      title: titleEl?.text.trim().nullIfEmpty,
      titleUrl: titleLink?.attributes['href'],
      thumbnail: thumbnail,
      bodyHtml: bodyHtml,
    );
  }

  static bool _isThumbnail(dom.Element e) {
    if (e.localName != 'img') return false;
    if (e.classes.contains('thumbnail')) return true;
    return e.classes.contains('onebox-avatar');
  }
}

class OneboxThumbnail {
  const OneboxThumbnail({
    required this.src,
    required this.aspectRatio,
    required this.isAvatar,
  });

  final String src;

  final double? aspectRatio;

  final bool isAvatar;

  // Onebox dimensions are remote layout hints, not authority. At the fixed
  // 88px generic width this keeps reserved height between 22px and 352px.
  static const double _minimumAspectRatio = 1 / 4;
  static const double _maximumAspectRatio = 4;

  static OneboxThumbnail? from(dom.Element img) {
    final src = img.attributes['src'];
    if (src == null || src.isEmpty) return null;

    final width = double.tryParse(img.attributes['width'] ?? '');
    final height = double.tryParse(img.attributes['height'] ?? '');
    final aspectRatio =
        width != null &&
            height != null &&
            width.isFinite &&
            height.isFinite &&
            width > 0 &&
            height > 0
        ? (width / height)
              .clamp(_minimumAspectRatio, _maximumAspectRatio)
              .toDouble()
        : null;
    return OneboxThumbnail(
      src: src,
      aspectRatio: aspectRatio,
      isAvatar: img.classes.contains('onebox-avatar'),
    );
  }
}

class OneboxEngine {
  const OneboxEngine({required this.matches, required this.build});

  final bool Function(dom.Element aside) matches;

  final Widget Function(dom.Element aside, OneboxData envelope, String? siteUrl)
  build;
}

class OneboxCard extends StatelessWidget {
  const OneboxCard({
    super.key,
    required this.data,
    required this.child,
    this.siteUrl,
    this.readsAsOneLink = false,
  });

  final OneboxData data;
  final String? siteUrl;

  final Widget child;

  /// Engine-specific bodies can contain their own metadata links. Leave those
  /// individual semantics nodes alone; the generic fallback is the single
  /// whole-card destination that should read as one link.
  final bool readsAsOneLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.shell;
    final url = data.url;

    final mergeLinkSemantics = url != null && readsAsOneLink;

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: shell.panel,
        border: Border.all(color: shell.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.siteName != null || data.siteIcon != null) ...[
            if (mergeLinkSemantics && data.siteName == data.title)
              ExcludeSemantics(
                child: _Header(
                  icon: data.siteIcon,
                  name: data.siteName,
                  siteUrl: siteUrl,
                ),
              )
            else
              _Header(
                icon: data.siteIcon,
                name: data.siteName,
                siteUrl: siteUrl,
              ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );

    if (url == null) return card;

    final link = LinkTarget(
      url: url,
      siteUrl: siteUrl,
      // The card draws its own bounds, so the item adds no inset or hover
      // fill: the card stays flush with the post column at any width.
      child: DItem(
        size: DItemSize.artwork,
        highlightOnInteraction: false,
        link: mergeLinkSemantics,
        onPressed: () => openLink(context, url, siteUrl: siteUrl),
        children: [card],
      ),
    );
    if (!mergeLinkSemantics) return link;

    return MergeSemantics(child: link);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.name,
    required this.siteUrl,
  });

  final String? icon;
  final String? name;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        if (icon != null) ...[
          SiteImage(
            url: icon!,
            siteUrl: siteUrl,
            width: 16,
            height: 16,
            cacheWidth: imagePhysicalPixels(context, 16),
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox();
            },
          ),
          const SizedBox(width: 6),
        ],
        if (name != null)
          Flexible(
            child: Text(
              name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
