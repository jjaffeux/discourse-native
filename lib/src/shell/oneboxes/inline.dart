import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../open_link.dart';
import 'discourse/topic/inline.dart';
import 'github/issue/inline.dart';
import 'github/pr/inline.dart';

/// Renders Discourse's inline oneboxes natively, for the cooked HTML's custom
/// widget builder.
///
/// A link that does not sit alone on its line is not oneboxed into an
/// `aside.onebox`; when `enable_inline_onebox` is on, Discourse's
/// `InlineOneboxer` fetches its title instead and rewrites the anchor as
/// `<a class="inline-onebox">Title</a>`, sometimes with an extra class such
/// as `--gh-status-merged`. Left alone, that renders as an ordinary link —
/// which is what the web shows too — so the only ones claimed here are the
/// ones with something native to add, like the pull request status glyph.
Widget? inlineOneboxWidgetBuilder(dom.Element element, {String? siteUrl}) {
  if (element.localName != 'a') return null;
  if (!element.classes.contains('inline-onebox')) return null;

  final href = element.attributes['href'];
  if (href == null || href.isEmpty) return null;

  if (GithubPullRequestInlineOnebox.matches(element)) {
    return GithubPullRequestInlineOnebox.from(element, siteUrl: siteUrl);
  }
  if (GithubIssueInlineOnebox.matches(element)) {
    return GithubIssueInlineOnebox.from(element, siteUrl: siteUrl);
  }
  if (DiscourseTopicInlineOnebox.matches(element)) {
    return DiscourseTopicInlineOnebox.from(element, siteUrl: siteUrl);
  }

  // Anything else — an inline onebox of some other domain — is a link with
  // its title fetched, which the default anchor rendering already shows.
  return null;
}

/// The shared shape of an inline onebox: a run of text in link color,
/// optionally led by a small glyph, opening [href] on tap.
class InlineOneboxChip extends StatelessWidget {
  const InlineOneboxChip({
    super.key,
    required this.href,
    required this.child,
    this.siteUrl,
  });

  final String href;
  final InlineSpan child;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    // Same color as the default anchor: an inline onebox is a link first.
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final label = child
        .toPlainText(includePlaceholders: false)
        .trim()
        .nullIfEmpty;

    void activate() => openLink(context, href, siteUrl: siteUrl);

    // Inline oneboxes sit in a sentence through a WidgetSpan. They use WCAG's
    // inline-target exception rather than forcing a 44px paragraph line, while
    // the complete painted title remains clickable and keyboard focusable.
    return Semantics(
      container: true,
      link: true,
      label: label ?? href,
      onTap: activate,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: activate,
            borderRadius: BorderRadius.circular(2),
            focusColor: color.withValues(alpha: 0.16),
            child: Text.rich(child, style: TextStyle(color: color)),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
