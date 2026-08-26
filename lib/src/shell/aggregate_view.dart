import 'dart:async';

import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'aggregate_feed_controller.dart';
import 'forum_tabs_bar.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'topic_filter_input.dart';
import 'topic_list_view.dart';

/// The full-width, cross-forum stream selected from the top of the rail.
class AggregateView extends StatefulWidget {
  const AggregateView({super.key});

  @override
  State<AggregateView> createState() => _AggregateViewState();
}

class _AggregateViewState extends State<AggregateView> {
  final Map<String, ScrollController> _scrolls = {};
  ShellController? _controller;

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
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.shell.content,
      child: ListenableBuilder(
        listenable: controller.aggregate,
        builder: (context, _) {
          final state = controller.aggregate.state;
          final activeTabId = controller.activeAggregateTabId;
          return Column(
            children: [
              if (controller.forumTabsEnabled)
                _AggregateTabsBar(controller: controller),
              _AggregateHeader(
                state: state,
                onFilter: () => _showForumFilter(context, controller),
                onRefresh: state.loading || state.refreshing
                    ? null
                    : () => unawaited(controller.refreshAggregate()),
              ),
              if (state.refreshing) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _body(context, controller, state, activeTabId)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ShellController controller,
    AggregateFeedState state,
    String tabId,
  ) {
    if (state.loading && state.topics.isEmpty) {
      return Center(
        child: AdaptiveActivityIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (state.isEmpty) {
      final noForums = state.includedForums == 0;
      return _AggregateEmptyState(
        icon: noForums ? DIcons.filter : DIcons.inbox,
        title: noForums ? 'No forums selected' : 'No matching topics',
        message: noForums
            ? 'Choose which connected forums should contribute topics.'
            : 'There are no topics matching your saved forum filters.',
        actionLabel: noForums ? 'Choose forums' : 'Refresh',
        onAction: noForums
            ? () => _showForumFilter(context, controller)
            : () => unawaited(controller.refreshAggregate()),
      );
    }

    return RefreshIndicator.adaptive(
      onRefresh: controller.refreshAggregate,
      child: ListView.separated(
        key: PageStorageKey(('aggregate-topic-list', tabId)),
        controller: _scrollFor(tabId),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount:
            state.topics.length +
            (state.failures.isNotEmpty ? 1 : 0) +
            (state.loadingMore ? 1 : 0),
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: Theme.of(context).shell.divider),
        itemBuilder: (context, index) {
          if (state.failures.isNotEmpty) {
            if (index == 0) {
              return _PartialFailureBanner(
                failed: state.failures.length,
                onRetry: () => unawaited(controller.refreshAggregate()),
              );
            }
            index--;
          }
          if (index >= state.topics.length) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: AdaptiveActivityIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }
          return _AggregateTopicRow(
            key: ValueKey(state.topics[index]),
            reference: state.topics[index],
          );
        },
      ),
    );
  }

  Future<void> _showForumFilter(
    BuildContext context,
    ShellController controller,
  ) async {
    final forums = controller.instances;
    var selected = {
      for (final forum in forums)
        if (controller.aggregate.includes(forum)) forum.url,
    };
    final queries = {
      for (final forum in forums)
        forum.url: controller.aggregate.queryFor(forum.url),
    };
    final applied =
        await showShellSheet<
          ({Set<String> includedForums, Map<String, String> queries})
        >(
          context: context,
          title: 'Aggregate filters',
          dialogOnDesktop: true,
          footerBuilder: (footerContext) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(footerContext).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(
                  footerContext,
                ).pop((includedForums: {...selected}, queries: {...queries})),
                child: const Text('Save filters'),
              ),
            ],
          ),
          builder: (_) => StatefulBuilder(
            builder: (context, setSheetState) {
              final connected = forums
                  .where((forum) => forum.isConnected)
                  .toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Each included forum uses its own Discourse topic filter. '
                    'Leave a filter empty to use that forum’s default list.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: connected.isEmpty
                            ? null
                            : () => setSheetState(
                                () => selected = {
                                  for (final forum in connected) forum.url,
                                },
                              ),
                        child: const Text('All'),
                      ),
                      TextButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => setSheetState(() => selected = {}),
                        child: const Text('None'),
                      ),
                    ],
                  ),
                  for (final forum in forums)
                    Column(
                      key: ValueKey('aggregate-filter-row-${forum.url}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CheckboxListTile(
                          key: ValueKey('aggregate-filter-${forum.url}'),
                          contentPadding: EdgeInsets.zero,
                          value:
                              forum.isConnected && selected.contains(forum.url),
                          onChanged: forum.isConnected
                              ? (checked) => setSheetState(() {
                                  selected = {...selected};
                                  if (checked ?? false) {
                                    selected.add(forum.url);
                                  } else {
                                    selected.remove(forum.url);
                                  }
                                })
                              : null,
                          title: Text(forum.title),
                          subtitle: Text(
                            forum.isConnected
                                ? forum.host
                                : 'Sign in to include',
                          ),
                        ),
                        TopicFilterInput(
                          key: ValueKey('aggregate-filter-editor-${forum.url}'),
                          siteUrl: forum.url,
                          initialQuery: queries[forum.url]!,
                          options: controller.aggregate.filterOptionsFor(
                            forum.url,
                          ),
                          categories: controller.filterCategoriesFor(forum.url),
                          onSubmitted: (query) async {
                            queries[forum.url] = query;
                          },
                          onChanged: (query) => queries[forum.url] = query,
                          inputKey: ValueKey('aggregate-query-${forum.url}'),
                          clearKey: ValueKey(
                            'aggregate-query-clear-${forum.url}',
                          ),
                          hintText: 'Filter this forum',
                          padding: const EdgeInsets.fromLTRB(16, 0, 0, 12),
                          enabled:
                              forum.isConnected && selected.contains(forum.url),
                          preferSuggestionsAbove: true,
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        );
    if (applied == null || !context.mounted) return;
    if (!identical(ShellScope.read(context), controller)) return;
    await controller.setAggregateForumFilters(
      includedForums: applied.includedForums,
      queries: applied.queries,
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
          ForumTabItem(id: tabs[index].id, title: 'Aggregate ${index + 1}'),
      ],
      selectedId: controller.activeAggregateTabId,
      onAdd: controller.canCreateAggregateTab
          ? controller.createAggregateTab
          : null,
      onSelect: controller.selectAggregateTab,
      onClose: controller.closeAggregateTab,
      onReorder: controller.moveAggregateTab,
    );
  }
}

