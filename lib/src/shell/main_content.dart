import 'dart:async';

import 'package:flutter/material.dart';

import '../models/category_feed.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../plugins/chat/chat_header_button.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_shell.dart';
import 'categories_page.dart';
import 'composer_controller.dart';
import 'composer_panel.dart';
import 'draft_list.dart';
import 'forum_search.dart';
import 'forum_tabs_bar.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'title_bar.dart';
import 'topic_create_button.dart';
import 'topic_filter_page.dart';
import 'topic_list_view.dart';
import 'topic_title.dart';
import 'topic_view.dart';
import 'user_menu_button.dart';

/// The main region. There is only ever one of these on screen; navigating
/// deeper replaces what it shows rather than opening beside it.
class MainContent extends StatelessWidget {
  const MainContent({super.key, required this.layout});

  final ShellLayout layout;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<_MainContentSnapshot>(
      select: _MainContentSnapshot.from,
      builder: (context, state, _) =>
          _MainContentBody(layout: layout, state: state),
    );
  }
}

class _MainContentBody extends StatelessWidget {
  const _MainContentBody({required this.layout, required this.state});

  final ShellLayout layout;
  final _MainContentSnapshot state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forumTabsEnabled = ShellScope.read(context).forumTabsEnabled;

    final route = state.route;
    if (route == null) return ColoredBox(color: theme.shell.content);
    final pluginContent = _pluginContent(context, route);
    final contentKey = ValueKey((
      state.siteUrl,
      state.activeTabId,
      route.id,
      route.postNumber,
    ));

