import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../theme/app_theme.dart';
import '../../../../theme/d_icon.dart';
import '../../../code_block.dart' show monospaceTextStyle;
import '../../../cooked_dom.dart';
import '../../../relative_time.dart';
import '../../onebox.dart';
import '../github.dart';

/// The pull request engine: `aside.onebox.githubpullrequest`.
///
/// Discourse fetches the PR from GitHub's API and renders
/// `githubpullrequest.mustache` — an icon column beside the title, the
/// branches, a row of facts, then the body underneath. The web lays that out
/// with a CSS grid; this is the same arrangement as a column beside a column.
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

/// `base ← head`, the way the template writes the two branch names.
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

    // The template's shape for a PR deep link — a comment, a commit or a
    // review — has no `.date`/`.user`/`.lines` cells, just one run of text.
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

/// Everything the PR onebox carries, read out of the aside.
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

  /// The `--gh-status-*` class of the first row, when the site has
  /// `github_pr_status_enabled` on.
  final GithubPrStatus? status;

  /// The `title` of `github-icon-container`: a deep link into the PR —
  /// comment, commit or review — shows a different glyph than the PR itself.
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

  /// The single run of text a PR deep-link onebox carries instead of the
  /// date/user/lines cells.
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

  static GithubPullRequestData from(dom.Element aside) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;
    final rows = article.children
        .where((e) => e.classes.contains('github-row'))
        .toList();
    final row = rows.isNotEmpty ? rows.first : article;

    final titleLink = descendantWhere(
      row,
      (e) => e.localName == 'h4',
    )?.children.where((e) => e.localName == 'a').firstOrNull;

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
        : branches.children.where((e) => e.localName == 'code').toList();

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

    // The deep-link shape writes one `<span>` of free text where the PR
    // shape writes its cells.
    final hasCells = dateEl != null || userEl != null || linesEl != null;
    final infoText = info != null && !hasCells
        ? info.text.replaceAll(RegExp(r'\s+'), ' ').trim()
        : null;

    return GithubPullRequestData(
      title: (titleLink?.text ?? row.text).trim(),
      titleUrl: titleLink?.attributes['href'],
      status: GithubPrStatus.fromClasses(row.classes),
      iconVariant: iconContainer?.attributes['title'],
      baseLabel: codes.isNotEmpty ? codes[0].text.trim() : null,
      headLabel: codes.length > 1 ? codes[1].text.trim() : null,
      dateVerb: dateEl == null ? null : githubDateVerb(dateEl),
      date: dateEl == null ? null : githubLocalDate(dateEl),
      userLogin: userLink?.text.trim(),
      userAvatarUrl: userLink == null
          ? null
          : descendantWhere(
              userLink,
              (e) => e.classes.contains('onebox-avatar-inline'),
            )?.attributes['src'],
      userUrl: userLink?.attributes['href'],
      additions: _count(linesEl, 'added'),
      deletions: _count(linesEl, 'removed'),
      infoText: infoText,
      body: githubBody(article),
    );
  }

  /// `+123` in a `.added` span, as a number.
  static int? _count(dom.Element? linesEl, String className) {
    if (linesEl == null) return null;
    final span = descendantWhere(linesEl, (e) => e.classes.contains(className));
    return int.tryParse(span?.text.replaceAll(RegExp(r'[^\d]'), '') ?? '');
  }
}

/// Claims `aside.onebox.githubpullrequest`, for the dispatch in `onebox.dart`.
final OneboxEngine githubPullRequestBlock = OneboxEngine(
  matches: (aside) => aside.classes.contains('githubpullrequest'),
  build: (aside, envelope, siteUrl) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: GithubPullRequestOnebox(
      data: GithubPullRequestData.from(aside),
      siteUrl: siteUrl,
    ),
  ),
);
