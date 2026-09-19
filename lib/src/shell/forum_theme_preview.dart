import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'topic_list_view.dart';

/// Uses the production topic rows without allowing sample content to navigate.
class ForumThemePreview extends StatelessWidget {
  const ForumThemePreview({
    super.key,
    required this.theme,
    required this.siteUrl,
  });

  final ThemeData theme;
  final String siteUrl;

  static const topics = [
    Topic(
      id: -1001,
      title: 'What are you making this weekend?',
      slug: 'weekend-projects',
      excerpt:
          'I’m turning a sunny corner into a reading nook. Share your latest project.',
      lastPosterUsername: 'maya',
      postsCount: 25,
      likeCount: 8,
      pinned: true,
    ),
    Topic(
      id: -1002,
      title: 'A small discovery worth sharing',
      slug: 'small-discovery',
      excerpt:
          'The best ideas often start with a conversation. What have you learned lately?',
      lastPosterUsername: 'leo',
      postsCount: 9,
      bookmarked: true,
      unreadPosts: 2,
    ),
  ];

  @override
  Widget build(BuildContext context) => Theme(
    data: theme,
    child: Builder(
      builder: (context) => ExcludeFocus(
        child: IgnorePointer(
          child: DCard(
            key: const ValueKey('forum-theme-preview'),
            spacing: 0,
            footer: DCardFooter(
              rounded: true,
              backgroundColor: DTokens.of(context).footerBackground,
              borderColor: DTokens.of(context).footerBorder,
              child: Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  DButton(
                    variant: DButtonVariant.primary,
                    icon: const DIcon(DIcons.plus),
                    label: const Text('New topic'),
                    onPressed: () {},
                  ),
                  DButton(
                    icon: const DIcon(DIcons.bell),
                    label: const Text('Normal'),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(DSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.md,
                  children: [
                    Text(
                      'Latest topics',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    DToggleGroup<String>(
                      values: const ['latest'],
                      onChanged: (_) {},
                      items: const [
                        DToggleGroupItem(
                          value: 'latest',
                          child: Text('Latest'),
                        ),
                        DToggleGroupItem(
                          value: 'unread',
                          child: Text('Unread'),
                        ),
                        DToggleGroupItem(value: 'top', child: Text('Top')),
                      ],
                    ),
                  ],
                ),
              ),
              for (final topic in topics)
                TopicListRow(
                  key: ValueKey('theme-preview-topic-${topic.id}'),
                  topic: topic,
                  siteUrl: siteUrl,
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
