part of 'topic_list_view.dart';

Widget _topicRowCategory(BuildContext context, _TopicRowBody row) =>
    _CategoryBreadcrumb(
      parent: row.parentCategory,
      category: row.category!,
      siteUrl: row.siteUrl,
      onOpen: (category) => ShellScope.maybeRead(
        context,
      )?.openCategory(category, siteUrl: row.siteUrl),
    );

List<Widget> _topicRowTags(BuildContext context, _TopicRowBody row) {
  final controller = ShellScope.maybeRead(context);
  if (controller?.appSettings.topicListShowTags == false) return [];
  return [
    for (final tag in row.topic.tags.take(2))
      _TopicTag(
        tag: tag,
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
    if (row.topic.tags.length > 2)
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
    final large =
        ShellScope.maybeIdentityOf(context)?.appSettings.topicListLargerText ==
        true;
    final style =
        row.titleStyle ??
        (large ? theme.textTheme.titleMedium : theme.textTheme.titleSmall);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return DItemTitle(
      maxLines: largeText || mobile ? null : 2,
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
            if (shown)
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
              maxLines: largeText || mobile ? null : 2,
              overflow: largeText ? TextOverflow.clip : TextOverflow.ellipsis,
              style: style?.copyWith(
                color: topicListTitleColor(
                  theme,
                  visited: topic.visited && !topic.hasUnseenActivity,
                ),
                fontWeight: topic.visited && !topic.hasUnseenActivity
                    ? FontWeight.w400
                    : FontWeight.w600,
              ),
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
