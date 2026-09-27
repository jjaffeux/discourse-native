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
  final controller = ShellScope.maybeRead(context);
  return [
    for (final tag in compact ? row.topic.tags : row.topic.tags.take(2))
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
    if (!compact && row.topic.tags.length > 2)
      _TopicTagOverflow(tags: row.topic.tags.skip(2).toList()),
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
        (topic.pinned, DIcons.thumbtack, 'Pinned'),
        (topic.closed, DIcons.lock, 'Closed'),
        (topic.bookmarked, DIcons.bookmark, 'Bookmarked'),
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
            (topic.closed, DIcons.lock, 'Closed', null),
            (
              topic.pinned && !mobile,
              DIcons.thumbtack,
              'Pinned',
              theme.colorScheme.tertiary,
            ),
            (
              topic.bookmarked,
              DIcons.bookmark,
              'Bookmarked',
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
                          ? 'New topic'
                          : 'Topic has new replies',
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
