import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/material.dart';

import '../github.dart';

export '../github_onebox_data.dart' show GithubPullRequestData;

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
                    style: theme.textTheme.titleSmall?.copyWith(
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
        if (data.date case final date?)
          RelativeTimeBuilder(
            when: date,
            builder: (context, age) =>
                Text('${data.dateVerb ?? ''} $age'.trim(), style: muted),
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
