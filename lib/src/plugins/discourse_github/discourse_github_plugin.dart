import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../../plugin_api/site_plugin_api.dart';
import '../../shell/oneboxes/onebox.dart';
import 'oneboxes/commit/block.dart';
import 'oneboxes/issue/block.dart';
import 'oneboxes/pr/block.dart';
import 'oneboxes/pr/inline.dart';

/// Native presentation for oneboxes produced by GitHub and discourse-github.
///
/// Generic onebox chrome remains in core. This capability owns only the
/// provider-specific body parsers and the optional pull-request status glyph
/// that discourse-github adds to inline oneboxes.
final class DiscourseGithubPlugin
    implements SitePlugin, CookedElementPlugin, CookedInlinePlugin {
  const DiscourseGithubPlugin();

  @override
  String get name => 'discourse-github';

  static final List<OneboxEngine> _engines = [
    githubPullRequestBlock,
    githubIssueBlock,
    githubCommitBlock,
  ];

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) {
    if (element.localName != 'aside' || !element.classes.contains('onebox')) {
      return null;
    }

    for (final engine in _engines) {
      if (!engine.matches(element)) continue;
      return engine.build(element, OneboxData.from(element), siteUrl);
    }
    return null;
  }

  @override
  CookedInlinePrefix? cookedInlinePrefix(dom.Element element) {
    if (element.localName != 'a' ||
        !element.classes.contains('inline-onebox')) {
      return null;
    }
    final status = GithubPullRequestInlineOnebox.status(element);
    if (status == null) return null;
    return CookedInlinePrefix(
      child: GithubPullRequestInlineOnebox.statusIcon(status),
      excludeLinkSemantics: true,
    );
  }
}