    return ColoredBox(
      color: theme.shell.content,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            if (forumTabsEnabled) const CurrentForumTabsBar(),
            _ContentHeader(
              layout: layout,
              route: route,
              siteUrl: state.siteUrl,
              topic: state.topic,
              canPop: state.canPop,
              canReply: state.canReply,
              canCreateTopic: state.canCreateTopic && pluginContent == null,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: KeyedSubtree(
                      key: contentKey,
                      child:
                          !route.isTopic &&
                              route.id == 'drafts' &&
                              state.siteUrl != null
                          ? DraftListView(siteUrl: state.siteUrl!)
                          : !route.isTopic &&
                                route.id == 'all-categories' &&
                                state.siteUrl != null &&
                                state.categoryFeed != null
                          ? CategoriesPage(
                              siteUrl: state.siteUrl!,
                              feed: state.categoryFeed!,
                            )
                          : !route.isTopic &&
                                route.id == 'filter' &&
                                state.siteUrl != null &&
                                state.feed != null
                          ? TopicFilterPage(
                              siteUrl: state.siteUrl!,
                              feed: state.feed!,
                              categories: state.filterCategories,
                            )
                          : switch ((
                              route.isTopic,
                              pluginContent,
                              state.feed,
                            )) {
                              // A topic route wins over its originating list.
                              (true, _, _) => TopicView(
                                showRecommendationsPanel:
                                    layout == ShellLayout.expanded,
                              ),
                              // A route an optional feature claims is that feature's,
                              // whichever list happens to still be cached behind it.
                              (false, final content?, _) => content,
                              // Destinations backed by a topic list show the real
                              // thing; the rest retain the placeholder.
                              (false, null, final feed?) => TopicListView(
                                feed: feed,
                              ),
                              (false, null, null) => _ContentPlaceholder(
                                route: route,
                              ),
                            },
                    ),
                  ),
                  if (state.composer case final composer?)
                    Positioned.fill(
                      child: FloatingComposerPanel(
                        key: ObjectKey(composer),
                        composer: composer,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The screen an optional feature draws for this route, or null when none of
/// them claims it.
///
/// The body of [PostFooter] with a route in place of a post, and asked before
/// core for the same reason it is there: the first plugin with something to say
/// wins, and core's answer is what is left when none of them do.
Widget? _pluginContent(BuildContext context, ContentRoute route) {
  return pluginRegistry.content(context, route);
}

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({
    required this.layout,
    required this.route,
    required this.siteUrl,
    required this.topic,
    required this.canPop,
    required this.canReply,
    required this.canCreateTopic,
  });

  final ShellLayout layout;
  final ContentRoute route;
  final String? siteUrl;
  final TopicDetail? topic;
  final bool canPop;
  final bool canReply;
  final bool canCreateTopic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final topicHeader = switch ((siteUrl, topic)) {
      (final siteUrl?, final topic?) => pluginRegistry.topicHeader(
        context,
        siteUrl,
        topic,
      ),
      _ => const <Widget>[],
    };

    // On compact the main region has replaced the sidebar, so back always has
    // somewhere to go. On wider layouts it only matters inside the stack.
    final showBack = layout.isCompact || canPop;

    return Container(
      height: shellHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final carriesSearch = !ShellTitleBar.isSupported;
          final showRouteIdentity =
              !carriesSearch || constraints.maxWidth >= 620;
          final searchWidth = constraints.maxWidth >= 800 ? 360.0 : 260.0;

          return Row(
            children: [
              if (showBack)
                IconButton(
                  onPressed: () => controller.handleBack(
                    canReturnToSidebar: layout.isCompact,
                  ),
                  icon: const DIcon(DIcons.arrowLeft, size: 20),
                  tooltip: 'Back',
                )
              else
                const SizedBox(width: 8),
              if (showRouteIdentity)
                if (route.color case final color?)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: DIcon(
                      route.icon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              if (showRouteIdentity)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (route.isTopic && siteUrl != null)
                        TopicTitle(
                          route.title,
                          siteUrl: siteUrl!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        Text(
                          route.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (route.subtitle case final subtitle?)
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
                )
              else if (carriesSearch)
                const Expanded(child: ForumSearch(dense: true)),
              if (carriesSearch && showRouteIdentity) ...[
                SizedBox(
                  width: searchWidth,
                  child: const ForumSearch(dense: true),
                ),
                const SizedBox(width: 4),
              ],
              ...topicHeader,
              if (route.isTopic && canReply)
                IconButton(
                  onPressed: () => controller.openReply(),
                  icon: const DIcon(DIcons.reply, size: 20),
                  tooltip: 'Reply to this topic',
                ),
              if (!route.isTopic && canCreateTopic)
                TopicCreateButton(
                  showLabel: MediaQuery.sizeOf(context).width >= 640,
                  onPressed: () => unawaited(controller.openNewTopic()),
                ),
              // Only where there is no title bar above to hold it: this is the
              // furthest right the shell goes once the strip is gone.
              if (ShellTitleBar.columnsCarryUserMenu) ...[
                ChatHeaderButton(
                  hideWhenChatActive: layout.isCompact,
                  ringColor: theme.shell.content,
                ),
                UserMenuButton(ringColor: theme.shell.content),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Stand-in for real content. Doubles as a way to exercise every navigation
/// mode the shell supports before any of the real screens exist.
class _ContentPlaceholder extends StatelessWidget {
  const _ContentPlaceholder({required this.route});

  final ContentRoute route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final stack = controller.contentStack;
    final depth = stack.length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(
              route.icon,
              size: 56,
              color: route.color ?? theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              route.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            if (depth > 1) ...[
              const SizedBox(height: 4),
              Text(
                stack.map((r) => r.title).join('  ›  '),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => controller.pushContent(
                    ContentRoute(
                      id: '${route.id}-$depth',
                      title: 'Topic $depth',
                      icon: DIcons.comments,
                      subtitle: 'opened from ${route.title}',
                    ),
                  ),
                  icon: const DIcon(DIcons.upRightFromSquare, size: 18),
                  label: const Text('Replace with deeper view'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showShellSheet<void>(
                    context: context,
                    title: route.title,
                    builder: (context) => Text(
                      'Sheets sit over the shell instead of replacing the main '
                      'region. Use them for composing, quick actions and '
                      'anything the user should be able to dismiss without '
                      'losing their place.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  icon: const DIcon(DIcons.arrowUp, size: 18),
                  label: const Text('Show sheet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MainContentSnapshot {
  const _MainContentSnapshot({
    required this.siteUrl,
    required this.activeTabId,
    required this.route,
    required this.topic,
    required this.feed,
    required this.composer,
    required this.canPop,
    required this.canReply,
    required this.canCreateTopic,
    required this.canAssignLegacyTargets,
    required this.filterCategories,
    required this.categoryFeed,
  });

  factory _MainContentSnapshot.from(ShellController controller) =>
      _MainContentSnapshot(
        siteUrl: controller.currentInstance?.url,
        activeTabId: controller.activeTabId,
        route: controller.currentContent,
        topic: controller.currentTopic,
        feed: controller.currentFeed,
        composer: controller.visibleComposer,
        canPop: controller.canPopContent,
        canReply: controller.canReplyHere,
        canCreateTopic: controller.canCreateTopicHere,
        canAssignLegacyTargets: switch (controller.currentInstance?.url) {
          final siteUrl? => controller.canAssignForTarget(siteUrl, null),
          null => false,
        },
        filterCategories: switch ((
          controller.currentContent?.id,
          controller.currentInstance?.url,
        )) {
          ('filter', final siteUrl?) => controller.filterCategoriesFor(siteUrl),
          _ => const [],
        },
        categoryFeed: switch ((
          controller.currentContent?.id,
          controller.currentInstance?.url,
        )) {
          ('all-categories', final siteUrl?) => controller.categoryFeedFor(
            siteUrl,
          ),
          _ => null,
        },
      );

  final String? siteUrl;
  final String? activeTabId;
  final ContentRoute? route;
  final TopicDetail? topic;
  final TopicFeed? feed;
  final ComposerController? composer;
  final bool canPop;
  final bool canReply;
  final bool canCreateTopic;
  final bool canAssignLegacyTargets;
  final List<TopicCategory> filterCategories;
  final CategoryFeed? categoryFeed;

  @override
  bool operator ==(Object other) =>
      other is _MainContentSnapshot &&
      siteUrl == other.siteUrl &&
      activeTabId == other.activeTabId &&
      identical(route, other.route) &&
      identical(topic, other.topic) &&
      identical(feed, other.feed) &&
      identical(composer, other.composer) &&
      canPop == other.canPop &&
      canReply == other.canReply &&
      canCreateTopic == other.canCreateTopic &&
      canAssignLegacyTargets == other.canAssignLegacyTargets &&
      identical(filterCategories, other.filterCategories) &&
      identical(categoryFeed, other.categoryFeed);

  @override
  int get hashCode => Object.hash(
    siteUrl,
    activeTabId,
    identityHashCode(route),
    identityHashCode(topic),
    identityHashCode(feed),
    identityHashCode(composer),
    canPop,
    canReply,
    canCreateTopic,
    canAssignLegacyTargets,
    identityHashCode(filterCategories),
    identityHashCode(categoryFeed),
  );
}
