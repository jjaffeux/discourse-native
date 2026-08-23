import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../theme/app_theme.dart';
import '../../../cooked_dom.dart';
import '../../../relative_time.dart';
import '../../onebox.dart';
import '../github.dart';

/// The commit engine: `aside.onebox.githubcommit`.
///
/// The first line of the commit message as the title, then who committed it,
/// when, and what the diff touched.
class GithubCommitOnebox extends StatelessWidget {
  const GithubCommitOnebox({super.key, required this.data, this.siteUrl});

  final GithubCommitData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GithubOneboxIcon(
              icon: githubCommitIcon,
              color: theme.discourse.primaryHigh,
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

class _Info extends StatelessWidget {
  const _Info({required this.data, required this.siteUrl});

  final GithubCommitData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (data.committedAt != null)
          Text(
            '${data.committedVerb ?? 'Committed'} '
            '${relativeTime(data.committedAt!)}',
            style: muted,
          ),
        if (data.authorLogin != null)
          GithubUser(
            login: data.authorLogin!,
            avatarUrl: data.authorAvatarUrl,
            url: data.authorUrl,
            siteUrl: siteUrl,
          ),
        if (data.additions != null && data.deletions != null)
          GithubLineCounts(
            additions: data.additions!,
            deletions: data.deletions!,
            url: data.titleUrl,
            siteUrl: siteUrl,
          ),
      ],
    );
  }
}

/// Everything the commit onebox carries, read out of the aside.
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

  static GithubCommitData from(dom.Element aside) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;
    final row = article.children
        .where((e) => e.classes.contains('github-row'))
        .firstOrNull;
    final scope = row ?? article;

    final titleLink = descendantWhere(
      scope,
      (e) => e.localName == 'h4',
    )?.children.where((e) => e.localName == 'a').firstOrNull;

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

    return GithubCommitData(
      title: (titleLink?.text ?? scope.text).trim(),
      titleUrl: titleLink?.attributes['href'],
      committedVerb: dateEl == null ? null : githubDateVerb(dateEl),
      committedAt: dateEl == null ? null : githubLocalDate(dateEl),
      authorLogin: userLink?.text.trim(),
      authorAvatarUrl: userLink == null
          ? null
          : descendantWhere(
              userLink,
              (e) => e.classes.contains('onebox-avatar-inline'),
            )?.attributes['src'],
      authorUrl: userLink?.attributes['href'],
      additions: _count(linesEl, 'added'),
      deletions: _count(linesEl, 'removed'),
      body: githubBody(article),
    );
  }

  static int? _count(dom.Element? linesEl, String className) {
    if (linesEl == null) return null;
    final span = descendantWhere(linesEl, (e) => e.classes.contains(className));
    return int.tryParse(span?.text.replaceAll(RegExp(r'[^\d]'), '') ?? '');
  }
}

/// Claims `aside.onebox.githubcommit`, for the dispatch in `onebox.dart`.
final OneboxEngine githubCommitBlock = OneboxEngine(
  matches: (aside) => aside.classes.contains('githubcommit'),
  build: (aside, envelope, siteUrl) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: GithubCommitOnebox(
      data: GithubCommitData.from(aside),
      siteUrl: siteUrl,
    ),
  ),
);
