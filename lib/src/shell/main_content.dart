import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/category_feed.dart';
import '../models/content_route.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_shell.dart';
import 'categories_page.dart';
import 'draft_list.dart';
import 'forum_search.dart';
import 'forum_tabs_bar.dart';
import 'group_pages_coordinator.dart';
import 'group_pages_host.dart';
import 'group_pages_port.dart';
import 'group_pages_shell_port.dart';
import 'message_inbox_page.dart';
import 'preferences_page.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'tags_page.dart';
import 'title_bar.dart';
import 'topic_create_button.dart';
import 'topic_filter_page.dart';
import 'topic_list_navigation.dart';
import 'topic_list_view.dart';
import 'topic_title.dart';
import 'topic_view.dart';
import 'user_activity.dart';
import 'user_menu_button.dart';
import 'user_summary.dart';

class MainContent extends StatefulWidget {
  const MainContent({super.key, required this.layout, this.registry});

  final ShellLayout layout;
  final PluginRegistry? registry;

  @override
  State<MainContent> createState() => _MainContentState();
}

class _MainContentState extends State<MainContent> {
  final GroupPagesCoordinator _groupPages = GroupPagesCoordinator();

  @override
  Widget build(BuildContext context) {
    return ShellSelector<_MainContentSnapshot>(
      select: _MainContentSnapshot.from,
      builder: (context, state, _) {
        final shell = ShellScope.read(context);
        final port = ShellGroupPagesPort(shell);
        final route = state.route;
        _groupPages.bind(
          port,
          GroupPagesRouteSnapshot(
            owner: (
              siteUrl: state.siteUrl ?? '',
              accountIdentity: state.groupAccountIdentity ?? 'signed-out',
              tabId: state.activeTabId,
            ),
            routeId: route?.id ?? '',
            groupNamespace: _isGroupNamespace(route),
            route: route?.groupRoute,
            canPopContent: state.canPop,
          ),
        );
        return _MainContentBody(
          layout: widget.layout,
          state: state,
          registry:
              widget.registry ??
              PluginScope.maybeOf(context)?.registry ??
              PluginRegistry.empty,
          groupPages: _groupPages,
          groupPagesPort: port,
        );
      },
    );
  }

  @override
  void dispose() {
    _groupPages.dispose();
    super.dispose();
  }
}

bool _isGroupNamespace(ContentRoute? route) =>
    route != null &&
    (route.groupRoute != null ||
        route.id == 'groups' ||
        route.id.startsWith('group-'));

class _MainContentBody extends StatelessWidget {
  const _MainContentBody({
    required this.layout,
    required this.state,
    required this.registry,
    required this.groupPages,
    required this.groupPagesPort,
  });

  final ShellLayout layout;
  final _MainContentSnapshot state;
  final PluginRegistry registry;
  final GroupPagesCoordinator groupPages;
  final GroupPagesPort groupPagesPort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forumTabsEnabled = ShellScope.read(context).forumTabsEnabled;

    final route = state.route;
    if (route == null) return ColoredBox(color: theme.shell.content);
    final pluginContent = registry.content(context, route);
    final pluginOwnsChrome = registry.ownsContentChrome(context, route);
    final contentKey = ValueKey(
      groupPages.childIdentity ??
          (
            siteUrl: state.siteUrl,
            activeTabId: state.activeTabId,
            routeId: route.id,
            postNumber: route.postNumber,
          ),
    );

