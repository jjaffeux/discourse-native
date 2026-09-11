import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'content_reading_lane.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_list_filter_bar.dart';
import 'topic_list_filter_sheet.dart';
import 'topic_list_layout.dart';
import 'topic_list_view.dart';

typedef _TopicListNavigationSnapshot = ({
  TopicListMode? mode,
  bool signedIn,
  bool unifiedNew,
  int allCount,
  int topicCount,
  int replyCount,
  String? siteUrl,
  ContentRoute? route,
  List<TopicCategory> categories,
  List<SidebarTag> tags,
  bool taggingEnabled,
  _TopicListFilterOwner filterOwner,
});

typedef _TopicListFilterOwner = ({
  ShellController controller,
  ShellRootMode rootMode,
  String? siteUrl,
  String? accountIdentity,
  Object? session,
  String? tabId,
  String? routeId,
  String? feedPath,
});

_TopicListFilterOwner _filterOwner(ShellController controller) {
  final siteUrl = controller.currentInstance?.url;
  final route = controller.topicListContent ?? controller.currentContent;
  return (
    controller: controller,
    rootMode: controller.rootMode,
    siteUrl: siteUrl,
    accountIdentity: controller.currentAccountIdentity,
    session: siteUrl == null
        ? null
        : controller.lifecycle.capture(siteUrl).session,
    tabId: controller.activeTabId,
    routeId: route?.id,
    feedPath: route?.feedPath,
  );
}

typedef TopicListHeadingBuilder =
    Widget Function(BuildContext context, Widget? navigation);

class TopicListNavigation extends StatelessWidget {
  const TopicListNavigation({
    super.key,
    required this.child,
    this.trailing,
    this.headingBuilder,
    this.stacked = false,
    this.keepTopicOpen = false,
  });

  final Widget child;
  final Widget? trailing;
  final TopicListHeadingBuilder? headingBuilder;
  final bool stacked;
  final bool keepTopicOpen;

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<_TopicListNavigationSnapshot>(
    select: (controller) {
      final counts = controller.topicListNewCounts;
      final siteUrl = controller.currentInstance?.url;
      final route = controller.topicListContent ?? controller.currentContent;
      final showsFilters = route?.isTopicListFilter == true;
      return (
        mode: controller.currentTopicListMode,
        signedIn: controller.currentInstance?.user != null,
        unifiedNew: controller.currentInstance?.user?.unifiedNewEnabled == true,
        allCount: counts.all,
        topicCount: counts.topics,
        replyCount: counts.replies,
        siteUrl: siteUrl,
        route: route,
        filterOwner: _filterOwner(controller),
        categories: showsFilters && siteUrl != null
            ? controller.filterCategoriesFor(siteUrl)
            : const <TopicCategory>[],
        tags: showsFilters && siteUrl != null
            ? controller.topicListFilterTagsFor(siteUrl)
            : const <SidebarTag>[],
        taggingEnabled:
            showsFilters &&
            siteUrl != null &&
            controller.siteConfigFor(siteUrl).taggingEnabled,
      );
    },
    builder: (context, state, _) {
      final showsTabs = state.mode != null;
      final showsFilters =
          state.siteUrl != null && state.route?.isTopicListFilter == true;
      if (!showsTabs && !showsFilters && trailing == null) {
        return child;
      }
      return Column(
        children: [
          _TopicListNavigationControls(
            state: state,
            showsTabs: showsTabs,
            showsFilters: showsFilters,
            trailing: trailing,
            headingBuilder: headingBuilder,
            stacked: stacked,
            keepTopicOpen: keepTopicOpen,
          ),
          Expanded(child: child),
        ],
      );
    },
  );
}

class _TopicListNavigationControls extends StatelessWidget {
  const _TopicListNavigationControls({
    required this.state,
    required this.showsTabs,
    required this.showsFilters,
    required this.trailing,
    required this.headingBuilder,
    required this.stacked,
    required this.keepTopicOpen,
  });

