import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../github.dart';

export '../github_onebox_data.dart' show GithubCommitData;

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
                    style: theme.textTheme.titleSmall?.copyWith(
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
        if (data.committedAt case final committedAt?)
          RelativeTimeBuilder(
            when: committedAt,
            builder: (context, age) => Text(
              '${data.committedVerb ?? context.l10n.committed} $age',
              style: muted,
            ),
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

final GithubOneboxEngine githubCommitBlock = GithubOneboxEngine(
  matches: (aside) => aside.classes.contains('githubcommit'),
  build: (aside, envelope, siteUrl, cookedTimeParser) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: GithubCommitOnebox(
      data: GithubCommitData.from(aside, cookedTimeParser: cookedTimeParser),
      siteUrl: siteUrl,
    ),
  ),
);
