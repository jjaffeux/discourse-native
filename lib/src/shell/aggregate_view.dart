import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/discourse_instance.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'aggregate_feed_controller.dart';
import 'content_reading_lane.dart';
import 'forum_tabs_bar.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_filter_input.dart';
import 'topic_list_view.dart';

abstract final class _AggregateTheme {
  static const purple = Color(0xFF7B5FE2);
  static const yellow = Color(0xFFF8DE6A);
  static const orange = Color(0xFFF15D3A);

  static ThemeData from(ThemeData base) {
    final isDark = base.brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF9F8FC) : const Color(0xFF333638);
    final muted = isDark ? const Color(0xFFC8C0D3) : const Color(0xFF6A6672);
    final canvas = isDark ? const Color(0xFF17131F) : const Color(0xFFF9F8FC);
    final card = isDark ? const Color(0xFF211B2B) : Colors.white;
    final tabs = isDark ? const Color(0xFF1D1726) : const Color(0xFFF1EDF9);
    final divider = isDark ? const Color(0xFF3C3149) : const Color(0xFFE5DEEF);
    final hover = isDark ? const Color(0xFF2D2538) : const Color(0xFFF2EDFC);
    final accent = isDark ? const Color(0xFF9B85EF) : purple;
    final accentSoft = isDark
        ? const Color(0xFF392F50)
        : const Color(0xFFE9E2FF);

    final shell = base.shell.copyWith(
      sidebar: tabs,
      content: canvas,
      panel: card,
      divider: divider,
      floating: card,
      hover: hover,
      selected: accentSoft,
      selectedForeground: ink,
      marker: muted,
      mention: accentSoft,
    );
    final discourse = base.discourse.copyWith(
      unreadIndicator: accent,
      primaryLowMid: muted.withValues(alpha: 0.58),
      primaryHigh: muted,
      whisper: muted,
      primaryVeryHigh: ink,
    );
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: accentSoft,
      onPrimaryContainer: ink,
      secondary: orange,
      onSecondary: Colors.white,
      secondaryContainer: orange.withValues(alpha: 0.16),
      onSecondaryContainer: ink,
      tertiary: yellow,
      onTertiary: const Color(0xFF382F10),
      tertiaryContainer: yellow.withValues(alpha: 0.22),
      onTertiaryContainer: ink,
      surface: canvas,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: canvas,
      surfaceContainerLow: tabs,
      surfaceContainer: card,
      surfaceContainerHigh: card,
      surfaceContainerHighest: card,
      outline: divider,
      outlineVariant: divider,
      surfaceTint: accent,
    );
    final textTheme = base.textTheme.apply(bodyColor: ink, displayColor: ink);

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: canvas,
      hoverColor: hover,
      extensions: [
        for (final extension in base.extensions.values)
          if (extension is! ShellColors &&
              extension is! DiscourseColors &&
              extension is! DiscourseButtonTheme &&
              extension is! DTokens)
            extension,
        shell,
        discourse,
        DTokens(
          colors: scheme,
          background: canvas,
          surface: card,
          muted: tabs,
          border: divider,
          hover: hover,
          selected: accentSoft,
          selectedForeground: ink,
        ),
        DiscourseButtonTheme.fromColors(
          scheme,
          borderRadius: 999,
          hover: hover,
          success: discourse.success,
        ),
      ],
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class AggregateView extends StatefulWidget {
  const AggregateView({super.key});

  @override
  State<AggregateView> createState() => AggregateViewState();
}

class AggregateViewState extends State<AggregateView> {
  final Map<String, ScrollController> _scrolls = {};
  ShellController? _controller;
  bool _releaseScheduled = false;

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
    if (scroll.position.extentAfter < 640) {
      unawaited(controller.aggregate.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    _controller = controller;
    final theme = _AggregateTheme.from(Theme.of(context));
    return Theme(
      data: theme,
      child: ColoredBox(
        color: theme.shell.content,
        child: ListenableBuilder(
          listenable: controller.aggregate,
          builder: (context, _) {
            _releaseClosedTabScrolls(controller);
            final state = controller.aggregate.state;
            final tabId = controller.activeAggregateTabId;
            return Column(
              children: [
                if (controller.forumTabsEnabled)
                  _AggregateTabsBar(controller: controller),
                const _AggregateHeader(),
                Expanded(
                  child: ContentReadingLane(
                    basePadding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    builder: (context, lane) => RefreshIndicator.adaptive(
                      onRefresh: controller.refreshAggregate,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        key: PageStorageKey(('aggregate-topic-list', tabId)),
                        controller: _scrollFor(tabId),
                        slivers: [
                          SliverPadding(
                            padding: lane.padding,
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: DButton(
                                      key: const ValueKey(
                                        'aggregate-refresh-button',
                                      ),
                                      label: const Text('Refresh'),
                                      loadingLabel: const Text('Refreshing…'),
                                      icon: const DIcon(
                                        DIcons.arrowsRotate,
                                        size: 16,
                                      ),
                                      variant: DButtonVariant.outline,
                                      loading:
                                          state.loading || state.refreshing,
                                      onPressed:
                                          state.loading || state.refreshing
                                          ? null
                                          : () => unawaited(
                                              controller.refreshAggregate(),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _AggregateInlineFilters(
                                    key: ValueKey(('aggregate-filters', tabId)),
                                    controller: controller,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (state.loading && state.topics.isEmpty)
                            const SliverToBoxAdapter(
                              child: Center(child: DSpinner()),
                            )
                          else if (state.isEmpty)
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
                                    const DSeparator(space: 1),
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
                                child: Center(child: DSpinner()),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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

  @override
  Widget build(BuildContext context) => DCard(
    spacing: 0,
    child: DCollapsible(
      open: !controller.aggregate.filtersCollapsed,
      onOpenChange: (open) => controller.aggregate.setFiltersCollapsed(!open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DCollapsibleTrigger(
              key: const ValueKey('aggregate-filter-collapse'),
              child: Row(
                children: [
                  DIcon(
                    controller.aggregate.filtersCollapsed
                        ? DIcons.chevronRight
                        : DIcons.chevronDown,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Text('Forum filters'),
                ],
              ),
            ),
          ),
          DCollapsibleContent(
            keepMounted: true,
            child: Column(
              children: [
                for (final forum in controller.instances) ...[
                  const DSeparator(space: 1),
                  _AggregateForumFilterRow(
                    key: ValueKey(forum.url),
                    forum: forum,
                    controller: controller,
                    tabId: controller.activeAggregateTabId,
                  ),
                ],
              ],
            ),
          ),
        ],
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
          ),
      ],
      recentlyClosedItems: [
        for (final tab in controller.recentlyClosedAggregateTabs)
          ForumTabItem(id: tab.id, title: tab.name ?? 'Aggregate tab'),
      ],
      selectedId: controller.activeAggregateTabId,
      onAdd: controller.canCreateAggregateTab
          ? controller.createAggregateTab
          : null,
      onSelect: controller.selectAggregateTab,
      onClose: controller.closeAggregateTab,
      onReorder: controller.moveAggregateTab,
      onRename: controller.renameAggregateTab,
      onCloseOthers: controller.closeOtherAggregateTabs,
      onReopen: controller.canCreateAggregateTab
          ? (id) => controller.reopenClosedAggregateTab(id)
          : null,
    );
  }
}

class _AggregateHeader extends StatelessWidget {
  const _AggregateHeader();
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('aggregate-hero'),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: Row(
      children: [
        Text('Discourse', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        const DBadge(variant: DBadgeVariant.outline, child: Text('alpha')),
      ],
    ),
  );
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
