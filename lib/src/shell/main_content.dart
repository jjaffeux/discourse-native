import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/category_feed.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import '../models/post_flag.dart';
import '../models/topic.dart';
import '../models/topic_feed.dart';
import '../plugins/plugin_scope.dart';
import '../plugins/site_plugin.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_shell.dart';
import 'bookmark_ui.dart';
import 'categories_page.dart';
import 'choice_menu.dart';
import 'command_menu.dart';
import 'composer_controller.dart';
import 'composer_panel.dart';
import 'draft_list.dart';
import 'forum_search.dart';
import 'forum_tabs_bar.dart';
import 'post_flag_editor.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';
import 'title_bar.dart';
import 'topic_create_button.dart';
import 'topic_filter_page.dart';
import 'topic_list_view.dart';
import 'topic_share.dart';
import 'topic_title.dart';
import 'topic_view.dart';
import 'user_menu_button.dart';

/// The main region. There is only ever one of these on screen; navigating
/// deeper replaces what it shows rather than opening beside it.
class MainContent extends StatelessWidget {
  const MainContent({super.key, required this.layout, this.registry});

  final ShellLayout layout;
  final PluginRegistry? registry;

  @override
  Widget build(BuildContext context) {
    return ShellSelector<_MainContentSnapshot>(
      select: _MainContentSnapshot.from,
      builder: (context, state, _) => _MainContentBody(
        layout: layout,
        state: state,
        registry:
            registry ??
            PluginScope.maybeOf(context)?.registry ??
            pluginRegistry,
      ),
    );
  }
}

class _MainContentBody extends StatelessWidget {
  const _MainContentBody({
    required this.layout,
    required this.state,
    required this.registry,
  });

  final ShellLayout layout;
  final _MainContentSnapshot state;
  final PluginRegistry registry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forumTabsEnabled = ShellScope.read(context).forumTabsEnabled;

    final route = state.route;
    if (route == null) return ColoredBox(color: theme.shell.content);
    final pluginContent = registry.content(context, route);
    final pluginOwnsChrome = registry.ownsContentChrome(context, route);
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
            if (!pluginOwnsChrome)
              _ContentHeader(
                layout: layout,
                route: route,
                siteUrl: state.siteUrl,
                topic: state.topic,
                canPop: state.canPop,
                canReply: state.canReply,
                bookmarkBusy: state.bookmarkBusy,
                showCreateTopicAction: pluginContent == null,
                isConnected: state.isConnected,
                registry: registry,
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: KeyedSubtree(
                      key: contentKey,
                      child: _ContentViewport(
                        layout: layout,
                        route: route,
                        siteUrl: state.siteUrl,
                        isConnected: state.isConnected,
                        pluginContent: pluginContent,
                        filterCategories: state.filterCategories,
                        categoryFeed: state.categoryFeed,
                      ),
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

/// Chooses static destinations without subscribing them to topic-feed work.
///
/// Only the two destinations whose bodies render a [TopicFeed] cross the
/// [_TopicFeedSelector] boundary below. A page request can therefore update
/// the list without rebuilding the surrounding shell, plugin content, or
/// unrelated built-in pages.
class _ContentViewport extends StatelessWidget {
  const _ContentViewport({
    required this.layout,
    required this.route,
    required this.siteUrl,
    required this.isConnected,
    required this.pluginContent,
    required this.filterCategories,
    required this.categoryFeed,
  });

  final ShellLayout layout;
  final ContentRoute route;
  final String? siteUrl;
  final bool isConnected;
  final Widget? pluginContent;
  final List<TopicCategory> filterCategories;
  final CategoryFeed? categoryFeed;

  @override
  Widget build(BuildContext context) {
    if (!route.isTopic && route.id == 'messages' && !isConnected) {
      return const _SignedOutMessagesState();
    }
    if (!route.isTopic && route.id == 'drafts' && siteUrl != null) {
      return DraftListView(siteUrl: siteUrl!);
    }
    if (!route.isTopic &&
        route.id == 'all-categories' &&
        siteUrl != null &&
        categoryFeed != null) {
      return CategoriesPage(siteUrl: siteUrl!, feed: categoryFeed!);
    }
    if (!route.isTopic && route.id == 'filter' && siteUrl != null) {
      return _FeedBackedContent(
        route: route,
        siteUrl: siteUrl!,
        filterCategories: filterCategories,
        fallback: pluginContent,
      );
    }
    // A topic route wins over its originating list.
    if (route.isTopic) {
      return TopicView(
        showRecommendationsPanel: layout == ShellLayout.expanded,
      );
    }
    // A route an optional feature claims is that feature's, whichever list
    // happens to still be cached behind it.
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
        if (feed == null) return fallback ?? _ContentPlaceholder(route: route);
        if (route.id == 'filter' && siteUrl != null) {
          return TopicFilterPage(
            siteUrl: siteUrl!,
            feed: feed,
            categories: filterCategories,
          );
        }
        return TopicListView(feed: feed);
      },
    );
  }
}

class _ContentHeader extends StatelessWidget {
  const _ContentHeader({
    required this.layout,
    required this.route,
    required this.siteUrl,
    required this.topic,
    required this.canPop,
    required this.canReply,
    required this.bookmarkBusy,
    required this.showCreateTopicAction,
    required this.isConnected,
    required this.registry,
  });

