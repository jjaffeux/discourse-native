part of 'topic_list_view.dart';

const _topicTailGap = 14.0;
const _topicTagGap = 5.0;

TextStyle _topicMetadataStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: Color.lerp(
        DTokens.of(context).background,
        DTokens.of(context).foreground,
        .4,
      ),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

String _topicCompactCount(int count) => count >= 10000
    ? '${(count / 1000).round()}k'
    : count >= 1000
    ? '${(count / 1000).toStringAsFixed(1)}k'
    : '$count';

/// Measure the same styled/scaled text that the Native links display.
double _topicTextWidth(BuildContext context, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _topicMetadataStyle(context)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _TopicCardFooter extends StatelessWidget {
  const _TopicCardFooter({required this.row, required this.allowSort});
  final _TopicRowBody row;
  final bool allowSort;

  @override
  Widget build(BuildContext context) => switch (row.topic.bumpedAt) {
    final bumpedAt? => RelativeTimeBuilder(
      when: bumpedAt,
      builder: (context, age) => _build(context, age),
    ),
    null => _build(context, '—'),
  };

  Widget _build(BuildContext context, String age) {
    final topic = row.topic;
    final posters = topic.posters.isNotEmpty
        ? topic.posters
        : [
            if (topic.lastPosterUsername != null)
              TopicPoster(
                userId: -1,
                username: topic.lastPosterUsername,
                avatarUrl: topic.lastPosterAvatarUrl,
                latest: true,
                single: true,
              ),
          ];
    final shown = posters.take(Topic.maximumPosterAvatars).toList();
    final avatarsWidth = shown.isEmpty ? 0.0 : 20 + (shown.length - 1) * 13.0;
    final avatars = DAvatarGroup(
      key: ValueKey('topic-card-posters-${topic.id}'),
      overlap: 7,
      ringWidth: 1.5,
      dimension: 20,
      children: [
        for (final poster in shown)
          DTooltip(
            message: [
              poster.username,
              poster.description,
            ].whereType<String>().join(' — '),
            excludeFromSemantics: true,
            child: DAvatar(
              dimension: 20,
              border: false,
              ring: poster.latest && !poster.single && shown.length > 1,
              ringStyle: DAvatarRingStyle.outside,
              semanticLabel: [
                poster.username,
                poster.description,
              ].whereType<String>().join(' — '),
              child: AvatarImage(
                url: poster.avatarUrl,
                size: 20,
                fallback: DAvatarFallback(
                  child: Text(
                    poster.username?.characters.firstOrNull?.toUpperCase() ??
                        '',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final time = KeyedSubtree(
      key: ValueKey('inbox-row-time-${topic.id}'),
      child: _TopicCardSortValue(
        row: row,
        allowSort: allowSort,
        column: 'activity',
        label: age,
        child: Text(age, style: _topicMetadataStyle(context)),
      ),
    );
    final taxonomy = _TopicCardTaxonomy(row: row, allowSort: allowSort);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.maxWidth -
            avatarsWidth -
            _topicTextWidth(context, age) -
            (shown.isEmpty ? 14 : 28);
        // At accessibility sizes the entire metadata strip gets its own line.
        // Keep every link/count available instead of squeezing it to zero.
        final wrap =
            room < _topicCountsWidth(context, row, allowSort: allowSort) + 45;
        final footer = wrap
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (shown.isNotEmpty) avatars,
                      const Spacer(),
                      time,
                    ],
                  ),
                  const SizedBox(height: 5),
                  taxonomy,
                ],
              )
            : Row(
                children: [
                  if (shown.isNotEmpty) ...[
                    avatars,
                    const SizedBox(width: _topicTailGap),
                  ],
                  Expanded(child: taxonomy),
                  const SizedBox(width: _topicTailGap),
                  time,
                ],
              );
        if (row.forum case final forum?) {
          final site = Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              DAvatar(
                dimension: 15,
                decorative: true,
                borderRadius: BorderRadius.circular(DRadius.code),
                child: AvatarImage(
                  url: forum.iconUrl,
                  size: 15,
                  fallback: DAvatarFallback(
                    child: Text(forum.title.characters.firstOrNull ?? ''),
                  ),
                ),
              ),
              Flexible(
                child: Text(forum.title, style: _topicMetadataStyle(context)),
              ),
            ],
          );
          final siteWidth = 20 + _topicTextWidth(context, forum.title);
          if (!wrap &&
              room - siteWidth - _topicTailGap >=
                  _topicCountsWidth(context, row, allowSort: allowSort) + 82) {
            return Row(
              spacing: _topicTailGap,
              children: [
                site,
                Expanded(child: footer),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 5,
            children: [site, footer],
          );
        }
        return footer;
      },
    );
  }
}

List<(int, DIconData, CountNoun, String)> _topicCounts(_TopicRowBody row) => [
  (row.topic.replyCount, DIcons.comment, CountNoun.reply, 'posts'),
  (row.topic.likeCount, DIcons.heart, CountNoun.like, 'likes'),
  if (row.showViews) (row.topic.views, DIcons.farEye, CountNoun.view, 'views'),
];

double _topicCountsWidth(
  BuildContext context,
  _TopicRowBody row, {
  required bool allowSort,
}) {
  final order = allowSort
      ? (row.onSort != null
            ? row.order
            : ShellScope.maybeRead(context)?.topicListContent?.topicListOrder)
      : null;
  return _topicCounts(row).fold(
    0.0,
    (width, count) =>
        width +
        11 +
        4 +
        _topicTextWidth(context, _topicCompactCount(count.$1)) +
        _topicTailGap +
        (order == count.$4 ? 18 : 0),
  );
}

class _TopicCardTaxonomy extends StatefulWidget {
  const _TopicCardTaxonomy({required this.row, required this.allowSort});
  final _TopicRowBody row;
  final bool allowSort;
  @override
  State<_TopicCardTaxonomy> createState() => _TopicCardTaxonomyState();
}

class _TopicCardTaxonomyState extends State<_TopicCardTaxonomy> {
  bool _allTags = false;
  _TopicRowBody get row => widget.row;

  @override
  void didUpdateWidget(_TopicCardTaxonomy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.topic.id != row.topic.id ||
        oldWidget.row.siteUrl != row.siteUrl) {
      _allTags = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final topic = row.topic;
      final path = <TopicCategory>[
        if (!topic.privateMessage) ...[
          if (row.showCategoryBreadcrumb) ...row.categoryAncestors,
          if (row.category != null) row.category!,
        ],
      ];
      double measure(String text) => _topicTextWidth(context, text);
      final layout = TopicCardTaxonomyLayout.calculate(
        width: constraints.maxWidth,
        countsWidth: _topicCountsWidth(
          context,
          row,
          allowSort: widget.allowSort,
        ),
        categories: path.map((c) => c.name).toList(),
        tags: topic.tags.map((t) => t.name).toList(),
        measure: measure,
      );
      final shownPath = layout.abridged
          ? path.skip(path.length - 1).toList()
          : path;
      final shownTags = _allTags ? topic.tags.length : layout.visibleTags;
      final children = <Widget>[
        if (topic.privateMessage)
          Text(
            context.l10n.privateConversation,
            style: _topicMetadataStyle(context),
          )
        else if (shownPath.isNotEmpty)
          _categoryPath(context, shownPath, layout),
        for (var i = 0; i < shownTags; i++) _tag(context, topic.tags[i]),
        if (!_allTags && layout.stub != null)
          _tag(context, topic.tags[shownTags], label: layout.stub),
        if (!_allTags && layout.remainingTags > 0)
          DButton(
            key: const ValueKey('topic-row-tag-overflow'),
            variant: DButtonVariant.inline,
            size: DButtonSize.small,
            density: DButtonDensity.inlineMetadata,
            foregroundColor: _topicMetadataStyle(context).color,
            semanticLabel: context.l10n.moreTopiclistview(layout.remainingTags),
            label: Text(
              '+${layout.remainingTags}',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => setState(() => _allTags = true),
          ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            start:
                path.isNotEmpty || topic.tags.isNotEmpty || topic.privateMessage
                ? _topicTailGap - _topicTagGap
                : 0,
          ),
          child: Wrap(
            key: ValueKey('topic-card-activity-${topic.id}'),
            spacing: _topicTailGap,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final count in _topicCounts(row)) _count(context, count),
            ],
          ),
        ),
      ];
      // Expanded tags wrap; extremely narrow accessible layouts may also wrap
      // the category and counts instead of dropping information.
      return Wrap(
        spacing: _topicTagGap,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    },
  );

  Widget _categoryPath(
    BuildContext context,
    List<TopicCategory> path,
    TopicCardTaxonomyLayout layout,
  ) {
    final dim = _topicMetadataStyle(context).color;
    Widget separator() => Transform.flip(
      flipX: Directionality.of(context) == TextDirection.rtl,
      child: SizedBox(
        width: 7,
        child: DIconGlyphTheme(
          scale: 1,
          naturalWidth: true,
          child: DIcon(DIcons.chevronRight, size: 10, color: dim),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _topicTagGap,
      children: [
        if (layout.abridged) ...[
          Text('…', style: _topicMetadataStyle(context)),
          separator(),
        ],
        for (var i = 0; i < path.length; i++) ...[
          if (i > 0) separator(),
          Flexible(
            child: _category(
              context,
              path[i],
              i == path.length - 1 ? layout.leaf : path[i].name,
              parent: i < path.length - 1,
            ),
          ),
        ],
      ],
    );
  }

  Widget _category(
    BuildContext context,
    TopicCategory category,
    String label, {
    required bool parent,
  }) => DTooltip(
    message: category.name,
    excludeFromSemantics: true,
    child: LinkTarget(
      url: resolveSiteRootPath(row.siteUrl, '/c/${category.id}'),
      title: category.name,
      siteUrl: row.siteUrl,
      child: DBreadcrumbLink(
        key: ValueKey((
          parent ? 'topic-row-parent-category' : 'topic-row-category',
          category.id,
        )),
        compact: true,
        semanticLabel: parent
            ? context.l10n.parentCategory(category.name)
            : context.l10n.categoryTopiclistview(category.name),
        onPressed: () => ShellScope.maybeRead(
          context,
        )?.openCategory(category, siteUrl: row.siteUrl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            CategoryIcon(
              key: ValueKey(('topic-row-category-swatch', category.id)),
              category: category,
              siteUrl: row.siteUrl,
              size: 13,
              squareSize: 9,
            ),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  color: parent ? _topicMetadataStyle(context).color : null,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tag(BuildContext context, TopicTag tag, {String? label}) {
    final shell = ShellScope.maybeRead(context);
    return DTooltip(
      message: tag.name,
      excludeFromSemantics: true,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTertiaryTapUp: (_) => shell?.openTopicTag(
          tag,
          siteUrl: row.siteUrl,
          privateMessage: row.topic.privateMessage,
          newTab: true,
        ),
        child: DButton(
          variant: DButtonVariant.inline,
          size: DButtonSize.small,
          density: DButtonDensity.inlineMetadata,
          foregroundColor: _topicMetadataStyle(context).color,
          semanticLabel: context.l10n.tag(tag.name),
          isLink: true,
          label: Text(
            label ?? '#${tag.name}',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
          ),
          onPressed: () => shell?.openTopicTag(
            tag,
            siteUrl: row.siteUrl,
            privateMessage: row.topic.privateMessage,
          ),
        ),
      ),
    );
  }

  Widget _count(
    BuildContext context,
    (int, DIconData, CountNoun, String) count,
  ) {
    final label = countLabel(count.$1, count.$3);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        DIcon(
          count.$2,
          size: 10.5,
          color: Color.lerp(
            DTokens.of(context).background,
            DTokens.of(context).foreground,
            .32,
          ),
        ),
        Text(_topicCompactCount(count.$1), style: _topicMetadataStyle(context)),
      ],
    );
    return DTooltip(
      message: label,
      excludeFromSemantics: true,
      child: _TopicCardSortValue(
        row: row,
        allowSort: widget.allowSort,
        column: count.$4,
        label: label,
        child: content,
      ),
    );
  }
}

class _TopicCardSortValue extends StatelessWidget {
  const _TopicCardSortValue({
    required this.row,
    required this.allowSort,
    required this.column,
    required this.label,
    required this.child,
  });
  final _TopicRowBody row;
  final bool allowSort;
  final String column, label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeRead(context);
    final route = shell?.topicListContent;
    final canSort =
        allowSort &&
        row.forum == null &&
        !row.topic.privateMessage &&
        route?.canSortTopicList == true;
    final onSort = allowSort
        ? row.onSort ??
              (canSort
                  ? (String column) => unawaited(shell!.sortTopicList(column))
                  : null)
        : null;
    if (onSort == null) {
      return Semantics(label: label, excludeSemantics: true, child: child);
    }
    final order = row.onSort != null ? row.order : route?.topicListOrder;
    final ascending = row.onSort != null
        ? row.ascending
        : route?.topicListAscending ?? false;
    return DButton(
      key: ValueKey('topic-sort-$column'),
      variant: DButtonVariant.inline,
      density: DButtonDensity.inlineMetadata,
      semanticLabel: context.l10n.sortByConversationtopiccard(
        (order == column).toString(),
        label,
        switch (column) {
          'posts' => context.l10n.replies,
          'activity' => context.l10n.activity,
          'views' => context.l10n.views,
          'likes' => context.l10n.likes,
          _ => label,
        },
        order == column ? (ascending ? 'ascending' : 'descending') : '',
      ),
      label: child,
      icon: order == column
          ? RotatedBox(
              quarterTurns: ascending ? 2 : 0,
              child: const DIcon(DIcons.chevronDown, size: 12),
            )
          : null,
      iconPosition: DButtonIconPosition.end,
      onPressed: () => onSort(column),
    );
  }
}
