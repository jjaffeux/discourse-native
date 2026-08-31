import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/oneboxes/onebox.dart';
import '../local_dates/local_dates_contract.dart';
import 'discourse_github_services.dart';
import 'oneboxes/commit/block.dart';
import 'oneboxes/github.dart';
import 'oneboxes/issue/block.dart';
import 'oneboxes/pr/block.dart';
import 'oneboxes/pr/inline.dart';

final class DiscourseGithubPlugin
    implements SitePlugin, CookedElementPlugin, CookedInlinePlugin {
  const DiscourseGithubPlugin({this.cookedTimeParser});

  final CookedTimeParser? cookedTimeParser;

  @override
  String get name => 'discourse-github';

  static final List<GithubOneboxEngine> _engines = [
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
      return _GithubOnebox(
        engine: engine,
        aside: element,
        envelope: OneboxData.from(element),
        siteUrl: siteUrl,
        cookedTimeParser: cookedTimeParser,
      );
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

final class _GithubOnebox extends StatelessWidget {
  const _GithubOnebox({
    required this.engine,
    required this.aside,
    required this.envelope,
    required this.siteUrl,
    required this.cookedTimeParser,
  });

  final GithubOneboxEngine engine;
  final dom.Element aside;
  final OneboxData envelope;
  final String? siteUrl;
  final CookedTimeParser? cookedTimeParser;

  @override
  Widget build(BuildContext context) => engine.build(
    aside,
    envelope,
    siteUrl,
    cookedTimeParser ??
        PluginUiScope.maybe(context, discourseGithubCookedTimeParserService),
  );
}
