part of 'topic_list_view.dart';

/// A full-width conversation row, shared by every topic source.
class _ConversationTopicCard extends StatefulWidget {
  const _ConversationTopicCard({required this.row});
  final _TopicRowBody row;

  @override
  State<_ConversationTopicCard> createState() => _ConversationTopicCardState();
}

class _ConversationTopicCardState extends State<_ConversationTopicCard> {
  _TopicRowBody get row => widget.row;
  VoidCallback? _releaseHover;

  void _stopHover() {
    _releaseHover?.call();
    _releaseHover = null;
  }

  void _hoverChanged(bool hovered) {
    _stopHover();
    if (hovered && TickerMode.valuesOf(context).enabled) {
      _releaseHover = ShellScope.maybeRead(
        context,
      )?.hoverTopic(row.siteUrl, row.topic);
    }
  }

  @override
  void didUpdateWidget(_ConversationTopicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.siteUrl != row.siteUrl ||
        oldWidget.row.topic.id != row.topic.id ||
        oldWidget.row.topic.lastUnreadPostNumber !=
            row.topic.lastUnreadPostNumber) {
      _stopHover();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _stopHover();
  }

  @override
  void deactivate() {
    _stopHover();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    if (row.compact case final compact?) {
      return _buildCard(context, mobile: compact);
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildCard(context, mobile: constraints.maxWidth < 600),
    );
  }

