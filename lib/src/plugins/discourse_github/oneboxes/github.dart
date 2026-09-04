import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../shell/avatar_image.dart';
import '../../../shell/code_block.dart' show monospaceTextStyle;
import '../../../shell/cooked_dom.dart';
import '../../../shell/inline_action.dart';
import '../../../shell/oneboxes/markup.dart';
import '../../../shell/oneboxes/onebox.dart';
import '../../../shell/open_link.dart';
import '../../../shell/site_url.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/d_icon.dart';
import '../../local_dates/local_dates_contract.dart';

class GithubOneboxEngine {
  const GithubOneboxEngine({required this.matches, required this.build});

  final bool Function(dom.Element aside) matches;
  final Widget Function(
    dom.Element aside,
    OneboxData envelope,
    String? siteUrl,
    CookedTimeParser? cookedTimeParser,
  )
  build;
}

int? githubLineCount(dom.Element? lines, String className) => lines == null
    ? null
    : digitsIn(descendantWhere(lines, (e) => e.classes.contains(className)));

const DIconData githubIssueIcon = DIconData(
  'octicon-issue-opened',
  LucideIcons.circleDot,
);

const DIconData githubPullRequestIcon = DIconData(
  'octicon-git-pull-request',
  LucideIcons.gitPullRequest,
);

const DIconData githubCommitIcon = DIconData(
  'octicon-commit',
  LucideIcons.gitCommitHorizontal,
);

const DIconData githubCommentIcon = DIconData(
  'octicon-comment',
  LucideIcons.messageSquare,
);

const DIconData githubDiscussionIcon = DIconData(
  'octicon-discussion',
  LucideIcons.messagesSquare,
);

enum GithubPrStatus {
  draft,
  open,
  approved,
  changesRequested,
  merged,
  closed;

  static GithubPrStatus? fromClasses(Iterable<String> classes) {
    for (final className in classes) {
      if (!className.startsWith('--gh-status-')) continue;
      final name = className.substring('--gh-status-'.length);
      for (final status in values) {
        if (status._className == name) return status;
      }
    }
    return null;
  }

  String get _className => switch (this) {
    changesRequested => 'changes_requested',
    _ => name,
  };

  /// GitHub identity color from `github-pr-status.scss`, independent of theme.
  Color get color => switch (this) {
    draft || open => const Color(0xFF8B949E),
    approved => const Color(0xFF3FB950),
    changesRequested => const Color(0xFFF79939),
    merged => const Color(0xFFA371F7),
    closed => const Color(0xFFF85149),
  };

  DIconData get icon => switch (this) {
    draft => githubPrDraftIcon,
    merged => githubPrMergedIcon,
    closed => githubPrClosedIcon,
    _ => githubPrOpenIcon,
  };
}

const DIconData githubPrOpenIcon = DIconData(
  'octicon-git-pull-request-open',
  LucideIcons.gitPullRequest,
);

const DIconData githubPrDraftIcon = DIconData(
  'octicon-git-pull-request-draft',
  LucideIcons.gitPullRequestDraft,
);

const DIconData githubPrMergedIcon = DIconData(
  'octicon-git-pull-request-merged',
  LucideIcons.gitMerge,
);

const DIconData githubPrClosedIcon = DIconData(
  'octicon-git-pull-request-closed',
  LucideIcons.gitPullRequestClosed,
);

const Color githubAdditionColor = Color(0xFF3FB950);
const Color githubDeletionColor = Color(0xFFF85149);

/// Preserves the onebox icon column while rendering the Lucide glyphs square.
const double _githubOneboxFontSize = 16;
const double githubIconColumnWidth = _githubOneboxFontSize * 2.5;
const double githubIconGap = _githubOneboxFontSize * 0.75;
const Size githubLegacyIconSize = Size.square(_githubOneboxFontSize * 1.8);
const Size githubPrStatusIconSize = Size.square(githubIconColumnWidth);
const Size githubPrStatusSlotSize = githubPrStatusIconSize;

class GithubOneboxIcon extends StatelessWidget {
  const GithubOneboxIcon({
    super.key,
    required this.icon,
    required this.color,
    this.isPrStatus = false,
  });

