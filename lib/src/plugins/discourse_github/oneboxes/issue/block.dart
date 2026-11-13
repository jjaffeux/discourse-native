import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../github.dart';

export '../github_onebox_data.dart' show GithubIssueData;

class GithubIssueOnebox extends StatelessWidget {
  const GithubIssueOnebox({super.key, required this.data, this.siteUrl});

  final GithubIssueData data;
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
              icon: githubIssueIcon,
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
  const _Info({required this.data, required this.siteUrl});

  final GithubIssueData data;
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
        if (data.openedAt case final openedAt?)
          RelativeTimeBuilder(
            when: openedAt,
            builder: (context, age) => Text(
              '${data.openedVerb ?? context.l10n.opened} $age',
              style: muted,
            ),
          ),
        if (data.closedAt case final closedAt?)
          RelativeTimeBuilder(
            when: closedAt,
            builder: (context, age) => Text(
              '${data.closedVerb ?? context.l10n.closed} $age',
              style: muted,
            ),
          ),
        if (data.userLogin != null)
          GithubUser(
            login: data.userLogin!,
            avatarUrl: data.userAvatarUrl,
            url: data.userUrl,
            siteUrl: siteUrl,
          ),
      ],
    );
  }
}

/// Upstream CSS overrides template label colors with one muted chip.
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

final GithubOneboxEngine githubIssueBlock = GithubOneboxEngine(
  matches: (aside) => aside.classes.contains('githubissue'),
  build: (aside, envelope, siteUrl, cookedTimeParser) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: GithubIssueOnebox(
      data: GithubIssueData.from(aside, cookedTimeParser: cookedTimeParser),
      siteUrl: siteUrl,
    ),
  ),
);