  Widget _buildCard(BuildContext context, {required bool mobile}) {
    final topic = row.topic;
    final shell = ShellScope.maybeRead(context);
    final registry =
        PluginScope.maybeOf(context)?.registry ?? PluginRegistry.empty;
    final compactMetadata = registry.compactTopicListMetadata(
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
    final tokens = DTokens.of(context);
    final muted = tokens.mutedForeground;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    Widget field(String label, String column) => _TopicCardField(
      label: label,
      column: column,
      order: order,
      ascending: ascending,
      onSort: onSort,
    );
    Widget ageLabel(String age) => mobile
        ? Text(
            age,
            style: textStyle?.copyWith(
              fontSize: DiscourseTypography.xs,
              fontWeight: FontWeight.w400,
              color: Color.lerp(tokens.background, tokens.foreground, .4),
            ),
          )
        : field(age, 'activity');
    final taxonomyItems = <Widget>[
      if (row.forum case final forum? when mobile)
        Row(
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
              child: Text(
                forum.title,
                style: textStyle?.copyWith(fontSize: DiscourseTypography.micro),
              ),
            ),
          ],
        ),
      if (topic.privateMessage)
        Text(
          context.l10n.privateConversation,
          style: mobile
              ? textStyle?.copyWith(fontSize: DiscourseTypography.micro)
              : textStyle,
        )
      else if (row.category != null)
        _topicRowCategory(context, row, compact: mobile),
      ..._topicRowTags(context, row, compact: mobile),
      if (!mobile && row.forum != null)
        Text(row.forum!.title, style: textStyle),
    ];
    Widget desktopDetails() => Text.rich(
      TextSpan(
        children: [
          for (final child in taxonomyItems)
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: DSpacing.xs),
                child: child,
              ),
            ),
          if (topic.lastPosterUsername case final username?) ...[
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
              child: Text(
                context.l10n.lastPostBy((username).toString()),
                semanticsLabel: context.l10n.lastPostByConversationtopiccard(
                  (username).toString(),
                ),
                style: textStyle,
              ),
            ),
          ],
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: field(
              countLabel(topic.replyCount, CountNoun.reply),
              'posts',
            ),
          ),
          if (row.showViews) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ExcludeSemantics(child: Text(' · ', style: textStyle)),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: field(countLabel(topic.views, CountNoun.view), 'views'),
            ),
          ],
        ],
      ),
      textScaler: TextScaler.noScaling,
      textWidthBasis: TextWidthBasis.longestLine,
    );
    return Padding(
      padding:
          row.outerPadding ??
          (mobile
              ? EdgeInsets.symmetric(horizontal: selected ? 4 : 16)
              : EdgeInsets.zero),
      child: LinkTarget(
        bookmarkUrl: resolveSiteRootPath(row.siteUrl, '/t/${topic.id}'),
        url: resolveSiteRootPath(
          row.siteUrl,
          '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
        ),
        title: topic.title,
        siteUrl: row.siteUrl,
        child: Semantics(
          key: row.inbox ? ValueKey('inbox-row-${topic.id}') : null,
          container: true,
          selected: selected,
          child: DItem(
            key: ValueKey('topic-card-${topic.id}'),
            shape: mobile ? DItemShape.standard : DItemShape.fullWidth,
            padding:
                row.contentPadding ??
                (mobile
                    ? EdgeInsets.symmetric(
                        horizontal: selected ? 12 : 0,
                        vertical: 12,
                      )
                    : DInsets.listRow),
            link: true,
            onPressed: row.onTap,
            onHoverChanged: context.isTouch ? null : _hoverChanged,
            selected: selected,
            selectionStyle: mobile
                ? DItemSelectionStyle.filled
                : DItemSelectionStyle.leadingAccent,
            showSelectionIndicator: false,
            children: [
              DItemContent(
                spacing: mobile ? 0 : DSpacing.controlGap,
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
                          _TopicListTitle(row: row, mobile: mobile),
                        ),
                      ),
                      SizedBox(width: mobile ? 10 : DSpacing.sm),
                      KeyedSubtree(
                        key: ValueKey('inbox-row-time-${topic.id}'),
                        child: switch (topic.bumpedAt) {
                          final bumpedAt? => RelativeTimeBuilder(
                            when: bumpedAt,
                            builder: (context, age) => ageLabel(age),
                          ),
                          null => ageLabel('—'),
                        },
                      ),
                    ],
                  ),
                  if (mobile) const SizedBox(height: 5),
                  if (topic.excerpt case final excerpt?
                      when excerpt.isNotEmpty) ...[
                    SiteEmojiText.plain(
                      excerpt,
                      siteUrl: row.siteUrl,
                      maxLines: largeText ? null : 2,
                      overflow: largeText
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: DiscourseTypography.preview,
                        color: muted,
                        height: DiscourseTypography.lineHeightPreview,
                      ),
                    ),
                    if (mobile) const SizedBox(height: 7),
                  ],
                  if (mobile)
                    _MobileTopicDetails(row: row, taxonomyItems: taxonomyItems)
                  else
                    desktopDetails(),
                  if (mobile &&
                      (compactMetadata.isNotEmpty || metadata.isNotEmpty))
                    const SizedBox(height: 5),
                  if (compactMetadata.isNotEmpty)
                    Wrap(
                      spacing: DSpacing.xs,
                      runSpacing: DSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: compactMetadata,
                    ),
                  if (mobile &&
                      compactMetadata.isNotEmpty &&
                      metadata.isNotEmpty)
                    const SizedBox(height: 5),
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

class _MobileTopicDetails extends StatelessWidget {
  const _MobileTopicDetails({required this.row, required this.taxonomyItems});

  final _TopicRowBody row;
  final List<Widget> taxonomyItems;

  @override
  Widget build(BuildContext context) {
    final topic = row.topic;
    final tokens = DTokens.of(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
      color: Color.lerp(tokens.background, tokens.foreground, .4),
    );
    final username = topic.lastPosterUsername;
    final replies = countLabel(topic.replyCount, CountNoun.reply);
    final activity = TextSpan(
      children: [
        if (username != null) ...[
          TextSpan(text: context.l10n.lastPostByConversationtopiccardValue),
          TextSpan(
            text: username,
            style: TextStyle(
              color: Color.lerp(tokens.background, tokens.foreground, .62),
            ),
          ),
          const TextSpan(text: ' · '),
        ],
        TextSpan(text: replies),
        if (row.showViews)
          TextSpan(text: ' · ${countLabel(topic.views, CountNoun.view)}'),
      ],
    );
    return _TopicMetadataWrap(
      children: [
        ...taxonomyItems,
        // CSS flex:1 before activity: consumes remaining room on its line.
        const SizedBox.shrink(),
        Row(
          key: ValueKey('topic-card-activity-${topic.id}'),
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (username != null)
              DAvatar(
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
            Flexible(child: Text.rich(activity, style: style)),
          ],
        ),
      ],
    );
  }
}

/// Wraps metadata like the mockup's flex row, including its flexible spacer.
/// Only layout is handled here; Native components own all link interactions.
class _TopicMetadataWrap extends MultiChildRenderObjectWidget {
  const _TopicMetadataWrap({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _TopicMetadataRenderWrap(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _TopicMetadataRenderWrap renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _TopicMetadataRenderWrap extends RenderWrap {
  _TopicMetadataRenderWrap(TextDirection direction)
    : super(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        textDirection: direction,
      );

  @override
  void performLayout() {
    super.performLayout();
    final activity = lastChild!;
    final activityData = activity.parentData! as WrapParentData;
    final spacer = activityData.previousSibling!;
    final spacerData = spacer.parentData! as WrapParentData;
    // If the activity wrapped past the spacer it starts at the leading edge.
    // Otherwise the spacer expands to push it to the trailing edge.
    final sameRun =
        (activityData.offset.dy +
                activity.size.height / 2 -
                spacerData.offset.dy -
                spacer.size.height / 2)
            .abs() <
        .01;
    if (sameRun) {
      activityData.offset = Offset(
        textDirection == TextDirection.rtl
            ? 0
            : size.width - activity.size.width,
        activityData.offset.dy,
      );
    }
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
          key: ValueKey('topic-sort-$column'),
          size: DButtonSize.small,
          variant: DButtonVariant.inline,
          label: Text(label),
          // The visible value is excluded once a semantic label is set, so
          // the label carries it ahead of the sort action and its state.
          semanticLabel: context.l10n.sortByConversationtopiccard(
            (order == column).toString(),
            (label).toString(),
            (switch (column) {
              'posts' => context.l10n.replies,
              'activity' => context.l10n.activity,
              'views' => context.l10n.views,
              _ => label,
            }).toString(),
            ((order == column)
                    ? ((ascending ? 'ascending' : 'descending'))
                    : '')
                .toString(),
          ),
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
