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
                  ? tokens.titleRead
                  : topic.muted
                  ? tokens.mutedForeground
                  : tokens.foreground,
              fontWeight: read ? FontWeight.w400 : FontWeight.w700,
            );
    final match = row.match;
    if (match != null) {
      return DItemTitle(
        maxLines: null,
        child: SiteEmojiText(
          topicSearchRuns(context, match.title, match.query),
          siteUrl: row.siteUrl,
          style: titleStyle,
        ),
      );
    }
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
              child: DTooltip(
                message: context.l10n.closed,
                excludeFromSemantics: true,
                child: DIcon(
                  DIcons.lock,
                  key: ValueKey('topic-row-lock-${topic.id}'),
                  size: 11,
                  color: titleStyle?.color,
                  semanticLabel: context.l10n.closed,
                ),
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

List<SiteEmojiTextRun> topicSearchRuns(
  BuildContext context,
  String text,
  String query,
) {
  final pattern = searchWordPattern(query);
  if (pattern == null) return [SiteEmojiTextRun(text)];
  final accent = DTokens.of(context).primary;
  final runs = <SiteEmojiTextRun>[];
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      runs.add(SiteEmojiTextRun(text.substring(cursor, match.start)));
    }
    runs.add(
      SiteEmojiTextRun(
        match.group(0)!,
        style: TextStyle(
          color: accent,
          backgroundColor: accent.withValues(alpha: .18),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) runs.add(SiteEmojiTextRun(text.substring(cursor)));
  return runs;
}
