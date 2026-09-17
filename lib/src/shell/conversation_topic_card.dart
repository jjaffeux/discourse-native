part of 'topic_list_view.dart';

/// A topic surface with its conversation metadata in a separate footer.
class _ConversationTopicCard extends StatelessWidget {
  const _ConversationTopicCard({required this.row});
  final _TopicRowBody row;

  @override
  Widget build(BuildContext context) {
    final topic = row.topic;
    final shell = ShellScope.maybeRead(context);
    final settings = ShellScope.maybeIdentityOf(context)?.appSettings;
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
    final contentInsets =
        (row.contentPadding ?? const EdgeInsets.all(DSpacing.md)).resolve(
          Directionality.of(context),
        );
    Widget field(String label, String column) => _TopicCardField(
      label: label,
      column: column,
      order: order,
      ascending: ascending,
      onSort: onSort,
    );
    Widget stat(String label, String column, String value, {Key? key}) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        field(label, column),
        const SizedBox(width: DSpacing.xs),
        Text(value, style: textStyle),
      ],
    );
    final author = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topic.lastPosterUsername != null) ...[
          DAvatar(
            dimension: 22,
            decorative: true,
            child: AvatarImage(
              url: topic.lastPosterAvatarUrl,
              size: 22,
              fallback: DAvatarFallback(
                child: Text(
                  topic.lastPosterUsername!.characters.firstOrNull
                          ?.toUpperCase() ??
                      '',
                ),
              ),
            ),
          ),
          const SizedBox(width: DSpacing.sm),
        ],
        Flexible(
          child: Text(
            topic.lastPosterUsername == null
                ? ''
                : 'Last reply by ${topic.lastPosterUsername}',
            style: textStyle,
          ),
        ),
      ],
    );
    final stats = Wrap(
      spacing: DSpacing.md,
      runSpacing: DSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        stat('Replies', 'posts', '${topic.replyCount}'),
        if (row.showViews) stat('Views', 'views', '${topic.views}'),
        stat(
          'Activity',
          'activity',
          age,
          key: ValueKey('inbox-row-time-${topic.id}'),
        ),
      ],
    );
    return Padding(
      padding:
          row.outerPadding ??
          const EdgeInsets.symmetric(horizontal: topicListHorizontalPadding),
      child: Padding(
        padding: const EdgeInsets.only(bottom: DSpacing.md),
        child: LinkTarget(
          url:
              '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
          title: topic.title,
          siteUrl: row.siteUrl,
          child: Semantics(
            key: row.inbox ? ValueKey('inbox-row-${topic.id}') : null,
            container: true,
            selected: selected,
            child: DCard(
              spacing: 0,
              child: DItem(
                key: ValueKey('topic-card-${topic.id}'),
                shape: DItemShape.card,
                padding: EdgeInsets.zero,
                link: true,
                onPressed: row.onTap,
                selected: selected,
                selectionStyle: DItemSelectionStyle.outline,
                showSelectionIndicator: false,
                children: [
                  DItemContent(
                    spacing: 0,
                    alignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: contentInsets,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (row.category != null ||
                                topic.tags.isNotEmpty ||
                                row.forum != null ||
                                topic.privateMessage) ...[
                              Text.rich(
                                TextSpan(
                                  children: [
                                    for (final child in <Widget>[
                                      if (topic.privateMessage)
                                        Text(
                                          'Private conversation',
                                          style: textStyle,
                                        )
                                      else if (row.category != null)
                                        _topicRowCategory(context, row),
                                      if (!topic.privateMessage &&
                                          row.category != null &&
                                          topic.tags.isNotEmpty)
                                        const DSeparator(
                                          orientation: Axis.vertical,
                                          length: 12,
                                        ),
                                      ..._topicRowTags(context, row),
                                      if (row.forum != null)
                                        Text(
                                          row.forum!.title,
                                          style: textStyle,
                                        ),
                                    ])
                                      WidgetSpan(
                                        alignment: child is DSeparator
                                            ? PlaceholderAlignment.middle
                                            : PlaceholderAlignment.baseline,
                                        baseline: TextBaseline.alphabetic,
                                        child: Padding(
                                          padding: child is _TopicTag
                                              ? EdgeInsets.zero
                                              : const EdgeInsetsDirectional.only(
                                                  end: DSpacing.xs,
                                                ),
                                          child: child,
                                        ),
                                      ),
                                  ],
                                ),
                                // Each Native component scales its own text.
                                textScaler: TextScaler.noScaling,
                              ),
                              const SizedBox(height: DSpacing.sm),
                            ],
                            registry.decorateTopicListTitle(
                              context,
                              row.siteUrl,
                              topic,
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _TopicListTitle(row: row, card: true),
                                  if (settings?.topicListExcerpts == true &&
                                      topic.excerpt?.trim().isNotEmpty ==
                                          true) ...[
                                    const SizedBox(height: DSpacing.sm),
                                    DCardDescription(
                                      child: SiteEmojiText.plain(
                                        topic.excerpt!,
                                        siteUrl: row.siteUrl,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (assignments.isNotEmpty) ...[
                              const SizedBox(height: DSpacing.md),
                              Wrap(
                                spacing: DSpacing.xs,
                                runSpacing: DSpacing.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: assignments,
                              ),
                            ],
                            if (metadata.isNotEmpty) ...[
                              const SizedBox(height: DSpacing.sm),
                              Wrap(
                                spacing: DSpacing.sm,
                                runSpacing: DSpacing.xs,
                                children: metadata,
                              ),
                            ],
                          ],
                        ),
                      ),
                      DCardFooter(
                        child: Padding(
                          padding: contentInsets.copyWith(
                            top: DSpacing.sm,
                            bottom: DSpacing.sm,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final stacked =
                                  constraints.maxWidth <
                                  560 *
                                      MediaQuery.textScalerOf(
                                        context,
                                      ).scale(12) /
                                      12;
                              return stacked
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        author,
                                        const SizedBox(height: DSpacing.sm),
                                        stats,
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(child: author),
                                        const SizedBox(width: DSpacing.lg),
                                        stats,
                                      ],
                                    );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: DTokens.of(context).mutedForeground,
          ),
        )
      : DButton(
          size: DButtonSize.small,
          variant: DButtonVariant.inline,
          label: Text(label),
          semanticLabel:
              '$label, ${order == column ? (ascending ? 'ascending' : 'descending') : 'unsorted'}',
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
