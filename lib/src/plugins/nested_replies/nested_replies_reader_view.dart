part of 'nested_replies_reader.dart';

extension _NestedRepliesReaderView on _NestedRepliesReaderState {
  Widget _sortControl(BuildContext context) {
    final mobile = context.isTouch;
    final chip = StreamChip.of(context, floating: true);
    return DSelect<NestedRepliesSort>.controlled(
      value: _controller.requestedSort,
      semanticLabel: appL10n.sort,
      enabled: !_controller.loading,
      side: DPopoverSide.top,
      align: DPopoverAlign.end,
      alignItemWithTrigger: false,
      triggerBuilder: (context, state, _) => DButton(
        key: const ValueKey('nested-sort-button'),
        variant: mobile ? DButtonVariant.tool : DButtonVariant.outline,
        density: mobile ? DButtonDensity.standard : DButtonDensity.floatingDate,
        size: mobile ? DButtonSize.floating : DButtonSize.chip,
        shape: DButtonShape.pill,
        backgroundColor: mobile
            ? DTokens.of(context).wellFill
            : chip.background,
        interactiveBackgroundColor: chip.hover,
        foregroundColor: chip.foreground,
        borderColor: mobile ? Colors.transparent : chip.border,
        onPressed: state.enabled ? state.toggle : null,
        focusNode: state.focusNode,
        expanded: state.open,
        hasPopup: true,
        tooltip: appL10n.sort,
        semanticLabel: appL10n.sort,
        trailing: const DIcon(DIcons.chevronDown, size: 12),
        label: Text(
          _sortLabel(_controller.requestedSort),
          style: TextStyle(
            fontWeight: mobile ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ),
      entries: [
        for (final sort in NestedRepliesSort.values)
          if (sort != NestedRepliesSort.hot || widget.settings.hotEnabled)
            DSelectOption(
              value: sort,
              label: _sortLabel(sort),
              child: Text(_sortLabel(sort)),
            ),
      ],
      onChanged: (sort) {
        if (sort == null) return;
        unawaited(_changeSort(sort));
      },
    );
  }

  Widget _intro(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_controller.contextMode) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: Text(appL10n.nestedRepliesAllReplies),
              onPressed: () => _navigate(),
            ),
            if (_controller.ancestorsTruncated)
              DButton(
                label: Text(appL10n.nestedRepliesParentContext),
                onPressed: () => _navigate(
                  target: _controller.ancestors.firstOrNull?.postNumber,
                ),
              ),
            for (final ancestor in _controller.ancestors)
              DButton(
                label: Text(
                  reader.post(ancestor.postId)?.displayName ??
                      '#${ancestor.postNumber}',
                ),
                onPressed: () =>
                    _navigate(target: ancestor.postNumber, context: 0),
              ),
          ],
        ),
        if (_controller.ancestors.isEmpty &&
            (_controller.target?.data.replyToPostNumber ?? 0) > 1 &&
            _controller.contextDepth != 0)
          DAlert(
            description: DAlertDescription(
              child: Text(appL10n.nestedRepliesEarlierUnavailable),
            ),
          ),
      ],
      if (_controller.pendingRoots.isNotEmpty)
        DButton(
          label: Text(
            '${_controller.pendingRoots.length} ${appL10n.nestedRepliesNewReplies}',
          ),
          onPressed: _controller.showPendingRoots,
        ),
      if (_controller.loading &&
          _controller.op == null &&
          _controller.roots.isEmpty)
        const Center(child: DSpinner()),
      if (_controller.error != null)
        _error(
          appL10n.nestedRepliesCouldNotLoad,
          _controller.roots.isNotEmpty || _controller.op != null
              ? _reload
              : () => _open(),
        ),
    ],
  );

  Widget _collapseControl(NestedReplyNode node, {required bool collapsed}) =>
      DToggle.iconOnly(
        key: ValueKey('nested-collapse-${node.postId}'),
        semanticLabel: collapsed
            ? appL10n.nestedRepliesExpandPost
            : appL10n.nestedRepliesCollapsePost,
        pressed: collapsed,
        focusNode: _collapseFocus.putIfAbsent(node.postNumber, FocusNode.new),
        icon: const DIcon(DIcons.minus),
        selectedIcon: const DIcon(DIcons.plus),
        density: DToggleDensity.disclosure,
        onPressedChanged: (value) => _collapsePost(node.postNumber, value),
      );

  Widget _post(
    BuildContext context,
    NestedReplyNode node,
    int depth, {
    int? displayDepth,
    List<bool> continuations = const [],
    List<int> ancestors = const [],
    bool endOfThread = false,
  }) {
    if (depth < 0) {
      return KeyedSubtree(
        key: _postKeys.putIfAbsent(node.postId, GlobalKey.new),
        child: PluginTopicPost(reader: reader, postId: node.postId),
      );
    }
    final phone = _usesMobileLayout;
    final displayLevel = displayDepth ?? depth;
    final step = phone ? 16.0 : 32.0;
    final visualLimit = phone ? _phoneDepthLimit : widget.settings.maxDepth;
    final visualDepth = math.min(displayLevel, visualLimit);
    final collapsed = _controller.isCollapsed(node.postNumber);
    final children = _controller.childrenFor(node.postNumber);
    final childDepth = math.max(1, depth + 1);
    final atLimit = depth >= widget.settings.maxDepth;
    final flattened =
        widget.settings.capDepth && childDepth >= widget.settings.maxDepth;
    final total = flattened
        ? node.data.totalDescendantCount
        : node.data.directReplyCount;
    final childPage = _controller.childrenState(
      node.postNumber,
      depth: childDepth,
    );
    final expanded = _controller.isExpanded(node.postNumber, depth: depth);
    final hasChildren =
        !collapsed &&
        expanded &&
        children.isNotEmpty &&
        (!phone || displayLevel < visualLimit);
    final hasMore = childPage.fetchedFromServer
        ? childPage.hasMore
        : total > children.length;
    final ordinary =
        node.data.placeholder == NestedPostPlaceholder.none ||
        (!node.data.redacted && reader.currentUserStaff);
    void collapse() => _collapsePost(node.postNumber, true);
    void toggle() => _collapsePost(node.postNumber, !collapsed);
    Widget rail({bool interactive = false}) => DThreadRail(
      onPressed: interactive ? collapse : null,
      semanticLabel: interactive ? appL10n.nestedRepliesCollapsePost : null,
    );
    Widget footerRail() => Stack(children: [Positioned.fill(child: rail())]);
    final control = phone ? null : _collapseControl(node, collapsed: collapsed);
    final footer = phone
        ? null
        : Column(
            children: [
              SizedBox(height: 10, child: footerRail()),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: footerRail()),
                    const SizedBox(height: 4),
                    control!,
                    const SizedBox(height: 4),
                    Expanded(
                      child: hasChildren
                          ? footerRail()
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          );
    Widget post = ordinary
        ? PluginTopicPost(
            key: collapsed
                ? null
                : _postKeys.putIfAbsent(node.postId, GlobalKey.new),
            reader: reader,
            postId: node.postId,
            layout: collapsed
                ? TopicPostLayout.headerOnly
                : phone
                ? TopicPostLayout.stacked
                : TopicPostLayout.compact,
            leading: collapsed ? control : null,
            bodyLeading: phone
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: rail(interactive: true),
                  ),
            footerLeading: footer,
            onBodyPressed: phone ? toggle : null,
            bodyActionLabel: phone ? appL10n.nestedRepliesCollapsePost : null,
          )
        : _placeholder(
            node,
            collapsed: collapsed,
            control: control,
            phone: phone,
          );
    if (phone) {
      post = DItem(
        key: ValueKey('nested-collapse-${node.postId}'),
        size: DItemSize.artwork,
        shape: DItemShape.fullWidth,
        highlightOnInteraction: false,
        focusNode: _collapseFocus.putIfAbsent(node.postNumber, FocusNode.new),
        onPressed: toggle,
        semanticLabel: collapsed
            ? appL10n.nestedRepliesExpandPost
            : appL10n.nestedRepliesCollapsePost,
        children: [post],
      );
    }
    final extras = <Widget>[
      if (_controller.pinnedPostIds.contains(node.postId))
        DBadge(child: Text(appL10n.pinned)),
      if (reader.post(node.postId)?.userId != null &&
          reader.post(node.postId)?.userId ==
              reader.post(_controller.op?.postId ?? 0)?.userId)
        DBadge(child: Text(appL10n.nestedRepliesOriginalPoster)),
      if (total > 0 && !atLimit && (!phone || displayLevel < visualLimit))
        DToggle(
          key: ValueKey('nested-replies-toggle-${node.postId}'),
          variant: DToggleVariant.inline,
          size: DToggleSize.chip,
          pressed: expanded,
          onPressedChanged: _controller.restoringPages && children.isEmpty
              ? null
              : (value) {
                  _controller.setRepliesExpanded(node.postNumber, value);
                  if (value && children.isEmpty) {
                    unawaited(
                      _controller.loadChildren(
                        node.postNumber,
                        depth: childDepth,
                      ),
                    );
                  }
                },
          child: Text(countLabel(total, CountNoun.reply)),
        ),
      if (hasMore &&
          expanded &&
          !atLimit &&
          (!phone || displayLevel < visualLimit))
        DButton(
          variant: DButtonVariant.inline,
          size: DButtonSize.chip,
          label: Text(
            childPage.loading ? appL10n.loading : appL10n.nestedRepliesLoadMore,
          ),
          onPressed: childPage.loading || _controller.restoringPages
              ? null
              : () => _controller.loadChildren(
                  node.postNumber,
                  depth: childDepth,
                ),
        ),
      if ((phone && displayLevel >= visualLimit) ||
          (atLimit && !widget.settings.capDepth))
        DButton(
          variant: DButtonVariant.inline,
          size: DButtonSize.chip,
          label: Text(appL10n.nestedRepliesContinueThread),
          onPressed: () => _navigate(target: node.postNumber, context: 0),
        ),
    ];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            post,
            if (!phone && hasChildren && ordinary)
              PositionedDirectional(
                start: 16,
                width: 32,
                bottom: 0,
                height: 8,
                child: rail(),
              ),
          ],
        ),
        if (!collapsed && (extras.isNotEmpty || childPage.error != null))
          Stack(
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: phone ? 16 : 56,
                  end: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: extras,
                    ),
                    if (childPage.error != null)
                      _error(
                        appL10n.nestedRepliesCouldNotLoad,
                        () => _controller.loadChildren(
                          node.postNumber,
                          depth: childDepth,
                        ),
                      ),
                  ],
                ),
              ),
              if (!phone && hasChildren)
                PositionedDirectional(
                  start: 16,
                  width: 32,
                  top: 0,
                  bottom: 0,
                  child: rail(),
                ),
            ],
          ),
      ],
    );
    if (phone) {
      return Stack(
        key: ValueKey('nested-row-${node.postId}'),
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: visualDepth * step,
              bottom: endOfThread ? 16 : 0,
            ),
            child: content,
          ),
          for (var level = 0; level < visualDepth; level++)
            PositionedDirectional(
              start: 15 + level * step,
              width: 2,
              top: 0,
              bottom: endOfThread ? 16 : 0,
              child: const DThreadRail(),
            ),
        ],
      );
    }
    return Stack(
      key: ValueKey('nested-row-${node.postId}'),
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: 8 + visualDepth * step,
            end: 8,
            bottom: endOfThread ? 16 : 0,
          ),
          child: content,
        ),
        for (
          var level = 0;
          level < math.min(visualDepth, continuations.length);
          level++
        )
          if (level == visualDepth - 1 || continuations[level])
            PositionedDirectional(
              start: 8 + 32 + level * step - 1,
              width: level == visualDepth - 1 ? step - 15 : 2,
              top: 0,
              bottom: 0,
              child: level == visualDepth - 1
                  ? DThreadConnector(
                      width: step - 15,
                      junction: 24,
                      continuesBelow: continuations[level],
                      onPressed: () => _collapsePost(ancestors[level], true),
                      semanticLabel: appL10n.nestedRepliesCollapsePost,
                    )
                  : DThreadRail(
                      onPressed: () => _collapsePost(ancestors[level], true),
                      semanticLabel: appL10n.nestedRepliesCollapsePost,
                    ),
            ),
      ],
    );
  }

  Widget _placeholder(
    NestedReplyNode node, {
    required bool collapsed,
    required Widget? control,
    required bool phone,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (!phone) ...[
              SizedBox(width: 32, height: 32, child: Center(child: control)),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                node.data.placeholder == NestedPostPlaceholder.deleted
                    ? appL10n.nestedRepliesDeletedPost
                    : appL10n.nestedRepliesIgnoredPost,
              ),
            ),
          ],
        ),
        if (!collapsed)
          Padding(
            padding: EdgeInsetsDirectional.only(start: phone ? 0 : 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_revealed[node.postId] case final cooked?)
                  CookedHtml(html: cooked, siteUrl: reader.siteUrl),
                if (node.data.placeholder == NestedPostPlaceholder.ignored &&
                    !_revealed.containsKey(node.postId))
                  DButton(
                    variant: DButtonVariant.inline,
                    size: DButtonSize.chip,
                    label: Text(
                      _revealing.contains(node.postId)
                          ? appL10n.loading
                          : appL10n.nestedRepliesRevealIgnored,
                    ),
                    onPressed: _revealing.contains(node.postId)
                        ? null
                        : () => _reveal(node),
                  ),
                if (_revealErrors.containsKey(node.postId))
                  Text(appL10n.nestedRepliesCouldNotLoad),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _footer(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_controller.rootPageError != null)
        _error(appL10n.nestedRepliesCouldNotLoad, _controller.loadMoreRoots),
      if (_controller.hasMoreRoots)
        DButton(
          label: Text(
            _controller.loadingMoreRoots
                ? appL10n.loading
                : appL10n.nestedRepliesLoadMore,
          ),
          onPressed: _controller.loadingMoreRoots || _controller.restoringPages
              ? null
              : _controller.loadMoreRoots,
        ),
      if (!_controller.loading &&
          _controller.error == null &&
          _controller.roots.isEmpty)
        Text(appL10n.nestedRepliesNoReplies),
      if (!_controller.loading && !_controller.hasMoreRoots)
        for (final source
            in reader.topic?.recommendations?.sources ??
                const <TopicRecommendationSource>[]) ...[
          if (source.topics.isNotEmpty)
            Semantics(
              header: true,
              child: Text(
                source.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          for (final topic in source.topics)
            TopicListRow(
              topic: topic,
              siteUrl: reader.siteUrl,
              onTap: () =>
                  openLink(context, topic.path, siteUrl: reader.siteUrl),
            ),
        ],
    ],
  );

  Widget _error(String message, Future<void> Function() retry) => DAlert(
    variant: DAlertVariant.destructive,
    description: DAlertDescription(child: Text(message)),
    action: DAlertAction(
      child: DButton(
        label: Text(appL10n.retry),
        onPressed: () => unawaited(retry()),
      ),
    ),
  );

  String _sortLabel(NestedRepliesSort sort) => switch (sort) {
    NestedRepliesSort.top => appL10n.nestedRepliesSortTop,
    NestedRepliesSort.hot => appL10n.nestedRepliesSortHot,
    NestedRepliesSort.newest => appL10n.nestedRepliesSortNew,
    NestedRepliesSort.oldest => appL10n.nestedRepliesSortOld,
  };
}
