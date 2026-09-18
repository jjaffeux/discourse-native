part of 'topic_list_view.dart';

/// A full-width conversation row, shared by every topic source.
class _ConversationTopicCard extends StatelessWidget {
  const _ConversationTopicCard({required this.row});
  final _TopicRowBody row;

  @override
  Widget build(BuildContext context) {
    final topic = row.topic;
    final shell = ShellScope.maybeRead(context);
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final assignments = registry.compactTopicListMetadata(
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
    final route = shell?.topicListContent;
    final canSort =
        row.forum == null &&
        !topic.privateMessage &&
        route?.canSortTopicList == true;
    final onSort =
        row.onSort ??
        (canSort
            ? (String column) => unawaited(shell!.sortTopicList(column))
            : null);
    final order = row.onSort != null ? row.order : route?.topicListOrder;
    final ascending = row.onSort != null
        ? row.ascending
        : route?.topicListAscending ?? false;
    final selected = row.selected || KeyboardSelection.isSelectedOf(context);
    final muted = DTokens.of(context).mutedForeground;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final age = topic.bumpedAt == null ? '—' : relativeTime(topic.bumpedAt!);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    Widget field(String label, String column) => _TopicCardField(
      label: label,
      column: column,
      order: order,
      ascending: ascending,
      onSort: onSort,
    );
    final taxonomy = Text.rich(
      TextSpan(
        children: [
          for (final child in <Widget>[
            if (topic.privateMessage)
              Text('Private conversation', style: textStyle)
            else if (row.category != null)
              _topicRowCategory(context, row),
            ..._topicRowTags(context, row),
            if (row.forum != null) Text(row.forum!.title, style: textStyle),
          ])
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: DSpacing.xs),
                child: child,
              ),
            ),
        ],
      ),
      textScaler: TextScaler.noScaling,
    );
    final author = Text.rich(
      TextSpan(
        children: [
          if (topic.lastPosterUsername case final username?
              when shell?.appSettings.topicListShowLastPoster != false) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: DSpacing.xs),
                child: DAvatar(
                  dimension: 22,
                  decorative: true,
                  child: AvatarImage(
                    url: topic.lastPosterAvatarUrl,
                    size: 22,
                    fallback: DAvatarFallback(
                      child: Text(
                        username.characters.firstOrNull?.toUpperCase() ?? '',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Text('Last post by $username · ', style: textStyle),
            ),
          ],
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: field('${topic.replyCount} replies', 'posts'),
          ),
          if (row.showViews) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Text(' · ', style: textStyle),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: field('${topic.views} views', 'views'),
            ),
          ],
        ],
      ),
      textScaler: TextScaler.noScaling,
      textWidthBasis: TextWidthBasis.longestLine,
    );
    return Padding(
      padding: row.outerPadding ?? EdgeInsets.zero,
      child: LinkTarget(
        url: '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
        title: topic.title,
        siteUrl: row.siteUrl,
        child: Semantics(
          key: row.inbox ? ValueKey('inbox-row-${topic.id}') : null,
          container: true,
          selected: selected,
          child: DItem(
            key: ValueKey('topic-card-${topic.id}'),
            shape: DItemShape.fullWidth,
            padding:
                row.contentPadding ??
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            link: true,
            onPressed: row.onTap,
            selected: selected,
            selectionStyle: DItemSelectionStyle.leadingAccent,
            showSelectionIndicator: false,
            children: [
              DItemContent(
                spacing: 6,
                alignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: registry.decorateTopicListTitle(
                          context,
                          row.siteUrl,
                          topic,
                          _TopicListTitle(row: row),
                        ),
                      ),
                      const SizedBox(width: DSpacing.sm),
                      KeyedSubtree(
                        key: ValueKey('inbox-row-time-${topic.id}'),
                        child: field(age, 'activity'),
                      ),
                    ],
                  ),
                  if (topic.excerpt case final excerpt? when excerpt.isNotEmpty)
                    SiteEmojiText.plain(
                      excerpt,
                      siteUrl: row.siteUrl,
                      maxLines: largeText ? null : 2,
                      overflow: largeText
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: muted, height: 1.5),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          constraints.maxWidth <
                          540 * MediaQuery.textScalerOf(context).scale(12) / 12;
                      return stacked
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: DSpacing.xs,
                              children: [taxonomy, author],
                            )
                          : Row(
                              children: [
                                Expanded(child: taxonomy),
                                const SizedBox(width: DSpacing.sm),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * .55,
                                  ),
                                  child: author,
                                ),
                              ],
                            );
                    },
                  ),
                  if (assignments.isNotEmpty)
                    Wrap(
                      spacing: DSpacing.xs,
                      runSpacing: DSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: assignments,
                    ),
                  if (metadata.isNotEmpty)
                    Wrap(
                      spacing: DSpacing.sm,
                      runSpacing: DSpacing.xs,
                      children: metadata,
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

class _TopicCardField extends StatelessWidget {
  const _TopicCardField({
    required this.label,
    required this.column,
    required this.order,
    required this.ascending,
    required this.onSort,
  });
  final String label, column;
  final String? order;
  final bool ascending;
  final ValueChanged<String>? onSort;

  @override
  Widget build(BuildContext context) => onSort == null
      ? Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: DTokens.of(context).mutedForeground),
        )
      : DButton(
          key: ValueKey('topic-sort-$column'),
          size: DButtonSize.small,
          variant: DButtonVariant.inline,
          label: Text(label),
          semanticLabel:
              '${switch (column) {
                'posts' => 'Replies',
                'activity' => 'Activity',
                'views' => 'Views',
                _ => label,
              }}, ${order == column ? (ascending ? 'ascending' : 'descending') : 'unsorted'}',
          icon: order == column
              ? RotatedBox(
                  quarterTurns: ascending ? 2 : 0,
                  child: const DIcon(DIcons.chevronDown, size: 12),
                )
              : null,
          iconPosition: DButtonIconPosition.end,
          onPressed: () => onSort!(column),
        );
}
