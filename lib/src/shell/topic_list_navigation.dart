import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/sidebar_tag.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import 'category_notifications.dart';
import 'content_reading_lane.dart';
import 'platform.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_feed_menu.dart';
import 'topic_list_actions.dart';
import 'topic_list_bottom_bar.dart';
import 'topic_list_filter_bar.dart';

export 'topic_feed_menu.dart';

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
  int maxCategoryNesting,
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

_TopicListFilterOwner _filterOwner(
  ShellController controller,
  ShellTabContext tab,
) {
  final siteUrl = controller.currentInstance?.url;
  final route = tab.topicListContent ?? tab.currentContent;
  return (
    controller: controller,
    rootMode: controller.rootMode,
    siteUrl: siteUrl,
    accountIdentity: controller.currentAccountIdentity,
    session: siteUrl == null
        ? null
        : controller.lifecycle.capture(siteUrl).session,
    tabId: tab.activeTabId,
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
    this.keepTopicOpen = false,
  });

  final Widget child;
  final Widget? trailing;
  final TopicListHeadingBuilder? headingBuilder;
  final bool keepTopicOpen;

  @override
  Widget build(
    BuildContext context,
  ) => ForumTabSelector<_TopicListNavigationSnapshot>(
    select: (controller, tab) {
      final counts = tab.topicListNewCounts;
      final siteUrl = controller.currentInstance?.url;
      final route = tab.topicListContent ?? tab.currentContent;
      final showsFilters = route?.isTopicListFilter == true;
      return (
        mode: tab.currentTopicListMode,
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
        filterOwner: _filterOwner(controller, tab),
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
        maxCategoryNesting: siteUrl == null
            ? SiteConfig.defaultMaxCategoryNesting
            : controller.siteConfigFor(siteUrl).maxCategoryNesting,
      );
    },
    builder: (context, state, _) {
      final showsTabs = state.mode != null;
      final showsFilters =
          state.siteUrl != null && state.route?.isTopicListFilter == true;
      if (!showsTabs && !showsFilters && trailing == null) {
        return child;
      }
      final controls = _TopicListNavigationControls(
        state: state,
        showsTabs: showsTabs,
        showsFilters: showsFilters,
        trailing: trailing,
        headingBuilder: headingBuilder,
        keepTopicOpen: keepTopicOpen,
      );
      if (headingBuilder == null) {
        return DPageSurface(framed: false, header: controls, child: child);
      }
      return DPageSurface.headed(
        identity: state.filterOwner,
        title: KeyedSubtree(
          key: const ValueKey('topic-list-primary-row'),
          child: headingBuilder!(context, null),
        ),
        controls: controls,
        child: child,
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
    required this.keepTopicOpen,
  });

  final _TopicListNavigationSnapshot state;
  final bool showsTabs;
  final bool showsFilters;
  final Widget? trailing;
  final TopicListHeadingBuilder? headingBuilder;
  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    final tab = ForumTabScope.tabOf(context);
    final mode = state.mode ?? TopicListMode.latest;
    void selectMode(TopicListMode value) =>
        unawaited(tab.selectTopicListMode(value, keepTopicOpen: keepTopicOpen));
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
        identical(ShellScope.read(context), controller) &&
        tab.isCurrent &&
        _filterOwner(controller, tab) == owner;
    final filterMenu =
        controller.mobileNavigationEnabled &&
            state.siteUrl != null &&
            state.route?.isMessages != true
        ? TopicListFilterMenu(
            key: ValueKey((state.siteUrl, state.route!.id)),
            siteUrl: state.siteUrl!,
            query: controller.topicListFilterEditorQuery(state.route!),
          )
        : null;
    final filters = !showsFilters
        ? null
        : TopicListFilterBar(
            key: ValueKey((
              owner.controller,
              owner.siteUrl,
              owner.accountIdentity,
              owner.session,
              owner.tabId,
              owner.rootMode,
            )),
            inline: true,
            wrap: true,
            leading: showsTabs ? navigation : null,
            trailing: filterMenu,
            siteUrl: state.siteUrl!,
            filterQuery: controller.topicListFilterEditorQuery(state.route!),
            categories: state.categories,
            knownTags: state.route?.categoryId == null ? state.tags : const [],
            selectedCategoryId: state.route!.categoryId,
            selectedTagName: state.route!.tagName,
            selectedTagNames: state.route!.tagNames,
            taggingEnabled: state.taggingEnabled,
            maxCategoryNesting: state.maxCategoryNesting,
            searchTags: (query) async {
              if (!ownsFeed()) return const [];
              final result = await controller.searchFilterTags(
                siteUrl: state.siteUrl!,
                term: query,
                categoryId: state.route?.categoryId,
              );
              return ownsFeed() ? result : const [];
            },
            onCategorySelected: (category) {
              if (ownsFeed()) {
                tab.selectTopicListCategory(
                  category,
                  keepTopicOpen: keepTopicOpen,
                );
              }
            },
            onTagSelected: (tag) {
              if (ownsFeed()) {
                final folded = tag?.toLowerCase();
                final named = state.tags
                    .where((item) => item.name.toLowerCase() == folded)
                    .firstOrNull;
                final slugged = state.tags
                    .where((item) => item.slug.toLowerCase() == folded)
                    .firstOrNull;
                tab.selectTopicListTag(
                  named?.name ?? slugged?.name ?? tag,
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
          ContentReadingLaneBox(
            child: Padding(
              padding: headingBuilder == null
                  ? EdgeInsets.fromLTRB(
                      16,
                      controller.mobileNavigationEnabled ? 16 : 8,
                      16,
                      controller.mobileNavigationEnabled ? 14 : 16,
                    )
                  : EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wrap =
                      constraints.maxWidth < 600 &&
                      MediaQuery.textScalerOf(context).scale(14) > 21;
                  // The filters wrap among themselves; a control that is not
                  // a filter stands beside them instead of being stranded on
                  // a run of its own.
                  final primary = Wrap(
                    spacing: DSpacing.sm,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (filters != null)
                        filters
                      else ...[
                        if (showsTabs) navigation,
                        ?filterMenu,
                      ],
                    ],
                  );
                  final actions = <Widget>[
                    if (controller.mobileNavigationEnabled || !context.isTouch)
                      const DismissNewTopicsButton(compact: true),
                    if (state.connected &&
                        state.siteUrl != null &&
                        state.route?.categoryId != null &&
                        state.route?.isMessages != true &&
                        (!context.isTouch ||
                            controller.mobileNavigationEnabled))
                      CategoryNotificationLevelButton(
                        siteUrl: state.siteUrl!,
                        categoryId: state.route!.categoryId!,
                        size: DButtonSize.filter,
                        quiet: true,
                        showChevron: !controller.mobileNavigationEnabled,
                      ),
                    ?trailing,
                  ];
                  if (wrap) {
                    return DControlWrap(
                      key: const ValueKey('topic-list-feed-row'),
                      spacing: DSpacing.sm,
                      runSpacing: 8,
                      children: [primary, ...actions],
                    );
                  }
                  return Row(
                    key: const ValueKey('topic-list-feed-row'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: primary),
                      for (final action in actions) ...[
                        const SizedBox(width: DSpacing.sm),
                        action,
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
