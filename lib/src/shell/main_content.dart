import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../app_shortcuts.dart';
import '../models/badge_route.dart';
import '../models/bookmark.dart';
import '../models/category_feed.dart';
import '../models/content_route.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'adaptive_shell.dart';
import 'badges_host.dart';
import 'categories_page.dart';
import 'category_icon.dart';
import 'category_notifications.dart';
import 'content_reading_lane.dart';
import 'draft_list.dart';
import 'forum_search.dart';
import 'forum_tabs_bar.dart';
import 'group_pages_coordinator.dart';
import 'group_pages_host.dart';
import 'group_pages_port.dart';
import 'group_pages_shell_port.dart';
import 'inline_action.dart';
import 'keyboard_navigation.dart';
import 'message_create_button.dart';
import 'message_inbox_page.dart';
import 'message_inbox_title.dart';
import 'open_link.dart';
import 'preferences_page.dart';
import 'resizable_pane.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'tags_page.dart';
import 'title_bar.dart';
import 'topic_create_button.dart';
import 'topic_filter_page.dart';
import 'topic_inbox_header.dart';
import 'topic_list_bottom_bar.dart';
import 'topic_list_layout.dart';
import 'topic_list_navigation.dart';
import 'topic_list_view.dart';
import 'topic_sheet_scope.dart';
import 'topic_title.dart';
import 'topic_view.dart';
import 'user_activity.dart';
import 'user_menu_button.dart';
import 'user_summary.dart';
import 'users_page.dart';

class MainContent extends StatefulWidget {
  const MainContent({super.key, required this.layout, this.registry});

  final ShellLayout layout;
  final PluginRegistry? registry;

  @override
  State<MainContent> createState() => _MainContentState();
}

