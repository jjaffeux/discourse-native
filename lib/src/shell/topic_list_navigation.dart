import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_list_filter_bar.dart';
import 'topic_list_layout.dart';

typedef _TopicListNavigationSnapshot = ({
  TopicListMode? mode,
  bool signedIn,
  bool unifiedNew,
  int allCount,
  int unreadCount,
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
        unreadCount: controller.currentTotals?.topicTrackingUnread ?? 0,
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
      return LayoutBuilder(
        builder: (context, constraints) {
          final controls = _TopicListNavigationControls(
            state: state,
            showsTabs: showsTabs,
            showsFilters: showsFilters,
            trailing: trailing,
            headingBuilder: headingBuilder,
            stacked: stacked,
            keepTopicOpen: keepTopicOpen,
          );
          return Column(
            children: [
              if (constraints.maxHeight < 320)
                Flexible(child: DScrollArea(child: controls))
              else
                controls,
              Expanded(child: child),
            ],
          );
        },
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
    final navigation = TopicFeedMenu(
      mode: mode,
      filtered: state.route?.isAdvancedTopicFilter == true,
      signedIn: state.signedIn,
      unreadCount: state.unreadCount,
      newCount: state.allCount,
      onSelected: selectMode,
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
      }
      return null;
    }

    final owner = state.filterOwner;
    final lease = state.siteUrl == null
        ? null
        : controller.lifecycle.capture(state.siteUrl!);
    bool ownsFeed() =>
        context.mounted &&
        lease?.isCurrent == true &&
        _filterOwner(controller) == owner;
    final filters = !showsFilters
        ? null
        : TopicListFilterBar(
            key: ValueKey(owner),
            inline: true,
            wrap: true,
            siteUrl: state.siteUrl!,
            categories: state.categories,
            knownTags: state.tags,
            selectedCategoryId: state.route!.categoryId,
            selectedTagName: state.route!.tagName,
            selectedTagNames: state.route!.tagNames,
            taggingEnabled: state.taggingEnabled,
            searchTags: (query) async {
              if (!ownsFeed()) return const [];
              final result = await controller.searchFilterTags(
                siteUrl: state.siteUrl!,
                term: query,
              );
              return ownsFeed() ? result : const [];
            },
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
    return Semantics(
      key: const ValueKey('topic-list-navigation'),
      container: true,
      label: 'Topic lists',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headingBuilder != null)
            KeyedSubtree(
              key: const ValueKey('topic-list-primary-row'),
              child: headingBuilder!(context, null),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: topicListHorizontalPadding,
              vertical: 8,
            ),
            child: Row(
              key: const ValueKey('topic-list-feed-row'),
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [if (showsTabs) navigation, ?filters],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
          if (contextualFor(false) case final contextual?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                topicListHorizontalPadding,
                0,
                topicListHorizontalPadding,
                8,
              ),
              child: contextual,
            ),
        ],
      ),
    );
  }
}

/// Shared feed menu: periods are direct choices beneath Top, never a second picker.
class TopicFeedMenu extends StatelessWidget {
  const TopicFeedMenu({
    super.key,
    required this.mode,
    required this.onSelected,
    this.filtered = false,
    this.signedIn = true,
    this.unreadCount = 0,
    this.newCount = 0,
  });
  final TopicListMode mode;
  final ValueChanged<TopicListMode> onSelected;
  final bool signedIn;
  final bool filtered;
  final int unreadCount, newCount;

  static String label(TopicListMode mode) => switch (mode) {
    TopicListMode.latest => 'Latest',
    TopicListMode.unread => 'Unread',
    TopicListMode.newActivity ||
    TopicListMode.newTopics ||
    TopicListMode.newReplies => 'New',
    TopicListMode.unseen => 'Unseen',
    TopicListMode.popular => 'Trending',
    _ => 'Top · ${mode.topPeriod!.label}',
  };

  @override
  Widget build(BuildContext context) {
    final selected = mode.isNew ? TopicListMode.newActivity : mode;
    Widget item(
      TopicListMode value,
      String description, {
      int count = 0,
      bool inset = false,
    }) => DDropdownMenuItem(
      key: ValueKey(
        value.isTop
            ? 'topic-list-top-period-${value.topPeriod!.queryValue}'
            : 'topic-list-${value == TopicListMode.newActivity
                  ? 'new'
                  : value == TopicListMode.popular
                  ? 'popular'
                  : value.name}',
      ),
      inset: inset,
      onPressed: () => onSelected(value),
      semanticLabel:
          '${value.isTop ? value.topPeriod!.label : label(value)}${count > 0 ? ', $count topics' : ''}${selected == value ? ', selected' : ''}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected == value) const DIcon(DIcons.check, size: 14),
          if (count > 0) ...[
            if (selected == value) const SizedBox(width: 8),
            DBadge(variant: DBadgeVariant.secondary, child: Text('$count')),
          ],
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value.isTop ? value.topPeriod!.label : label(value)),
          if (description.isNotEmpty)
            Text(
              description,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: DTokens.of(context).mutedForeground,
              ),
            ),
        ],
      ),
    );
    final count = mode == TopicListMode.unread
        ? unreadCount
        : mode.isNew
        ? newCount
        : 0;
    return DDropdownMenu(
      content: DDropdownMenuContent(
        width: 304,
        semanticLabel: 'Choose topic feed',
        children: [
          item(TopicListMode.latest, 'Recently active conversations'),
          if (signedIn) ...[
            item(
              TopicListMode.unread,
              'Replies in conversations you follow',
              count: unreadCount,
            ),
            item(
              TopicListMode.newActivity,
              'New topics and replies',
              count: newCount,
            ),
            item(TopicListMode.unseen, 'Topics you haven’t visited'),
          ],
          const DDropdownMenuLabel(child: Text('Top')),
          for (final period in [
            TopPeriod.yearly,
            TopPeriod.quarterly,
            TopPeriod.monthly,
            TopPeriod.weekly,
            TopPeriod.daily,
            TopPeriod.all,
          ])
            item(TopicListMode.top(period), '', inset: true),
          item(TopicListMode.popular, 'Conversations gaining momentum'),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, trigger) => DButton(
          key: const ValueKey('topic-list-feed-menu'),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(filtered ? 'Filtered' : label(mode)),
              if (count > 0) ...[
                const SizedBox(width: 8),
                DBadge(variant: DBadgeVariant.secondary, child: Text('$count')),
              ],
              const SizedBox(width: 8),
              const DIcon(DIcons.chevronDown, size: 12),
            ],
          ),
          variant: DButtonVariant.outline,
          focusNode: trigger.focusNode,
          hasPopup: true,
          expanded: trigger.open,
          onPressed: trigger.toggle,
        ),
      ),
    );
  }
}
