import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/count_label.dart';
import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'category_notifications.dart';
import 'content_reading_lane.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_list_bottom_bar.dart';
import 'topic_list_filter_bar.dart';

typedef _TopicListNavigationSnapshot = ({
  TopicListMode? mode,
  bool signedIn,
  bool connected,
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
        connected: controller.currentInstance?.isConnected == true,
        unifiedNew: controller.currentInstance?.user?.unifiedNewEnabled == true,
        allCount: counts.all,
        // Unread lists exactly the topics Replies counts, so it shares that
        // count's category and tag scope and its live tracking.
        unreadCount: counts.replies,
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
          return DPageSurface(
            framed: false,
            identity: state.filterOwner,
            header: constraints.maxHeight < 320
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight / 2,
                    ),
                    child: DScrollArea(child: controls),
                  )
                : controls,
            child: child,
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
      signedIn: state.signedIn,
      unreadCount: state.unreadCount,
      newCount: state.allCount,
      unifiedNew: state.unifiedNew,
      topicCount: state.topicCount,
      replyCount: state.replyCount,
      onSelected: selectMode,
    );
    final owner = state.filterOwner;
    final lease = state.siteUrl == null
        ? null
        : controller.lifecycle.capture(state.siteUrl!);
    bool ownsFeed() =>
        context.mounted &&
        lease?.isCurrent == true &&
        controller.readTab(owner.tabId, () => _filterOwner(controller)) ==
            owner;
    final filters = !showsFilters
        ? null
        : TopicListFilterBar(
            key: ValueKey(owner),
            inline: true,
            wrap: true,
            leading: showsTabs ? navigation : null,
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
      label: context.l10n.topicLists,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headingBuilder != null)
            KeyedSubtree(
              key: const ValueKey('topic-list-primary-row'),
              child: headingBuilder!(context, null),
            ),
          ContentReadingLaneBox(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                context.isTouch && headingBuilder != null ? 0 : 8,
                16,
                16,
              ),
              child: Row(
                key: const ValueKey('topic-list-feed-row'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: DSpacing.controlGap,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (filters != null)
                          filters
                        else if (showsTabs)
                          navigation,
                      ],
                    ),
                  ),
                  // The mobile dock keeps a fixed geometry, so these page
                  // actions live with the list rather than beside it.
                  if (controller.mobileNavigationEnabled) ...[
                    const SizedBox(width: DSpacing.controlGap),
                    const DismissNewTopicsButton(compact: true),
                  ],
                  if (state.connected &&
                      state.siteUrl != null &&
                      state.route?.categoryId != null &&
                      state.route?.isMessages != true &&
                      (!context.isTouch ||
                          controller.mobileNavigationEnabled)) ...[
                    if (!controller.mobileNavigationEnabled)
                      const SizedBox(width: DSpacing.controlGap),
                    CategoryNotificationLevelButton(
                      siteUrl: state.siteUrl!,
                      categoryId: state.route!.categoryId!,
                      showChevron: !controller.mobileNavigationEnabled,
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: DSpacing.controlGap),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
          if (headingBuilder != null)
            const ContentReadingLaneBox(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: DSeparator(key: ValueKey('topic-list-heading-separator')),
            ),
        ],
      ),
    );
  }
}

/// Shared feed menu with direct choices for New subsets and Top periods.
class TopicFeedMenu extends StatelessWidget {
  const TopicFeedMenu({
    super.key,
    required this.mode,
    required this.onSelected,
    this.signedIn = true,
    this.unreadCount = 0,
    this.newCount = 0,
    this.unifiedNew = false,
    this.topicCount = 0,
    this.replyCount = 0,
  });
  final TopicListMode mode;
  final ValueChanged<TopicListMode> onSelected;
  final bool signedIn;
  final bool unifiedNew;
  final int unreadCount, newCount, topicCount, replyCount;

  static String label(TopicListMode mode) => switch (mode) {
    TopicListMode.latest => appL10n.latest,
    TopicListMode.unread => appL10n.unread,
    TopicListMode.newActivity => appL10n.messageNew,
    TopicListMode.newTopics => appL10n.newTopics,
    TopicListMode.newReplies => appL10n.newReplies,
    TopicListMode.unseen => appL10n.unseen,
    TopicListMode.popular => appL10n.trending,
    _ => appL10n.top((mode.topPeriod!.label).toString()),
  };

  @override
  Widget build(BuildContext context) {
    final selected = mode;
    String itemLabel(TopicListMode value) => switch (value) {
      TopicListMode.newActivity when unifiedNew => context.l10n.all,
      TopicListMode.newTopics => context.l10n.topics,
      TopicListMode.newReplies => context.l10n.replies,
      _ => value.isTop ? value.topPeriod!.label : label(value),
    };
    Widget item(TopicListMode value, {int count = 0}) => DDropdownMenuItem(
      key: ValueKey(
        value.isTop
            ? 'topic-list-top-period-${value.topPeriod!.queryValue}'
            : 'topic-list-${value == TopicListMode.newActivity
                  ? (unifiedNew ? 'new-all' : 'new')
                  : value == TopicListMode.newTopics
                  ? 'new-topics'
                  : value == TopicListMode.newReplies
                  ? 'new-replies'
                  : value == TopicListMode.popular
                  ? 'popular'
                  : value.name}',
      ),
      onPressed: () => onSelected(value),
      semanticLabel:
          '${itemLabel(value)}${count > 0 ? ', ${countLabel(count, CountNoun.topic)}' : ''}${selected == value ? context.l10n.selectedTopiclistnavigation : ''}',
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
      child: Text(itemLabel(value)),
    );
    final count = mode == TopicListMode.unread
        ? unreadCount
        : mode == TopicListMode.newTopics
        ? topicCount
        : mode == TopicListMode.newReplies
        ? replyCount
        : mode.isNew
        ? newCount
        : 0;
    return DDropdownMenu(
      sheetOnMobile: true,
      content: DDropdownMenuContent(
        width: 304,
        semanticLabel: context.l10n.chooseTopicFeed,
        children: [
          item(TopicListMode.latest),
          if (signedIn) ...[
            item(TopicListMode.unread, count: unreadCount),
            if (unifiedNew) ...[
              DDropdownMenuLabel(child: Text(context.l10n.messageNew)),
              DDropdownMenuGroup(
                showGuide: true,
                semanticLabel: context.l10n.newActivity,
                children: [
                  item(TopicListMode.newActivity, count: newCount),
                  item(TopicListMode.newTopics, count: topicCount),
                  item(TopicListMode.newReplies, count: replyCount),
                ],
              ),
            ] else
              item(TopicListMode.newActivity, count: newCount),
            item(TopicListMode.unseen),
          ],
          DDropdownMenuLabel(child: Text(context.l10n.topTopiclistnavigation)),
          DDropdownMenuGroup(
            showGuide: true,
            semanticLabel: context.l10n.topPeriods,
            children: [
              for (final period in [
                TopPeriod.yearly,
                TopPeriod.quarterly,
                TopPeriod.monthly,
                TopPeriod.weekly,
                TopPeriod.daily,
                TopPeriod.all,
              ])
                item(TopicListMode.top(period)),
            ],
          ),
          item(TopicListMode.popular),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, trigger) => DButton(
          key: const ValueKey('topic-list-feed-menu'),
          size: DButtonSize.filter,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label(mode),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                DBadge(variant: DBadgeVariant.secondary, child: Text('$count')),
              ],
              const SizedBox(width: 6),
              const DIcon(DNativeIcons.filterChevron, size: 10),
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
