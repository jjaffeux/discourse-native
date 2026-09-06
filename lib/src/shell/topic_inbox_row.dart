import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'topic_list_indicators.dart';
import 'topic_title.dart';

/// The narrow Inbox keeps activity separate from the title and taxonomy.
class TopicInboxRow extends StatelessWidget {
  const TopicInboxRow({
    super.key,
    required this.topic,
    required this.siteUrl,
    required this.onTap,
    this.selected = false,
    this.recommendation = false,
  });

  final Topic topic;
  final String siteUrl;
  final VoidCallback onTap;
  final bool selected;
  final bool recommendation;

  @override
  Widget build(BuildContext context) => ShellSelector<TopicCategory?>(
    select: (shell) => shell.categoryFor(topic.categoryId, siteUrl: siteUrl),
    builder: (context, category, _) {
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurfaceVariant;
      final metadata =
          (PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty)
              .topicListMetadata(context, siteUrl, topic);
      final smallStyle = theme.textTheme.labelSmall?.copyWith(
        fontSize: DiscourseTypography.fontDown2,
        color: muted,
      );
      final metadataStyle = smallStyle?.copyWith(
        fontSize: DiscourseTypography.fontDown1,
      );
      final titleStyle = theme.textTheme.titleSmall?.copyWith(
        fontSize: DiscourseTypography.base,
        height: 1.45,
        fontWeight: topic.visited
            ? FontWeight.w400
            : topic.hasUnseenActivity
            ? FontWeight.w600
            : FontWeight.w500,
        color: topicListTitleColor(theme, visited: topic.visited),
      );
      final titleLineHeight =
          MediaQuery.textScalerOf(context).scale(DiscourseTypography.base) *
          1.45;
      final age = topic.bumpedAt == null ? null : relativeTime(topic.bumpedAt!);
      final preview =
          topic.excerpt ??
          (topic.lastPosterUsername == null
              ? null
              : 'Last post by @${topic.lastPosterUsername}');
      Widget replies() => Semantics(
        key: ValueKey('inbox-row-replies-${topic.id}'),
        label:
            '${topic.replyCount} ${topic.replyCount == 1 ? 'reply' : 'replies'}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(DIcons.comment, size: 14, color: muted),
            const SizedBox(width: 4),
            Text('${topic.replyCount}', style: smallStyle),
          ],
        ),
      );
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: recommendation ? 0 : 8),
        child: LinkTarget(
          url:
              '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
          title: topic.title,
          siteUrl: siteUrl,
          child: Material(
            key: ValueKey('inbox-row-${topic.id}'),
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: .12)
                : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(selected ? 7 : 0),
              side: selected
                  ? BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: .4),
                    )
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              selected: selected,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    recommendation ? 0 : 16,
                    12,
                    recommendation ? 0 : 10,
                    12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (topic.showNewTopicDot ||
                                    topic.showNewRepliesDot)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top:
                                          (titleLineHeight - 8).clamp(
                                            0,
                                            double.infinity,
                                          ) /
                                          2,
                                      right: 6,
                                    ),
                                    child: TopicStateDot(
                                      key: ValueKey(
                                        topic.showNewTopicDot
                                            ? 'new-topic-dot'
                                            : 'new-replies-dot',
                                      ),
                                      label: topic.showNewTopicDot
                                          ? 'New topic'
                                          : 'Topic has new replies',
                                    ),
                                  ),
                                if (topic.closed ||
                                    topic.pinned ||
                                    topic.bookmarked)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 4,
                                      right: 5,
                                    ),
                                    child: DIcon(
                                      topic.closed
                                          ? DIcons.lock
                                          : topic.pinned
                                          ? DIcons.thumbtack
                                          : DIcons.bookmark,
                                      size: 14,
                                      color: muted,
                                    ),
                                  ),
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: TopicTitle(
                                          topic.title,
                                          siteUrl: siteUrl,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: titleStyle,
                                        ),
                                      ),
                                      if (topic.showUnreadCount)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                            top: 2,
                                          ),
                                          child: TopicUnreadBadge(
                                            key: ValueKey(
                                              'inbox-row-unread-${topic.id}',
                                            ),
                                            count: topic.unreadCount,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (!recommendation && age != null) ...[
                                  const SizedBox(width: 10),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      age,
                                      key: ValueKey(
                                        'inbox-row-time-${topic.id}',
                                      ),
                                      style: smallStyle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (category != null || topic.tags.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (category != null) ...[
                                    CategoryIcon(
                                      category: category,
                                      siteUrl: siteUrl,
                                      size: 13,
                                      squareSize: 8,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        category.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: metadataStyle,
                                      ),
                                    ),
                                  ],
                                  for (final tag in topic.tags.take(2)) ...[
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme.shell.hover,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                        child: Text(
                                          tag.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: metadataStyle,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (topic.tags.length > 2) ...[
                                    const SizedBox(width: 5),
                                    Tooltip(
                                      message: topic.tags
                                          .skip(2)
                                          .map((tag) => '# ${tag.name}')
                                          .join(', '),
                                      child: Text(
                                        '+${topic.tags.length - 2}',
                                        style: metadataStyle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            if (!recommendation) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (metadata.isNotEmpty)
                                    Expanded(
                                      child: Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: metadata,
                                      ),
                                    )
                                  else ...[
                                    if (topic.lastPosterUsername
                                        case final username?
                                        when topic.excerpt == null) ...[
                                      Tooltip(
                                        message: '@$username',
                                        child: CircleAvatar(
                                          radius: 10,
                                          backgroundColor: theme.shell.hover,
                                          foregroundColor: muted,
                                          child: Text(
                                            username.isEmpty
                                                ? '?'
                                                : username
                                                      .substring(0, 1)
                                                      .toUpperCase(),
                                            style: smallStyle,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                    ] else if (preview == null &&
                                        topic.posterAvatars.isNotEmpty) ...[
                                      for (final avatar
                                          in topic.posterAvatars.take(3))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 2,
                                          ),
                                          child: ClipOval(
                                            child: AvatarImage(
                                              url: avatar,
                                              size: 20,
                                              fallback: const SizedBox.square(
                                                dimension: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 3),
                                    ],
                                    Expanded(
                                      child: Text(
                                        preview ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: metadataStyle,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  replies(),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (recommendation) ...[
                        const SizedBox(width: 16),
                        replies(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
