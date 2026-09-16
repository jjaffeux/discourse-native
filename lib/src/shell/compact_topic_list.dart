part of 'topic_list_view.dart';

/// The inset of an xs DItem (10px padding + 1px border), used to align the
/// passive table header with the tables inside the interactive list items.
const _compactItemInset = 11.0;

class _CompactTopicLayout {
  _CompactTopicLayout(
    BuildContext context,
    double width,
    List<TopicListColumn> columns,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final effective = width / scale;
    category = effective >= 560;
    activity = effective >= 300;
    avatar = category;
    pluginColumns = effective >= 850 ? columns : const [];
    widths = {
      0: const FlexColumnWidth(),
      if (category) 1: FixedColumnWidth(136 * scale),
      for (var i = 0; i < pluginColumns.length; i++)
        (category ? 2 : 1) + i: FixedColumnWidth(
          pluginColumns[i].width * scale,
        ),
      if (activity) ...{
        (category ? 2 : 1) + pluginColumns.length: FixedColumnWidth(
          (category ? 66 : 52) * scale,
        ),
        (category ? 3 : 2) + pluginColumns.length: FixedColumnWidth(
          (avatar ? 96 : 52) * scale,
        ),
      },
    };
  }

  late final bool category;
  late final bool activity;
  late final bool avatar;
  late final List<TopicListColumn> pluginColumns;
  late final Map<int, TableColumnWidth> widths;
}

