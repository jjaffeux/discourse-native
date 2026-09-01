import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/post.dart';
import '../models/user_status.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import 'code_block.dart';
import 'emoji.dart';
import 'hashtag.dart';
import 'image_grid.dart';
import 'inline_code.dart';
import 'inline_video.dart';
import 'lightbox.dart';
import 'mention.dart';
import 'oneboxes/onebox.dart';
import 'open_link.dart';
import 'quote.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'youtube_video.dart';

class CookedHtml extends StatelessWidget {
  const CookedHtml({
    super.key,
    required this.html,
    this.textStyle,
    this.siteUrl,
    this.post,
    this.containingTopic,
    this.registry,
    this.compactParagraphs = false,
    this.revisionDiff = false,
    this.mentionedUserStatuses = const {},
  });

  final String html;
  final TextStyle? textStyle;

  final String? siteUrl;

  final Post? post;

  final PluginContainingTopic? containingTopic;

  final PluginRegistry? registry;

  final bool compactParagraphs;

  final bool revisionDiff;

  final Map<String, UserStatusReference> mentionedUserStatuses;

  static bool buildsAsynchronously(String html) =>
      html.length > kShouldBuildAsync;

  static Widget? Function(dom.Element) _customWidget(
    BuildContext context,
    TextStyle? textStyle,
    String? siteUrl,
    Post? post,
    PluginContainingTopic? containingTopic,
    PluginRegistry registry,
    Map<String, UserStatusReference> mentionedUserStatuses,
  ) => (element) {
    if (post != null) {
      _decorateLinkCount(element, post.linkCounts);
    }

    return _pluginWidget(
          context,
          element,
          siteUrl,
          post,
          containingTopic,
          registry,
        ) ??
        registry.cookedElement(siteUrl, element) ??
        emojiWidgetBuilder(element, siteUrl, textStyle) ??
        mentionWidgetBuilder(
          element,
          textStyle,
          siteUrl: siteUrl,
          userStatuses: mentionedUserStatuses,
        ) ??
        hashtagWidgetBuilder(
          element,
          textStyle,
          siteUrl: siteUrl,
          pluginPresentation: registry.pluginHashtagPresentation,
        ) ??
        imageGridWidgetBuilder(element, siteUrl: siteUrl) ??
        lightboxWidgetBuilder(element, siteUrl: siteUrl) ??
        inlineVideoWidgetBuilder(element, siteUrl: siteUrl) ??
        youtubeVideoWidgetBuilder(element, siteUrl: siteUrl) ??
        oneboxWidgetBuilder(element, siteUrl: siteUrl) ??
        quoteWidgetBuilder(element, siteUrl: siteUrl) ??
        codeBlockWidgetBuilder(element) ??
        inlineCodeWidgetBuilder(element, textStyle);
  };

  static Widget? _pluginWidget(
    BuildContext context,
    dom.Element element,
    String? siteUrl,
    Post? post,
    PluginContainingTopic? containingTopic,
    PluginRegistry registry,
  ) {
    if (siteUrl == null || post == null) return null;
    return registry.postBodyElement(
      context,
      siteUrl,
      post,
      element,
      topic: containingTopic,
    );
  }

