import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html/dom.dart' as dom;

import '../../../shell/avatar_image.dart';
import '../../../shell/code_block.dart' show monospaceTextStyle;
import '../../../shell/cooked_dom.dart';
import '../../../shell/oneboxes/markup.dart';
import '../../../shell/open_link.dart';
import '../../../shell/site_url.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/d_icon.dart';

/// The shared visual language of GitHub's oneboxes.
///
/// Discourse draws GitHub oneboxes from octicons embedded in its mustache
/// templates (`lib/onebox/templates/github*.mustache`) and colors their pull
/// request statuses from `plugins/discourse-github/.../github-pr-status.scss`.
/// The shapes below are taken verbatim from those files, so a onebox here
/// carries the same glyph and the same status color as on the web.

/// `+123` or `-45` from a `.lines` block, as a number.
///
/// The pull request and the commit engines read the same block of the same
/// template, and it writes the sign and the label in with the digits.
int? githubLineCount(dom.Element? lines, String className) => lines == null
    ? null
    : digitsIn(descendantWhere(lines, (e) => e.classes.contains(className)));

// --- Icons, path data taken from the upstream templates.

const DIconData githubIssueIcon = DIconData(
  'octicon-issue-opened',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 16"><path d="M7 2.3c3.14 0 5.7 2.56 5.7 5.7s-2.56 5.7-5.7 5.7A5.71 5.71 0 0 1 1.3 8c0-3.14 2.56-5.7 5.7-5.7zM7 1C3.14 1 0 4.14 0 8s3.14 7 7 7 7-3.14 7-7-3.14-7-7-7zm1 3H6v5h2V4zm0 6H6v2h2v-2z"/></svg>',
);

const DIconData githubPullRequestIcon = DIconData(
  'octicon-git-pull-request',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 12 16"><path d="M11 11.28V5c-.03-.78-.34-1.47-.94-2.06C9.46 2.35 8.78 2.03 8 2H7V0L4 3l3 3V4h1c.27.02.48.11.69.31.21.2.3.42.31.69v6.28A1.993 1.993 0 0 0 10 15a1.993 1.993 0 0 0 1-3.72zm-1 2.92c-.66 0-1.2-.55-1.2-1.2 0-.65.55-1.2 1.2-1.2.65 0 1.2.55 1.2 1.2 0 .65-.55 1.2-1.2 1.2zM4 3c0-1.11-.89-2-2-2a1.993 1.993 0 0 0-1 3.72v6.56A1.993 1.993 0 0 0 2 15a1.993 1.993 0 0 0 1-3.72V4.72c.59-.34 1-.98 1-1.72zm-.8 10c0 .66-.55 1.2-1.2 1.2-.65 0-1.2-.55-1.2-1.2 0-.65.55-1.2 1.2-1.2.65 0 1.2.55 1.2 1.2zM2 4.2C1.34 4.2.8 3.65.8 3c0-.65.55-1.2 1.2-1.2.65 0 1.2.55 1.2 1.2 0 .65-.55 1.2-1.2 1.2z"/></svg>',
);

const DIconData githubCommitIcon = DIconData(
  'octicon-commit',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 16"><path d="M10.86 7c-.45-1.72-2-3-3.86-3-1.86 0-3.41 1.28-3.86 3H0v2h3.14c.45 1.72 2 3 3.86 3 1.86 0 3.41-1.28 3.86-3H14V7h-3.14zM7 10.2c-1.22 0-2.2-.98-2.2-2.2 0-1.22.98-2.2 2.2-2.2 1.22 0 2.2.98 2.2 2.2 0 1.22-.98 2.2-2.2 2.2z"/></svg>',
);

