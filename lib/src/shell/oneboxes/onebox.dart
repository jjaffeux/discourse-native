import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../../theme/app_theme.dart';
import '../cooked_html.dart';
import '../open_link.dart';
import 'discourse/category/block.dart';
import 'discourse/topic/block.dart';
import 'discourse/user/block.dart';
import 'github/commit/block.dart';
import 'github/issue/block.dart';
import 'github/pr/block.dart';

/// Renders Discourse oneboxes natively instead of as styled HTML.
///
/// Discourse styles oneboxes with a stylesheet, and [HtmlWidget] has no
/// stylesheet engine — it only reads the `style` attribute of individual
/// elements. So none of Discourse's onebox CSS can be reused here, and an
/// unhandled onebox renders as an unstyled pile of text and images.
///
/// Every onebox arrives in the envelope the `_layout` template writes —
/// `aside.onebox`, `header.source`, `article.onebox-body` — which
/// [OneboxData] reads. The engines under this directory claim the asides
/// whose body they know how to draw (the GitHub ones, the links to Discourse
/// itself); everything else falls back to the generic [OneboxCard], which
/// hands the body it did not claim back to [HtmlWidget]. New and unknown
/// engines therefore still show their content, inside native chrome.
///
/// `tool/onebox_contract.dart` checks the envelope and the engines' markup
/// for drift against discourse/discourse.
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

  /// Where the onebox points, from `data-onebox-src` or the title link.
  final String? url;

  /// Favicon shown in the header, `img.site-icon`.
  final String? siteIcon;

  /// Header link text: a domain, or the site's name if it advertises one.
  final String? siteName;

  final String? title;
  final String? titleUrl;
  final OneboxThumbnail? thumbnail;

  /// Everything in `article.onebox-body` that this parser did not claim,
  /// rendered by [HtmlWidget]. Empty when the body was only a title and image.
  final String bodyHtml;

  /// Reads [aside], which must be the `aside.onebox` element itself.
  static OneboxData from(dom.Element aside) {
    final header = _descendant(aside, (e) => e.localName == 'header');
    final article =
        _descendant(aside, (e) => e.classes.contains('onebox-body')) ?? aside;

    final iconImg = header == null
        ? null
        : _descendant(
            header,
            (e) => e.localName == 'img' && e.classes.contains('site-icon'),
          );
    final siteLink = header == null
        ? null
        : _descendant(header, (e) => e.localName == 'a');

    final titleEl = _descendant(
      article,
      (e) => const {'h1', 'h2', 'h3', 'h4'}.contains(e.localName),
    );
    final titleLink = titleEl == null
        ? null
        : _descendant(titleEl, (e) => e.localName == 'a');

    final thumbImg = _descendant(article, _isThumbnail);
    final thumbnail = thumbImg == null ? null : OneboxThumbnail.from(thumbImg);

    // Serialize the rest of the body rather than removing nodes from it: the
    // document belongs to the caller's [HtmlWidget], not to us.
    final claimed = {
      if (titleEl != null) _topLevelAncestor(article, titleEl),
      if (thumbImg != null) _topLevelAncestor(article, thumbImg),
    };
    final bodyHtml = article.nodes
        .where((node) => !claimed.contains(node))
        .map(_serialize)
        .join()
        .trim();

    return OneboxData(
      url: aside.attributes['data-onebox-src'] ?? titleLink?.attributes['href'],
      siteIcon: iconImg?.attributes['src'],
      siteName: siteLink?.text.trim().nullIfEmpty,
      title: titleEl?.text.trim().nullIfEmpty,
      titleUrl: titleLink?.attributes['href'],
      thumbnail: thumbnail,
      bodyHtml: bodyHtml,
    );
  }

  /// Images the body styles as content, as opposed to inline decoration.
  static bool _isThumbnail(dom.Element e) {
    if (e.localName != 'img') return false;
    if (e.classes.contains('thumbnail')) return true;
    return !e.classes.any(
      const {
        'avatar',
        'emoji',
        'onebox-avatar-inline',
        'site-icon',
        'favicon',
      }.contains,
    );
  }

  /// The child of [root] that contains [node], so wrappers such as
  /// `div.aspect-image` are claimed along with the image inside them.
  static dom.Node _topLevelAncestor(dom.Element root, dom.Element node) {
    dom.Node current = node;
    while (current.parent != null && current.parent != root) {
      current = current.parent!;
    }
    return current;
  }

  static dom.Element? _descendant(
    dom.Element root,
    bool Function(dom.Element) test,
  ) {
    for (final child in root.children) {
      if (test(child)) return child;
      final found = _descendant(child, test);
      if (found != null) return found;
    }
    return null;
  }

  static String _serialize(dom.Node node) =>
      node is dom.Element ? node.outerHtml : (node.text ?? '');
}