class _AggregateHeader extends StatelessWidget {
  const _AggregateHeader({
    required this.state,
    required this.onFilter,
    required this.onRefresh,
  });

  final AggregateFeedState state;
  final VoidCallback onFilter;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = state.loaded
        ? '${state.topics.length} ${state.topics.length == 1 ? 'topic' : 'topics'} '
              'from ${state.includedForums} '
              '${state.includedForums == 1 ? 'forum' : 'forums'}'
        : 'Topics from your saved forum filters';
    return Container(
      height: shellHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: Row(
        children: [
          const DIcon(DIcons.layerGroup, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aggregate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('aggregate-filter-button'),
            onPressed: onFilter,
            tooltip: 'Configure forum filters',
            icon: const DIcon(DIcons.filter, size: 17),
          ),
          IconButton(
            key: const ValueKey('aggregate-refresh-button'),
            onPressed: onRefresh,
            tooltip: 'Refresh',
            icon: const DIcon(DIcons.arrowsRotate, size: 17),
          ),
        ],
      ),
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
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text(message)));
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
      child: ListTile(
        leading: DIcon(
          DIcons.triangleExclamation,
          color: theme.colorScheme.onErrorContainer,
          size: 18,
        ),
        title: Text(
          '$failed ${failed == 1 ? 'forum could' : 'forums could'} not be refreshed.',
        ),
        trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DIcon(icon, size: 36, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