  final DIconData icon;
  final Color color;
  final bool isPrStatus;

  @override
  Widget build(BuildContext context) {
    final iconSize = isPrStatus ? githubPrStatusIconSize : githubLegacyIconSize;
    final slotSize = isPrStatus ? githubPrStatusSlotSize : githubLegacyIconSize;

    return SizedBox.fromSize(
      size: slotSize,
      child: Center(
        child: DIcon(icon, size: iconSize.width, color: color),
      ),
    );
  }
}

class GithubUser extends StatelessWidget {
  const GithubUser({
    super.key,
    required this.login,
    required this.avatarUrl,
    required this.url,
    this.siteUrl,
  });

  final String login;
  final String? avatarUrl;
  final String? url;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final label = Text.rich(
      TextSpan(
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          if (avatarUrl != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox.square(
                  dimension: 20,
                  child: AvatarImage(
                    url: resolveSiteUrl(avatarUrl!, siteUrl),
                    size: 20,
                    fallback: ColoredBox(color: theme.shell.floating),
                  ),
                ),
              ),
            ),
            const WidgetSpan(child: SizedBox(width: 4)),
          ],
          TextSpan(text: login),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final url = this.url;
    if (url == null) return label;

    return _GithubInlineLink(
      label: login,
      url: url,
      siteUrl: siteUrl,
      child: label,
    );
  }
}

class GithubLineCounts extends StatelessWidget {
  const GithubLineCounts({
    super.key,
    required this.additions,
    required this.deletions,
    required this.url,
    this.siteUrl,
  });

  final int additions;
  final int deletions;
  final String? url;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    final counts = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+$additions',
            style: style?.copyWith(color: githubAdditionColor),
          ),
          const WidgetSpan(child: SizedBox(width: 6)),
          TextSpan(
            text: '−$deletions',
            style: style?.copyWith(color: githubDeletionColor),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final url = this.url;
    if (url == null) return counts;

    return _GithubInlineLink(
      label:
          '$additions ${additions == 1 ? 'addition' : 'additions'}, '
          '$deletions ${deletions == 1 ? 'deletion' : 'deletions'}',
      url: url,
      siteUrl: siteUrl,
      child: counts,
    );
  }
}

/// Uses the inline-target exception without losing keyboard focus or activation.
class _GithubInlineLink extends StatelessWidget {
  const _GithubInlineLink({
    required this.label,
    required this.url,
    required this.siteUrl,
    required this.child,
  });

  final String label;
  final String url;
  final String? siteUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) => LinkTarget(
    url: url,
    siteUrl: siteUrl,
    child: InlineAction.link(
      onTap: () => openLink(context, url, siteUrl: siteUrl),
      semanticLabel: label,
      excludeChildSemantics: true,
      child: child,
    ),
  );
}

class GithubBodyText extends StatelessWidget {
  const GithubBodyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium
            ?.merge(monospaceTextStyle)
            .copyWith(
              fontSize: DiscourseTypography.code,
              height: DiscourseTypography.codeLineHeight,
              color: theme.discourse.primaryVeryHigh,
            ),
      ),
    );
  }
}

String? githubDateVerb(dom.Element dateEl) {
  final text = dateEl.nodes
      .whereType<dom.Text>()
      .map((node) => node.data)
      .join()
      .trim();
  return text.isEmpty ? null : text;
}

String? githubBody(dom.Element article) {
  final p = descendantWhere(
    article,
    (e) => e.classes.contains('github-body-container'),
  );
  if (p == null) return null;

  final buffer = StringBuffer();
  final pending = <dom.Node>[];
  void pushReversed(List<dom.Node> nodes) {
    for (var index = nodes.length - 1; index >= 0; index--) {
      pending.add(nodes[index]);
    }
  }

  pushReversed(p.nodes);
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node is dom.Element) {
      if (node.classes.contains('excerpt') ||
          node.classes.contains('show-more-container')) {
        continue;
      }
      pushReversed(node.nodes);
      continue;
    }
    buffer.write(node.text);
  }

  final text = buffer.toString().trim();
  return text.isEmpty ? null : text;
}
