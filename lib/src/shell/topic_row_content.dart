part of 'topic_list_view.dart';

class _TopicListTitle extends StatelessWidget {
  const _TopicListTitle({required this.row});
  final _TopicRowBody row;

  @override
  Widget build(BuildContext context) {
    final topic = row.topic;
    final tokens = DTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final read = topic.visited && !topic.hasUnseenActivity;
    final titleStyle =
        (row.titleStyle ??
                textTheme.titleSmall?.copyWith(
                  fontFamily: textTheme.bodyLarge?.fontFamily,
                  fontFamilyFallback: textTheme.bodyLarge?.fontFamilyFallback,
                ))
            ?.copyWith(
              color: read
                  ? Color.lerp(tokens.background, tokens.foreground, .9)
                  : tokens.foreground,
              fontWeight: read ? FontWeight.w500 : FontWeight.w700,
            );
    return DItemTitle(
      maxLines: null,
      child: TopicTitle(
        topic.displayTitle,
        siteUrl: row.siteUrl,
        keepTrailingWithLastWord: topic.showUnreadCount,
        style: titleStyle,
        leading: [
          if (topic.closed)
            Padding(
              padding: EdgeInsetsDirectional.only(
                end:
                    (titleStyle?.fontSize ?? DiscourseTypography.rowTitle) * .4,
              ),
              child: DIcon(
                DIcons.lock,
                key: ValueKey('topic-row-lock-${topic.id}'),
                size: 11,
                color: titleStyle?.color,
                semanticLabel: context.l10n.closed,
              ),
            ),
        ],
        trailing: [
          if (topic.showNewTopicDot || topic.showNewRepliesDot)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: TopicStateDot(
                label: topic.showNewTopicDot
                    ? context.l10n.newTopic
                    : context.l10n.topicHasNewReplies,
              ),
            ),
          if (topic.showUnreadCount)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: TopicUnreadBadge(
                key: ValueKey('inbox-row-unread-${topic.id}'),
                count: topic.unreadCount,
                compact: true,
              ),
            ),
        ],
      ),
    );
  }
}