const DIconData githubCommentIcon = DIconData(
  'octicon-comment',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M1.5 2.75a.25.25 0 01.25-.25h8.5a.25.25 0 01.25.25v5.5a.25.25 0 01-.25.25h-3.5a.75.75 0 00-.53.22L3.5 11.44V9.25a.75.75 0 00-.75-.75h-1a.25.25 0 01-.25-.25v-5.5zM1.75 1A1.75 1.75 0 000 2.75v5.5C0 9.216.784 10 1.75 10H2v1.543a1.457 1.457 0 002.487 1.03L7.061 10h3.189A1.75 1.75 0 0012 8.25v-5.5A1.75 1.75 0 0010.25 1h-8.5zM14.5 4.75a.25.25 0 00-.25-.25h-.5a.75.75 0 110-1.5h.5c.966 0 1.75.784 1.75 1.75v5.5A1.75 1.75 0 0114.25 12H14v1.543a1.457 1.457 0 01-2.487 1.03L9.22 12.28a.75.75 0 111.06-1.06l2.22 2.22v-2.19a.75.75 0 01.75-.75h1a.25.25 0 00.25-.25v-5.5z"/></svg>',
);

const DIconData githubDiscussionIcon = DIconData(
  'octicon-discussion',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M1.679 7.932c.412-.621 1.242-1.75 2.366-2.717C5.175 4.242 6.527 3.5 8 3.5c1.473 0 2.824.742 3.955 1.715 1.124.967 1.954 2.096 2.366 2.717a.119.119 0 010 .136c-.412.621-1.242 1.75-2.366 2.717C10.825 11.758 9.473 12.5 8 12.5c-1.473 0-2.824-.742-3.955-1.715C2.92 9.818 2.09 8.69 1.679 8.068a.119.119 0 010-.136zM8 2c-1.981 0-3.67.992-4.933 2.078C1.797 5.169.88 6.423.43 7.1a1.619 1.619 0 000 1.798c.45.678 1.367 1.932 2.637 3.024C4.329 13.008 6.019 14 8 14c1.981 0 3.67-.992 4.933-2.078 1.27-1.091 2.187-2.345 2.637-3.023a1.619 1.619 0 000-1.798c-.45-.678-1.367-1.932-2.637-3.023C11.671 2.992 9.981 2 8 2zm0 8a2 2 0 100-4 2 2 0 000 4z"/></svg>',
);

// --- Pull request status, from `--gh-status-*` classes.

/// The states `github_pr_status_enabled` can stamp onto a pull request
/// onebox, written by the server as `--gh-status-<name>` classes.
enum GithubPrStatus {
  draft,
  open,
  approved,
  changesRequested,
  merged,
  closed;

  /// Reads a `--gh-status-*` class list, null when none is present.
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

  /// GitHub's own color for the status, as in `github-pr-status.scss`. One
  /// value for both brightnesses: these are GitHub's identity colors, not the
  /// site's.
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
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 1 1.5 0 .75.75 0 0 1-1.5 0Z"/></svg>',
);

const DIconData githubPrDraftIcon = DIconData(
  'octicon-git-pull-request-draft',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 14a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM14 4.25a.75.75 0 0 1-.75.75h-2a.75.75 0 0 1 0-1.5h2a.75.75 0 0 1 .75.75Zm-.75 3.75a.75.75 0 0 0 0-1.5h-2a.75.75 0 0 0 0 1.5Z"/></svg>',
);

const DIconData githubPrMergedIcon = DIconData(
  'octicon-git-pull-request-merged',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z"/></svg>',
);

const DIconData githubPrClosedIcon = DIconData(
  'octicon-git-pull-request-closed',
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 3.25 1Zm9.5 5.5a.75.75 0 0 1 .75.75v3.378a2.251 2.251 0 1 1-1.5 0V7.25a.75.75 0 0 1 .75-.75Zm-2.03-5.273a.75.75 0 0 1 1.06 0l.97.97.97-.97a.748.748 0 0 1 1.265.332.75.75 0 0 1-.205.729l-.97.97.97.97a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-.97-.97-.97.97a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l.97-.97-.97-.97a.75.75 0 0 1 0-1.06ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"/></svg>',
);

/// The color GitHub paints diff counts with — additions and deletions in
/// block oneboxes read the way they do on github.com itself.
const Color githubAdditionColor = Color(0xFF3FB950);
const Color githubDeletionColor = Color(0xFFF85149);

// --- Shared body parts, drawn the same by issues, PRs and commits.

