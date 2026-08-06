import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'cooked_html.dart';
import 'open_link.dart';
import 'shell_scope.dart';
import 'user_card.dart';

/// Renders quotes natively instead of as styled HTML.
///
/// Discourse draws a quote as `aside.quote` — an attribution row plus a
/// `<blockquote>` — and styles both from its stylesheet. [HtmlWidget] has no
/// stylesheet engine, so left to itself it prints the attribution as a stray
/// line of text ("martin:") next to a raw avatar, indistinguishable from the
/// post around it.
///
/// A plain markdown `>` produces a bare `<blockquote>` with no attribution,
/// which lands here too and draws the same body without a header.
class QuoteData {
  const QuoteData({
    required this.username,
    required this.avatarUrl,
    required this.title,
    required this.link,
    required this.bodyHtml,
  });

  /// Who is being quoted, from `data-username`.
  final String? username;

  /// `img.avatar` in the title row, as the markup wrote it.
  final String? avatarUrl;

  /// The attribution line: a name, or the topic title for a cross-topic quote.
  /// Discourse writes the name with a trailing colon, which is dropped here.
  final String? title;

  /// Where the attribution points, for quotes that name their source post.
  final String? link;

  /// The `<blockquote>` contents, rendered by [CookedHtml] so a quote can
  /// hold anything a post can — including another quote.
  final String bodyHtml;

  /// Reads [element], which is either `aside.quote` or a bare `<blockquote>`.
  static QuoteData from(dom.Element element) {
    final isAside = element.localName == 'aside';
    final titleEl = isAside
        ? _descendant(element, (e) => e.classes.contains('title'))
        : null;
    final blockquote = isAside
        ? _descendant(element, (e) => e.localName == 'blockquote')
        : element;

    final avatar = titleEl == null
        ? null
        : _descendant(
            titleEl,
            (e) => e.localName == 'img' && e.classes.contains('avatar'),
          );
    final link = titleEl == null
        ? null
        : _descendant(titleEl, (e) => e.localName == 'a');

    return QuoteData(
      username: element.attributes['data-username']?.nullIfEmpty,
      avatarUrl: avatar?.attributes['src']?.nullIfEmpty,
      title: _title(titleEl),
      link: link?.attributes['href']?.nullIfEmpty,
      bodyHtml: (blockquote?.innerHtml ?? '').trim(),
    );
  }

  /// The attribution text, without the `div.quote-controls` buttons the web
  /// client puts in the same row and without Discourse's trailing colon.
  static String? _title(dom.Element? titleEl) {
    if (titleEl == null) return null;

    final text = titleEl.nodes
        .where(
          (node) =>
              node is! dom.Element || !node.classes.contains('quote-controls'),
        )
        .map((node) => node is dom.Element ? node.text : (node.text ?? ''))
        .join()
        .trim();

    final trimmed = text.endsWith(':')
        ? text.substring(0, text.length - 1).trim()
        : text;
    return trimmed.nullIfEmpty;
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
}

/// Hands quotes to [QuoteBlock], for [HtmlWidget.customWidgetBuilder].
Widget? quoteWidgetBuilder(dom.Element element) {
  final isQuote =
      element.localName == 'blockquote' ||
      (element.localName == 'aside' && element.classes.contains('quote'));
  if (!isQuote) return null;
  return QuoteBlock(data: QuoteData.from(element));
}

class QuoteBlock extends StatelessWidget {
  const QuoteBlock({super.key, required this.data});

  final QuoteData data;

  static const double _avatarSize = 20;
  static const double _barWidth = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = theme.shell;
    final hasHeader = data.title != null || data.avatarUrl != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: shell.panel,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(6),
        ),
        // The accent bar is the quote's one strong signal, so it stays the
        // full height of the block rather than sitting beside the header.
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: _barWidth),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader) ...[_Header(data: data), const SizedBox(height: 8)],
            CookedHtml(
              html: data.bodyHtml,
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data});

  final QuoteData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final link = data.link;

    final row = Row(
      children: [
        if (data.avatarUrl != null) ...[
          ClipOval(
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
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (link != null) ...[
          const SizedBox(width: 4),
          DIcon(DIcons.arrowUp, size: 12, color: muted),
        ],
      ],
    );

    // The attribution behaves like the name on a post: it opens the person,
    // unless the quote names a source post, which opens that instead.
    if (link != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openLink(context, link),
          child: row,
        ),
      );
    }
    if (data.username case final username?) {
      return UserCardTarget(username: username, child: row);
    }
    return row;
  }

  /// Quote avatars are written site-relative, unlike the absolute URLs the
  /// JSON payloads carry, so they need the current site to resolve against.
  String? _absoluteAvatar(BuildContext context, String src) {
    final url = ShellScope.maybeOf(context)?.absoluteUrl(src) ?? src;
    return url.startsWith('http') ? url : null;
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
