part of 'topic_list_view.dart';

const _compactItemInset = 11.0;

class _CompactTopicLayout {
  _CompactTopicLayout(
    BuildContext context,
    double width, {
    bool showCategory = true,
    bool showViews = false,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final effective = width / scale;
    category = showCategory && effective >= 660;
    activity = effective >= 300;
    avatar = effective >= 900;
    views = showViews && effective >= 480;
    var index = 0;
    widths = {
      index++: const FlexColumnWidth(),
      if (category)
        index++: FixedColumnWidth((effective * .19).clamp(140, 240) * scale),
      if (avatar) index++: FixedColumnWidth(138 * scale),
      if (activity) index++: FixedColumnWidth(92 * scale),
      if (views) index++: FixedColumnWidth(92 * scale),
      if (activity) index++: FixedColumnWidth(100 * scale),
    };
  }
  late final bool category, activity, avatar, views;
  late final Map<int, TableColumnWidth> widths;
}

/// Aligns with the virtualized rows. Only columns supported by the source have actions.
class TopicListTableHeader extends StatelessWidget {
  const TopicListTableHeader({
    super.key,
    this.showCategory = true,
    this.showViews = false,
    this.sortCategory = false,
    this.order,
    this.ascending = false,
    this.onSort,
    this.compact,
  });
  final bool showCategory, showViews, ascending;
  final bool sortCategory;
  final String? order;
  final ValueChanged<String>? onSort;
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    if (TopicListLayout.forceCardOf(context)) return const SizedBox.shrink();
    final settings = ShellScope.maybeIdentityOf(context)?.appSettings;
    Widget header() =>
        (compact ?? settings?.topicListMode != TopicListDisplayMode.card)
        ? _buildHeader(context)
        : const SizedBox.shrink();
    return settings == null || compact != null
        ? header()
        : ListenableBuilder(
            listenable: settings,
            builder: (context, _) => header(),
          );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: topicListHorizontalPadding + _compactItemInset,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final layout = _CompactTopicLayout(
          context,
          constraints.maxWidth,
          showCategory: showCategory,
          showViews: showViews,
        );
        final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: DTokens.of(context).mutedForeground,
        );
        DTableHead heading(String text, {bool end = false, String? sort}) =>
            DTableHead(
              padding: EdgeInsetsDirectional.only(end: end ? 0 : 8),
              alignment: end
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              textStyle: style,
              child: sort != null && onSort != null
                  ? DButton(
                      key: ValueKey('topic-sort-$sort'),
                      size: DButtonSize.small,
                      variant: DButtonVariant.transparentBackground,
                      semanticLabel:
                          '$text, ${order == sort
                              ? ascending
                                    ? 'ascending'
                                    : 'descending'
                              : 'unsorted'}',
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (order == sort) ...[
                            const SizedBox(width: 4),
                            RotatedBox(
                              quarterTurns: ascending ? 2 : 0,
                              child: const DIcon(DIcons.chevronDown, size: 12),
                            ),
                          ],
                        ],
                      ),
                      onPressed: () => onSort!(sort),
                    )
                  : Text(text),
            );
        return DTable(
          key: const ValueKey('compact-topic-list-header'),
          borderColor: Colors.transparent,
          columnWidths: layout.widths,
          header: DTableHeader(
            rows: [
              DTableRow(
                highlightOnHover: false,
                cells: [
                  heading('Topic'),
                  if (layout.category)
                    heading('Category', sort: sortCategory ? 'category' : null),
                  if (layout.avatar) heading('Last reply'),
                  if (layout.activity)
                    heading('Replies', end: true, sort: 'posts'),
                  if (layout.views) heading('Views', end: true, sort: 'views'),
                  if (layout.activity)
                    heading('Activity', end: true, sort: 'activity'),
                ],
              ),
            ],
          ),
          body: const DTableBody(rows: []),
        );
      },
    ),
  );
}

class _CompactTopicRow extends StatelessWidget {
  const _CompactTopicRow({required this.row});
  final _TopicRowBody row;