/// Core's onebox font is 16px. Legacy GitHub SVGs are square and capped at
/// 1.8em; the status plugin reserves the old 12:16 slot for its 2.5em-wide
/// replacement. The replacement SVGs themselves have square 16:16 viewBoxes,
/// so they stay square inside that slot instead of being stretched to fit it.
const double _githubOneboxFontSize = 16;
const double githubIconColumnWidth = _githubOneboxFontSize * 2.5;
const double githubIconGap = _githubOneboxFontSize * 0.75;
const Size githubLegacyIconSize = Size.square(_githubOneboxFontSize * 1.8);
const Size githubPrStatusIconSize = Size.square(githubIconColumnWidth);
const Size githubPrStatusSlotSize = Size(
  githubIconColumnWidth,
  githubIconColumnWidth / (12 / 16),
);

/// A block-onebox GitHub SVG with core's raw sizing rather than [DIcon]'s
/// Font Awesome optical scaling.
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
        child: SizedBox.fromSize(
          size: iconSize,
          child: SvgPicture.string(
            icon.tintableSvg,
            fit: BoxFit.contain,
            theme: SvgTheme(currentColor: color),
          ),
        ),
      ),
    );
  }
}

/// The avatar the info row carries, 20px with 2px corners as on the web.
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

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (avatarUrl != null) ...[
          ClipRRect(
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
          const SizedBox(width: 4),
        ],
        Text(
          login,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final url = this.url;
    if (url == null) return row;

    return _GithubInlineLink(
      label: login,
      url: url,
      siteUrl: siteUrl,
      child: row,
    );
  }
}

/// A diff count such as `+123 −45`, opening the files tab when it has a link.
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

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('+$additions', style: style?.copyWith(color: githubAdditionColor)),
        const SizedBox(width: 6),
        Text('−$deletions', style: style?.copyWith(color: githubDeletionColor)),
      ],
    );

    final url = this.url;
    if (url == null) return row;

    return _GithubInlineLink(
      label:
          '$additions ${additions == 1 ? 'addition' : 'additions'}, '
          '$deletions ${deletions == 1 ? 'deletion' : 'deletions'}',
      url: url,
      siteUrl: siteUrl,
      child: row,
    );
  }
}

/// A compact metadata link inside a GitHub card.
///
/// It uses the inline-target exception rather than stretching the card's info
/// row to 44 pixels, but still exposes a native keyboard focus and action path.
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
  Widget build(BuildContext context) {
    final hover = Theme.of(context).shell.hover;
    return Semantics(
      container: true,
      link: true,
      label: label,
      child: InkWell(
        onTap: () => openLink(context, url, siteUrl: siteUrl),
        borderRadius: BorderRadius.circular(2),
        hoverColor: hover,
        focusColor: hover,
        child: ExcludeSemantics(child: child),
      ),
    );
  }
}

/// The onebox body: GitHub's API returns it as markdown, Discourse's template
/// escapes it and prints it in a monospace face, truncated.
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

// --- DOM reading shared by the GitHub engines.

/// The `discourse-local-date` span carries the real moment in `data-date` and
/// `data-time`; the text the server wrote as a fallback is a fixed-time
/// string nobody asked for.
DateTime? githubLocalDate(dom.Element scope) {
  final span = descendantWhere(
    scope,
    (e) => e.classes.contains('discourse-local-date'),
  );
  if (span == null) return null;

  final date = span.attributes['data-date'];
  final time = span.attributes['data-time'];
  if (date == null || time == null) return null;
  return DateTime.tryParse('$date $time Z');
}

/// The verb a `.date` cell leads with — "Opened", "Merged"… — which is the
/// text around its `discourse-local-date` span, localized server-side.
String? githubDateVerb(dom.Element dateEl) {
  final text = dateEl.nodes
      .map((node) => node.text ?? '')
      .join()
      .replaceAll(githubLocalDateText(dateEl), '')
      .trim();
  return text.isEmpty ? null : text;
}

String githubLocalDateText(dom.Element dateEl) {
  final span = descendantWhere(
    dateEl,
    (e) => e.classes.contains('discourse-local-date'),
  );
  return span?.text ?? '';
}

/// The issue/PR/commit body, minus the "show more" link and the hidden
/// excerpt the template appends for the web's expander.
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
