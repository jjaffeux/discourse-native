import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../theme/d_icon.dart';
import '../github.dart';

class GithubPullRequestInlineOnebox {
  static bool matches(dom.Element anchor) {
    final uri = Uri.tryParse(anchor.attributes['href'] ?? '');
    if (uri == null) return false;

    final host = uri.host;
    if (host != 'github.com' && host != 'www.github.com') return false;

    final segments = uri.pathSegments;
    return segments.length >= 4 && segments[2] == 'pull';
  }

  static GithubPrStatus? status(dom.Element anchor) =>
      matches(anchor) ? GithubPrStatus.fromClasses(anchor.classes) : null;

  /// 1.2em, the size the web gives the glyph next to the title.
  static Widget statusIcon(GithubPrStatus status) => ExcludeSemantics(
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
