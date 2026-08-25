import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/post.dart';
import '../plugins/plugin_scope.dart';
import '../plugins/site_plugin.dart';
import 'code_block.dart';
import 'emoji.dart';
import 'hashtag.dart';
import 'image_grid.dart';
import 'inline_code.dart';
import 'lightbox.dart';
import 'mention.dart';
import 'oneboxes/onebox.dart';
import 'open_link.dart';
import 'quote.dart';
import 'shell_scope.dart';
import 'site_image.dart';

/// Draws Discourse's `cooked` HTML.
///
/// Discourse already resolved the markdown, oneboxes, mentions and emoji, so
/// [HtmlWidget] does most of the work. The exceptions are the pieces Discourse
/// styles from its stylesheet rather than inline — [HtmlWidget] has no
/// stylesheet engine, so those arrive unstyled and are drawn natively instead.
///
/// Onebox bodies come back through here, which is why an onebox containing a
/// code block gets the same code block a post does.
class CookedHtml extends StatelessWidget {
  const CookedHtml({
    super.key,
    required this.html,
    this.textStyle,
    this.siteUrl,
    this.post,
    this.compactParagraphs = false,
  });

  final String html;
  final TextStyle? textStyle;

  /// The site that cooked [html]. Direct callers may omit it and inherit the
  /// selected site; long-lived application content always supplies it.
  final String? siteUrl;

  /// The owner of a top-level topic body. Recursive cooked fragments omit it,
  /// keeping quoted plugin placeholders noninteractive.
  final Post? post;

  /// Uses the compact top-level paragraph rhythm of Discourse chat.
  ///
  /// The HTML renderer otherwise applies the browser default `1em` vertical
  /// margin to every paragraph. Chat overrides that to `0.5em`, with `0.1em`
  /// at the outer edges, so a reaction row or upload follows the message
  /// instead of looking detached from it.
  final bool compactParagraphs;

  /// Inline code and emoji size themselves against the prose around them, so
  /// unlike the other builders those two need the style the widget was given.
  /// Emoji additionally need the site, to resolve their root-relative `src`.
  static Widget? Function(dom.Element) _customWidget(
    TextStyle? textStyle,
    String? siteUrl,
    Post? post,
    PluginRegistry registry,
  ) =>
      (element) =>
          _pluginWidget(element, siteUrl, post, registry) ??
          registry.cookedElement(siteUrl, element) ??
          emojiWidgetBuilder(element, siteUrl, textStyle) ??
          mentionWidgetBuilder(element, textStyle, siteUrl: siteUrl) ??
          hashtagWidgetBuilder(element, textStyle, siteUrl: siteUrl) ??
          imageGridWidgetBuilder(element, siteUrl: siteUrl) ??
          lightboxWidgetBuilder(element, siteUrl: siteUrl) ??
          oneboxWidgetBuilder(element, siteUrl: siteUrl) ??
          quoteWidgetBuilder(element, siteUrl: siteUrl) ??
          codeBlockWidgetBuilder(element) ??
          inlineCodeWidgetBuilder(element, textStyle);

  static Widget? _pluginWidget(
    dom.Element element,
    String? siteUrl,
    Post? post,
    PluginRegistry registry,
  ) {
    if (siteUrl == null || post == null) return null;
    return registry.postBodyElement(siteUrl, post, element);
  }

  /// Discourse leaves links undecorated and lets colour carry them, but
  /// [HtmlWidget] underlines every `a[href]` by default. Inline styles are the
  /// only styling it reads, so the override has to arrive as one.
  static Map<String, String>? _customStyles(
    dom.Element element,
    bool compactParagraphs,
  ) {
    final styles = <String, String>{};

    if (element.localName == 'a') {
      styles['text-decoration'] = 'none';
    }

    // `.chat-cooked > p`: nested paragraphs retain their ordinary cooked
    // spacing, just as they do in Discourse's stylesheet.
    if (compactParagraphs &&
        element.localName == 'p' &&
        element.parentNode is dom.DocumentFragment) {
      final paragraphs = element.parentNode!.nodes
          .whereType<dom.Element>()
          .where((sibling) => sibling.localName == 'p')
          .toList(growable: false);
      final top = identical(element, paragraphs.first) ? '0.1em' : '0.5em';
      final bottom = identical(element, paragraphs.last) ? '0.1em' : '0.5em';
      styles['margin'] = '$top 0 $bottom';
    }

    return styles.isEmpty ? null : styles;
  }

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? Theme.of(context).textTheme.bodyMedium;
    // `maybeRead`, because this also renders outside the shell — a quote or an
    // onebox in a test. Emoji fall back to their shortcode there, which is what
    // they did everywhere before [emojiWidgetBuilder] existed.
    final resolvedSiteUrl =
        siteUrl ?? ShellScope.maybeRead(context)?.currentInstance?.url;
    final registry = PluginScope.maybeOf(context)?.registry ?? pluginRegistry;

    return HtmlWidget(
      html,
      baseUrl: resolvedSiteUrl == null ? null : Uri.tryParse(resolvedSiteUrl),
      textStyle: style,
      renderMode: RenderMode.column,
      factoryBuilder: () => SiteImageWidgetFactory(siteUrl: resolvedSiteUrl),
      customWidgetBuilder: _customWidget(
        style,
        resolvedSiteUrl,
        post,
        registry,
      ),
      customStylesBuilder: (element) =>
          _customStyles(element, compactParagraphs),
      // The builders close over the style and resolved site, and [HtmlWidget]
      // caches what they built — so a change to either has to say so to reach
      // the inline code and the emoji.
      rebuildTriggers: [
        style,
        resolvedSiteUrl,
        post?.plugins,
        registry,
        compactParagraphs,
      ],
      onTapUrl: (url) => openLink(context, url, siteUrl: resolvedSiteUrl),
    );
  }
}
