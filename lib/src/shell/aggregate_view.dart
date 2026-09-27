import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import '../utils/pagination.dart';
import 'aggregate_feed_controller.dart';
import 'content_reading_lane.dart';
import 'forum_settings_controller.dart';
import 'forum_settings_page.dart';
import 'forum_tabs_bar.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'topic_filter_input.dart';
import 'topic_list_layout.dart';
import 'topic_list_view.dart';

class AggregateView extends StatefulWidget {
  const AggregateView({super.key});

  @override
  State<AggregateView> createState() => AggregateViewState();
}

class AggregateViewState extends State<AggregateView> {
  final Map<String, ScrollController> _scrolls = {};
  ShellController? _controller;
  bool _releaseScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.read(context);
    if (_controller == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) shell.aggregate.setFiltersCollapsed(true);
      });
    }
  }

  /// One controller per open tab whose topic list has been laid out.
  @visibleForTesting
  int get retainedScrollControllerCount => _scrolls.length;

  @override
  void dispose() {
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    _scrolls.clear();
    super.dispose();
  }

  ScrollController _scrollFor(String tabId) => _scrolls.putIfAbsent(tabId, () {
    final scroll = ScrollController();
    scroll.addListener(() => _loadMoreNearEnd(tabId, scroll));
    return scroll;
  });

  /// A tab closed while active keeps its list attached until this build's
  /// unmount pass, so its controller is released once the frame has ended and
  /// the position has detached. A tab reopened before then keeps its
  /// controller.
  void _releaseClosedTabScrolls(ShellController controller) {
    if (_releaseScheduled) return;
    final open = {for (final tab in controller.aggregateTabs) tab.id};
    if (_scrolls.keys.every(open.contains)) return;
    _releaseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _releaseScheduled = false;
      if (!mounted) return;
      final stillOpen = {for (final tab in controller.aggregateTabs) tab.id};
      _scrolls.removeWhere((tabId, scroll) {
        if (stillOpen.contains(tabId) || scroll.hasClients) return false;
        scroll.dispose();
        return true;
      });
    });
  }

  void _loadMoreNearEnd(String tabId, ScrollController scroll) {
    final controller = _controller;
    if (controller == null ||
        controller.activeAggregateTabId != tabId ||
        !scroll.hasClients) {
      return;
    }
    if (scroll.position.extentAfter <
        paginationPrefetchDistance(scroll.position)) {
      unawaited(controller.aggregate.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    final controller = ShellScope.read(context);
    _controller = controller;
    final theme = Theme.of(context);
    return Theme(
      data: theme,
      child: ColoredBox(
        color: theme.shell.content,
        child: ListenableBuilder(
          listenable: Listenable.merge([controller.aggregate, controller]),
          builder: (context, _) {
            _releaseClosedTabScrolls(controller);
            final state = controller.aggregate.state;
            final tabId = controller.activeAggregateTabId;
            final settingsOpen = controller.aggregateSettingsOpen;
            return DPageSurface(
              border: false,
              borderRadius: WorkspacePanelCorner.borderRadiusOf(context),
              identity: settingsOpen ? 'settings' : tabId,
              framed: !context.isTouch,
              limitContentSize: ContentSettingsScope.limitContentSizeOf(
                context,
              ),
              tabs: controller.forumTabsEnabled || settingsOpen
                  ? _AggregateTabsBar(controller: controller)
                  : null,
              header: settingsOpen
                  ? null
                  : Column(
                      key: const ValueKey('aggregate-page-header'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Topics',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              _AggregateInlineFilters(
                                key: ValueKey(('aggregate-filters', tabId)),
                                controller: controller,
                              ),
                            ],
                          ),
                        ),
                        const DSeparator(
                          key: ValueKey('topic-list-heading-separator'),
                        ),
                      ],
                    ),
              child: settingsOpen
                  ? const ForumSettingsPage(
                      siteUrl: ForumSettingsController.homeSite,
                    )
                  : ContentReadingLane(
                      widthLimit: topicListContentWidth,
                      basePadding: const EdgeInsets.symmetric(
                        horizontal: topicListHorizontalPadding,
                        vertical: 8,
                      ),
                      builder: (context, lane) => CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        key: PageStorageKey(('aggregate-topic-list', tabId)),
                        controller: _scrollFor(tabId),
                        slivers: [
                          if (state.loading && state.topics.isEmpty)
                            const SliverToBoxAdapter(child: SizedBox.shrink())
                          // A forum that failed says nothing about whether the
                          // filters match, so failures take the banner path.
                          else if (state.isEmpty && state.failures.isEmpty)
                            SliverToBoxAdapter(
                              child: _AggregateEmptyState(
                                icon: DIcons.inbox,
                                title: state.includedForums == 0
                                    ? 'No forums selected'
                                    : 'No matching topics',
                                message: '',
                                actionLabel: state.includedForums == 0
                                    ? 'Choose forums'
                                    : 'Refresh',
                                onAction: state.includedForums == 0
                                    ? () => controller.aggregate
                                          .setFiltersCollapsed(false)
                                    : () => unawaited(
                                        controller.refreshAggregate(),
                                      ),
                              ),
                            )
                          else ...[
                            if (state.failures.isNotEmpty)
                              SliverToBoxAdapter(
                                child: _PartialFailureBanner(
                                  failed: state.failures.length,
                                  onRetry: () =>
                                      unawaited(controller.refreshAggregate()),
                                ),
                              ),
                            SliverPadding(
                              padding: lane.padding.copyWith(top: 0),
                              sliver: SliverList.separated(
                                itemCount: state.topics.length,
                                separatorBuilder: (_, _) =>
                                    const TopicListSeparator(),
                                itemBuilder: (_, index) {
                                  final reference = state.topics[index];
                                  return _AggregateTopicRow(
                                    key: ValueKey(
                                      'aggregate-topic-card-${reference.siteUrl}-${reference.topicId}',
                                    ),
                                    reference: reference,
                                  );
                                },
                              ),
                            ),
                            if (state.loadingMore)
                              const SliverToBoxAdapter(
                                child: SizedBox.shrink(),
                              ),
                          ],
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _AggregateInlineFilters extends StatelessWidget {
  const _AggregateInlineFilters({super.key, required this.controller});
  final ShellController controller;

  bool get _hasFilters => controller.instances
      .where((forum) => forum.isConnected)
      .any(
        (forum) =>
            !controller.aggregate.includes(forum) ||
            controller.aggregate.queryFor(forum.url).trim().isNotEmpty,
      );

  @override
  Widget build(BuildContext context) => DPopover(
    open: !controller.aggregate.filtersCollapsed,
    onOpenChange: (open, _) => controller.aggregate.setFiltersCollapsed(!open),
    content: DPopoverContent(
      width: 640,
      align: DPopoverAlign.end,
      semanticLabel: 'Forum filters',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final forum in controller.instances)
            _AggregateForumFilterRow(
              key: ValueKey(forum.url),
              forum: forum,
              controller: controller,
              tabId: controller.activeAggregateTabId,
            ),
        ],
      ),
    ),
    child: DPopoverTrigger(
      builder: (context, trigger) => DButton.iconOnly(
        key: const ValueKey('aggregate-filter-collapse'),
        tooltip: _hasFilters ? 'Edit active filters' : 'Forum filters',
        icon: const DIcon(DNativeIcons.filterLines),
        size: DButtonSize.large,
        variant: _hasFilters
            ? DButtonVariant.primary
            : DButtonVariant.transparentBackground,
        focusNode: trigger.focusNode,
        hasPopup: true,
        expanded: trigger.open,
        onPressed: trigger.toggle,
      ),
    ),
  );
}

class _AggregateForumFilterRow extends StatefulWidget {
  const _AggregateForumFilterRow({
    super.key,
    required this.forum,
    required this.controller,
    required this.tabId,
  });
  final DiscourseInstance forum;
  final ShellController controller;
  final String tabId;
  @override
  State<_AggregateForumFilterRow> createState() =>
      _AggregateForumFilterRowState();
}

class _AggregateForumFilterRowState extends State<_AggregateForumFilterRow> {
  late bool _included;
  late String _query;
  bool _saving = false;
  final _inputKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    final aggregate = widget.controller.aggregate;
    final draft = aggregate.filterDraftFor(widget.forum.url);
    _included = draft?.included ?? aggregate.includes(widget.forum);
    _query = draft?.query ?? aggregate.queryFor(widget.forum.url);
  }

  void _rememberDraft() {
    if (widget.controller.activeAggregateTabId != widget.tabId) return;
    widget.controller.aggregate.setFilterDraft(
      widget.forum.url,
      included: _included,
      query: _query,
    );
  }

  Future<void> _apply() async {
    final controller = widget.controller;
    if (_saving || controller.activeAggregateTabId != widget.tabId) return;
    setState(() => _saving = true);
    try {
      await controller.setAggregateForumFilters(
        includedForums: {
          for (final forum in controller.instances)
            if (forum.isConnected &&
                (forum.url == widget.forum.url
                    ? _included
                    : controller.aggregate.includes(forum)))
              forum.url,
        },
        queries: {
          for (final forum in controller.instances)
            forum.url: forum.url == widget.forum.url
                ? _query
                : controller.aggregate.queryFor(forum.url),
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forum = widget.forum;
    final aggregate = widget.controller.aggregate;
    final dirty =
        _included != aggregate.includes(forum) ||
        _query != aggregate.queryFor(forum.url);
    final enabled = forum.isConnected && !_saving;
    final checkbox = DCheckbox(
      key: ValueKey('aggregate-filter-${forum.url}'),
      value: forum.isConnected && _included,
      title: Text(forum.title),
      onChanged: enabled
          ? (value) {
              setState(() => _included = value ?? false);
              _rememberDraft();
            }
          : null,
    );
    final input = TopicFilterInput(
      key: _inputKey,
      siteUrl: forum.url,
      initialQuery: _query,
      options: aggregate.filterOptionsFor(forum.url),
      categories: widget.controller.filterCategoriesFor(forum.url),
      onSubmitted: (query) async {
        if (mounted) {
          setState(() => _query = query);
          _rememberDraft();
        }
      },
      onChanged: (query) {
        if (mounted) {
          setState(() => _query = query);
          _rememberDraft();
        }
      },
      inputKey: ValueKey('aggregate-query-${forum.url}'),
      clearKey: ValueKey('aggregate-query-clear-${forum.url}'),
      hintText: 'Use forum default',
      padding: EdgeInsets.zero,
      enabled: enabled && _included,
      tokenized: true,
    );
    final apply = DButton(
      key: ValueKey('aggregate-apply-${forum.url}'),
      label: const Text('Apply'),
      variant: DButtonVariant.outline,
      loading: _saving,
      onPressed: enabled && dirty ? _apply : null,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 620
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  checkbox,
                  const SizedBox(height: 12),
                  input,
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: apply,
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 200, child: checkbox),
                  const SizedBox(width: 16),
                  Expanded(child: input),
                  const SizedBox(width: 16),
                  apply,
                ],
              ),
      ),
    );
  }
}

class _AggregateTabsBar extends StatelessWidget {
  const _AggregateTabsBar({required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) {
    final tabs = controller.aggregateTabs;
    return ForumTabsBar(
      key: const ValueKey('aggregate-tabs'),
      forumName: 'Aggregate',
      items: [
        for (var index = 0; index < tabs.length; index++)
          ForumTabItem(
            id: tabs[index].id,
            title: tabs[index].name ?? 'Aggregate ${index + 1}',
            icon: DIcons.circleNodes,
          ),
        if (controller.aggregateSettingsOpen)
          const ForumTabItem(
            id: 'settings',
            title: 'Settings',
            icon: DIcons.gear,
          ),
      ],
      recentlyClosedItems: [
        for (final tab in controller.recentlyClosedAggregateTabs)
          ForumTabItem(
            id: tab.id,
            title: tab.name ?? 'Aggregate tab',
            icon: DIcons.circleNodes,
          ),
      ],
      selectedId: controller.aggregateSettingsOpen
          ? 'settings'
          : controller.activeAggregateTabId,
      onAdd: controller.canCreateAggregateTab
          ? controller.createAggregateTab
          : null,
      onSelect: (id) => id == 'settings'
          ? controller.openCurrentSettings()
          : controller.selectAggregateTab(id),
      onClose: (id) => id == 'settings'
          ? controller.closeAggregateSettings()
          : controller.closeAggregateTab(id),
      onReorder: (id, index) {
        if (id != 'settings') controller.moveAggregateTab(id, index);
      },
      onRename: (id, name) {
        if (id != 'settings') controller.renameAggregateTab(id, name);
      },
      onCloseOthers: (id) {
        if (id != 'settings') controller.closeOtherAggregateTabs(id);
      },
      onReopen: controller.canCreateAggregateTab
          ? (id) => controller.reopenClosedAggregateTab(id)
          : null,
    );
  }
}

class _AggregateTopicRow extends StatelessWidget {
  const _AggregateTopicRow({super.key, required this.reference});

  final AggregateTopicRef reference;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final forum = controller.instanceFor(reference.siteUrl);
    if (forum == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Topic?>(
      valueListenable: controller.topicRef(
        reference.siteUrl,
        reference.topicId,
      ),
      builder: (context, topic, _) {
        if (topic == null) return const SizedBox.shrink();
        return TopicListRow(
          topic: topic,
          forum: forum,
          itemVariant: DItemVariant.standard,
          onTap: () {
            final result = controller.openAggregateTopic(
              reference.siteUrl,
              reference.topicId,
            );
            final message = switch (result) {
              AggregateTopicOpenResult.opened => null,
              AggregateTopicOpenResult.tabLimitReached =>
                'This forum already has 20 tabs. Close one and try again.',
              AggregateTopicOpenResult.unavailable =>
                'That topic is no longer available.',
            };
            if (message != null) {
              DToast.show(context, message);
            }
          },
        );
      },
    );
  }
}

class _PartialFailureBanner extends StatelessWidget {
  const _PartialFailureBanner({required this.failed, required this.onRetry});
  final int failed;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => DAlert(
    variant: DAlertVariant.destructive,
    icon: const DIcon(DIcons.triangleExclamation),
    description: DAlertDescription(
      child: Text(
        '$failed ${failed == 1 ? 'forum could' : 'forums could'} not be refreshed.',
      ),
    ),
    action: DAlertAction(
      child: DButton(
        label: const Text('Retry'),
        onPressed: onRetry,
        variant: DButtonVariant.link,
      ),
    ),
  );
}

class _AggregateEmptyState extends StatelessWidget {
  const _AggregateEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final DIconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
              DEmptyTitle(title),
              DEmptyDescription(message),
            ],
          ),
          DEmptyContent(
            children: [
              DButton(
                label: Text(actionLabel),
                onPressed: onAction,
                variant: DButtonVariant.primary,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
