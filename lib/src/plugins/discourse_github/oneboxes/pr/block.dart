import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../shell/code_block.dart' show monospaceTextStyle;
import '../../../../shell/cooked_dom.dart';
import '../../../../shell/oneboxes/markup.dart';
import '../../../../shell/oneboxes/onebox.dart';
import '../../../../shell/relative_time.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/d_icon.dart';
import '../../../local_dates/local_dates_contract.dart';
import '../github.dart';

class GithubPullRequestOnebox extends StatelessWidget {
  const GithubPullRequestOnebox({super.key, required this.data, this.siteUrl});

  final GithubPullRequestData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: data.status == null
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            GithubOneboxIcon(
              icon: data.icon,
              color: data.status?.color ?? theme.discourse.primaryHigh,
              isPrStatus: data.status != null,
            ),
            const SizedBox(width: githubIconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (data.baseLabel != null && data.headLabel != null) ...[
                    const SizedBox(height: 4),
                    _Branches(base: data.baseLabel!, head: data.headLabel!),
                  ],
                  const SizedBox(height: 6),
                  _Info(data: data, siteUrl: siteUrl),
                ],
              ),
            ),
          ],
        ),
        if (data.body != null) GithubBodyText(text: data.body!),
      ],
    );
  }
}

class _Branches extends StatelessWidget {
  const _Branches({required this.base, required this.head});

  final String base;
  final String head;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium
        ?.merge(monospaceTextStyle)
        .copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: base, style: style),
          TextSpan(text: ' ← ', style: style),
          TextSpan(text: head, style: style),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.data, required this.siteUrl});

  final GithubPullRequestData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // PR deep-link markup has one text run instead of metadata cells.
    if (data.infoText != null) {
      return Text(
        data.infoText!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted,
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (data.date != null)
          Text(
            '${data.dateVerb ?? ''} ${relativeTime(data.date!)}'.trim(),
            style: muted,
          ),
        if (data.userLogin != null)
          GithubUser(
            login: data.userLogin!,
            avatarUrl: data.userAvatarUrl,
            url: data.userUrl,
            siteUrl: siteUrl,
          ),
        if (data.additions != null && data.deletions != null)
          GithubLineCounts(
            additions: data.additions!,
            deletions: data.deletions!,
            url: data.titleUrl == null ? null : '${data.titleUrl}/files',
            siteUrl: siteUrl,
          ),
      ],
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

final GithubOneboxEngine githubPullRequestBlock = GithubOneboxEngine(
  matches: (aside) => aside.classes.contains('githubpullrequest'),
  build: (aside, envelope, siteUrl, cookedTimeParser) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: GithubPullRequestOnebox(
      data: GithubPullRequestData.from(
        aside,
        cookedTimeParser: cookedTimeParser,
      ),
      siteUrl: siteUrl,
    ),
  ),
);
