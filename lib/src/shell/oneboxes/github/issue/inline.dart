import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../inline.dart';

/// An inline onebox pointing at a GitHub issue.
///
/// The web draws it as a plain link with its fetched title — no glyph,
/// unlike the pull request's status icon — and this claims it anyway so the
/// shape has a home when it grows one.
class GithubIssueInlineOnebox {
  static bool matches(dom.Element anchor) {
    final uri = Uri.tryParse(anchor.attributes['href'] ?? '');
    if (uri == null) return false;

    final host = uri.host;
    if (host != 'github.com' && host != 'www.github.com') return false;

    final segments = uri.pathSegments;
    return segments.length >= 4 && segments[2] == 'issues';
  }

  static Widget from(dom.Element anchor) => InlineOneboxChip(
    href: anchor.attributes['href']!,
    child: TextSpan(text: anchor.text.trim()),
  );
}
