import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:html/dom.dart' as dom;

import '../../local_dates/local_dates_contract.dart';

int? githubLineCount(dom.Element? lines, String className) => lines == null
    ? null
    : digitsIn(descendantWhere(lines, (e) => e.classes.contains(className)));

// Path data copied from the upstream GitHub onebox templates.

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
      if (node.localName == 'br') {
        buffer.writeln();
        continue;
      }
      pushReversed(node.nodes);
    } else if (node is dom.Text) {
      buffer.write(node.data);
    }
  }

  final text = buffer.toString().trim();
  return text.isEmpty ? null : text;
}

class GithubIssueData {
  const GithubIssueData({
    required this.title,
    required this.titleUrl,
    required this.openedVerb,
    required this.openedAt,
    required this.closedVerb,
    required this.closedAt,
    required this.userLogin,
    required this.userAvatarUrl,
    required this.userUrl,
    required this.labels,
    required this.body,
  });

  final String title;
  final String? titleUrl;

  final String? openedVerb;
  final DateTime? openedAt;
  final String? closedVerb;
  final DateTime? closedAt;

  final String? userLogin;
  final String? userAvatarUrl;
  final String? userUrl;

  final List<String> labels;

  final String? body;

  static GithubIssueData from(
    dom.Element aside, {
    required CookedTimeParser? cookedTimeParser,
  }) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;
    final row = childWhere(article, (e) => e.classes.contains('github-row'));
    final scope = row ?? article;

    final titleHeading = descendantWhere(scope, (e) => e.localName == 'h4');
    final titleLink = titleHeading == null
        ? null
        : childWhere(titleHeading, (e) => e.localName == 'a');

    final info = descendantWhere(
      scope,
      (e) => e.classes.contains('github-info'),
    );
    final dates = info == null
        ? <dom.Element>[]
        : descendantsWhere(info, (e) => e.classes.contains('date'));
    final userEl = info == null
        ? null
        : descendantWhere(info, (e) => e.classes.contains('user'));
    final userLink = userEl == null
        ? null
        : descendantWhere(userEl, (e) => e.localName == 'a');
    final openedTime = dates.isEmpty
        ? null
        : cookedTimeParser?.parseDescendant(dates[0]);
    final closedTime = dates.length < 2
        ? null
        : cookedTimeParser?.parseDescendant(dates[1]);

    final labelsEl = descendantWhere(
      scope,
      (e) => e.classes.contains('labels'),
    );
    final labels = labelsEl == null
        ? <String>[]
        : childrenWhere(
            labelsEl,
            (e) => e.localName == 'span',
          ).map((e) => e.text.trim()).where((text) => text.isNotEmpty).toList();

    return GithubIssueData(
      title: (titleLink?.text ?? scope.text).trim(),
      titleUrl: titleLink?.attributes['href'],
      openedVerb: dates.isNotEmpty ? githubDateVerb(dates[0]) : null,
      openedAt: openedTime,
      closedVerb: dates.length > 1 ? githubDateVerb(dates[1]) : null,
      closedAt: closedTime,
      userLogin: userLink?.text.trim(),
      userAvatarUrl: userLink == null
          ? null
          : descendantWhere(
              userLink,
              (e) => e.classes.contains('onebox-avatar-inline'),
            )?.attributes['src'],
      userUrl: userLink?.attributes['href'],
      labels: labels,
      body: githubBody(article),
    );
  }
}

class GithubCommitData {
  const GithubCommitData({
    required this.title,
    required this.titleUrl,
    required this.committedVerb,
    required this.committedAt,
    required this.authorLogin,
    required this.authorAvatarUrl,
    required this.authorUrl,
    required this.additions,
    required this.deletions,
    required this.body,
  });

  final String title;
  final String? titleUrl;

  final String? committedVerb;
  final DateTime? committedAt;

  final String? authorLogin;
  final String? authorAvatarUrl;
  final String? authorUrl;

  final int? additions;
  final int? deletions;

  final String? body;

  static GithubCommitData from(
    dom.Element aside, {
    required CookedTimeParser? cookedTimeParser,
  }) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;
    final row = childWhere(article, (e) => e.classes.contains('github-row'));
    final scope = row ?? article;

    final titleHeading = descendantWhere(scope, (e) => e.localName == 'h4');
    final titleLink = titleHeading == null
        ? null
        : childWhere(titleHeading, (e) => e.localName == 'a');