/// A onebox's lead image, with the intrinsic size Discourse recorded for it.
class OneboxThumbnail {
  const OneboxThumbnail({
    required this.src,
    required this.aspectRatio,
    required this.isAvatar,
  });

  final String src;

  /// Width over height, or null when the markup did not say.
  final double? aspectRatio;

  /// Engines like Twitter use the lead image as a small round avatar.
  final bool isAvatar;

  static OneboxThumbnail? from(dom.Element img) {
    final src = img.attributes['src'];
    if (src == null || src.isEmpty) return null;

    final width = double.tryParse(img.attributes['width'] ?? '');
    final height = double.tryParse(img.attributes['height'] ?? '');
    return OneboxThumbnail(
      src: src,
      aspectRatio: (width != null && height != null && height > 0)
          ? width / height
          : null,
      isAvatar: img.classes.contains('onebox-avatar'),
    );
  }
}

/// A body parser for one engine, and the test that decides the aside is one.
class OneboxEngine {
  const OneboxEngine({required this.matches, required this.build});

  final bool Function(dom.Element aside) matches;

  /// Builds the whole widget for the aside, [envelope] included.
  final Widget Function(dom.Element aside, OneboxData envelope) build;
}

/// The engines this app draws natively, first claim wins. Anything none of
/// them recognises lands on the generic [OneboxCard].
final List<OneboxEngine> _engines = [
  githubPullRequestBlock,
  githubIssueBlock,
  githubCommitBlock,
  discourseTopicBlock,
  discourseUserBlock,
  discourseCategoryBlock,
];

/// Hands `aside.onebox` to whichever engine claims it, for
/// [HtmlWidget.customWidgetBuilder].
Widget? oneboxWidgetBuilder(dom.Element element) {
  if (element.localName != 'aside') return null;
  if (!element.classes.contains('onebox')) return null;

  final envelope = OneboxData.from(element);
  for (final engine in _engines) {
    if (engine.matches(element)) return engine.build(element, envelope);
  }
  return OneboxCard(data: envelope);
}

/// The card every onebox sits in: the site header, and either a body an
/// engine built or the generic title-and-thumbnail one.
class OneboxCard extends StatelessWidget {
  const OneboxCard({super.key, required this.data, this.child});

  final OneboxData data;

  /// The engine-specific body. Null asks for the generic one, which is what
  /// unknown engines get.
  final Widget? child;

  static const double _thumbnailWidth = 88;
  static const double _avatarSize = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.shell;

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
            _Header(icon: data.siteIcon, name: data.siteName),
            const SizedBox(height: 10),
          ],
          child ?? _genericBody(context),
        ],
      ),
    );

    final url = data.url;
    if (url == null) return card;

    return InkWell(
      onTap: () => openLink(context, url),
      borderRadius: BorderRadius.circular(8),
      child: card,
    );
  }

  Widget _genericBody(BuildContext context) {
    final thumbnail = data.thumbnail;
    final text = _genericText(context);

    if (thumbnail == null) return text;

    // The web layout floats the image left of the text, which is also what
    // reads best in a column narrower than a browser window.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Thumbnail(
          thumbnail: thumbnail,
          width: thumbnail.isAvatar ? _avatarSize : _thumbnailWidth,
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
              color: theme.colorScheme.tertiary,
            ),
          ),
        if (title != null && data.bodyHtml.isNotEmpty)
          const SizedBox(height: 4),
        if (data.bodyHtml.isNotEmpty)
          CookedHtml(html: data.bodyHtml, textStyle: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.name});

  final String? icon;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        if (icon != null) ...[
          Image.network(
            icon!,
            width: 16,
            height: 16,
            errorBuilder: (context, error, stackTrace) => const SizedBox(),
          ),
          const SizedBox(width: 6),
        ],
        if (name != null)
          Flexible(
            child: Text(
              name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.thumbnail, required this.width});

  final OneboxThumbnail thumbnail;
  final double width;

  @override
  Widget build(BuildContext context) {
    // Reserve the slot from the ratio the markup declared so the text does not
    // reflow when the image lands.
    final image = AspectRatio(
      aspectRatio: thumbnail.aspectRatio ?? 1,
      child: Image.network(
        thumbnail.src,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const SizedBox(),
      ),
    );

    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(thumbnail.isAvatar ? width / 2 : 4),
        child: image,
      ),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
