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
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'topic_filter_input.dart';
import 'topic_list_view.dart';

abstract final class _AggregateTheme {
  static const purple = Color(0xFF7B5FE2);
  static const yellow = Color(0xFFF8DE6A);
  static const orange = Color(0xFFF15D3A);
  static const heroStart = Color(0xFF3B285E);
  static const heroEnd = Color(0xFF2B1C47);

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
          if (extension is! ShellColors && extension is! DiscourseColors)
            extension,
        shell,
        discourse,
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
    final theme = _AggregateTheme.from(Theme.of(context));

    return Theme(
      data: theme,
      child: ColoredBox(
        color: theme.shell.content,
        child: ListenableBuilder(
          listenable: controller.aggregate,
          builder: (context, _) {
            final state = controller.aggregate.state;
            final activeTabId = controller.activeAggregateTabId;
            return Column(
              children: [
                _AggregateHeader(
                  state: state,
                  onFilter: () => _showForumFilter(context, controller),
                  onRefresh: state.loading || state.refreshing
                      ? null
                      : () => unawaited(controller.refreshAggregate()),
                ),
                if (controller.forumTabsEnabled)
                  _AggregateTabsBar(controller: controller),
                if (state.refreshing)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(child: _body(context, controller, state, activeTabId)),
              ],
            );
          },
        ),
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount:
            state.topics.length +
            (state.failures.isNotEmpty ? 1 : 0) +
            (state.loadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 9),
        itemBuilder: (context, index) {
          if (state.failures.isNotEmpty) {
            if (index == 0) {
              return _AggregateCard(
                child: _PartialFailureBanner(
                  failed: state.failures.length,
                  onRetry: () => unawaited(controller.refreshAggregate()),
                ),
              );
            }
            index--;
          }
          if (index >= state.topics.length) {
            return _AggregateCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: AdaptiveActivityIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          }
          final reference = state.topics[index];
          return _AggregateCard(
            key: ValueKey(
              'aggregate-topic-card-${reference.siteUrl}-${reference.topicId}',
            ),
            child: _AggregateTopicRow(
              key: ValueKey(reference),
              reference: reference,
            ),
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
          ForumTabItem(
            id: tabs[index].id,
            title: tabs[index].name ?? 'Aggregate ${index + 1}',
          ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        return Container(
          key: const ValueKey('aggregate-hero'),
          height: compact ? 126 : 142,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_AggregateTheme.heroStart, _AggregateTheme.heroEnd],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: compact ? 54 : 230,
                top: -64,
                child: const _AggregateHeroOrb(
                  size: 142,
                  color: Color(0x287B5FE2),
                ),
              ),
              const Positioned(
                right: -42,
                bottom: -76,
                child: _AggregateHeroOrb(size: 172, color: Color(0x20F8DE6A)),
              ),
              if (!compact)
                const Positioned(
                  right: 262,
                  bottom: 18,
                  child: _AggregateHeroGlyph(),
                ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 28,
                  vertical: compact ? 15 : 18,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DIcon(
                                  DIcons.layerGroup,
                                  size: 12,
                                  color: _AggregateTheme.yellow,
                                ),
                                SizedBox(width: 7),
                                Text(
                                  'AGGREGATE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            compact
                                ? 'Every forum. One feed.'
                                : 'Every forum. One shared feed.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontSize: compact ? 22 : 28,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.70),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 28),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AggregateHeroAction(
                          key: const ValueKey('aggregate-filter-button'),
                          icon: DIcons.filter,
                          label: 'Filters',
                          tooltip: 'Configure forum filters',
                          showLabel: !compact,
                          emphasized: true,
                          onPressed: onFilter,
                        ),
                        const SizedBox(width: 8),
                        _AggregateHeroAction(
                          key: const ValueKey('aggregate-refresh-button'),
                          icon: DIcons.arrowsRotate,
                          label: 'Refresh',
                          tooltip: 'Refresh',
                          showLabel: !compact,
                          onPressed: onRefresh,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AggregateHeroOrb extends StatelessWidget {
  const _AggregateHeroOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _AggregateHeroGlyph extends StatelessWidget {
  const _AggregateHeroGlyph();

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: _AggregateTheme.orange,
      borderRadius: BorderRadius.circular(9),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: const Center(
      child: DIcon(DIcons.comments, size: 14, color: Colors.white),
    ),
  );
}

class _AggregateHeroAction extends StatelessWidget {
  const _AggregateHeroAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.showLabel,
    required this.onPressed,
    this.emphasized = false,
  });

  final DIconData icon;
  final String label;
  final String tooltip;
  final bool showLabel;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final foreground = onPressed == null
        ? Colors.white.withValues(alpha: 0.42)
        : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        child: Material(
          color: emphasized
              ? _AggregateTheme.purple
              : Colors.white.withValues(alpha: 0.08),
          shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: showLabel ? 16 : 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DIcon(icon, size: 16, color: foreground),
                    if (showLabel) ...[
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AggregateCard extends StatelessWidget {
  const _AggregateCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: theme.shell.floating,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.shell.divider),
      ),
      elevation: isDark ? 0 : 1,
      shadowColor: const Color(0x1A2B1C47),
      child: child,
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
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(message)));
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
          constraints: const BoxConstraints(maxWidth: 460),
          child: _AggregateCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 34, 36, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: DIcon(
                        icon,
                        size: 28,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.35,
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
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: onAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(actionLabel),
                    ),
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