class _MainContentState extends State<MainContent> {
  final GroupPagesCoordinator _groupPages = GroupPagesCoordinator();
  VoidCallback? _unregisterRefresher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unregisterRefresher?.call();
    _unregisterRefresher = ShellScope.identityOf(context)
        .registerContentRefresher(
          () => _groupPages.page.isOwned
              ? _groupPages.requestLoad(refresh: true)
              : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final background = TopicSheetScope.isBackground(context);
    return ShellSelector<_MainContentSnapshot>(
      select: (shell) =>
          _MainContentSnapshot.from(shell, background: background),
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
    _unregisterRefresher?.call();
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
    final forumTabsEnabled =
        ShellScope.read(context).forumTabsEnabled &&
        !TopicSheetScope.isBackground(context);

    final route = state.route;
    if (route == null) return ColoredBox(color: theme.shell.content);
    final pluginContent = registry.content(context, route);
    final pluginOwnsChrome = registry.ownsContentChrome(context, route);
    final sourceRoute = state.sourceRoute;
    if (pluginContent == null &&
        !pluginOwnsChrome &&
        sourceRoute != null &&
        (!sourceRoute.isMessages || state.isConnected)) {
      return Material(
        color: theme.shell.content,
        child: SafeArea(
          left: false,
          child: Column(
            children: [
              if (forumTabsEnabled) const CurrentForumTabsBar(),
              Expanded(
                child: _TopicInboxWorkspace(
                  key: ValueKey((state.siteUrl, state.activeTabId)),
                  layout: layout,
                  state: state,
                  sourceRoute: sourceRoute,
                  registry: registry,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final usesTopicToolbar =
        !layout.isCompact &&
        !pluginOwnsChrome &&
        pluginContent == null &&
        !state.canPop &&
        route.categoryId == null &&
        registry.contentHeaderLeading(context, route) == null &&
        registry.contentHeaderTitleTrailing(context, route) == null &&
        registry.contentHeaderTitleAction(context, route) == null &&
        TopicListMode.fromRoute(route) != null;
    final topicListActions = usesTopicToolbar
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...registry.contentHeaderActions(context, route),
              _TopicCreateAction(
                controller: ShellScope.read(context),
                compact: ShellTitleBar.isSupported,
                leadingPadding: false,
              ),
            ],
          )
        : null;
    final Key contentKey;
    if (groupPages.childIdentity case final childIdentity?) {
      contentKey = ValueKey<GroupPagesChildIdentity>(childIdentity);
    } else if (route.isMessages && pluginContent == null && !pluginOwnsChrome) {
      // Folder changes must retain focus in the shared message navigation.
      contentKey = ValueKey((state.siteUrl, state.activeTabId, 'messages'));
    } else {
      contentKey = ValueKey<(String?, String?, String, int?)>((
        state.siteUrl,
        state.activeTabId,
        route.id,
        route.postNumber,
      ));
    }

    return Material(
      color: theme.shell.content,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            if (forumTabsEnabled) const CurrentForumTabsBar(),
            if (!pluginOwnsChrome &&
                !route.isTopic &&
                !(usesTopicToolbar && ShellTitleBar.isSupported))
              _ContentHeader(
                layout: layout,
                route: route,
                siteUrl: state.siteUrl,
                canPop: state.canPop,
                showCreateTopicAction:
                    pluginContent == null && !usesTopicToolbar,
                searchOnly: usesTopicToolbar,
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
                  topicListActions: topicListActions,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list owns a stable subtree, including when a small window shows only
/// the reader. Opening a topic must not dispose its scroll or paging state.
class _TopicInboxWorkspace extends StatefulWidget {
  const _TopicInboxWorkspace({
    super.key,
    required this.layout,
    required this.state,
    required this.sourceRoute,
    required this.registry,
  });

  final ShellLayout layout;
  final _MainContentSnapshot state;
  final ContentRoute sourceRoute;
  final PluginRegistry registry;

  @override
  State<_TopicInboxWorkspace> createState() => _TopicInboxWorkspaceState();
}

class _TopicInboxWorkspaceState extends State<_TopicInboxWorkspace> {
  final _listWidth = PanelWidthController(
    initialWidth: 325,
    minimumWidth: 304,
    maximumWidth: 480,
  );

  @override
  void dispose() {
    _listWidth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReadingShortcuts(
    sequenceContext: (
      widget.state.siteUrl,
      widget.state.activeTabId,
      widget.state.route,
    ),
    commands: {
      ReadingCommand.openNextTopic: () =>
          openAdjacentTopic(context, next: true, fromKeyboard: true),
      ReadingCommand.openPreviousTopic: () =>
          openAdjacentTopic(context, next: false, fromKeyboard: true),
    },
    child: _buildWorkspace(context),
  );

  Widget _buildWorkspace(
    BuildContext context,
  ) => ValueListenableBuilder<double>(
    valueListenable: _listWidth,
    builder: (context, _, _) => LayoutBuilder(
      builder: (context, constraints) {
        final controller = ShellScope.read(context);
        final layout = widget.layout;
        final state = widget.state;
        final sourceRoute = widget.sourceRoute;
        final registry = widget.registry;
        final theme = Theme.of(context);
        final topicOpen = state.route!.isTopic;
        final split = topicOpen && constraints.maxWidth >= 880;
        final maximumListWidth = (constraints.maxWidth - 520).clamp(
          304.0,
          480.0,
        );
        final listWidth = split
            ? _listWidth.effectiveWidth(maximum: maximumListWidth)
            : constraints.maxWidth;
        final buttonFontSize = DButton.fontSizeFor(DButtonSize.regular);
        final buttonTextScale =
            MediaQuery.textScalerOf(context).scale(buttonFontSize) /
            buttonFontSize;
        final showsUserMenu = !topicOpen && ShellTitleBar.columnsCarryUserMenu;
        final messages = sourceRoute.isMessages;
        final createAction = messages
            ? const MessageCreateButton(showLabel: true)
            : _TopicCreateAction(
                controller: controller,
                compact: true,
                fromList: true,
                leadingPadding: false,
              );
        Widget heading(Widget? navigation) => Row(
          key: const ValueKey('topic-list-heading'),
          children: [
            if (layout.isCompact)
              DButton.iconOnly(
                icon: const DIcon(DIcons.arrowLeft),
                tooltip: 'Back',
                variant: DButtonVariant.ghost,
                onPressed: () =>
                    controller.handleBack(canReturnToSidebar: true),
              ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    flex: 1,
                    fit: navigation == null ? FlexFit.tight : FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: navigation == null ? double.infinity : 220,
                      ),
                      child: messages
                          ? MessageInboxTitle(
                              selectedGroup: sourceRoute.messageGroupName,
                              keepTopicOpen: split,
                            )
                          : _TopicListHeadingTitle(
                              siteUrl: state.siteUrl,
                              categoryId: sourceRoute.categoryId,
                            ),
                    ),
                  ),
                  if (navigation != null) ...[
                    const SizedBox(width: DSpacing.sm),
                    Flexible(flex: 3, child: navigation),
                  ],
                ],
              ),
            ),
            ...registry.contentHeaderActions(context, sourceRoute),
          ],
        );
        // Account controls stay at the pane edge; title, tabs and actions
        // share the same reading lane as the topics below them.
        Widget buildHeading(BuildContext context, Widget? navigation) =>
            ContentReadingLane(
              widthLimit: topicListContentWidth,
              builder: (context, lane) => ConstrainedBox(
                constraints: const BoxConstraints(minHeight: shellHeaderHeight),
                child: Padding(
                  // Match the sidebar account header's baseline.
                  padding: EdgeInsets.only(bottom: showsUserMenu ? 1 : 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: DDirection.of(context) == TextDirection.ltr
                                ? lane.leftInset
                                : lane.rightInset,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(
                              width: lane.width,
                              child: Padding(
                                padding: EdgeInsetsDirectional.only(
                                  start: topicListHorizontalPadding,
                                  end: split
                                      ? topicInboxDividerInset
                                      : topicListHorizontalPadding,
                                ),
                                child: heading(navigation),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (topicOpen && split)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: DResizableHandle.resolveHitExtent(context, 8),
                          ),
                          child: TopicCloseButton(
                            canReturnToSidebar: layout.isCompact,
                          ),
                        ),
                      if (showsUserMenu)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...registry.shellHeaderActions(
                                context,
                                surface: PluginHeaderSurface.content,
                                compact: layout.isCompact,
                                ringColor: theme.shell.content,
                              ),
                              UserMenuButton(ringColor: theme.shell.content),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
        return Stack(
          children: [
            PositionedDirectional(
              key: const ValueKey('inbox-topic-list-pane'),
              start: 0,
              top: 0,
              bottom: 0,
              width: listWidth,
              child: ResizablePane(
                controller: _listWidth,
                resizeEnabled: split,
                edge: ResizablePaneEdge.trailing,
                resizeKey: 'inbox-list',
                semanticsLabel: messages
                    ? 'Resize message list'
                    : 'Resize topic list',
                maximumWidth: maximumListWidth,
                handleWidth: 8,
                // The resize handle owns the list/reader boundary. When the
                // list fills the reader, the shell or composer owns its edge.
                dividerWidth: 1,
                child: Offstage(
                  offstage: topicOpen && !split,
                  child: TickerMode(
                    enabled: !topicOpen || split,
                    child: Column(
                      children: [
                        if (!ShellTitleBar.isSupported)
                          const ContentReadingLaneBox(
                            widthLimit: topicListContentWidth,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                topicListHorizontalPadding,
                                0,
                                topicListHorizontalPadding,
                                8,
                              ),
                              child: ForumSearch(dense: true),
                            ),
                          ),
                        Expanded(
                          child: _FeedBackedContent(
                            route: sourceRoute,
                            siteUrl: state.siteUrl,
                            inbox: true,
                            keepTopicOpen: split,
                            topicListHeadingBuilder: buildHeading,
                          ),
                        ),
                        TopicListBottomBar(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: createAction),
                              if (state.isConnected &&
                                  state.siteUrl != null &&
                                  sourceRoute.categoryId != null) ...[
                                const SizedBox(width: DSpacing.sm),
                                CategoryNotificationLevelButton(
                                  siteUrl: state.siteUrl!,
                                  categoryId: sourceRoute.categoryId!,
                                  showLabel: listWidth >= 440 * buttonTextScale,
                                ),
                              ],
                            ],
                          ),
                          // The footer padding already clears the desktop handle.
                          trailingInset: split
                              ? DResizableHandle.resolveHitExtent(context, 8) -
                                    topicBottomBarPadding.horizontal / 2
                              : 0,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (topicOpen)
              PositionedDirectional(
                key: const ValueKey('inbox-topic-reader-pane'),
                start: split ? listWidth : 0,
                end: 0,
                top: 0,
                bottom: 0,
                child: TopicView(
                  key: ValueKey(state.route!.topicId),
                  inbox: true,
                  keepTopicListOpen: split,
                  route: state.route!,
                  canReturnToSidebar: layout.isCompact,
                  canReply: state.canReply,
                  bookmarkBusy: state.bookmarkBusy,
                  isConnected: state.isConnected,
                  registry: registry,
                ),
              ),
          ],
        );
      },
    ),
  );
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
    this.topicListActions,
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
  final Widget? topicListActions;

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
    if (route.isBadges && siteUrl != null) {
      return BadgesHost(
        siteUrl: siteUrl!,
        route: route.badgeRoute ?? const BadgeRoute.directory(),
      );
    }
    if (route.isUsers && siteUrl != null) {
      return UsersDirectoryHost(siteUrl: siteUrl!);
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
        inbox: true,
        canReturnToSidebar: layout.isCompact,
        route: route,
        canReply: canReply,
        bookmarkBusy: bookmarkBusy,
        isConnected: isConnected,
        registry: registry,
      );
    }
    if (pluginContent case final content?) return content;

    return _FeedBackedContent(
      route: route,
      siteUrl: siteUrl,
      topicListActions: topicListActions,
    );
  }
}

class _FeedBackedContent extends StatelessWidget {
  const _FeedBackedContent({
    required this.route,
    required this.siteUrl,
    this.filterCategories = const [],
    this.fallback,
    this.topicListActions,
    this.topicListHeadingBuilder,
    this.inbox = false,
    this.keepTopicOpen = false,
  });

  final ContentRoute route;
  final String? siteUrl;
  final List<TopicCategory> filterCategories;
  final Widget? fallback;
  final Widget? topicListActions;
  final TopicListHeadingBuilder? topicListHeadingBuilder;
  final bool inbox;
  final bool keepTopicOpen;

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return _TopicFeedSelector<TopicFeed?>(
      controller: controller,
      select: (controller) => controller.currentFeed,
      builder: (context, feed, _) {
        final Widget content;
        if (route.isMessages) {
          content = MessageInboxPage(
            feed: feed ?? const TopicFeed(),
            heading: topicListHeadingBuilder?.call(context, null),
            keepTopicOpen: keepTopicOpen,
          );
        } else if (feed == null) {
          content = fallback ?? _ContentPlaceholder(route: route);
        } else if (route.id == 'filter' && siteUrl != null) {
          content = TopicFilterPage(
            siteUrl: siteUrl!,
            feed: feed,
            categories: filterCategories,
          );
        } else {
          content = TopicListView(
            feed: feed,
            inbox: inbox,
            showHeader: !route.isTopicListFilter,
          );
        }

        if (TopicListMode.fromRoute(route) != null || route.isTopicListFilter) {
          return TopicListNavigation(
            stacked: inbox,
            keepTopicOpen: keepTopicOpen,
            trailing: topicListActions,
            headingBuilder: topicListHeadingBuilder,
            child: content,
          );
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
    this.searchOnly = false,
  });

  final ShellLayout layout;
  final ContentRoute route;
  final String? siteUrl;
  final bool canPop;
  final bool showCreateTopicAction;
  final bool isConnected;
  final PluginRegistry registry;
  final GroupPagesCoordinator groupPages;
  final bool searchOnly;

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
              !searchOnly &&
              ((route.isMessages && isConnected) ||
                  !carriesSearch ||
                  constraints.maxWidth >= 620);
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
                  icon: const DIcon(DIcons.arrowLeft),
                  tooltip: 'Back',
                  variant: DButtonVariant.ghost,
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
                else if (route.categoryId != null && siteUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryHeaderIcon(
                      siteUrl: siteUrl!,
                      categoryId: route.categoryId!,
                      fallbackColor: route.color,
                      fallbackIcon: route.icon,
                    ),
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
                  child: route.isMessages && isConnected
                      ? MessageInboxTitle(
                          selectedGroup: route.messageGroupName,
                          trailing: contentHeaderTitleTrailing,
                        )
                      : route.categoryId != null && siteUrl != null
                      ? _CategoryHeaderIdentity(
                          route: route,
                          siteUrl: siteUrl!,
                          trailing: contentHeaderTitleTrailing,
                          titleAction: contentHeaderTitleAction,
                        )
                      : Semantics(
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
              if (carriesSearch &&
                  showRouteIdentity &&
                  constraints.maxWidth >= 620) ...[
                SizedBox(
                  key: _searchSlotKey,
                  width: searchWidth,
                  child: const ForumSearch(dense: true),
                ),
                const SizedBox(width: 4),
              ],
              if (!searchOnly) ...contentHeader,
              if (isConnected && siteUrl != null && route.categoryId != null)
                CategoryNotificationLevelButton(
                  siteUrl: siteUrl!,
                  categoryId: route.categoryId!,
                ),
              if (!route.isTopic &&
                  route.id != 'activity' &&
                  !route.isUsers &&
                  !route.isBadges &&
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

class _TopicListHeadingTitle extends StatelessWidget {
  const _TopicListHeadingTitle({
    required this.siteUrl,
    required this.categoryId,
  });

  final String? siteUrl;
  final int? categoryId;

  @override
  Widget build(BuildContext context) {
    Widget title(String name) => Text(
      name,
      key: const ValueKey('topic-list-title'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    final categoryId = this.categoryId;
    if (categoryId == null) return title('Topics');
    final siteUrl = this.siteUrl;
    if (siteUrl == null) return title('Category');
    return ValueListenableBuilder<TopicCategory?>(
      valueListenable: ShellScope.read(
        context,
      ).categoryRef(siteUrl, categoryId),
      builder: (context, category, _) => title(category?.name ?? 'Category'),
    );
  }
}

class _CategoryHeaderIcon extends StatelessWidget {
  const _CategoryHeaderIcon({
    required this.siteUrl,
    required this.categoryId,
    required this.fallbackColor,
    required this.fallbackIcon,
  });

  final String siteUrl;
  final int categoryId;
  final Color? fallbackColor;
  final DIconData fallbackIcon;

  @override
  Widget build(BuildContext context) => ShellSelector<TopicCategory?>(
    select: (controller) =>
        controller.categoryFor(categoryId, siteUrl: siteUrl),
    builder: (context, category, _) {
      if (category != null) {
        return CategoryIcon(
          key: const ValueKey('content-header-category-icon'),
          category: category,
          siteUrl: siteUrl,
          size: 18,
          squareSize: 12,
        );
      }
      final fallbackColor = this.fallbackColor;
      return fallbackColor == null
          ? DIcon(fallbackIcon, size: 18)
          : CategorySquare(color: fallbackColor, size: 12);
    },
  );
}

class _CategoryHeaderIdentity extends StatelessWidget {
  const _CategoryHeaderIdentity({
    required this.route,
    required this.siteUrl,
    required this.trailing,
    required this.titleAction,
  });

  final ContentRoute route;
  final String siteUrl;
  final Widget? trailing;
  final VoidCallback? titleAction;

  @override
  Widget build(BuildContext context) => ShellSelector<TopicCategory?>(
    select: (controller) {
      final category = controller.categoryFor(
        route.categoryId,
        siteUrl: siteUrl,
      );
      return controller.categoryFor(
        category?.parentCategoryId,
        siteUrl: siteUrl,
      );
    },
    builder: (context, parent, _) {
      if (parent == null) {
        return _CategoryHeaderTitle(
          route: route,
          trailing: trailing,
          titleAction: titleAction,
        );
      }

      final controller = ShellScope.read(context);
      final theme = Theme.of(context);
      return Row(
        children: [
          Flexible(
            child: LinkTarget(
              url: '/c/${parent.id}',
              title: parent.name,
              siteUrl: siteUrl,
              child: InlineAction.link(
                key: const ValueKey('content-header-parent-category'),
                onTap: () => controller.openCategory(parent, siteUrl: siteUrl),
                semanticLabel: 'Parent category: ${parent.name}',
                excludeChildSemantics: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CategoryIcon(
                        key: const ValueKey(
                          'content-header-parent-category-icon',
                        ),
                        category: parent,
                        siteUrl: siteUrl,
                        size: 15,
                        squareSize: 10,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          parent.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      DIcon(
                        DIcons.chevronRight,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 2,
            child: _CategoryHeaderTitle(
              route: route,
              trailing: trailing,
              titleAction: titleAction,
            ),
          ),
        ],
      );
    },
  );
}

class _CategoryHeaderTitle extends StatelessWidget {
  const _CategoryHeaderTitle({
    required this.route,
    required this.trailing,
    this.titleAction,
  });

  final ContentRoute route;
  final Widget? trailing;
  final VoidCallback? titleAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Row(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            route.title,
            key: const ValueKey('content-header-category-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        ?trailing,
      ],
    );
    if (titleAction == null) return title;

    return Semantics(
      button: true,
      label: 'Open ${route.title} details',
      child: InkWell(
        key: const ValueKey('content-header-title-action'),
        onTap: titleAction,
        borderRadius: BorderRadius.circular(4),
        child: title,
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
  const _TopicCreateAction({
    required this.controller,
    this.compact = false,
    this.leadingPadding = true,
    this.fromList = false,
  });

  final ShellController controller;
  final bool compact;
  final bool leadingPadding;
  final bool fromList;

  @override
  Widget build(BuildContext context) => _TopicFeedSelector<bool>(
    controller: controller,
    select: (controller) => fromList
        ? controller.canCreateTopicFromList
        : controller.canCreateTopicHere,
    builder: (context, canCreateTopic, _) => canCreateTopic
        ? Padding(
            padding: EdgeInsets.only(left: leadingPadding ? 8 : 0),
            child: TopicCreateButton(
              compact: compact,
              onPressed: () => unawaited(
                fromList
                    ? controller.openNewTopicFromList()
                    : controller.openNewTopic(),
              ),
            ),
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
    widget.controller.addListener(_select);
  }

  @override
  void didUpdateWidget(_TopicFeedSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.topicFeeds.removeListener(_select);
      oldWidget.controller.removeListener(_select);
      widget.controller.topicFeeds.addListener(_select);
      widget.controller.addListener(_select);
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
    widget.controller.removeListener(_select);
    super.dispose();
  }
}

class _SignedOutMessagesState extends StatelessWidget {
  const _SignedOutMessagesState();

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<({bool connecting, String? error})>(
    select: (controller) =>
        (connecting: controller.connecting, error: controller.connectError),
    builder: (context, state, _) {
      final theme = Theme.of(context);
      final controller = ShellScope.read(context);

      return Center(
        child: SingleChildScrollView(
          child: DEmpty(
            children: [
              const DEmptyHeader(
                children: [
                  DEmptyMedia(
                    variant: DEmptyMediaVariant.icon,
                    child: DIcon(DIcons.lock),
                  ),
                  DEmptyTitle('Sign in to view your messages'),
                  DEmptyDescription(
                    'Private messages are tied to your forum account and aren’t available while you’re signed out.',
                  ),
                ],
              ),
              if (state.error case final error?)
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
              DEmptyContent(
                children: [
                  DButton(
                    key: const ValueKey('messages-sign-in'),
                    label: const Text('Sign in'),
                    onPressed: () =>
                        unawaited(controller.connectCurrentInstance()),
                    icon: const DIcon(DIcons.user),
                    variant: DButtonVariant.primary,
                    loading: state.connecting,
                    loadingLabel: const Text('Signing in…'),
                  ),
                ],
              ),
            ],
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
                  icon: const DIcon(DIcons.upRightFromSquare),
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
                  icon: const DIcon(DIcons.arrowUp),
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
    required this.sourceRoute,
    required this.canPop,
    required this.canReply,
    required this.bookmarkBusy,
    required this.isConnected,
    required this.filterCategories,
    required this.categoryFeed,
    required this.groupAccountIdentity,
  });

  factory _MainContentSnapshot.from(
    ShellController controller, {
    bool background = false,
  }) {
    final stack = controller.contentStack;
    final route = background
        ? stack.reversed.where((route) => !route.isTopic).firstOrNull ??
              ContentRoute.topicList(TopicListMode.latest)
        : controller.currentContent;
    return _MainContentSnapshot(
      siteUrl: controller.currentInstance?.url,
      activeTabId: controller.activeTabId,
      route: route,
      sourceRoute: background
          ? (route?.isTopicList == true ? route : null)
          : controller.topicListContent,
      canPop: background ? stack.indexOf(route!) > 0 : controller.canPopContent,
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
      filterCategories: switch ((route?.id, controller.currentInstance?.url)) {
        ('filter', final siteUrl?) => controller.filterCategoriesFor(siteUrl),
        _ => const [],
      },
      categoryFeed: switch ((route?.id, controller.currentInstance?.url)) {
        ('all-categories', final siteUrl?) => controller.categoryFeedFor(
          siteUrl,
        ),
        _ => null,
      },
      groupAccountIdentity: _isGroupNamespace(route)
          ? controller.currentAccountIdentity
          : null,
    );
  }

  final String? siteUrl;
  final String? activeTabId;
  final ContentRoute? route;
  final ContentRoute? sourceRoute;
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
      identical(sourceRoute, other.sourceRoute) &&
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
    identityHashCode(sourceRoute),
    canPop,
    canReply,
    bookmarkBusy,
    isConnected,
    identityHashCode(filterCategories),
    identityHashCode(categoryFeed),
    groupAccountIdentity,
  );
}
