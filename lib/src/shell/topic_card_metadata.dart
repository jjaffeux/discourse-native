part of 'topic_list_view.dart';

const _topicTailGap = 14.0;
const _topicTagGap = 5.0;

TextStyle _topicMetadataStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: DiscourseTypography.xs,
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

double _topicCategoryMarkWidth(TopicCategory category) =>
    (category.styleType == 'icon' ||
            (category.styleType == 'emoji' && category.emoji != null)
        ? 13.0
        : 9.0) +
    (category.readRestricted ? 4 + 13 : 0);

double _topicMinimumTaxonomyWidth(
  _TopicRowBody row,
  double Function(String) measure,
) {
  final ellipsis = measure('…');
  var width = 0.0;
  if (row.topic.privateMessage) {
    width = ellipsis;
  } else if (row.topic.categoryId != null &&
      row.topic.categoryId != row.hiddenCategoryId) {
    width = 30 + _topicTagGap + ellipsis;
    if (row.showCategoryBreadcrumb) {
      width += ellipsis + 7 + _topicTagGap * 2;
    }
  }
  if (row.topic.tags.isNotEmpty) {
    width +=
        (width > 0 ? _topicTagGap : 0) +
        measure('+${row.topic.tags.length}').clamp(16.0, double.infinity);
  }
  return width.clamp(45.0, double.infinity);
}

String? _topicSortOrder(
  BuildContext context,
  _TopicRowBody row, {
  required bool allowSort,
}) {
  if (!allowSort) return null;
  if (row.onSort != null) return row.order;
  final route = ShellScope.maybeRead(context) == null
      ? null
      : ForumTabScope.tabOf(context).topicListContent;
  return row.forum == null &&
          !row.topic.privateMessage &&
          route?.canSortTopicList == true
      ? route?.topicListOrder
      : null;
}

class _TopicCardFooter extends StatefulWidget {
  const _TopicCardFooter({required this.row, required this.allowSort});
  final _TopicRowBody row;
  final bool allowSort;

  @override
  State<_TopicCardFooter> createState() => _TopicCardFooterState();
}

class _TopicCardFooterState extends State<_TopicCardFooter> {
  final _measurements = TopicTextMeasurements();
  SiteLease? _lease;
  VoidCallback? _removeRetirementListener;
  _TopicRowBody get row => widget.row;
  bool get allowSort => widget.allowSort;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  void _fontsChanged() {
    _measurements.clear();
    setState(() {});
  }

