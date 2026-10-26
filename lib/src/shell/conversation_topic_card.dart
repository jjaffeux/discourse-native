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
  final _prefetchBounds = GlobalKey();
  _TopicListPrefetch? _prefetch;

  void _stopHover() {
    _releaseHover?.call();
    _releaseHover = null;
  }

  void _hoverChanged(bool hovered) {
    if (_prefetch case final prefetch?) {
      prefetch.hover(this, hovered);
      return;
    }
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
      _prefetch?.invalidate((
        oldWidget.row.siteUrl,
        oldWidget.row.topic.id,
        oldWidget.row.topic.lastUnreadPostNumber,
      ));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefetch = context
        .findAncestorStateOfType<_TopicListViewState>()
        ?._prefetch;
    if (!identical(prefetch, _prefetch)) {
      _prefetch?.unregister(this);
      _stopHover();
      _prefetch = prefetch;
    }
    _prefetch?.register(this);
    if (!TickerMode.valuesOf(context).enabled) _stopHover();
  }

  @override
  void deactivate() {
    _prefetch?.unregister(this);
    _stopHover();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    if (row.compact case final compact?) {
      return _buildCard(context, compact: compact);
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildCard(context, compact: constraints.maxWidth < 600),
    );
  }

  Widget _buildCard(BuildContext context, {required bool compact}) {
    final topic = row.topic;
    final siteUrl = row.siteUrl;
    final shell = ShellScope.maybeRead(context);
    final lease = shell?.lifecycle.capture(siteUrl);
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
    final selected = row.selected || KeyboardSelection.isSelectedOf(context);
    final tokens = DTokens.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return Opacity(
      opacity: topic.muted ? .55 : 1,
      child: Padding(
        padding:
            row.outerPadding ??
            EdgeInsets.symmetric(horizontal: selected ? 4 : 16),
        child: LinkTarget(
          key: _prefetchBounds,
          bookmarkUrl: resolveSiteRootPath(row.siteUrl, '/t/${topic.id}'),
          url: resolveSiteRootPath(
            row.siteUrl,
            '/t/${topic.slug}/${topic.id}/${topic.lastUnreadPostNumber ?? 1}',
          ),
          title: topic.displayTitle,
          siteUrl: row.siteUrl,
          contextMenuItems: [
            if (!context.isTouch &&
                shell?.instanceFor(siteUrl)?.isConnected == true &&
                (!topic.visited || topic.hasUnseenActivity) &&
                topic.highestPostNumber > 0)
              DContextMenuItem(
                onPressed: () {
                  if (lease?.isCurrent != true) return;
                  final latest = shell!.store.read<Topic>(siteUrl, topic.id);
                  if (latest == null) return;
                  unawaited(
                    shell.markTopicRead(
                      siteUrl,
                      topic.id,
                      latest.highestPostNumber,
                      caughtUp: true,
                    ),
                  );
                },
                child: Text(context.l10n.markTopicRead),
              ),
          ],
          child: Semantics(
            key: row.inbox ? ValueKey('inbox-row-${topic.id}') : null,
            container: true,
            selected: selected,
            child: DItem(
              key: ValueKey('topic-card-${topic.id}'),
              shape: selected ? DItemShape.standard : DItemShape.fullWidth,
              padding:
                  row.contentPadding ??
                  EdgeInsets.symmetric(
                    horizontal: selected ? 12 : 0,
                    vertical: 12,
                  ),
              link: true,
              onPressed: row.onTap,
              onHoverChanged: context.isTouch ? null : _hoverChanged,
              highlightOnInteraction: false,
              selected: selected,
              selectionStyle: DItemSelectionStyle.filled,
              showSelectionIndicator: false,
              children: [
                DItemContent(
                  spacing: 0,
                  alignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 779),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 6,
                          children: [
                            Expanded(
                              child: registry.decorateTopicListTitle(
                                context,
                                row.siteUrl,
                                topic,
                                _TopicListTitle(row: row),
                              ),
                            ),
                            _TopicCardStatus(
                              topic: topic,
                              titleStyle: row.titleStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (topic.excerpt case final excerpt?
                        when excerpt.isNotEmpty) ...[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: SiteEmojiText.plain(
                            excerpt,
                            siteUrl: row.siteUrl,
                            maxLines: largeText ? null : 2,
                            overflow: largeText
                                ? TextOverflow.clip
                                : TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: DiscourseTypography.preview,
                                  fontFamily: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.fontFamily,
                                  fontFamilyFallback: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.fontFamilyFallback,
                                  color: tokens.mutedForeground,
                                  height: DiscourseTypography.lineHeightPreview,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                    ],
                    _TopicCardFooter(row: row, allowSort: !compact),
                    if (compactMetadata.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: DSpacing.xs,
                        runSpacing: DSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: compactMetadata,
                      ),
                    ],
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: DSpacing.sm,
                        runSpacing: DSpacing.xs,
                        children: metadata,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicCardStatus extends StatelessWidget {
  const _TopicCardStatus({required this.topic, this.titleStyle});
  final Topic topic;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final style = titleStyle ?? Theme.of(context).textTheme.titleSmall;
    final lineHeight =
        MediaQuery.textScalerOf(
          context,
        ).scale(style?.fontSize ?? DiscourseTypography.rowTitle) *
        (style?.height ?? DiscourseTypography.lineHeightRowTitle);
    final states = [
      if (topic.pinned) (DIcons.thumbtack, context.l10n.pinned),
      if (topic.closed) (DIcons.lock, context.l10n.closed),
      if (topic.bookmarked) (DIcons.bookmark, context.l10n.bookmarked),
    ];
    return Padding(
      padding: EdgeInsets.only(
        top: ((lineHeight - 11) / 2).clamp(0, double.infinity),
      ),
      child: SizedBox(
        key: ValueKey('topic-card-status-${topic.id}'),
        width: 13,
        child: states.isEmpty
            ? null
            : DTooltip(
                message: states.map((s) => s.$2).join(', '),
                excludeFromSemantics: true,
                child: DIcon(
                  states.first.$1,
                  size: 11,
                  color: Color.lerp(
                    DTokens.of(context).background,
                    DTokens.of(context).foreground,
                    .4,
                  ),
                  semanticLabel: states.map((s) => s.$2).join(', '),
                ),
              ),
      ),
    );
  }
}
