import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../theme/d_icon.dart';
import '../../inline.dart';
import '../github.dart';

/// An inline onebox pointing at a GitHub pull request.
///
/// With `github_pr_status_enabled`, the server stamps the PR's state onto
/// the anchor as a `--gh-status-*` class; the web answers with a small
/// status-colored glyph ahead of the title (`github-pr-status.scss`), and so
/// does this.
class GithubPullRequestInlineOnebox {
  static bool matches(dom.Element anchor) {
    final uri = Uri.tryParse(anchor.attributes['href'] ?? '');
    if (uri == null) return false;

    final host = uri.host;
    if (host != 'github.com' && host != 'www.github.com') return false;

    final segments = uri.pathSegments;
    return segments.length >= 4 && segments[2] == 'pull';
  }

  static Widget from(dom.Element anchor) {
    final status = GithubPrStatus.fromClasses(anchor.classes);

    return InlineOneboxChip(
      href: anchor.attributes['href']!,
      child: TextSpan(
        children: [
          if (status != null) _statusIcon(status),
          TextSpan(text: anchor.text.trim()),
        ],
      ),
    );
  }

  /// 1.2em, the size the web gives the glyph next to the title.
  static WidgetSpan _statusIcon(GithubPrStatus status) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Builder(
        builder: (context) {
          final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
          return DIcon(status.icon, size: fontSize * 1.2, color: status.color);
        },
      ),
    ),
  );
}