  @override
  void didUpdateWidget(_TopicCardFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.topic.id != row.topic.id ||
        oldWidget.row.siteUrl != row.siteUrl) {
      _measurements.clear();
    }
  }

  double Function(String) _resolveMeasure(BuildContext context) {
    final lease = ShellScope.maybeRead(context)?.lifecycle.capture(row.siteUrl);
    if (!identical(lease?.session, _lease?.session)) {
      _removeRetirementListener?.call();
      _measurements.clear();
      _lease = lease;
      _removeRetirementListener = lease?.onRetire(_measurements.clear);
    }
    var style = _topicMetadataStyle(context);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final ambientLocale = Localizations.maybeLocaleOf(context);
    final ambientDefaultTextStyle = DefaultTextStyle.of(context).style;
    final ambientLineHeightScaleFactor =
        MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
    final ambientLetterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(
      context,
    );
    final ambientWordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
    return (text) {
      final retired = lease != null && !lease.isCurrent;
      if (retired) _measurements.clear();
      final width = _measurements.measure(
        text,
        style: style,
        textScaler: textScaler,
        textDirection: textDirection,
        ambientLocale: ambientLocale,
        ambientDefaultTextStyle: ambientDefaultTextStyle,
        ambientLineHeightScaleFactor: ambientLineHeightScaleFactor,
        ambientLetterSpacing: ambientLetterSpacing,
        ambientWordSpacing: ambientWordSpacing,
      );
      if (retired) _measurements.clear();
      return width;
    };
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _removeRetirementListener?.call();
    _measurements.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (row.topic.bumpedAt) {
    final bumpedAt? => RelativeTimeBuilder(
      when: bumpedAt,
      builder: (context, age) => _build(context, age),
    ),
    null => _build(context, '—'),
  };

  Widget _build(BuildContext context, String age) {
    final measure = _resolveMeasure(context);
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
            child: UserCardTarget.avatar(
              username: poster.username ?? '',
              siteUrl: row.siteUrl,
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
                        fontSize: DiscourseTypography.badge,
                        fontWeight: FontWeight.w700,
                      ),
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
    final taxonomy = _TopicCardTaxonomy(
      row: row,
      allowSort: allowSort,
      measure: measure,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.maxWidth -
            avatarsWidth -
            measure(age) -
            (_topicSortOrder(context, row, allowSort: allowSort) == 'activity'
                ? 18
                : 0) -
            (shown.isEmpty ? 14 : 28);
        // At accessibility sizes the entire metadata strip gets its own line.
        // Keep every link/count available instead of squeezing it to zero.
        final minimumTaxonomyWidth = _topicMinimumTaxonomyWidth(row, measure);
        final wrap =
            room <
            _topicCountsWidth(context, row, measure, allowSort: allowSort) +
                minimumTaxonomyWidth;
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
          final siteWidth = 20 + measure(forum.title);
          if (!wrap &&
              room - siteWidth - _topicTailGap >=
                  _topicCountsWidth(
                        context,
                        row,
                        measure,
                        allowSort: allowSort,
                      ) +
                      minimumTaxonomyWidth.clamp(82.0, double.infinity)) {
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
  _TopicRowBody row,
  double Function(String) measure, {
  required bool allowSort,
}) {
  final order = _topicSortOrder(context, row, allowSort: allowSort);
  return _topicCounts(row).fold(
    0.0,
    (width, count) =>
        width +
        11 +
        4 +
        measure(_topicCompactCount(count.$1)) +
        _topicTailGap +
        (order == count.$4 ? 18 : 0),
  );
}

class _TopicCardTaxonomy extends StatefulWidget {
  const _TopicCardTaxonomy({
    required this.row,
    required this.allowSort,
    required this.measure,
  });
  final _TopicRowBody row;
  final bool allowSort;
  final double Function(String) measure;
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
      final measure = widget.measure;
      final layout = TopicCardTaxonomyLayout.calculate(
        width: constraints.maxWidth,
        countsWidth: _topicCountsWidth(
          context,
          row,
          measure,
          allowSort: widget.allowSort,
        ),
        categories: path.map((c) => c.name).toList(),
        categoryMarkWidths: path.map(_topicCategoryMarkWidth).toList(),
        tags: _allTags ? [] : topic.tags.map((t) => t.name).toList(),
        measure: measure,
      );
      final shownPath = layout.abridged
          ? path.skip(path.length - 1).toList()
          : path;
      final shownTags = layout.visibleTags;
      final children = <Widget>[
        if (topic.privateMessage)
          Flexible(
            child: Text(
              context.l10n.privateConversation,
              style: _topicMetadataStyle(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else if (shownPath.isNotEmpty)
          Flexible(child: _categoryPath(context, shownPath, layout)),
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
              style: const TextStyle(fontSize: DiscourseTypography.xs),
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
          child: Row(
            key: ValueKey('topic-card-activity-${topic.id}'),
            mainAxisSize: MainAxisSize.min,
            spacing: _topicTailGap,
            children: [
              for (final count in _topicCounts(row)) _count(context, count),
            ],
          ),
        ),
      ];
      // Counts cannot wrap: the category yields its space after tag fitting.
      // Explicitly expanded tags get a separate run below this stable row.
      final metadata = Row(spacing: _topicTagGap, children: children);
      if (!_allTags || topic.tags.isEmpty) return metadata;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 5,
        children: [
          metadata,
          Wrap(
            spacing: _topicTagGap,
            runSpacing: 5,
            children: [for (final tag in topic.tags) _tag(context, tag)],
          ),
        ],
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
                  fontSize: DiscourseTypography.xs,
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
            style: const TextStyle(fontSize: DiscourseTypography.xs),
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
    final tab = shell == null ? null : ForumTabScope.tabOf(context);
    final route = tab?.topicListContent;
    final canSort =
        allowSort &&
        row.forum == null &&
        !row.topic.privateMessage &&
        route?.canSortTopicList == true;
    final onSort = allowSort
        ? row.onSort ??
              (canSort
                  ? (String column) => unawaited(tab!.sortTopicList(column))
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
