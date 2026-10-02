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
    return DItemTitle(
      maxLines: null,
      child: TopicTitle(
        topic.title,
        siteUrl: row.siteUrl,
        keepTrailingWithLastWord: topic.showUnreadCount,
        style:
            (row.titleStyle ??
                    textTheme.titleSmall?.copyWith(
                      fontFamily: textTheme.bodyLarge?.fontFamily,
                      fontFamilyFallback:
                          textTheme.bodyLarge?.fontFamilyFallback,
                    ))
                ?.copyWith(
                  color: read
                      ? Color.lerp(tokens.background, tokens.foreground, .9)
                      : tokens.foreground,
                  fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                ),
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
