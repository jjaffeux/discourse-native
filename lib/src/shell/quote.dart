import 'package:discourse_native/discourse_ui.dart' show DAvatar;
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'cooked_dom.dart';
import 'cooked_html.dart';
import 'inline_action.dart';
import 'open_link.dart';
import 'quote_panel.dart';
import 'shell_scope.dart';
import 'site_url.dart';
import 'topic_title.dart';
import 'user_card.dart';

class QuoteData {
  const QuoteData({
    required this.username,
    required this.avatarUrl,
    required this.title,
    required this.link,
    required this.bodyHtml,
  });

  final String? username;

  final String? avatarUrl;

  final String? title;

  final String? link;

  final String bodyHtml;

  static QuoteData from(dom.Element element) {
    final isAside = element.localName == 'aside';
    final titleEl = isAside
        ? descendantWhere(element, (e) => e.classes.contains('title'))
        : null;
    final blockquote = isAside
        ? descendantWhere(element, (e) => e.localName == 'blockquote')
        : element;

    final avatar = titleEl == null
        ? null
        : descendantWhere(
            titleEl,
            (e) => e.localName == 'img' && e.classes.contains('avatar'),
          );
    final link = titleEl == null
        ? null
        : descendantWhere(titleEl, (e) => e.localName == 'a');

    return QuoteData(
      username: element.attributes['data-username']?.nullIfEmpty,
      avatarUrl: avatar?.attributes['src']?.nullIfEmpty,
      title: _title(titleEl, linked: link != null),
      link: link?.attributes['href']?.nullIfEmpty,
      bodyHtml: (blockquote?.innerHtml ?? '').trim(),
    );
  }

  static String? _title(dom.Element? titleEl, {required bool linked}) {
    if (titleEl == null) return null;

    final buffer = StringBuffer();
    final pending = <dom.Node>[];
    void pushChildren(dom.Node parent) {
      final nodes = parent.nodes;
      for (var index = nodes.length - 1; index >= 0; index--) {
        pending.add(nodes[index]);
      }
    }

    pushChildren(titleEl);
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node is dom.Text) {
        buffer.write(node.data);
      } else if (node is dom.Element && !_outsideTitle(node)) {
        if (_isEmoji(node)) {
          buffer.write(_shortcode(node));
        } else {
          pushChildren(node);
        }
      }
    }
    final text = buffer.toString().trim();

    // Core writes the colon after a `username:` attribution; a linked title is
    // the topic's own text, colon included.
    final trimmed = !linked && text.endsWith(':')
        ? text.substring(0, text.length - 1).trim()
        : text;
    return trimmed.nullIfEmpty;
  }

  static bool _isEmoji(dom.Element element) =>
      element.localName == 'img' && element.classes.contains('emoji');

  // Core unescapes a linked title's `:tada:` and 🎉 alike into an image named
  // bare, `tada`, where a post body's image keeps the colons. Either way the
  // title carries the shortcode, which is what a topic title is drawn from.
  static String _shortcode(dom.Element emoji) {
    final attributes = emoji.attributes;
    final named = attributes['alt']?.nullIfEmpty ?? attributes['title'] ?? '';
    final name = named.replaceAll(_shortcodeColons, '');
    return name.isEmpty ? '' : ':$name:';
  }

  static final RegExp _shortcodeColons = RegExp(r'^:|:$');

  // A same-site topic link is cooked as a quote whose title carries the
  // topic's category badge after the topic link. The badge names the
  // category, not the quoted source, so it is neither drawn nor announced as
  // part of the title — in its current `badge-category__wrapper` form, the
  // older `badge-wrapper` form, or as a bare `badge-category`.
  static bool _outsideTitle(dom.Element element) {
    final classes = element.classes;
    return classes.contains('quote-controls') ||
        classes.contains('badge-category__wrapper') ||
        classes.contains('badge-wrapper') ||
        classes.contains('badge-category');
  }
}

Widget? quoteWidgetBuilder(dom.Element element, {String? siteUrl}) {
  final isQuote =
      element.localName == 'blockquote' ||
      (element.localName == 'aside' && element.classes.contains('quote'));
  if (!isQuote) return null;
  return QuoteBlock(data: QuoteData.from(element), siteUrl: siteUrl);
}

class QuoteBlock extends StatelessWidget {
  const QuoteBlock({super.key, required this.data, this.siteUrl});

  final QuoteData data;
  final String? siteUrl;

  static const double _avatarSize = 20;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHeader = data.title != null || data.avatarUrl != null;

    return QuotePanel(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader) ...[
            _Header(data: data, siteUrl: siteUrl),
            const SizedBox(height: 8),
          ],
          CookedHtml(
            html: data.bodyHtml,
            siteUrl: siteUrl,
            textStyle: theme.textTheme.bodyLarge?.copyWith(
              height: DiscourseTypography.lineHeightCooked,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.siteUrl});

  final QuoteData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final link = data.link;
    final titleStyle = theme.textTheme.labelMedium?.copyWith(
      color: muted,
      fontWeight: FontWeight.w600,
    );
    // A linked title is a topic title, so its shortcodes draw as the site's
    // emoji; a username attribution is a name and stays plain text. Artwork
    // needs the shell, which quotes rendered outside one do not have.
    final emojiSite = link != null && ShellScope.maybeRead(context) != null
        ? siteUrl
        : null;

    final row = Row(
      children: [
        if (data.avatarUrl != null) ...[
          DAvatar.frame(
            child: SizedBox(
              width: QuoteBlock._avatarSize,
              height: QuoteBlock._avatarSize,
              child: AvatarImage(
                url: _absoluteAvatar(context, data.avatarUrl!),
                size: QuoteBlock._avatarSize,
                fallback: ColoredBox(color: theme.shell.floating),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (data.title case final title?)
          Flexible(
            child: switch (emojiSite) {
              final site? => TopicTitle(
                title,
                siteUrl: site,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              null => Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            },
          ),
        if (link != null) ...[
          const SizedBox(width: 4),
          DIcon(DIcons.arrowUp, size: 12, color: muted),
        ],
      ],
    );

    if (link != null) {
      return LinkTarget(
        url: link,
        siteUrl: siteUrl,
        child: InlineAction.link(
          onTap: () => openLink(context, link, siteUrl: siteUrl),
          semanticLabel: data.title ?? link,
          excludeChildSemantics: true,
          child: row,
        ),
      );
    }
    if (data.username case final username?) {
      return UserCardTarget(username: username, siteUrl: siteUrl, child: row);
    }
    return row;
  }

  String? _absoluteAvatar(BuildContext context, String src) {
    final url =
        ShellScope.maybeRead(context)?.absoluteUrl(src, siteUrl: siteUrl) ??
        resolveSiteUrl(src, siteUrl);
    return url.startsWith('http') ? url : null;
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