  static Map<String, String>? _customStyles(
    dom.Element element,
    bool compactParagraphs,
    String horizontalRuleColor,
    String? insertedBackground,
    String? deletedBackground,
    String linkCountBackground,
    String linkCountForeground,
  ) {
    final styles = <String, String>{};

    if (element.localName == 'a') {
      styles['text-decoration'] = 'none';
    }

    if (element.classes.contains(_linkClickCountClass)) {
      styles.addAll({
        'background-color': linkCountBackground,
        'border-radius': '10px',
        'color': linkCountForeground,
        'display': 'inline-block',
        'font-size': '${DiscourseTypography.fontDown2}px',
        'font-weight': 'normal',
        'line-height': '${DiscourseTypography.lineHeightMedium}',
        'margin': '0.15em',
        'min-width': '0.5em',
        'padding': '0.21em 0.42em',
        'text-align': 'center',
        'vertical-align': 'middle',
        'white-space': 'nowrap',
      });
    }

    // Core draws `<hr>` with `--content-border-color`. HtmlWidget's default
    // border has no explicit colour, so it inherits the foreground text colour
    // and becomes much more prominent, especially in dark themes.
    if (element.localName == 'hr') {
      styles['border-top'] = '1px solid $horizontalRuleColor';
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

    final inserted =
        element.localName == 'ins' || element.classes.contains('diff-ins');
    final deleted =
        element.localName == 'del' || element.classes.contains('diff-del');
    if (inserted && insertedBackground != null) {
      styles['background-color'] = insertedBackground;
      styles['text-decoration'] = 'none';
    } else if (deleted && deletedBackground != null) {
      styles['background-color'] = deletedBackground;
      styles['text-decoration'] = 'none';
    }

    return styles.isEmpty ? null : styles;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = textStyle ?? theme.textTheme.bodyMedium;
    final surface = theme.colorScheme.surface;
    final horizontalRuleColor = _cssColor(
      theme.extension<ShellColors>()?.divider ?? theme.dividerColor,
    );
    final linkCountBackground = _cssColor(
      theme.colorScheme.surfaceContainerHighest,
    );
    final linkCountForeground = _cssColor(
      theme.extension<DiscourseColors>()?.whisper ??
          theme.colorScheme.onSurfaceVariant,
    );
    final insertedBackground = revisionDiff
        ? _cssColor(
            Color.alphaBlend(
              theme.discourse.success.withValues(alpha: 0.18),
              surface,
            ),
          )
        : null;
    final deletedBackground = revisionDiff
        ? _cssColor(
            Color.alphaBlend(
              theme.colorScheme.error.withValues(alpha: 0.14),
              surface,
            ),
          )
        : null;
    // Quotes, oneboxes, and tests can render outside ShellScope.
    final resolvedSiteUrl =
        siteUrl ?? ShellScope.maybeRead(context)?.currentInstance?.url;
    final resolvedRegistry =
        registry ??
        PluginRegistryScope.maybeOf(context) ??
        PluginScope.maybeOf(context)?.registry ??
        PluginRegistry.empty;

    return PluginRegistryScope(
      registry: resolvedRegistry,
      child: HtmlWidget(
        html,
        baseUrl: resolvedSiteUrl == null ? null : Uri.tryParse(resolvedSiteUrl),
        textStyle: style,
        renderMode: RenderMode.column,
        factoryBuilder: () => SiteImageWidgetFactory(
          siteUrl: resolvedSiteUrl,
          registry: resolvedRegistry,
        ),
        customWidgetBuilder: _customWidget(
          context,
          style,
          resolvedSiteUrl,
          post,
          containingTopic,
          resolvedRegistry,
          mentionedUserStatuses,
        ),
        customStylesBuilder: (element) => _customStyles(
          element,
          compactParagraphs,
          horizontalRuleColor,
          insertedBackground,
          deletedBackground,
          linkCountBackground,
          linkCountForeground,
        ),
        // The builders close over the style and resolved site, and [HtmlWidget]
        // caches what they built — so a change to either has to say so to reach
        // the inline code and the emoji.
        rebuildTriggers: [
          style,
          resolvedSiteUrl,
          post?.plugins,
          containingTopic,
          resolvedRegistry,
          compactParagraphs,
          revisionDiff,
          horizontalRuleColor,
          insertedBackground,
          deletedBackground,
          post?.linkCounts,
          linkCountBackground,
          linkCountForeground,
          mentionedUserStatuses,
        ],
        onTapUrl: (url) => openLink(context, url, siteUrl: resolvedSiteUrl),
      ),
    );
  }
}

const _linkClickCountClass = 'discourse-native-link-click-count';

void _decorateLinkCount(dom.Element element, List<PostLinkCount> linkCounts) {
  if (element.localName != 'a' ||
      element.attributes.containsKey('data-clicks') ||
      !_isCountedLink(element)) {
    return;
  }

  final href = element.attributes['href'];
  if (href == null) return;

  PostLinkCount? matched;
  for (final count in linkCounts) {
    if (count.clicks > 0 && _linkCountMatches(href, count)) {
      // Core applies the records in payload order, so the final duplicate wins.
      matched = count;
    }
  }
  if (matched == null || !_isBestOneboxLink(element)) return;

  final count = matched.clicks;
  final linkLabel = element.text.trim();
  final clickLabel = count == 1
      ? 'link clicked 1 time'
      : 'link clicked $count times';
  element.attributes['data-clicks'] = count.toString();
  element.attributes['aria-label'] = linkLabel.isEmpty
      ? clickLabel
      : '$linkLabel $clickLabel';
  element.append(
    dom.Element.tag('span')
      ..classes.add(_linkClickCountClass)
      ..text = _shortClickCount(count),
  );
}

bool _linkCountMatches(String href, PostLinkCount count) {
  if (href == count.url) return true;
  if (!count.internal) return false;
  if (count.url.startsWith('/uploads/') && href.contains(count.url)) {
    return true;
  }
  final query = href.indexOf('?');
  return query >= 0 && href.substring(0, query) == count.url;
}

bool _isCountedLink(dom.Element link) {
  const ignoredLinkClasses = {
    'lightbox',
    'no-track-link',
    'hashtag',
    'hashtag-cooked',
    'back',
  };
  if (link.classes.any(ignoredLinkClasses.contains)) return false;

  for (final ancestor in _ancestors(link)) {
    if ((ancestor.localName == 'aside' && ancestor.classes.contains('quote')) ||
        ancestor.classes.contains('elided') ||
        ancestor.classes.contains('expanded-embed')) {
      return false;
    }
  }

  final insideOneboxResult = _ancestors(link).any(
    (ancestor) =>
        ancestor.classes.contains('onebox-result') ||
        ancestor.classes.contains('onebox-body'),
  );
  if (insideOneboxResult) {
    final onebox = _closestOnebox(link);
    final headerLink = onebox?.querySelector('header a[href]');
    if (headerLink != null &&
        headerLink.attributes['href'] == link.attributes['href']) {
      return true;
    }
  }

  if (link.classes.contains('track-link')) return true;
  const ignoredAncestorClasses = {
    'hashtag',
    'hashtag-cooked',
    'hashtag-icon-placeholder',
    'badge-category',
    'onebox-result',
    'onebox-body',
  };
  return !_ancestors(
    link,
  ).any((ancestor) => ancestor.classes.any(ignoredAncestorClasses.contains));
}

bool _isBestOneboxLink(dom.Element link) {
  final onebox = _closestOnebox(link);
  if (onebox == null) return true;

  dom.Element? best;
  for (var level = 1; level <= 6; level++) {
    best = onebox.querySelector('h$level a[href]');
    if (best != null) break;
  }
  best ??= onebox.querySelector('header a[href]');
  return best == null || identical(best, link);
}

dom.Element? _closestOnebox(dom.Element element) {
  for (final ancestor in _ancestors(element)) {
    if (ancestor.classes.contains('onebox')) return ancestor;
  }
  return null;
}

Iterable<dom.Element> _ancestors(dom.Element element) sync* {
  dom.Node? current = element.parentNode;
  while (current != null) {
    if (current is dom.Element) yield current;
    current = current.parentNode;
  }
}

String _shortClickCount(int count) {
  if (count > 999999) return '${_shortDecimal(count / 1000000)}M';
  if (count > 99999) return '${count ~/ 1000}k';
  if (count > 999) return '${_shortDecimal(count / 1000)}k';
  return '$count';
}

String _shortDecimal(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

String _cssColor(Color color) =>
    '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0')}';
