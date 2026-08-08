import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../theme/app_theme.dart';
import '../../../../theme/d_icon.dart';
import '../../../relative_time.dart';
import '../../onebox.dart';
import '../github.dart';

/// The issue engine: `aside.onebox.githubissue`.
///
/// Same arrangement as the pull request onebox — icon column beside title and
/// facts, body underneath — with labels in place of branches and diff counts.
class GithubIssueOnebox extends StatelessWidget {
  const GithubIssueOnebox({super.key, required this.data});

  final GithubIssueData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: githubIconSize + 4,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: DIcon(
                  githubIssueIcon,
                  size: githubIconSize,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _Info(data: data),
                  if (data.labels.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final label in data.labels) _Label(name: label),
                      ],
                    ),
                  ],
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
  const _Info({required this.data});

  final GithubIssueData data;

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
        if (data.openedAt != null)
          Text(
            '${data.openedVerb ?? 'Opened'} ${relativeTime(data.openedAt!)}',
            style: muted,
          ),
        if (data.closedAt != null)
          Text(
            '${data.closedVerb ?? 'Closed'} ${relativeTime(data.closedAt!)}',
            style: muted,
          ),
        if (data.userLogin != null)
          GithubUser(
            login: data.userLogin!,
            avatarUrl: data.userAvatarUrl,
            url: data.userUrl,
          ),
      ],
    );
  }
}

/// The web paints every label the same muted chip — the colors the template
/// writes inline are overridden by its stylesheet.
class _Label extends StatelessWidget {
  const _Label({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.shell.hover,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Everything the issue onebox carries, read out of the aside.
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

  static GithubIssueData from(dom.Element aside) {
    final article =
        githubDescendant(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;
    final row = article.children
        .where((e) => e.classes.contains('github-row'))
        .firstOrNull;
    final scope = row ?? article;

    final titleLink = githubDescendant(
      scope,
      (e) => e.localName == 'h4',
    )?.children.where((e) => e.localName == 'a').firstOrNull;

    final info = githubDescendant(
      scope,
      (e) => e.classes.contains('github-info'),
    );
    final dates = info == null
        ? <dom.Element>[]
        : githubDescendants(info, (e) => e.classes.contains('date'));
    final userEl = info == null
        ? null
        : githubDescendant(info, (e) => e.classes.contains('user'));
    final userLink = userEl == null
        ? null
        : githubDescendant(userEl, (e) => e.localName == 'a');

    final labelsEl = githubDescendant(
      scope,
      (e) => e.classes.contains('labels'),
    );
    final labels = labelsEl == null
        ? <String>[]
        : labelsEl.children
              .where((e) => e.localName == 'span')
              .map((e) => e.text.trim())
              .where((text) => text.isNotEmpty)
              .toList();

    return GithubIssueData(
      title: (titleLink?.text ?? scope.text).trim(),
      titleUrl: titleLink?.attributes['href'],
      openedVerb: dates.isNotEmpty ? githubDateVerb(dates[0]) : null,
      openedAt: dates.isNotEmpty ? githubLocalDate(dates[0]) : null,
      closedVerb: dates.length > 1 ? githubDateVerb(dates[1]) : null,
      closedAt: dates.length > 1 ? githubLocalDate(dates[1]) : null,
      userLogin: userLink?.text.trim(),
      userAvatarUrl: userLink == null
          ? null
          : githubDescendant(
              userLink,
              (e) => e.classes.contains('onebox-avatar-inline'),
            )?.attributes['src'],
      userUrl: userLink?.attributes['href'],
      labels: labels,
      body: githubBody(article),
    );
  }
}

/// Claims `aside.onebox.githubissue`, for the dispatch in `onebox.dart`.
final OneboxEngine githubIssueBlock = OneboxEngine(
  matches: (aside) => aside.classes.contains('githubissue'),
  build: (aside, envelope) => OneboxCard(
    data: envelope,
    child: GithubIssueOnebox(data: GithubIssueData.from(aside)),
  ),
);