class _CompactTopicListHeader extends StatelessWidget {
  const _CompactTopicListHeader({required this.columns});
  final List<TopicListColumn> columns;

  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    widthLimit: topicListContentWidth,
    padding: const EdgeInsets.symmetric(
      horizontal: topicListHorizontalPadding + _compactItemInset,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final layout = _CompactTopicLayout(
          context,
          constraints.maxWidth,
          columns,
        );
        final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: DTokens.of(context).mutedForeground,
        );
        DTableHead heading(String text, {bool end = false}) => DTableHead(
          padding: EdgeInsetsDirectional.only(end: end ? 0 : DSpacing.sm),
          alignment: end
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          textStyle: style,
          child: Text(text),
        );
        return DTable(
          key: const ValueKey('compact-topic-list-header'),
          columnWidths: layout.widths,
          header: DTableHeader(
            rows: [
              DTableRow(
                cells: [
                  heading('Topic'),
                  if (layout.category) heading('Category'),
                  for (final column in layout.pluginColumns)
                    heading(column.label),
                  if (layout.activity) ...[
                    heading('Replies', end: true),
                    heading('Activity', end: true),
                  ],
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
    final columns = registry.topicListColumns(row.siteUrl);
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
            onPressed: row.onTap,
            link: true,
            selected: row.selected || KeyboardSelection.isSelectedOf(context),
            selectionStyle: DItemSelectionStyle.outline,
            showSelectionIndicator: false,
            footer: metadata.isEmpty
                ? null
                : DItemFooter(
                    child: Wrap(
                      spacing: DSpacing.sm,
                      runSpacing: DSpacing.xs,
                      children: metadata,
                    ),
                  ),
            children: [
              DItemContent(
                alignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = _CompactTopicLayout(
                        context,
                        constraints.maxWidth,
                        row.columns ?? const [],
                      );
                      final style = Theme.of(context).textTheme.labelSmall;
                      final muted = DTokens.of(context).mutedForeground;
                      DTableCell cell(Widget child, {bool end = false}) =>
                          DTableCell(
                            padding: EdgeInsetsDirectional.only(
                              end: end ? 0 : DSpacing.sm,
                            ),
                            alignment: end
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            softWrap: true,
                            textStyle: style,
                            child: child,
                          );
                      Widget empty(String label) => Semantics(
                        label: label,
                        child: ExcludeSemantics(
                          child: Text('—', style: TextStyle(color: muted)),
                        ),
                      );
                      final age = topic.bumpedAt == null
                          ? null
                          : relativeTime(topic.bumpedAt!);
                      return DTable(
                        columnWidths: layout.widths,
                        body: DTableBody(
                          rows: [
                            DTableRow(
                              cells: [
                                cell(
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      registry.decorateTopicListTitle(
                                        context,
                                        row.siteUrl,
                                        topic,
                                        _CompactTopicTitle(row: row),
                                      ),
                                      if (row.forum != null ||
                                          (!layout.category &&
                                              row.category != null) ||
                                          topic.tags.isNotEmpty) ...[
                                        const SizedBox(height: DSpacing.xs),
                                        _taxonomy(
                                          context,
                                          category: !layout.category,
                                        ),
                                      ],
                                      for (final column in columns.where(
                                        (column) => !layout.pluginColumns.any(
                                          (shown) => shown.id == column.id,
                                        ),
                                      ))
                                        if (column.builder(
                                              context,
                                              topic,
                                              row.onTap,
                                            )
                                            case final child?)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: DSpacing.xs,
                                            ),
                                            child: Wrap(
                                              spacing: DSpacing.xs,
                                              runSpacing: DSpacing.xs,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  '${column.label} ',
                                                  style: TextStyle(
                                                    color: muted,
                                                  ),
                                                ),
                                                child,
                                              ],
                                            ),
                                          ),
                                      if (!layout.activity)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: DSpacing.xs,
                                          ),
                                          child: Text(
                                            '${topic.replyCount} replies${age == null ? '' : ' · $age'}',
                                            style: TextStyle(color: muted),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (layout.category)
                                  cell(
                                    row.category == null
                                        ? empty('No category')
                                        : _category(context),
                                  ),
                                for (final column in layout.pluginColumns)
                                  cell(
                                    column.builder(context, topic, row.onTap) ??
                                        empty('${column.label}: none'),
                                  ),
                                if (layout.activity) ...[
                                  cell(
                                    Semantics(
                                      label: '${topic.replyCount} replies',
                                      child: ExcludeSemantics(
                                        child: Text(
                                          '${topic.replyCount}',
                                          style: TextStyle(
                                            color: muted,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    end: true,
                                  ),
                                  cell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (layout.avatar &&
                                            topic.lastPosterUsername !=
                                                null) ...[
                                          DTooltip(
                                            message:
                                                'Last post by ${topic.lastPosterUsername}',
                                            child: DAvatar(
                                              dimension: 20,
                                              semanticLabel:
                                                  'Last post by ${topic.lastPosterUsername}',
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
                                          ),
                                          const SizedBox(width: DSpacing.sm),
                                        ],
                                        Flexible(
                                          child: Text(
                                            age ?? '—',
                                            style: TextStyle(color: muted),
                                          ),
                                        ),
                                      ],
                                    ),
                                    end: true,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _category(BuildContext context) => _CategoryBreadcrumb(
    parent: row.parentCategory,
    category: row.category!,
    siteUrl: row.siteUrl,
    onOpen: (category) => ShellScope.maybeRead(
      context,
    )?.openCategory(category, siteUrl: row.siteUrl),
  );

  Widget _taxonomy(BuildContext context, {required bool category}) {
    final controller = ShellScope.maybeRead(context);
    return Wrap(
      spacing: DSpacing.xs,
      runSpacing: DSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (row.forum case final forum?) Text(forum.title),
        if (category && row.category != null) _category(context),
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
      ],
    );
  }
}

class _CompactTopicTitle extends StatelessWidget {
  const _CompactTopicTitle({required this.row});
  final _TopicRowBody row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = row.topic;
    final style = row.titleStyle ?? theme.textTheme.titleSmall;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return DItemTitle(
      maxLines: largeText ? null : 2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          for (final (shown, icon, label) in [
            (topic.closed, DIcons.lock, 'Closed'),
            (topic.pinned, DIcons.thumbtack, 'Pinned'),
            (topic.bookmarked, DIcons.bookmark, 'Bookmarked'),
          ])
            if (shown)
              SizedBox(
                height:
                    MediaQuery.textScalerOf(
                      context,
                    ).scale(style?.fontSize ?? 14) *
                    (style?.height ?? 1.5),
                child: Center(
                  child: DIcon(icon, size: 14, semanticLabel: label),
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
                fontWeight: topic.visited ? FontWeight.w400 : FontWeight.w600,
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
