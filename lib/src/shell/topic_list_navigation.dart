import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import 'content_reading_lane.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_list_filter_bar.dart';
import 'topic_list_layout.dart';
import 'topic_list_search.dart';

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
          size: DControlSize.small,
          variant: DTabListVariant.line,
          children: [
            const DTabTrigger(
              key: ValueKey('topic-list-latest'),
              value: TopicListMode.latest,
              child: Text('Latest'),
            ),
            if (state.signedIn) ...[
              const DTabTrigger(
                key: ValueKey('topic-list-unread'),
                value: TopicListMode.unread,
                child: Text('Unread'),
              ),
              const DTabTrigger(
                key: ValueKey('topic-list-new'),
                value: TopicListMode.newActivity,
                child: Text('New'),
              ),
            ],
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
    Widget? contextualFor(bool wide) {
      if (showsTabs && mode.isNew && state.unifiedNew) {
        return DTabs<TopicListMode>.controlled(
          value: mode,
          onChanged: (value) {
            if (value != null) selectMode(value);
          },
          children: [
            Align(
              alignment: wide
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: DTabList<TopicListMode>(
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
            ),
          ],
        );
      } else if (showsTabs && mode.topPeriod != null) {
        return Align(
          key: const ValueKey('topic-list-top-period-segment'),
          alignment: wide
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
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
        return null;
      }
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
          final contextual = contextualFor(wide);
          final heading = headingBuilder;
          Widget inset(Widget child) => ContentReadingLaneBox(
            widthLimit: topicListContentWidth,
            padding: const EdgeInsets.symmetric(
              horizontal: topicListHorizontalPadding,
            ),
            child: child,
          );
          Widget search() => TopicListSearch(
            key: ValueKey((
              state.filterOwner.controller,
              state.filterOwner.session,
              state.filterOwner.tabId,
            )),
            query: state.route!.topicListSearch,
            categoryName: state.categories
                .where((category) => category.id == state.route!.categoryId)
                .firstOrNull
                ?.name,
            onChanged: (query) {
              if (_filterOwner(controller) == state.filterOwner) {
                controller.searchTopicList(query, keepTopicOpen: keepTopicOpen);
              }
            },
          );
          Widget primary() => ConstrainedBox(
            key: ValueKey(
              heading == null
                  ? 'topic-list-primary-row'
                  : 'topic-list-feed-row',
            ),
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
                  key: const ValueKey('topic-list-primary-row'),
                  child: heading(
                    context,
                    showsTabs && wide ? navigation : null,
                  ),
                ),
              if (heading == null || (!wide && showsTabs)) inset(primary()),
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
                            : TopicListFilterBar(
                                key: ValueKey(state.filterOwner),
                                inline: true,
                                wrap: wide,
                                compact: !wide,
                                siteUrl: state.siteUrl!,
                                categories: state.categories,
                                knownTags: state.tags,
                                selectedCategoryId: state.route!.categoryId,
                                selectedTagName: state.route!.tagName,
                                selectedTagNames: state.route!.tagNames,
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
                                onTagsSelected: (tags) {
                                  if (ownsFeed()) {
                                    controller.selectTopicListTags(
                                      tags,
                                      keepTopicOpen: keepTopicOpen,
                                    );
                                  }
                                },
                              );
                        return Flex(
                          key: const ValueKey('topic-list-refinement-row'),
                          direction: wide ? Axis.horizontal : Axis.vertical,
                          crossAxisAlignment: wide
                              ? CrossAxisAlignment.center
                              : CrossAxisAlignment.stretch,
                          children: [
                            if (filters != null)
                              if (wide) Expanded(child: filters) else filters,
                            if (filters != null && contextual != null)
                              SizedBox(
                                width: wide ? 16 : 0,
                                height: wide ? 0 : 12,
                              ),
                            if (wide && showsFilters) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 360,
                                  ),
                                  child: search(),
                                ),
                              ),
                            ],
                            if (contextual != null)
                              if (wide)
                                Flexible(
                                  child: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: contextual,
                                  ),
                                )
                              else
                                contextual,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              if (showsFilters && !wide)
                inset(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: search(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