  final _TopicListNavigationSnapshot state;
  final bool showsTabs;
  final bool showsFilters;
  final Widget? trailing;
  final TopicListHeadingBuilder? headingBuilder;
  final bool stacked;
  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final mode = state.mode ?? TopicListMode.latest;
    void selectMode(TopicListMode value) => unawaited(
      controller.selectTopicListMode(value, keepTopicOpen: keepTopicOpen),
    );
    final navigation = DTabs<TopicListMode>.controlled(
      value: mode.isNew
          ? TopicListMode.newActivity
          : mode.isTop
          ? TopicListMode.topYearly
          : mode,
      onChanged: (value) {
        if (value != null) {
          selectMode(value.isTop ? controller.defaultTopTopicListMode : value);
        }
      },
      children: [
        DTabList<TopicListMode>(
          key: const ValueKey('topic-list-feed-tabs'),
          variant: DTabListVariant.line,
          children: [
            const DTabTrigger(
              key: ValueKey('topic-list-latest'),
              value: TopicListMode.latest,
              child: Text('Recent'),
            ),
            if (state.signedIn)
              DTabTrigger(
                key: const ValueKey('topic-list-new'),
                value: TopicListMode.newActivity,
                semanticLabel: state.allCount > 0
                    ? 'New, ${state.allCount}'
                    : 'New',
                child: const ExcludeSemantics(child: Text('New')),
              ),
            const DTabTrigger(
              key: ValueKey('topic-list-top'),
              value: TopicListMode.topYearly,
              child: Text('Top'),
            ),
            const DTabTrigger(
              key: ValueKey('topic-list-popular'),
              value: TopicListMode.popular,
              child: Text('Trending'),
            ),
          ],
        ),
      ],
    );
    final Widget? contextual;
    if (showsTabs && mode.isNew && state.unifiedNew) {
      contextual = DTabs<TopicListMode>.controlled(
        value: mode,
        onChanged: (value) {
          if (value != null) selectMode(value);
        },
        children: [
          DTabList<TopicListMode>(
            key: const ValueKey('topic-list-new-segments'),
            children: [
              const DTabTrigger(
                key: ValueKey('topic-list-new-all'),
                value: TopicListMode.newActivity,
                child: Text('All'),
              ),
              for (final tab in [
                (
                  key: 'topics',
                  label: 'Topics',
                  value: TopicListMode.newTopics,
                  count: state.topicCount,
                ),
                (
                  key: 'replies',
                  label: 'Replies',
                  value: TopicListMode.newReplies,
                  count: state.replyCount,
                ),
              ])
                DTabTrigger(
                  key: ValueKey('topic-list-new-${tab.key}'),
                  value: tab.value,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tab.label),
                      if (tab.count > 0) ...[
                        const SizedBox(width: 6),
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          child: Text('${tab.count}'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    } else if (showsTabs && mode.topPeriod != null) {
      contextual = Align(
        key: const ValueKey('topic-list-top-period-segment'),
        alignment: AlignmentDirectional.centerStart,
        child: DSelect<TopPeriod>(
          key: const ValueKey('topic-list-top-period'),
          value: mode.topPeriod,
          semanticLabel: 'Top period',
          entries: [
            for (final period in TopPeriod.values)
              DSelectItem(
                value: period,
                textValue: period.label,
                child: Text(
                  period.label,
                  key: ValueKey('topic-list-top-period-${period.queryValue}'),
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) selectMode(TopicListMode.top(value));
          },
        ),
      );
    } else {
      contextual = null;
    }

    return Semantics(
      key: const ValueKey('topic-list-navigation'),
      container: true,
      label: 'Topic lists',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lane = ContentReadingLane.geometryFor(
            context,
            availableWidth: constraints.maxWidth,
            widthLimit: topicListContentWidth,
          );
          // App zoom expands the lane; system text scaling also needs room.
          final effectiveWidth =
              ContentReadingLane.breakpointWidthOf(context, lane.width) /
              MediaQuery.textScalerOf(context).scale(1);
          final wide = effectiveWidth >= 760;
          final heading = headingBuilder;
          Widget inset(Widget child) => ContentReadingLaneBox(
            widthLimit: topicListContentWidth,
            padding: const EdgeInsets.symmetric(
              horizontal: topicListHorizontalPadding,
            ),
            child: child,
          );
          Widget primary() => ConstrainedBox(
            key: const ValueKey('topic-list-primary-row'),
            constraints: const BoxConstraints(minHeight: 38),
            child: Row(
              children: [
                if (showsTabs) Expanded(child: navigation) else const Spacer(),
                if (trailing != null) ...[
                  const SizedBox(width: DSpacing.sm),
                  trailing!,
                ],
              ],
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (heading != null)
                KeyedSubtree(
                  key: wide ? const ValueKey('topic-list-primary-row') : null,
                  child: heading(
                    context,
                    wide && showsTabs ? navigation : null,
                  ),
                ),
              if (heading == null || !wide) inset(primary()),
              if (contextual != null || showsFilters)
                inset(
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: Builder(
                      builder: (filterContext) {
                        final lease = state.siteUrl == null
                            ? null
                            : controller.lifecycle.capture(state.siteUrl!);
                        bool ownsFeed() =>
                            filterContext.mounted &&
                            lease?.isCurrent == true &&
                            _filterOwner(controller) == state.filterOwner;
                        Future<List<TopicFilterLookupValue>> searchTags(
                          String query,
                        ) async {
                          if (!ownsFeed()) return const [];
                          final result = await controller.searchFilterTags(
                            siteUrl: state.siteUrl!,
                            term: query,
                          );
                          return ownsFeed() ? result : const [];
                        }

                        final Widget? filters = !showsFilters
                            ? null
                            : wide
                            ? TopicListFilterBar(
                                key: ValueKey(state.filterOwner),
                                inline: true,
                                wrap: true,
                                wrapAlignment: WrapAlignment.end,
                                siteUrl: state.siteUrl!,
                                categories: state.categories,
                                knownTags: state.tags,
                                selectedCategoryId: state.route!.categoryId,
                                selectedTagName: state.route!.tagName,
                                selectedTagNames: stacked
                                    ? state.route!.tagNames
                                    : null,
                                taggingEnabled: state.taggingEnabled,
                                searchTags: searchTags,
                                onCategorySelected: (category) {
                                  if (ownsFeed()) {
                                    controller.selectTopicListCategory(
                                      category,
                                      keepTopicOpen: keepTopicOpen,
                                    );
                                  }
                                },
                                onTagSelected: (tag) {
                                  if (ownsFeed()) {
                                    controller.selectTopicListTag(
                                      tag,
                                      keepTopicOpen: keepTopicOpen,
                                    );
                                  }
                                },
                                onTagsSelected: stacked
                                    ? (tags) {
                                        if (ownsFeed()) {
                                          controller.selectTopicListTags(
                                            tags,
                                            keepTopicOpen: keepTopicOpen,
                                          );
                                        }
                                      }
                                    : null,
                              )
                            : TopicListFilterSheet(
                                key: ValueKey(state.filterOwner),
                                siteUrl: state.siteUrl!,
                                multiple: stacked,
                                categories: state.categories,
                                knownTags: state.tags,
                                categoryId: state.route!.categoryId,
                                tags: state.route!.tagNames,
                                taggingEnabled: state.taggingEnabled,
                                searchTags: searchTags,
                                showLabel: effectiveWidth >= 390,
                                onApply: (selection) {
                                  if (ownsFeed()) {
                                    controller.selectTopicListFilters(
                                      category: selection.category,
                                      tags: selection.tags,
                                      keepTopicOpen: keepTopicOpen,
                                    );
                                  }
                                },
                              );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              key: const ValueKey('topic-list-refinement-row'),
                              children: [
                                if (contextual != null)
                                  Expanded(child: contextual)
                                else if (wide)
                                  const Spacer(),
                                if (contextual != null && filters != null)
                                  const SizedBox(width: DSpacing.sm),
                                if (filters != null)
                                  if (wide)
                                    Flexible(
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: filters,
                                      ),
                                    )
                                  else
                                    filters,
                              ],
                            ),
                            if (!wide &&
                                showsFilters &&
                                (state.route!.categoryId != null ||
                                    state.route!.tagNames.isNotEmpty))
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: DSpacing.sm,
                                ),
                                child: Wrap(
                                  spacing: DSpacing.xs,
                                  runSpacing: DSpacing.xs,
                                  children: [
                                    if (state.route!.categoryId
                                        case final categoryId?)
                                      _FilterChip(
                                        label:
                                            state.categories
                                                .where(
                                                  (c) => c.id == categoryId,
                                                )
                                                .firstOrNull
                                                ?.name ??
                                            'Category',
                                        semanticLabel: 'Remove category filter',
                                        onPressed: () {
                                          if (ownsFeed()) {
                                            controller.selectTopicListCategory(
                                              null,
                                              keepTopicOpen: keepTopicOpen,
                                            );
                                          }
                                        },
                                      ),
                                    for (final tag in state.route!.tagNames)
                                      _FilterChip(
                                        label: tag,
                                        semanticLabel: 'Remove tag $tag',
                                        onPressed: () {
                                          if (ownsFeed()) {
                                            controller.selectTopicListTags(
                                              state.route!.tagNames
                                                  .where((t) => t != tag)
                                                  .toList(),
                                              keepTopicOpen: keepTopicOpen,
                                            );
                                          }
                                        },
                                      ),
                                    DButton(
                                      key: const ValueKey(
                                        'topic-list-clear-filters',
                                      ),
                                      variant: DButtonVariant.ghost,
                                      size: DButtonSize.small,
                                      label: const Text('Clear all'),
                                      onPressed: () {
                                        if (ownsFeed()) {
                                          controller.selectTopicListFilters(
                                            category: null,
                                            tags: const [],
                                            keepTopicOpen: keepTopicOpen,
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              if (stacked) const TopicListHeader(),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DButton(
    variant: DButtonVariant.outline,
    size: DButtonSize.small,
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    icon: const DIcon(DIcons.xmark, size: 12),
    iconPosition: DButtonIconPosition.end,
    semanticLabel: semanticLabel,
    onPressed: onPressed,
  );
}