    final info = descendantWhere(
      scope,
      (e) => e.classes.contains('github-info'),
    );
    final dateEl = info == null
        ? null
        : descendantWhere(info, (e) => e.classes.contains('date'));
    final userEl = info == null
        ? null
        : descendantWhere(info, (e) => e.classes.contains('user'));
    final userLink = userEl == null
        ? null
        : descendantWhere(userEl, (e) => e.localName == 'a');
    final linesEl = info == null
        ? null
        : descendantWhere(info, (e) => e.classes.contains('lines'));
    final cookedTime = dateEl == null
        ? null
        : cookedTimeParser?.parseDescendant(dateEl);

    return GithubCommitData(
      title: (titleLink?.text ?? scope.text).trim(),
      titleUrl: titleLink?.attributes['href'],
      committedVerb: dateEl == null ? null : githubDateVerb(dateEl),
      committedAt: cookedTime,
      authorLogin: userLink?.text.trim(),
      authorAvatarUrl: userLink == null
          ? null
          : descendantWhere(
              userLink,
              (e) => e.classes.contains('onebox-avatar-inline'),
            )?.attributes['src'],
      authorUrl: userLink?.attributes['href'],
      additions: githubLineCount(linesEl, 'added'),
      deletions: githubLineCount(linesEl, 'removed'),
      body: githubBody(article),
    );
  }
}

class GithubPullRequestData {
  const GithubPullRequestData({
    required this.title,
    required this.titleUrl,
    required this.status,
    required this.iconVariant,
    required this.baseLabel,
    required this.headLabel,
    required this.dateVerb,
    required this.date,
    required this.userLogin,
    required this.userAvatarUrl,
    required this.userUrl,
    required this.additions,
    required this.deletions,
    required this.infoText,
    required this.body,
  });

  final String title;
  final String? titleUrl;

  final GithubPrStatus? status;

  final String? iconVariant;

  final String? baseLabel;
  final String? headLabel;

  final String? dateVerb;
  final DateTime? date;

  final String? userLogin;
  final String? userAvatarUrl;
  final String? userUrl;

  final int? additions;
  final int? deletions;

  final String? infoText;

  final String? body;

  DIconData get icon {
    final status = this.status;
    if (status != null) return status.icon;
    return switch (iconVariant) {
      'Commit' => githubCommitIcon,
      'Comment' => githubCommentIcon,
      'Discussion' => githubDiscussionIcon,
      _ => githubPullRequestIcon,
    };
  }

  static GithubPullRequestData from(
    dom.Element aside, {
    required CookedTimeParser? cookedTimeParser,
  }) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;
    final row =
        childWhere(article, (e) => e.classes.contains('github-row')) ?? article;

    final titleHeading = descendantWhere(row, (e) => e.localName == 'h4');
    final titleLink = titleHeading == null
        ? null
        : childWhere(titleHeading, (e) => e.localName == 'a');

    final iconContainer = descendantWhere(
      row,
      (e) => e.classes.contains('github-icon-container'),
    );
    final branches = descendantWhere(
      row,
      (e) => e.classes.contains('branches'),
    );
    final codes = branches == null
        ? <dom.Element>[]
        : childrenWhere(branches, (e) => e.localName == 'code');

    final info = descendantWhere(row, (e) => e.classes.contains('github-info'));
    final dateEl = info == null
        ? null
        : descendantWhere(info, (e) => e.classes.contains('date'));
    final userEl = info == null
        ? null
        : descendantWhere(info, (e) => e.classes.contains('user'));
    final userLink = userEl == null
        ? null
        : descendantWhere(userEl, (e) => e.localName == 'a');
    final linesEl = info == null
        ? null
        : descendantWhere(info, (e) => e.classes.contains('lines'));
    final cookedTime = dateEl == null
        ? null
        : cookedTimeParser?.parseDescendant(dateEl);

    final hasCells = dateEl != null || userEl != null || linesEl != null;
    final infoText = info != null && !hasCells ? oneLineText(info) : null;

    return GithubPullRequestData(
      title: (titleLink?.text ?? row.text).trim(),
      titleUrl: titleLink?.attributes['href'],
      status: GithubPrStatus.fromClasses(row.classes),
      iconVariant: iconContainer?.attributes['title'],
      baseLabel: codes.isNotEmpty ? codes[0].text.trim() : null,
      headLabel: codes.length > 1 ? codes[1].text.trim() : null,
      dateVerb: dateEl == null ? null : githubDateVerb(dateEl),
      date: cookedTime,
      userLogin: userLink?.text.trim(),
      userAvatarUrl: userLink == null
          ? null
          : descendantWhere(
              userLink,
              (e) => e.classes.contains('onebox-avatar-inline'),
            )?.attributes['src'],
      userUrl: userLink?.attributes['href'],
      additions: githubLineCount(linesEl, 'added'),
      deletions: githubLineCount(linesEl, 'removed'),
      infoText: infoText,
      body: githubBody(article),
    );
  }
}