  final ShellLayout layout;
  final ContentRoute route;
  final String? siteUrl;
  final TopicDetail? topic;
  final bool canPop;
  final bool canReply;
  final bool bookmarkBusy;
  final bool showCreateTopicAction;
  final bool isConnected;
  final PluginRegistry registry;

  static const _searchSlotKey = ValueKey('content-header-search-slot');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ShellScope.read(context);
    final topicHeader = switch ((siteUrl, topic)) {
      (final siteUrl?, final topic?) => registry.topicHeader(
        context,
        siteUrl,
        topic,
      ),
      _ => const <Widget>[],
    };
    final contentHeader = registry.contentHeaderActions(context, route);
    final contentHeaderTitleAction = registry.contentHeaderTitleAction(
      context,
      route,
    );
    final topicFlags = switch ((siteUrl, topic)) {
      (final String siteUrl, final TopicDetail topic) =>
        controller.availableTopicFlagTypes(siteUrl, topic),
      _ => const <PostFlagType>[],
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
          // On a signed-out phone the two explicit account actions need the
          // header width. Search remains one Back away in the sidebar's own
          // dedicated row; connected phones keep the field here as before.
          final carriesSearch =
              !ShellTitleBar.isSupported && !(layout.isCompact && !isConnected);
          final showRouteIdentity =
              !carriesSearch || constraints.maxWidth >= 620;
          final searchWidth = constraints.maxWidth >= 800 ? 360.0 : 260.0;

          return Row(
            children: [
              if (showBack)
                DButton.iconOnly(
                  onPressed: () => controller.handleBack(
                    canReturnToSidebar: layout.isCompact,
                  ),
                  icon: const DIcon(DIcons.arrowLeft, size: 20),
                  tooltip: 'Back',
                  variant: DButtonVariant.flat,
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
              ...topicHeader,
              if (route.isTopic && siteUrl != null && topic != null)
                DButton.iconOnly(
                  key: const ValueKey('topic-share-button'),
                  onPressed: () {
                    final instance = controller.currentInstance;
                    if (instance == null || instance.url != siteUrl) return;
                    unawaited(
                      showTopicShareSheet(
                        context: context,
                        title: topic!.title,
                        url: topicShareUrl(
                          siteUrl: siteUrl!,
                          topicId: topic!.id,
                          slug: route.slug,
                          config: instance.config,
                          username: instance.user?.username,
                        ),
                        onReplyAsNewTopic: topic!.canReplyAsNewTopic
                            ? () => controller.openReplyAsNewTopic(
                                topicContinuationMarkdown(
                                  title: topic!.title,
                                  url: topicShareUrl(
                                    siteUrl: siteUrl!,
                                    topicId: topic!.id,
                                    slug: route.slug,
                                    config: instance.config,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                  icon: const DIcon(DIcons.upRightFromSquare, size: 18),
                  tooltip: 'Share this topic',
                  variant: DButtonVariant.flat,
                ),
              if (route.isTopic &&
                  siteUrl != null &&
                  topic != null &&
                  topicFlags.isNotEmpty)
                DButton.iconOnly(
                  key: const ValueKey('topic-flag-button'),
                  onPressed:
                      controller.topicFlagWriteInFlight(siteUrl!, topic!.id)
                      ? null
                      : () => unawaited(
                          showTopicFlagEditor(
                            context: context,
                            siteUrl: siteUrl!,
                            topic: topic!,
                            flagTypes: topicFlags,
                          ),
                        ),
                  icon: const DIcon(DIcons.flag, size: 18),
                  tooltip: 'Flag this topic',
                  loading: controller.topicFlagWriteInFlight(
                    siteUrl!,
                    topic!.id,
                  ),
                  variant: DButtonVariant.flat,
                ),
              if (route.isTopic && siteUrl != null && topic != null)
                _TopicStatusButton(siteUrl: siteUrl!, topic: topic!),
              if (route.isTopic &&
                  siteUrl != null &&
                  topic != null &&
                  controller.currentInstance?.user != null)
                _TopicPinButton(siteUrl: siteUrl!, topic: topic!),
              if (route.isTopic &&
                  isConnected &&
                  siteUrl != null &&
                  topic != null)
                _TopicNotificationLevelButton(siteUrl: siteUrl!, topic: topic!),
              if (route.isTopic &&
                  siteUrl != null &&
                  topic != null &&
                  controller.currentInstance?.user != null)
                DButton.iconOnly(
                  onPressed: bookmarkBusy
                      ? null
                      : () => unawaited(
                          showTopicBookmarkMenu(
                            context: context,
                            controller: controller,
                            siteUrl: siteUrl!,
                            topic: topic!,
                          ),
                        ),
                  icon: bookmarkBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : DIcon(
                          topic!.topicBookmark?.reminderAt != null
                              ? DIcons.discourseBookmarkClock
                              : topic!.hasBookmarks
                              ? DIcons.bookmark
                              : DIcons.farBookmark,
                          size: 20,
                        ),
                  tooltip: topic!.hasBookmarks
                      ? 'Manage ${topic!.bookmarks.length} topic bookmark${topic!.bookmarks.length == 1 ? '' : 's'}'
                      : 'Bookmark this topic',
                  loading: bookmarkBusy,
                  variant: DButtonVariant.flat,
                ),
              if (route.isTopic && canReply)
                DButton.iconOnly(
                  onPressed: () => controller.openReply(),
                  icon: const DIcon(DIcons.reply, size: 20),
                  tooltip: 'Reply to this topic',
                  variant: DButtonVariant.flat,
                ),
              if (!route.isTopic && showCreateTopicAction)
                _TopicCreateAction(controller: controller),
              // Only where there is no title bar above to hold it: this is the
              // furthest right the shell goes once the strip is gone.
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

class _TopicPinButton extends StatelessWidget {
  const _TopicPinButton({required this.siteUrl, required this.topic});

  final String siteUrl;
  final TopicDetail topic;

  Future<void> _change(BuildContext context, bool pinned) async {
    final error = await ShellScope.read(context)
        .updateTopicPinPreference(siteUrl, topic.id, pinned);
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    if (!topic.hasPinPreference) return const SizedBox.shrink();
    final options = [
      ChoiceMenuOption(
        value: true,
        title: topic.pinnedGlobally ? 'Pinned globally' : 'Pinned',
        description: 'Keep this topic at the top of its list',
        icon: DIcons.thumbtack,
      ),
      const ChoiceMenuOption(
        value: false,
        title: 'Unpinned',
        description: 'Do not keep this topic at the top',
        icon: DIcons.thumbtack,
      ),
    ];
    return ShellSelector<bool>(
      select: (controller) =>
          controller.topicPinWriteInFlight(siteUrl, topic.id),
      builder: (context, busy, _) => ChoiceMenuAnchor<bool>(
        title: 'Pinned topic options',
        value: topic.pinned,
        options: options,
        enabled: !busy,
        onSelected: (pinned) => unawaited(_change(context, pinned)),
        builder: (context, openMenu) => DButton.iconOnly(
          key: const ValueKey('topic-pin-button'),
          tooltip: 'Pinned topic options',
          onPressed: openMenu,
          loading: busy,
          variant: DButtonVariant.flat,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const DIcon(DIcons.thumbtack, size: 18),
        ),
      ),
    );
  }
}

enum _TopicCommand { selectPosts, closed, archived, visible, delete, recover }

class _TopicStatusButton extends StatelessWidget {
  const _TopicStatusButton({required this.siteUrl, required this.topic});

  final String siteUrl;
  final TopicDetail topic;

  Future<void> _change(
    BuildContext context,
    TopicStatusProperty status,
    bool enabled,
  ) async {
    final controller = ShellScope.read(context);
    final error = await controller.updateTopicStatus(
      siteUrl,
      topic.id,
      status,
      enabled,
    );
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _changeDeletion(BuildContext context, bool deleted) async {
    final controller = ShellScope.read(context);
    if (deleted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete topic?'),
          content: const Text(
            'This removes the topic and all of its replies. Staff may be able '
            'to recover it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('topic-delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    final error = await controller.setTopicDeleted(siteUrl, topic.id, deleted);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Core redirects an ordinary author after deletion because the topic is no
    // longer readable to them. Staff keep it in place so Recover is available.
    if (deleted && controller.currentInstance?.user?.staff != true) {
      controller.handleBack(canReturnToSidebar: false);
    }
  }

  void _selectCommand(BuildContext context, _TopicCommand command) {
    switch (command) {
      case _TopicCommand.selectPosts:
        final controller = ShellScope.read(context);
        controller.setTopicPostSelectionEnabled(
          siteUrl,
          topic.id,
          !controller.topicPostSelectionEnabled(siteUrl, topic.id),
        );
      case _TopicCommand.closed:
        unawaited(_change(context, TopicStatusProperty.closed, !topic.closed));
      case _TopicCommand.archived:
        unawaited(
          _change(context, TopicStatusProperty.archived, !topic.archived),
        );
      case _TopicCommand.visible:
        unawaited(
          _change(context, TopicStatusProperty.visible, !topic.visible),
        );
      case _TopicCommand.delete:
        unawaited(_changeDeletion(context, true));
      case _TopicCommand.recover:
        unawaited(_changeDeletion(context, false));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!topic.hasStatusActions) return const SizedBox.shrink();
    final hasStatusCommands =
        topic.canCloseTopic ||
        topic.canArchiveTopic ||
        topic.canToggleTopicVisibility;
    final hasPriorToDestructive = topic.canSelectPosts || hasStatusCommands;
    final options = [
      if (topic.canSelectPosts)
        const CommandMenuOption(
          value: _TopicCommand.selectPosts,
          label: 'Select posts',
          icon: DIcons.list,
          key: ValueKey('topic-select-posts'),
        ),
      if (topic.canCloseTopic)
        CommandMenuOption(
          value: _TopicCommand.closed,
          label: topic.closed ? 'Open topic' : 'Close topic',
          icon: DIcons.lock,
          key: const ValueKey('topic-status-closed'),
          dividerBefore: topic.canSelectPosts,
        ),
      if (topic.canArchiveTopic)
        CommandMenuOption(
          value: _TopicCommand.archived,
          label: topic.archived ? 'Unarchive topic' : 'Archive topic',
          icon: topic.archived ? DIcons.folderOpen : DIcons.folder,
          key: const ValueKey('topic-status-archived'),
          dividerBefore: topic.canSelectPosts && !topic.canCloseTopic,
        ),
      if (topic.canToggleTopicVisibility)
        CommandMenuOption(
          value: _TopicCommand.visible,
          label: topic.visible ? 'Make topic unlisted' : 'Make topic visible',
          icon: topic.visible ? DIcons.farEyeSlash : DIcons.farEye,
          key: const ValueKey('topic-status-visible'),
          dividerBefore:
              topic.canSelectPosts &&
              !topic.canCloseTopic &&
              !topic.canArchiveTopic,
        ),
      if (topic.canDeleteTopic)
        CommandMenuOption(
          value: _TopicCommand.delete,
          label: 'Delete topic',
          icon: DIcons.trashCan,
          key: const ValueKey('topic-status-delete'),
          dividerBefore: hasPriorToDestructive,
          destructive: true,
        ),
      if (topic.canRecoverTopic)
        CommandMenuOption(
          value: _TopicCommand.recover,
          label: 'Recover topic',
          icon: DIcons.arrowRotateLeft,
          key: const ValueKey('topic-status-recover'),
          dividerBefore: !topic.canDeleteTopic && hasPriorToDestructive,
        ),
    ];
    return ShellSelector<bool>(
      select: (controller) =>
          controller.topicStatusWriteInFlight(siteUrl, topic.id) ||
          controller.topicDeletionWriteInFlight(siteUrl, topic.id) ||
          controller.topicPostSelectionWriteInFlight(siteUrl, topic.id),
      builder: (context, busy, _) => CommandMenuAnchor<_TopicCommand>(
        title: 'Topic actions',
        options: options,
        enabled: !busy,
        onSelected: (command) => _selectCommand(context, command),
        builder: (context, openMenu) => DButton.iconOnly(
          key: const ValueKey('topic-status-button'),
          tooltip: 'Topic actions',
          onPressed: openMenu,
          loading: busy,
          variant: DButtonVariant.flat,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const DIcon(DIcons.gear, size: 18),
        ),
      ),
    );
  }
}

class _TopicNotificationLevelButton extends StatelessWidget {
  const _TopicNotificationLevelButton({
    required this.siteUrl,
    required this.topic,
  });

  final String siteUrl;
  final TopicDetail topic;

  static const _options = [
    ChoiceMenuOption(
      value: TopicNotificationLevel.watching,
      title: 'Watching',
      description: 'Every reply and unread count',
      icon: DIcons.discourseBellExclamation,
    ),
    ChoiceMenuOption(
      value: TopicNotificationLevel.tracking,
      title: 'Tracking',
      description: 'Mentions, replies, and unread count',
      icon: DIcons.bell,
    ),
    ChoiceMenuOption(
      value: TopicNotificationLevel.normal,
      title: 'Normal',
      description: 'Mentions and replies only',
      icon: DIcons.farBell,
    ),
    ChoiceMenuOption(
      value: TopicNotificationLevel.muted,
      title: 'Muted',
      description: 'No notifications; hidden from Latest',
      icon: DIcons.discourseBellSlash,
    ),
  ];

  static DIconData _iconFor(TopicNotificationLevel level) => switch (level) {
    TopicNotificationLevel.watching => DIcons.discourseBellExclamation,
    TopicNotificationLevel.tracking => DIcons.bell,
    TopicNotificationLevel.normal => DIcons.farBell,
    TopicNotificationLevel.muted => DIcons.discourseBellSlash,
  };

  @override
  Widget build(BuildContext context) {
    final controller = ShellScope.read(context);
    return ChoiceMenuAnchor<TopicNotificationLevel>(
      title: 'Topic notifications',
      value: topic.notificationLevel,
      options: _options,
      onSelected: (level) => unawaited(
        controller.updateTopicNotificationLevel(siteUrl, topic.id, level),
      ),
      builder: (context, openMenu) => DButton.iconOnly(
        tooltip: 'Topic notifications',
        onPressed: openMenu,
        icon: DIcon(_iconFor(topic.notificationLevel), size: 18),
        variant: DButtonVariant.flat,
      ),
    );
  }
}

/// Observes only the capability derived from the current feed.
///
/// Feed pagination replaces the immutable feed snapshot, but does not change
/// this boolean, so the header action remains untouched while the list moves
/// through loading and loaded states.
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

/// A selected listenable boundary for state owned by
/// [ShellController.topicFeeds].
///
/// Navigation still comes through [_MainContentSnapshot] and updates this
/// widget normally. Between navigation changes, only the selected feed value
/// can mark this subtree dirty.
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

/// A defensive boundary for a stale restored tab or programmatic route.
///
/// Anonymous readers cannot ordinarily reach Messages because its sidebar
/// destination is hidden. If they do, explain the account boundary instead of
/// presenting an empty inbox or the generic unfinished-route placeholder.
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
                    FilledButton.icon(
                      key: const ValueKey('messages-sign-in'),
                      onPressed: state.connecting
                          ? null
                          : () =>
                                unawaited(controller.connectCurrentInstance()),
                      icon: state.connecting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : const DIcon(DIcons.user, size: 18),
                      label: Text(state.connecting ? 'Signing in…' : 'Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
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
    required this.composer,
    required this.canPop,
    required this.canReply,
    required this.bookmarkBusy,
    required this.isConnected,
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
        composer: controller.visibleComposer,
        canPop: controller.canPopContent,
        canReply: controller.canReplyHere,
        bookmarkBusy: switch (controller.currentTopic) {
          final topic? => controller.bookmarkWriteInFlight(
            topicId: topic.id,
            targetType: BookmarkTargetType.topic,
            targetId: topic.id,
          ),
          null => false,
        },
        isConnected: controller.currentInstance?.isConnected == true,
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
  final ComposerController? composer;
  final bool canPop;
  final bool canReply;
  final bool bookmarkBusy;
  final bool isConnected;
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
      identical(composer, other.composer) &&
      canPop == other.canPop &&
      canReply == other.canReply &&
      bookmarkBusy == other.bookmarkBusy &&
      isConnected == other.isConnected &&
      canAssignLegacyTargets == other.canAssignLegacyTargets &&
      identical(filterCategories, other.filterCategories) &&
      identical(categoryFeed, other.categoryFeed);

  @override
  int get hashCode => Object.hash(
    siteUrl,
    activeTabId,
    identityHashCode(route),
    identityHashCode(topic),
    identityHashCode(composer),
    canPop,
    canReply,
    bookmarkBusy,
    isConnected,
    canAssignLegacyTargets,
    identityHashCode(filterCategories),
    identityHashCode(categoryFeed),
  );
}