  @override
  Widget build(BuildContext context) {
    final topic = row.topic;
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final inlineMetadata = registry.compactTopicListMetadata(
      context,
      row.siteUrl,
      topic,
      ({String? property}) {
        row.onTap();
        if (property != null) {
          ShellScope.maybeRead(context)?.requestTopicProperty(
            siteUrl: row.siteUrl,
            topicId: topic.id,
            label: property,
          );
        }
      },
    );
    final metadata = registry.topicListMetadata(
      context,
      row.siteUrl,
      topic,
      compact: true,
    );
    return Padding(
      padding:
          row.outerPadding ??
          const EdgeInsets.symmetric(horizontal: topicListHorizontalPadding),
      child: LinkTarget(
        url: '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
        title: topic.title,
        siteUrl: row.siteUrl,
        child: Semantics(
          key: row.inbox ? ValueKey('inbox-row-${topic.id}') : null,
          container: true,
          selected: row.selected || KeyboardSelection.isSelectedOf(context),
          child: DItem(
            key: ValueKey('topic-compact-${topic.id}'),
            size: DItemSize.xs,
            link: true,
            onPressed: row.onTap,
            selected: row.selected || KeyboardSelection.isSelectedOf(context),
            selectionStyle: DItemSelectionStyle.outline,
            showSelectionIndicator: false,
            children: [
              DItemContent(
                alignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: DSpacing.xs),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final layout = _CompactTopicLayout(
                          context,
                          constraints.maxWidth,
                          showCategory: row.showCategoryColumn,
                          showViews: row.showViews,
                        );
                        final muted = DTokens.of(context).mutedForeground;
                        final style = Theme.of(context).textTheme.labelSmall
                            ?.copyWith(
                              color: muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            );
                        DTableCell cell(Widget child, {bool end = false}) =>
                            DTableCell(
                              padding: EdgeInsetsDirectional.only(
                                end: end ? 0 : 8,
                              ),
                              softWrap: true,
                              textStyle: style,
                              alignment: end
                                  ? AlignmentDirectional.centerEnd
                                  : AlignmentDirectional.centerStart,
                              child: child,
                            );
                        final age = topic.bumpedAt == null
                            ? '—'
                            : relativeTime(topic.bumpedAt!);
                        final title = Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TopicListTitle(row: row),
                            if (row.forum != null ||
                                (!layout.category && row.category != null) ||
                                topic.tags.isNotEmpty ||
                                inlineMetadata.isNotEmpty ||
                                (!layout.avatar &&
                                    topic.lastPosterUsername != null)) ...[
                              const SizedBox(height: 4),
                              _topicRowMetadata(
                                context,
                                row,
                                category: !layout.category,
                                lastPoster: !layout.avatar,
                                inlineMetadata: inlineMetadata,
                              ),
                            ],
                            if (!layout.activity)
                              Text(
                                '${topic.replyCount} replies · $age',
                                key: ValueKey('inbox-row-time-${topic.id}'),
                                style: style,
                              ),
                            if (metadata.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: metadata,
                                ),
                              ),
                          ],
                        );
                        return DTable(
                          columnWidths: layout.widths,
                          body: DTableBody(
                            rows: [
                              DTableRow(
                                highlightOnHover: false,
                                cells: [
                                  cell(
                                    registry.decorateTopicListTitle(
                                      context,
                                      row.siteUrl,
                                      topic,
                                      title,
                                    ),
                                  ),
                                  if (layout.category)
                                    cell(
                                      row.category == null
                                          ? const Text('—')
                                          : _topicRowCategory(context, row),
                                    ),
                                  if (layout.avatar)
                                    cell(
                                      Row(
                                        children: [
                                          if (topic.lastPosterUsername !=
                                              null) ...[
                                            DAvatar(
                                              dimension: 20,
                                              decorative: true,
                                              child: AvatarImage(
                                                url: topic.lastPosterAvatarUrl,
                                                size: 20,
                                                fallback: const DAvatarFallback(
                                                  child: DIcon(
                                                    DIcons.user,
                                                    size: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Flexible(
                                            child: Text(
                                              topic.lastPosterUsername ?? '—',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (layout.activity)
                                    cell(
                                      Text(
                                        '${topic.replyCount}',
                                        semanticsLabel:
                                            '${topic.replyCount} replies',
                                      ),
                                      end: true,
                                    ),
                                  if (layout.views)
                                    cell(
                                      Text(
                                        '${topic.views}',
                                        semanticsLabel: '${topic.views} views',
                                      ),
                                      end: true,
                                    ),
                                  if (layout.activity)
                                    cell(
                                      Text(
                                        age,
                                        key: ValueKey(
                                          'inbox-row-time-${topic.id}',
                                        ),
                                      ),
                                      end: true,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _topicRowCategory(BuildContext context, _TopicRowBody row) =>
    _CategoryBreadcrumb(
      parent: row.parentCategory,
      category: row.category!,
      siteUrl: row.siteUrl,
      onOpen: (category) => ShellScope.maybeRead(
        context,
      )?.openCategory(category, siteUrl: row.siteUrl),
    );

Widget _topicRowMetadata(
  BuildContext context,
  _TopicRowBody row, {
  required bool category,
  required bool lastPoster,
  required List<Widget> inlineMetadata,
}) {
  return Wrap(
    spacing: DSpacing.xs,
    runSpacing: DSpacing.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (row.forum != null) Text(row.forum!.title),
      if (category && row.category != null) _topicRowCategory(context, row),
      ..._topicRowTags(context, row),
      ...inlineMetadata,
      if (lastPoster)
        if (row.topic.lastPosterUsername case final username?)
          Text(
            username,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: DTokens.of(context).mutedForeground,
            ),
          ),
    ],
  );
}

List<Widget> _topicRowTags(BuildContext context, _TopicRowBody row) {
  final controller = ShellScope.maybeRead(context);
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
  const _TopicListTitle({required this.row, this.card = false});
  final _TopicRowBody row;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = row.topic;
    final large =
        ShellScope.maybeIdentityOf(context)?.appSettings.topicListLargerText ==
        true;
    final style =
        row.titleStyle ??
        (large
            ? (card ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
            : (card
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.titleSmall));
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return DItemTitle(
      maxLines: largeText ? null : 2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          // AppTheme maps Discourse tertiary to primary, highlight to tertiary.
          for (final (shown, icon, label, color) in [
            (topic.closed, DIcons.lock, 'Closed', null),
            (
              topic.pinned,
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
              maxLines: largeText ? null : 2,
              overflow: largeText ? TextOverflow.clip : TextOverflow.ellipsis,
              style: style?.copyWith(
                color: topicListTitleColor(theme, visited: topic.visited),
                fontWeight: FontWeight.w400,
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