    return Material(
      color: theme.shell.content,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            if (forumTabsEnabled) const CurrentForumTabsBar(),
            if (!pluginOwnsChrome && !route.isTopic)
              _ContentHeader(
                layout: layout,
                route: route,
                siteUrl: state.siteUrl,
                canPop: state.canPop,
                showCreateTopicAction: pluginContent == null,
                isConnected: state.isConnected,
                registry: registry,
                groupPages: groupPages,
              ),
            Expanded(
              child: KeyedSubtree(
                key: contentKey,
                child: _ContentViewport(
                  layout: layout,
                  route: route,
                  siteUrl: state.siteUrl,
                  isConnected: state.isConnected,
                  canReply: state.canReply,
                  bookmarkBusy: state.bookmarkBusy,
                  registry: registry,
                  pluginContent: pluginContent,
                  filterCategories: state.filterCategories,
                  categoryFeed: state.categoryFeed,
                  groupPages: groupPages,
                  groupPagesPort: groupPagesPort,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentViewport extends StatelessWidget {
  const _ContentViewport({
    required this.layout,
    required this.route,
    required this.siteUrl,
    required this.isConnected,
    required this.canReply,
    required this.bookmarkBusy,
    required this.registry,
    required this.pluginContent,
    required this.filterCategories,
    required this.categoryFeed,
    required this.groupPages,
    required this.groupPagesPort,
  });

  final ShellLayout layout;
  final ContentRoute route;
  final String? siteUrl;
  final bool isConnected;
  final bool canReply;
  final bool bookmarkBusy;
  final PluginRegistry registry;
  final Widget? pluginContent;
  final List<TopicCategory> filterCategories;
  final CategoryFeed? categoryFeed;
  final GroupPagesCoordinator groupPages;
  final GroupPagesPort groupPagesPort;

  @override
  Widget build(BuildContext context) {
    if (route.isMessages && !isConnected) {
      return const _SignedOutMessagesState();
    }
    if (!route.isTopic && route.id == 'drafts' && siteUrl != null) {
      return DraftListView(siteUrl: siteUrl!);
    }
    if (!route.isTopic && route.id == 'summary' && siteUrl != null) {
      return UserSummaryView(siteUrl: siteUrl!);
    }
    if (route.isPreferences && siteUrl != null) {
      return PreferencesPage(siteUrl: siteUrl!);
    }
    if (!route.isTopic && route.id == 'activity' && siteUrl != null) {
      return UserActivityView(siteUrl: siteUrl!);
    }
    if (groupPages.page.isOwned && siteUrl != null) {
      return GroupPagesHost(
        coordinator: groupPages,
        port: groupPagesPort,
        registry: registry,
      );
    }
    if (!route.isTopic &&
        route.id == 'all-categories' &&
        siteUrl != null &&
        categoryFeed != null) {
      return CategoriesPage(siteUrl: siteUrl!, feed: categoryFeed!);
    }
    if (!route.isTopic && route.id == 'all-tags' && siteUrl != null) {
      return TagsPage(siteUrl: siteUrl!);
    }
    if (!route.isTopic && route.id == 'filter' && siteUrl != null) {
      return _FeedBackedContent(
        route: route,
        siteUrl: siteUrl!,
        filterCategories: filterCategories,
        fallback: pluginContent,
      );
    }
    if (route.isTopic) {
      return TopicView(
        showSidebar: layout == ShellLayout.expanded,
        canReturnToSidebar: layout.isCompact,
        route: route,
        canReply: canReply,
        bookmarkBusy: bookmarkBusy,
        isConnected: isConnected,
        registry: registry,
      );
    }
    if (pluginContent case final content?) return content;

    return _FeedBackedContent(route: route, siteUrl: siteUrl);
  }
}

class _FeedBackedContent extends StatelessWidget {
  const _FeedBackedContent({
    required this.route,
    required this.siteUrl,
    this.filterCategories = const [],
    this.fallback,
  });

  final ContentRoute route;
  final String? siteUrl;
  final List<TopicCategory> filterCategories;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return _TopicFeedSelector<TopicFeed?>(
      controller: controller,
      select: (controller) => controller.currentFeed,
      builder: (context, feed, _) {
        final Widget content;
        if (feed == null) {
          content = fallback ?? _ContentPlaceholder(route: route);
        } else if (route.id == 'filter' && siteUrl != null) {
          content = TopicFilterPage(
            siteUrl: siteUrl!,
            feed: feed,
            categories: filterCategories,
          );
        } else if (route.isMessages) {
          content = MessageInboxPage(feed: feed);
        } else {
          content = TopicListView(feed: feed);
        }

        if (TopicListMode.fromRoute(route) != null) {
          return TopicListNavigation(child: content);
        }
        return content;
      },
    );
  }
}

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({
    required this.layout,
    required this.route,
    required this.siteUrl,
    required this.canPop,
    required this.showCreateTopicAction,
    required this.isConnected,
    required this.registry,
    required this.groupPages,
  });

  final ShellLayout layout;
  final ContentRoute route;
  final String? siteUrl;
  final bool canPop;
  final bool showCreateTopicAction;
  final bool isConnected;
  final PluginRegistry registry;
  final GroupPagesCoordinator groupPages;

  static const _searchSlotKey = ValueKey('content-header-search-slot');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final contentHeader = registry.contentHeaderActions(context, route);
    final contentHeaderLeading = registry.contentHeaderLeading(context, route);
    final contentHeaderTitleTrailing = registry.contentHeaderTitleTrailing(
      context,
      route,
    );
    final contentHeaderTitleAction = registry.contentHeaderTitleAction(
      context,
      route,
    );
    final groupBackIntent = groupPages.page.isOwned
        ? groupPages.backIntent(canReturnToSidebar: layout.isCompact)
        : null;
    final showBack = groupBackIntent != null
        ? groupBackIntent != GroupPagesBackIntent.none
        : layout.isCompact || canPop;

    return Container(
      height: shellHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.shell.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final carriesSearch =
              !ShellTitleBar.isSupported && !(layout.isCompact && !isConnected);
          final showRouteIdentity =
              !carriesSearch || constraints.maxWidth >= 620;
          final searchWidth = constraints.maxWidth >= 800 ? 360.0 : 260.0;

          return Row(
            children: [
              if (showBack)
                DButton.iconOnly(
                  onPressed: () {
                    if (groupBackIntent != null) {
                      groupPages.handleBack(
                        canReturnToSidebar: layout.isCompact,
                      );
                    } else {
                      controller.handleBack(
                        canReturnToSidebar: layout.isCompact,
                      );
                    }
                  },
                  icon: const DIcon(DIcons.arrowLeft, size: 20),
                  tooltip: 'Back',
                  variant: DButtonVariant.flat,
                )
              else
                const SizedBox(width: 8),
              if (showRouteIdentity)
                if (contentHeaderLeading case final leading?)
                  Padding(
                    key: const ValueKey('content-header-leading'),
                    padding: const EdgeInsets.only(right: 8),
                    child: leading,
                  )
                else if (route.color case final color?)
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
                  child: Semantics(
                    button: contentHeaderTitleAction != null,
                    label: contentHeaderTitleAction == null
                        ? null
                        : 'Open ${route.title} details',
                    child: InkWell(
                      key: contentHeaderTitleAction == null
                          ? null
                          : const ValueKey('content-header-title-action'),
                      onTap: contentHeaderTitleAction,
                      borderRadius: BorderRadius.circular(4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                fit: FlexFit.loose,
                                child: route.isTopic && siteUrl != null
                                    ? TopicTitle(
                                        route.title,
                                        siteUrl: siteUrl!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      )
                                    : Text(
                                        route.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                              ),
                              ?contentHeaderTitleTrailing,
                            ],
                          ),
                          if (route.isGroups && siteUrl != null)
                            _GroupsDirectoryCount(siteUrl: siteUrl!)
                          else if (route.subtitle case final subtitle?)
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
                  ),
                )
              else if (carriesSearch)
                const Expanded(
                  key: _searchSlotKey,
                  child: ForumSearch(dense: true),
                ),
              if (carriesSearch && showRouteIdentity) ...[
                SizedBox(
                  key: _searchSlotKey,
                  width: searchWidth,
                  child: const ForumSearch(dense: true),
                ),
                const SizedBox(width: 4),
              ],
              ...contentHeader,
              if (!route.isTopic &&
                  route.id != 'activity' &&
                  showCreateTopicAction)
                _TopicCreateAction(controller: controller),
              if (ShellTitleBar.columnsCarryUserMenu) ...[
                ...registry.shellHeaderActions(
                  context,
                  surface: PluginHeaderSurface.content,
                  compact: layout.isCompact,
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

class _GroupsDirectoryCount extends StatelessWidget {
  const _GroupsDirectoryCount({required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final groups = ShellScope.read(context).groups;
    return ListenableBuilder(
      listenable: groups,
      builder: (context, _) {
        final state = groups.presentedDirectoryState(siteUrl);
        if (state == null || !state.loaded) return const SizedBox.shrink();
        final count = state.totalRows;
        return Text(
          key: const ValueKey('groups-header-count'),
          count == 1 ? '1 group' : '$count groups',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

class _TopicCreateAction extends StatelessWidget {
  const _TopicCreateAction({required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) => _TopicFeedSelector<bool>(
    controller: controller,
    select: (controller) => controller.canCreateTopicHere,
    builder: (context, canCreateTopic, _) => canCreateTopic
        ? TopicCreateButton(
            showLabel: MediaQuery.sizeOf(context).width >= 640,
            onPressed: () => unawaited(controller.openNewTopic()),
          )
        : const SizedBox.shrink(),
  );
}

class _TopicFeedSelector<T> extends StatefulWidget {
  const _TopicFeedSelector({
    required this.controller,
    required this.select,
    required this.builder,
    this.child,
  });

  final ShellController controller;
  final T Function(ShellController controller) select;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  State<_TopicFeedSelector<T>> createState() => _TopicFeedSelectorState<T>();
}

class _TopicFeedSelectorState<T> extends State<_TopicFeedSelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.controller);
    widget.controller.topicFeeds.addListener(_select);
  }

  @override
  void didUpdateWidget(_TopicFeedSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.topicFeeds.removeListener(_select);
      widget.controller.topicFeeds.addListener(_select);
    }
    _value = widget.select(widget.controller);
  }

  void _select() {
    final next = widget.select(widget.controller);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);

  @override
  void dispose() {
    widget.controller.topicFeeds.removeListener(_select);
    super.dispose();
  }
}

class _SignedOutMessagesState extends StatelessWidget {
  const _SignedOutMessagesState();

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({bool connecting, String? error})>(
        select: (controller) =>
            (connecting: controller.connecting, error: controller.connectError),
        builder: (context, state, _) {
          final theme = Theme.of(context);
          final controller = ShellScope.read(context);

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DIcon(
                      DIcons.lock,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sign in to view your messages',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Private messages are tied to your forum account and '
                      'aren’t available while you’re signed out.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (state.error case final error?) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    DButton(
                      key: const ValueKey('messages-sign-in'),
                      label: const Text('Sign in'),
                      onPressed: () =>
                          unawaited(controller.connectCurrentInstance()),
                      icon: const DIcon(DIcons.user, size: 18),
                      variant: DButtonVariant.primary,
                      loading: state.connecting,
                      loadingLabel: const Text('Signing in…'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

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
                DButton(
                  label: const Text('Replace with deeper view'),
                  onPressed: () => controller.pushContent(
                    ContentRoute(
                      id: '${route.id}-$depth',
                      title: 'Topic $depth',
                      icon: DIcons.comments,
                      subtitle: 'opened from ${route.title}',
                    ),
                  ),
                  icon: const DIcon(DIcons.upRightFromSquare, size: 18),
                ),
                DButton(
                  label: const Text('Show sheet'),
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
    required this.canPop,
    required this.canReply,
    required this.bookmarkBusy,
    required this.isConnected,
    required this.filterCategories,
    required this.categoryFeed,
    required this.groupAccountIdentity,
  });

  factory _MainContentSnapshot.from(ShellController controller) =>
      _MainContentSnapshot(
        siteUrl: controller.currentInstance?.url,
        activeTabId: controller.activeTabId,
        route: controller.currentContent,
        canPop: controller.canPopContent,
        canReply: controller.canReplyHere,
        bookmarkBusy: switch ((
          controller.currentInstance?.url,
          controller.currentTopic,
        )) {
          (final siteUrl?, final topic?) => controller.bookmarkWriteInFlight(
            siteUrl: siteUrl,
            topicId: topic.id,
            targetType: BookmarkTargetType.topic,
            targetId: topic.id,
          ),
          _ => false,
        },
        isConnected: controller.currentInstance?.isConnected == true,
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
        groupAccountIdentity: _isGroupNamespace(controller.currentContent)
            ? controller.currentAccountIdentity
            : null,
      );

  final String? siteUrl;
  final String? activeTabId;
  final ContentRoute? route;
  final bool canPop;
  final bool canReply;
  final bool bookmarkBusy;
  final bool isConnected;
  final List<TopicCategory> filterCategories;
  final CategoryFeed? categoryFeed;
  final String? groupAccountIdentity;

  @override
  bool operator ==(Object other) =>
      other is _MainContentSnapshot &&
      siteUrl == other.siteUrl &&
      activeTabId == other.activeTabId &&
      identical(route, other.route) &&
      canPop == other.canPop &&
      canReply == other.canReply &&
      bookmarkBusy == other.bookmarkBusy &&
      isConnected == other.isConnected &&
      identical(filterCategories, other.filterCategories) &&
      identical(categoryFeed, other.categoryFeed) &&
      groupAccountIdentity == other.groupAccountIdentity;

  @override
  int get hashCode => Object.hash(
    siteUrl,
    activeTabId,
    identityHashCode(route),
    canPop,
    canReply,
    bookmarkBusy,
    isConnected,
    identityHashCode(filterCategories),
    identityHashCode(categoryFeed),
    groupAccountIdentity,
  );
}
