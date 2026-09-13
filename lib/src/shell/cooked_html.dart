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
    this.linkStyle,
    this.siteUrl,
    this.post,
    this.containingTopic,
    this.registry,
    this.buildAsync,
    this.compactParagraphs = false,
    this.contentSized = false,
    this.revisionDiff = false,
    this.mentionedUserStatuses = const {},
  });

  final String html;
  final TextStyle? textStyle;

  /// Optional link color and decoration for composition on a contrasting surface.
  /// Other text metrics continue to follow the surrounding rich content.
  final TextStyle? linkStyle;

  final String? siteUrl;

  final Post? post;

  final PluginContainingTopic? containingTopic;

  final PluginRegistry? registry;

  /// Pins parsing mode when interactive presentation can change HTML length.
  final bool? buildAsync;

  final bool compactParagraphs;

  /// Lets ordinary text blocks fit their content inside conversation bubbles.
  final bool contentSized;

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
  ) {
    final counts = post?.linkCounts;
    final linkCounts = counts == null || counts.isEmpty
        ? null
        : _LinkCountIndex(counts);
    return (element) {
      if (linkCounts != null) {
        _decorateLinkCount(element, linkCounts);
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
  }

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
    _CompactParagraphMargins? paragraphMargins,
    String horizontalRuleColor,
    String? insertedBackground,
    String? deletedBackground,
    String linkCountBackground,
    String linkCountForeground,
    TextStyle? linkStyle,
  ) {
    final styles = <String, String>{};

    if (element.localName == 'a') {
      styles['text-decoration'] =
          linkStyle?.decoration?.contains(TextDecoration.underline) == true
          ? 'underline'
          : 'none';
      if (linkStyle?.color case final color?) {
        styles['color'] = _cssColor(color);
      }
      if (linkStyle?.fontWeight case final weight?) {
        styles['font-weight'] = '${weight.value}';
      }
      if (linkStyle?.decorationColor case final color?) {
        styles['text-decoration-color'] = _cssColor(color);
      }
    }

    final headingLevel = switch (element.localName) {
      'h1' => 1,
      'h2' => 2,
      'h3' => 3,
      'h4' => 4,
      'h5' => 5,
      'h6' => 6,
      _ => null,
    };
    if (headingLevel != null) {
      styles['font-size'] =
          '${DiscourseTypography.headingSize(headingLevel)}px';
      styles['line-height'] =
          '${DiscourseTypography.headingLineHeight(headingLevel)}';
    }

    if (element.classes.contains(_linkClickCountClass)) {
      styles.addAll({
        'background-color': linkCountBackground,
        'border-radius': '10px',
        'color': linkCountForeground,
        'display': 'inline-block',
        'font-size': '${DiscourseTypography.xs}px',
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
    if (paragraphMargins != null &&
        element.localName == 'p' &&
        element.parentNode is dom.DocumentFragment) {
      styles['margin'] = paragraphMargins.marginFor(element);
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
    final style = textStyle ?? theme.textTheme.bodyLarge;
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
    // Scope the index to this renderer, with weak keys so reparsed documents
    // can be collected even while its style callback is still alive.
    final paragraphMargins = compactParagraphs
        ? _CompactParagraphMargins()
        : null;

    return PluginRegistryScope(
      registry: resolvedRegistry,
      child: HtmlWidget(
        html,
        buildAsync: buildAsync,
        baseUrl: resolvedSiteUrl == null ? null : Uri.tryParse(resolvedSiteUrl),
        textStyle: style,
        renderMode: RenderMode.column,
        factoryBuilder: () => SiteImageWidgetFactory(
          siteUrl: resolvedSiteUrl,
          registry: resolvedRegistry,
          onMiddleClickUrl: (url) =>
              openLink(context, url, siteUrl: resolvedSiteUrl, newTab: true),
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
        customStylesBuilder: (element) => {
          if (contentSized && element.localName == 'p') 'width': 'auto',
          ...?_customStyles(
            element,
            paragraphMargins,
            horizontalRuleColor,
            insertedBackground,
            deletedBackground,
            linkCountBackground,
            linkCountForeground,
            linkStyle,
          ),
        },
        // The builders close over the style and resolved site, and [HtmlWidget]
        // caches what they built — so a change to either has to say so to reach
        // the inline code and the emoji.
        rebuildTriggers: [
          style,
          linkStyle,
          resolvedSiteUrl,
          post?.plugins,
          containingTopic,
          resolvedRegistry,
          compactParagraphs,
          contentSized,
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

class _CompactParagraphMargins {
  final _bounds = Expando<({dom.Element? first, dom.Element? last})>();

  String marginFor(dom.Element element) {
    final document = element.parentNode!;
    var bounds = _bounds[document];
    if (bounds == null) {
      dom.Element? first;
      dom.Element? last;
      for (final sibling in document.nodes) {
        if (sibling is dom.Element && sibling.localName == 'p') {
          first ??= sibling;
          last = sibling;
        }
      }
      bounds = (first: first, last: last);
      _bounds[document] = bounds;
    }

    final top = identical(element, bounds.first) ? '0.1em' : '0.5em';
    final bottom = identical(element, bounds.last) ? '0.1em' : '0.5em';
    return '$top 0 $bottom';
  }
}

const _linkClickCountClass = 'discourse-native-link-click-count';

void _decorateLinkCount(dom.Element element, _LinkCountIndex linkCounts) {
  if (element.localName != 'a' ||
      element.attributes.containsKey('data-clicks') ||
      !_isCountedLink(element)) {
    return;
  }

  final href = element.attributes['href'];
  if (href == null) return;

  final count = linkCounts.clicksFor(href);
  if (count == null || !_isBestOneboxLink(element)) return;

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

typedef _LinkCountMatch = ({int order, int clicks});

// Owned by one renderer's callback; storage depends only on its payload, never
// on the number of anchors or reparsed documents passed through the callback.
class _LinkCountIndex {
  _LinkCountIndex(List<PostLinkCount> counts) {
    for (final (order, count) in counts.indexed) {
      if (count.clicks <= 0) continue;
      final url = count.url;
      final match = (order: order, clicks: count.clicks);
      _exact[url] = match;
      if (!count.internal) continue;
      _internal[url] = match;
      if (url.startsWith('/uploads/')) {
        _uploads.add((url: url, match: match));
      }
    }
  }

  final _exact = <String, _LinkCountMatch>{};
  final _internal = <String, _LinkCountMatch>{};
  final _uploads = <({String url, _LinkCountMatch match})>[];

  int? clicksFor(String href) {
    var matched = _exact[href];
    if (_internal.isNotEmpty) {
      final query = href.indexOf('?');
      if (query >= 0) {
        final internal = _internal[href.substring(0, query)];
        // Payload order also wins across different kinds of matches.
        if (internal != null &&
            (matched == null || internal.order > matched.order)) {
          matched = internal;
        }
      }
    }

    // Upload paths can overlap and occur anywhere in an href. Keep their
    // literal contains rule, examining only records newer than the best match.
    for (final upload in _uploads.reversed) {
      if (matched != null && upload.match.order <= matched.order) break;
      if (href.contains(upload.url)) {
        matched = upload.match;
        break;
      }
    }
    return matched?.clicks;
  }
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
