part of 'topic_list_view.dart';

Widget _topicRowCategory(
  BuildContext context,
  _TopicRowBody row, {
  bool compact = false,
}) => _CategoryBreadcrumb(
  parent: row.parentCategory,
  compact: compact,
  category: row.category!,
  siteUrl: row.siteUrl,
  onOpen: (category) => ShellScope.maybeRead(
    context,
  )?.openCategory(category, siteUrl: row.siteUrl),
);

List<Widget> _topicRowTags(
  BuildContext context,
  _TopicRowBody row, {
  bool compact = false,
}) {
  const maxVisibleTags = 5;
  final controller = ShellScope.maybeRead(context);
  return [
    for (final tag in row.topic.tags.take(maxVisibleTags))
      _TopicTag(
        tag: tag,
        compact: compact,
        onTap: () => controller?.openTopicTag(
          tag,
          siteUrl: row.siteUrl,
          privateMessage: row.topic.privateMessage,
        ),
        onMiddleClick: () async => controller?.openTopicTag(
          tag,
          siteUrl: row.siteUrl,
          privateMessage: row.topic.privateMessage,
          newTab: true,
        ),
      ),
    if (row.topic.tags.length > maxVisibleTags)
      _TopicTagOverflow(
        tags: row.topic.tags.skip(maxVisibleTags).toList(),
        compact: compact,
      ),
  ];
}

class _TopicListTitle extends StatelessWidget {
  const _TopicListTitle({required this.row, this.mobile = false});
  final bool mobile;
  final _TopicRowBody row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = row.topic;
    final style = row.titleStyle ?? theme.textTheme.titleSmall;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final tokens = DTokens.of(context);
    final statusIcons = [
      for (final (shown, icon, label) in [
        (topic.pinned, DIcons.thumbtack, context.l10n.pinned),
        (topic.closed, DIcons.lock, context.l10n.closed),
        (topic.bookmarked, DIcons.bookmark, context.l10n.bookmarked),
      ])
        if (shown)
          DIcon(
            icon,
            size: 11,
            color: tokens.mutedForeground,
            semanticLabel: label,
          ),
    ];
    return DItemTitle(
      maxLines: mobile || largeText ? null : 2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          // AppTheme maps Discourse tertiary to primary, highlight to tertiary.
          for (final (shown, icon, label, color) in [
            (topic.closed, DIcons.lock, context.l10n.closed, null),
            (
              topic.pinned && !mobile,
              DIcons.thumbtack,
              context.l10n.pinned,
              theme.colorScheme.tertiary,
            ),
            (
              topic.bookmarked,
              DIcons.bookmark,
              context.l10n.bookmarked,
              theme.colorScheme.primary,
            ),
          ])
            if (shown && !mobile)
              SizedBox(
                height:
                    MediaQuery.textScalerOf(
                      context,
                    ).scale(style?.fontSize ?? DiscourseTypography.sm) *
                    (style?.height ?? 1.5),
                child: Center(
                  child: DIcon(
                    icon,
                    size: 14,
                    color: color,
                    semanticLabel: label,
                  ),
                ),
              ),
          Flexible(
            child: TopicTitle(
              topic.title,
              siteUrl: row.siteUrl,
              maxLines: mobile || largeText ? null : 2,
              overflow: mobile || largeText
                  ? TextOverflow.clip
                  : TextOverflow.ellipsis,
              style: style?.copyWith(
                color: mobile
                    ? (topic.visited && !topic.hasUnseenActivity
                          ? Color.lerp(tokens.background, tokens.foreground, .9)
                          : tokens.foreground)
                    : topicListTitleColor(
                        theme,
                        visited: topic.visited && !topic.hasUnseenActivity,
                      ),
                fontWeight: topic.visited && !topic.hasUnseenActivity
                    ? FontWeight.w500
                    : FontWeight.w700,
              ),
              leading: [
                if (mobile && statusIcons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 3,
                      children: statusIcons,
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
                      compact: mobile,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
