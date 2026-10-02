import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:timezone/timezone.dart' as tz;

import '../foundation/calendar_day.dart';
import '../foundation/clock_time.dart';
import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/list_link.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import '../theme/discourse_typography.dart';
import 'avatar_image.dart';
import 'external_link.dart';
import 'forum_icon.dart';
import 'forum_tabs_bar.dart';
import 'instance_actions.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'site_url.dart';
import 'start_page_drag.dart';
import 'topic_list_actions.dart';

/// The landing surface for an otherwise empty forum tab.
class NewTabPage extends StatelessWidget {
  const NewTabPage({super.key, required this.onBrowseTopics});

  final VoidCallback onBrowseTopics;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    if (shell == null) return _buildPage(context);
    return ForumTabListenableBuilder(
      listenable: Listenable.merge([
        shell.accountActivity.bookmarksListenable,
        shell.topicFeeds,
        shell.search,
        TimezoneEnvironment.instance,
        ...?PluginScope.maybeOf(context)?.registry.sidebarListenables(context),
      ]),
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    final forum = shell?.currentInstance;
    final registry = PluginScope.maybeOf(context)?.registry;
    final siteUrl = forum?.url;
    final pluginSections =
        registry?.sidebarSections(context) ?? const <SidebarSection>[];
    final conversations = [
      for (final section in pluginSections)
        for (final destination in section.destinations)
          if (destination.enabled &&
              RegExp(r'^chat-c-[1-9][0-9]*$').hasMatch(destination.id))
            destination,
    ];
    final hasChat = pluginSections.any(
      (section) =>
          section.id.startsWith('chat') || section.id == 'direct-messages',
    );
    // Contributed community shortcuts are the ones the phone dock offers;
    // core must not name the feature that supplies them.
    final shortcuts =
        registry
            ?.communitySidebarDestinations(context)
            .where(
              (destination) =>
                  destination.mobileNavigationLabel != null &&
                  destination.enabled,
            )
            .toList() ??
        const <SidebarDestination>[];
    final categoryDetails = siteUrl == null
        ? <int, TopicCategory>{}
        : {
            for (final category in shell!.filterCategoriesFor(siteUrl))
              category.id: category,
          };
    // This catalogue is scoped by the server to the current reader. History
    // must never reintroduce categories removed by a permission change.
    final categories = siteUrl == null
        ? <ContentRoute>[]
        : [
            for (final recent in shell!.recentCategoriesFor(siteUrl))
              if (categoryDetails[recent.categoryId] case final category?)
                ContentRoute.list(
                  ListLink.parse('/c/${category.slug}/${category.id}')!,
                  title: category.name,
                  color: Color(category.colorValue),
                ),
          ];
    final recentTopics = siteUrl == null
        ? <ContentRoute>[]
        : shell!.recentTopicsFor(siteUrl);
    final recentChats = siteUrl == null
        ? <SidebarDestination>[]
        : [
            for (final recent in shell!.recentChannelsFor(siteUrl))
              for (final destination in conversations)
                if (destination.id == recent.id) destination,
          ];
    final bookmarks = siteUrl == null
        ? <Bookmark>[]
        : shell!.bookmarksFor(siteUrl).loaded
        ? shell
              .bookmarksFor(siteUrl)
              .bookmarks
              .where((b) => b.path != null)
              .toList()
        : <Bookmark>[];
    final closed =
        shell?.recentlyClosedTabsForCurrentForum ?? const <ForumTab>[];
    final chatDestination = SidebarDestination(
      id: 'chat-channels',
      label: context.l10n.chat,
      icon: DIcons.comments,
    );
    void openCategories() => openLink(context, shell!.siteLink('/categories'));
    void openChat() => shell!.selectDestination(chatDestination);
    void openBookmarks() => shell!.selectDestination(
      SidebarDestination(
        id: 'user-bookmarks',
        label: context.l10n.bookmarks,
        icon: DIcons.bookmark,
      ),
    );

    final query = siteUrl == null
        ? ''
        : shell!.search.startPageQueryFor(
            siteUrl,
            ForumTabScope.idOf(context) ?? shell.activeTabId ?? 'start',
          );
    List<_StartPageEntry> matching(List<_StartPageEntry> entries) {
      final term = query.trim().toLowerCase();
      return term.isEmpty
          ? entries
          : entries
                .where(
                  (entry) => '${entry.title} ${entry.description ?? ''}'
                      .toLowerCase()
                      .contains(term),
                )
                .toList();
    }

    final categoryRows = matching([
      for (final route in categories.take(4))
        _StartPageEntry.fromRoute(
          route,
          () => _openRoute(context, route),
          siteUrl: siteUrl,
          icon: pluginIconNamed(
            context,
            categoryDetails[route.categoryId]?.icon,
          ),
          count: route.categoryId == null
              ? null
              : shell!.categoryActivityCountFor(siteUrl!, route.categoryId!),
          description: categoryDetails[route.categoryId]?.descriptionExcerpt,
        ),
    ]);
    final chatRows = matching([
      for (final destination in recentChats.take(4))
        _StartPageEntry.fromRoute(
          ContentRoute.fromDestination(destination),
          () => shell!.selectDestination(destination),
          siteUrl: siteUrl,
          destination: destination,
        ),
    ]);
    final topicRows = matching([
      for (final route in recentTopics.take(4))
        _StartPageEntry.fromTopic(
          route,
          siteUrl!,
          route.topicId == null
              ? null
              : shell!.store.read<Topic>(siteUrl, route.topicId!),
          categoryDetails,
          () => _openRoute(context, route),
        ),
    ]);
    final bookmarkRows = matching([
      for (final bookmark in bookmarks)
        _StartPageEntry(
          id: 'bookmark-${bookmark.id}',
          title: bookmark.title.isEmpty
              ? context.l10n.bookmark
              : bookmark.title,
          icon: bookmark.coreTargetType == BookmarkTargetType.post
              ? DIcons.reply
              : bookmark.coreTargetType == BookmarkTargetType.topic
              ? DIcons.layerGroup
              : DIcons.bookmark,
          color: categoryDetails[bookmark.categoryId] == null
              ? null
              : Color(categoryDetails[bookmark.categoryId]!.colorValue),
          time: bookmark.reminderAt == null
              ? null
              : bookmark.reminderAt!.isBefore(DateTime.now())
              ? context.l10n.due
              : context.l10n.reminderNewtabpage,
          description: [
            ?bookmark.name,
            ?categoryDetails[bookmark.categoryId]?.name,
            ?bookmark.bookmarkableType,
          ].join(' '),
          path: bookmark.path,
          targetBookmark: bookmark,
          onPressed: () => openLink(context, bookmark.path!),
        ),
    ]).take(4).toList();
    final closedRows = matching([
      for (final tab in closed)
        _closedEntry(context, tab, siteUrl!, categoryDetails, conversations),
    ]).take(query.isEmpty ? 8 : 16).toList();
    final found =
        categoryRows.length +
        chatRows.length +
        topicRows.length +
        bookmarkRows.length +
        closedRows.length;
    final primarySections = siteUrl == null
        ? <_StartSection>[]
        : <_StartSection>[
            if (bookmarkRows.isNotEmpty)
              _StartSection(
                title: context.l10n.bookmarks,
                icon: DIcons.bookmark,
                rows: bookmarkRows,
                siteUrl: siteUrl,
                onHeading: openBookmarks,
              ),
            if (categoryRows.isNotEmpty)
              _StartSection(
                title: context.l10n.categories,
                icon: DIcons.tag,
                rows: categoryRows,
                siteUrl: siteUrl,
                onHeading: openCategories,
              ),
            if (hasChat && chatRows.isNotEmpty)
              _StartSection(
                title: context.l10n.chat,
                icon: DIcons.comment,
                rows: chatRows,
                siteUrl: siteUrl,
                onHeading: openChat,
              ),
            if (topicRows.isNotEmpty)
              _StartSection(
                title: context.l10n.recentTopics,
                icon: DIcons.layerGroup,
                rows: topicRows,
                siteUrl: siteUrl,
                onHeading: onBrowseTopics,
              ),
          ];

    final links = <_LinkButton>[
      if (bookmarkRows.isEmpty && forum?.user != null)
        _LinkButton(
          label: context.l10n.bookmarks,
          icon: DIcons.bookmark,
          onPressed: openBookmarks,
        ),
      if (categoryRows.isEmpty)
        _LinkButton(
          label: context.l10n.categories,
          icon: DIcons.tag,
          url: shell?.siteLink('/categories'),
          onPressed: openCategories,
        ),
      if (hasChat && chatRows.isEmpty)
        _LinkButton(
          label: context.l10n.chat,
          icon: DIcons.comment,
          content: ContentRoute.fromDestination(chatDestination),
          onPressed: openChat,
        ),
      if (topicRows.isEmpty)
        _LinkButton(
          label: context.l10n.recentTopics,
          icon: DIcons.layerGroup,
          url: shell?.siteLink('/latest'),
          onPressed: onBrowseTopics,
        ),
      if (forum?.user != null)
        _LinkButton(
          label: context.l10n.messages,
          icon: DIcons.inbox,
          url: shell!.siteLink('/my/messages'),
          onPressed: () => openLink(context, shell.siteLink('/my/messages')),
        ),
      if (shell != null && siteUrl != null) ...[
        _LinkButton(
          label: context.l10n.groups,
          icon: DIcons.users,
          url: shell.siteLink('/g'),
          onPressed: () => openLink(context, shell.siteLink('/g')),
        ),
        _LinkButton(
          label: context.l10n.badges,
          icon: DIcons.certificate,
          url: shell.siteLink('/badges'),
          onPressed: () => openLink(context, shell.siteLink('/badges')),
        ),
        for (final shortcut in shortcuts)
          _LinkButton(
            label: shortcut.label,
            icon: shortcut.icon,
            content: ContentRoute.fromDestination(shortcut),
            onPressed: () => shell.selectDestination(shortcut),
          ),
        _LinkButton(
          label: context.l10n.users,
          icon: DIcons.user,
          url: shell.siteLink('/u'),
          onPressed: () => openLink(context, shell.siteLink('/u')),
        ),
        if (forum?.user != null)
          _LinkButton(
            label: context.l10n.preferences,
            icon: DNativeIcons.sliders,
            onPressed: () => shell.openPreferences(siteUrl),
          ),
        _LinkButton(
          label: context.l10n.settings,
          icon: DIcons.gear,
          onPressed: () => shell.openForumSettings(siteUrl),
        ),
      ],
    ];
    final title = LayoutBuilder(
      builder: (context, constraints) => Row(
        key: const ValueKey('start-page-heading'),
        spacing: 10,
        children: [
          if (forum != null) ForumIcon(forum: forum, size: 28),
          Flexible(
            child: forum == null
                ? Text(
                    context.l10n.startPage,
                    style: Theme.of(context).textTheme.headlineSmall,
                  )
                : DDropdownMenu(
                    content: DDropdownMenuContent(
                      width: 240,
                      children: [
                        DDropdownMenuItem(
                          leading: const DIcon(DIcons.upRightFromSquare),
                          child: Text(
                            context.l10n.openForumInBrowser,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () =>
                              unawaited(openExternalLink(forum.url)),
                        ),
                        const DDropdownMenuSeparator(),
                        DDropdownMenuItem(
                          variant: DDropdownMenuItemVariant.destructive,
                          leading: const DIcon(DIcons.trashCan),
                          child: Text(
                            context.l10n.removeForum,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () =>
                              unawaited(confirmInstanceRemoval(context, forum)),
                        ),
                      ],
                    ),
                    child: DDropdownMenuTrigger(
                      builder: (context, state) => DButton(
                        key: const ValueKey('start-page-forum-options'),
                        variant: DButtonVariant.inline,
                        semanticLabel: context.l10n.showForumActions,
                        focusNode: state.focusNode,
                        hasPopup: true,
                        expanded: state.open,
                        icon: const DIcon(DIcons.chevronDown, size: 10),
                        iconPosition: DButtonIconPosition.end,
                        label: SiteEmojiText.plain(
                          forum.title,
                          siteUrl: forum.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                        ),
                        onPressed: state.toggle,
                      ),
                    ),
                  ),
          ),
          if (forum != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .45),
              child: DButton(
                key: const ValueKey('start-page-forum-website'),
                variant: DButtonVariant.inline,
                size: DButtonSize.chip,
                foregroundColor: DTokens.of(context).mutedForeground,
                isLink: true,
                label: Text(
                  Uri.tryParse(forum.url)?.host ?? forum.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => unawaited(openExternalLink(forum.url)),
              ),
            ),
        ],
      ),
    );
    final controls = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 8,
      children: [
        if (siteUrl != null)
          TopicListFilterMenu(
            siteUrl: siteUrl,
            query: '',
            label: context.l10n.startPageFilters,
          ),
        if (shell != null) Expanded(child: _ShortcutBar(links: links)),
      ],
    );
    return DPageSurface(
      framed: false,
      hideHeaderOnScroll: true,
      scrollBody: true,
      identity: (siteUrl, ForumTabScope.idOf(context)),
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          shell?.desktopPanelsEnabled == true ? 4 : 16,
          16,
          16,
        ),
        child: title,
      ),
      headerControls: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            controls,
            if (query.isNotEmpty)
              Text(
                found == 0
                    ? context.l10n.startPageNoMatches(query)
                    : context.l10n.startPageResults(found, query),
                key: const ValueKey('start-page-search-results'),
                style: TextStyle(color: DTokens.of(context).mutedForeground),
              ),
          ],
        ),
      ),
      child: DPageReadingLaneBox(
        child: Padding(
          key: const ValueKey('start-page-content'),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 18,
            children: [
              if (closedRows.isNotEmpty)
                _StartSection(
                  title: context.l10n.recentlyClosedNewtabpage,
                  icon: DIcons.arrowRotateLeft,
                  rows: closedRows,
                  fullWidth: true,
                  siteUrl: siteUrl!,
                ),
              if (primarySections.isNotEmpty)
                _SectionGrid(sections: primarySections),
              if (shell == null)
                DButton(
                  onPressed: onBrowseTopics,
                  label: Text(context.l10n.browseLatestTopics),
                ),
            ],
          ),
        ),
      ),
    );
  }

  _StartPageEntry _closedEntry(
    BuildContext context,
    ForumTab tab,
    String siteUrl,
    Map<int, TopicCategory> categories,
    List<SidebarDestination> conversations,
  ) {
    final shell = ShellScope.read(context);
    final route = tab.currentContent;
    final topic = route.topicId == null
        ? null
        : shell.store.read<Topic>(siteUrl, route.topicId!);
    final category = categories[route.categoryId ?? topic?.categoryId];
    final destination = conversations
        .where((d) => d.id == route.id)
        .firstOrNull;
    return _StartPageEntry(
      id: 'closed-${tab.id}',
      title:
          topic?.title ?? category?.name ?? destination?.label ?? route.title,
      icon:
          destination?.icon ??
          pluginIconNamed(context, category?.icon) ??
          (topic?.pinned == true
              ? DIcons.thumbtack
              : topic?.closed == true
              ? DIcons.lock
              : route.icon),
      color:
          destination?.iconColor ??
          (category == null ? route.color : Color(category.colorValue)),
      count:
          topic?.unreadCount ??
          destination?.unreadCount ??
          (category == null
              ? null
              : shell.categoryActivityCountFor(siteUrl, category.id)),
      activityAt: topic?.bumpedAt ?? destination?.lastActivityAt,
      avatarUrl: destination?.avatarUrl,
      prefixBuilder: destination?.prefixBuilder,
      path: _recentRouteUrl(siteUrl, route),
      bookmarkUrl: route.topicId == null
          ? null
          : resolveSiteRootPath(siteUrl, '/t/${route.topicId}'),
      onPressed: () => shell.reopenClosedTab(tab.id),
    );
  }

  void _openRoute(BuildContext context, ContentRoute route) {
    final site = ShellScope.read(context).currentInstance;
    if (site == null) return;
    if (_recentRouteUrl(site.url, route) case final url?) {
      unawaited(openLink(context, url, title: route.title));
    } else {
      ShellScope.read(context).pushContent(route);
    }
  }
}

String? _recentRouteUrl(String? siteUrl, ContentRoute route) {
  if (siteUrl == null) return null;
  if (route.topicId case final id?) {
    return resolveSiteRootPath(siteUrl, '/t/${route.slug ?? 'topic'}/$id');
  }
  if (route.feedPath case final path?) {
    return resolveSiteRootPath(
      siteUrl,
      path.endsWith('.json') ? path.substring(0, path.length - 5) : path,
    );
  }
  final channel = RegExp(r'^chat-c-([1-9][0-9]*)$').firstMatch(route.id);
  return channel == null
      ? null
      : resolveSiteRootPath(siteUrl, '/chat/c/-/${channel.group(1)}');
}

/// Reminders are dated and named in the reader's zone, the account's when it
/// has one, as the bookmark sheet that set them shows them. [now] is read in
/// the same zone, or Today and Tomorrow would compare two calendars.
@visibleForTesting
String reminderDateLabel(
  DateTime date, {
  required tz.Location location,
  required DateTime now,
  required bool use24HourClock,
}) {
  final wall = tz.TZDateTime.from(date, location);
  final label =
      upcomingDayName(wall, now: tz.TZDateTime.from(now, location)) ??
      DateFormat.yMMMd().format(wall);
  return appL10n.atNewtabpage(
    (label).toString(),
    (clockTime(wall, use24HourClock: use24HourClock)).toString(),
  );
}

class _StartPageEntry {
  const _StartPageEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.onPressed,
    this.color,
    this.count,
    this.time,
    this.activityAt,
    this.description,
    this.path,
    this.targetBookmark,
    this.bookmarkUrl,
    this.avatarUrl,
    this.prefixBuilder,
  });

  factory _StartPageEntry.fromRoute(
    ContentRoute route,
    VoidCallback onPressed, {
    required String? siteUrl,
    SidebarDestination? destination,
    DIconData? icon,
    int? count,
    String? description,
  }) => _StartPageEntry(
    id: route.id,
    title: route.title,
    icon: icon ?? destination?.icon ?? route.icon,
    color: destination?.iconColor ?? route.color,
    count: count ?? destination?.unreadCount ?? destination?.badge?.count,
    avatarUrl: destination?.avatarUrl,
    prefixBuilder: destination?.prefixBuilder,
    activityAt: destination?.lastActivityAt,
    description: description ?? destination?.preview ?? route.subtitle,
    path: _recentRouteUrl(siteUrl, route),
    bookmarkUrl: route.topicId == null || siteUrl == null
        ? null
        : resolveSiteRootPath(siteUrl, '/t/${route.topicId}'),
    onPressed: onPressed,
  );

  factory _StartPageEntry.fromTopic(
    ContentRoute route,
    String siteUrl,
    Topic? topic,
    Map<int, TopicCategory> categories,
    VoidCallback onPressed,
  ) => _StartPageEntry(
    id: route.id,
    title: topic?.title ?? route.title,
    icon: topic?.pinned == true
        ? DIcons.thumbtack
        : topic?.closed == true
        ? DIcons.lock
        : DIcons.layerGroup,
    color: categories[topic?.categoryId] == null
        ? route.color
        : Color(categories[topic?.categoryId]!.colorValue),
    count: topic?.unreadCount,
    activityAt: topic?.bumpedAt,
    description: [
      if (topic?.excerpt != null) topic!.excerpt!,
      if (categories[topic?.categoryId] case final category?) category.name,
      ...?topic?.tags.map((tag) => tag.name),
    ].join(' '),
    path: _recentRouteUrl(siteUrl, route),
    bookmarkUrl: resolveSiteRootPath(siteUrl, '/t/${route.topicId}'),
    onPressed: onPressed,
  );

  final String id;
  final String title;
  final DIconData icon;
  final Color? color;
  final int? count;
  final String? time;
  final DateTime? activityAt;
  final String? description;
  final String? path;
  final String? bookmarkUrl;
  final Bookmark? targetBookmark;
  final String? avatarUrl;
  final SidebarRowDecorationBuilder? prefixBuilder;
  final VoidCallback? onPressed;

  Widget mark(BuildContext context, double size) {
    if (prefixBuilder case final builder?) return builder(context, size);
    if (avatarUrl case final url?) {
      return DAvatar.frame(
        decorative: true,
        child: AvatarImage(
          url: url,
          size: size,
          fallback: DIcon(icon, size: size, color: color),
        ),
      );
    }
    final tokens = DTokens.of(context);
    final tint = color ?? tokens.primary;
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: DAvatar(
          dimension: size * 29 / 34,
          decorative: true,
          border: false,
          borderRadius: BorderRadius.circular(size * 9 / 34),
          child: ColoredBox(
            color: Color.alphaBlend(
              tint.withValues(alpha: .2),
              tokens.background,
            ),
            child: Center(
              child: DIcon(icon, size: size * 13 / 34, color: tint),
            ),
          ),
        ),
      ),
    );
  }

  /// The age of [activityAt], which advances while the page stays open, or
  /// else the fixed [time].
  Widget? timeLabel({required TextStyle style, int? maxLines}) {
    if (activityAt case final at?) {
      return RelativeTimeText(at, style: style, maxLines: maxLines);
    }
    if (time case final time?) {
      return Text(time, style: style, maxLines: maxLines);
    }
    return null;
  }
}

class _StartSection extends StatelessWidget {
  const _StartSection({
    required this.title,
    required this.icon,
    required this.rows,
    required this.siteUrl,
    this.onHeading,
    this.fullWidth = false,
  });

  final String title;
  final DIconData icon;
  final List<_StartPageEntry> rows;
  final String siteUrl;
  final VoidCallback? onHeading;
  final bool fullWidth;

  Widget _row(BuildContext context, _StartPageEntry entry) {
    final siteUrl = this.siteUrl;
    final canDrag =
        entry.path != null && ShellScope.of(context).desktopPanelsEnabled;
    final tokens = DTokens.of(context);
    final unread = (entry.count ?? 0) > 0;
    final due =
        entry.targetBookmark?.reminderAt?.isBefore(DateTime.now()) == true;
    final metadata = fullWidth
        ? null
        : unread || due
        ? DBadge(
            size: DBadgeSize.compact,
            variant: DBadgeVariant.primary,
            child: Text(unread ? entry.count.toString() : context.l10n.due),
          )
        : entry.timeLabel(
            style: TextStyle(
              fontSize: DiscourseTypography.metadata,
              fontWeight: FontWeight.w400,
              color: tokens.mutedForeground,
            ),
          );
    final row = DItem(
      key: ValueKey('start-page-recent-${entry.id}'),
      variant: DItemVariant.standard,
      fitContent: fullWidth,
      size: DItemSize.xs,
      link: entry.path != null,
      onPressed: entry.onPressed,
      dragData: !canDrag
          ? null
          : StartPageDrag(
              siteUrl: siteUrl,
              path: entry.path!,
              title: entry.title,
            ),
      dragFeedback: !canDrag
          ? null
          : Transform.translate(
              offset: const Offset(DSpacing.md, 20),
              child: ForumTabDragFeedback(
                key: const ValueKey('start-page-drag-feedback'),
                item: ForumTabItem(
                  id: entry.id,
                  title: entry.title,
                  icon: entry.icon,
                  iconColor: entry.color,
                ),
                width: ForumTabsBar.maximumTabWidth,
              ),
            ),
      children: [
        entry.mark(context, 21),
        DItemContent(
          children: [
            SiteEmojiText.plain(
              entry.title,
              siteUrl: siteUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DiscourseTypography.control,
                fontWeight: FontWeight.w500,
                fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
                fontFamilyFallback: Theme.of(
                  context,
                ).textTheme.bodyLarge?.fontFamilyFallback,
              ),
            ),
          ],
        ),
        ?metadata,
      ],
    );
    final card = Stack(
      children: [
        Positioned.fill(
          child: DCard(
            spacing: 0,
            border: false,
            borderRadius: BorderRadius.circular(9),
            backgroundColor: tokens.footerBackground,
          ),
        ),
        row,
      ],
    );
    return entry.path == null
        ? card
        : LinkTarget(
            url: entry.path!,
            bookmarkUrl: entry.bookmarkUrl,
            targetBookmark: entry.targetBookmark,
            title: entry.title,
            siteUrl: siteUrl,
            child: card,
          );
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: surface(context)),
      contents(context),
    ],
  );

  Widget surface(BuildContext context) => DCard(
    key: ValueKey('start-page-section-$title'),
    border: false,
    spacing: 0,
    borderRadius: BorderRadius.circular(14),
    backgroundColor: _wellColor(DTokens.of(context).background),
  );

  Widget contents(BuildContext context) {
    final tokens = DTokens.of(context);
    final label = Text(
      title,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: DiscourseTypography.control,
        fontWeight: FontWeight.w700,
        color: tokens.foreground,
      ),
    );
    final heading = onHeading == null
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            child: Row(
              spacing: 9,
              children: [
                DIcon(icon, size: 12, color: tokens.mutedForeground),
                Flexible(child: label),
              ],
            ),
          )
        : DButton(
            key: ValueKey('start-page-section-link-$title'),
            variant: DButtonVariant.transparentBackground,
            size: DButtonSize.filter,
            foregroundColor: tokens.foreground,
            icon: DIcon(icon, size: 12, color: tokens.mutedForeground),
            label: Row(
              children: [
                Expanded(child: label),
                DIcon(
                  DIcons.chevronRight,
                  size: 10,
                  color: tokens.mutedForeground,
                ),
              ],
            ),
            onPressed: onHeading,
          );
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          heading,
          if (fullWidth)
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in rows)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth.clamp(0.0, 280.0),
                      ),
                      child: _row(context, entry),
                    ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [for (final entry in rows) _row(context, entry)],
            ),
        ],
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.sections});
  final List<_StartSection> sections;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var columns = math.max(1, ((constraints.maxWidth + 18) / 256).floor());
      for (var count = columns; count >= 2; count--) {
        if (sections.length % count == 0) {
          columns = count;
          break;
        }
      }
      return Column(
        spacing: 18,
        children: [
          for (var start = 0; start < sections.length; start += columns)
            _SectionRow(
              direction: Directionality.of(context),
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (start + column < sections.length) ...[
                    sections[start + column].surface(context),
                    sections[start + column].contents(context),
                  ] else ...[
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                  ],
                ],
              ],
            ),
        ],
      );
    },
  );
}

// Measure section contents once at their actual width, then stretch the Native
// surfaces behind them. Intrinsic estimates miss inline emoji height.
class _SectionRow extends MultiChildRenderObjectWidget {
  const _SectionRow({required this.direction, required super.children});
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSectionRow(direction);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSectionRow renderObject,
  ) {
    renderObject.direction = direction;
  }
}

class _SectionParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSectionRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SectionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SectionParentData> {
  _RenderSectionRow(this._direction);
  TextDirection _direction;
  set direction(TextDirection value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SectionParentData) {
      child.parentData = _SectionParentData();
    }
  }

  @override
  void performLayout() {
    final columns = childCount ~/ 2;
    final width = ((constraints.maxWidth - 18 * (columns - 1)) / columns).clamp(
      0.0,
      double.infinity,
    );
    final children = getChildrenAsList();
    var height = 0.0;
    for (var i = 1; i < children.length; i += 2) {
      final child = children[i];
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      height = math.max(height, child.size.height);
    }
    for (var i = 0; i < children.length; i += 2) {
      children[i].layout(BoxConstraints.tightFor(width: width, height: height));
      final x = (i ~/ 2) * (width + 18);
      final offset = Offset(
        _direction == TextDirection.ltr ? x : constraints.maxWidth - width - x,
        0,
      );
      (children[i].parentData! as _SectionParentData).offset = offset;
      (children[i + 1].parentData! as _SectionParentData).offset = offset;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

// Matches the mockup's oklch(from secondary calc(l - 0.08) c h).
// Changing only lightness is equivalent in Oklab and preserves hue/chroma.
Color _wellColor(Color color) {
  double linear(double v) =>
      v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  double root(double v) => v.sign * math.pow(v.abs(), 1 / 3).toDouble();
  final r = linear(color.r), g = linear(color.g), b = linear(color.b);
  final l = root(.4122214708 * r + .5363325363 * g + .0514459929 * b);
  final m = root(.2119034982 * r + .6806995451 * g + .1073969566 * b);
  final s = root(.0883024619 * r + .2817188376 * g + .6299787005 * b);
  final lightness = (.2104542553 * l + .793617785 * m - .0040720468 * s - .08)
      .clamp(0.0, 1.0);
  final a = 1.9779984951 * l - 2.428592205 * m + .4505937099 * s;
  final bb = .0259040371 * l + .7827717662 * m - .808675766 * s;
  double cube(double v) => v * v * v;
  double gamma(double v) =>
      (v <= .0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - .055)
          .clamp(0.0, 1.0)
          .toDouble();
  final ll = cube(lightness + .3963377774 * a + .2158037573 * bb);
  final mm = cube(lightness - .1055613458 * a - .0638541728 * bb);
  final ss = cube(lightness - .0894841775 * a - 1.291485548 * bb);
  return Color.from(
    alpha: color.a,
    red: gamma(4.0767416621 * ll - 3.3077115913 * mm + .2309699292 * ss),
    green: gamma(-1.2684380046 * ll + 2.6097574011 * mm - .3413193965 * ss),
    blue: gamma(-.0041960863 * ll - .7034186147 * mm + 1.707614701 * ss),
  );
}

/// Measures the Native buttons themselves so text scaling and localization
/// determine which shortcuts fit beside the menu trigger.
class _ShortcutBar extends StatefulWidget {
  const _ShortcutBar({required this.links});
  final List<_LinkButton> links;

  @override
  State<_ShortcutBar> createState() => _ShortcutBarState();
}

class _ShortcutBarState extends State<_ShortcutBar> {
  List<GlobalKey> _measureKeys = [];
  final _moreKey = GlobalKey();
  List<double> _widths = [];
  double _moreWidth = 0;
  String? _signature;
  bool _scheduled = false;

  void _measure() {
    _scheduled = false;
    if (!mounted) return;
    final widths = [
      for (final key in _measureKeys)
        (key.currentContext?.findRenderObject() as RenderBox?)?.size.width,
    ];
    if (widths.any((width) => width == null)) return;
    final more =
        (_moreKey.currentContext?.findRenderObject() as RenderBox?)?.size.width;
    if (more == null) return;
    final measured = widths.cast<double>();
    if (_moreWidth != more ||
        _widths.length != measured.length ||
        [
          for (var i = 0; i < measured.length; i++)
            if (_widths[i] != measured[i]) i,
        ].isNotEmpty) {
      setState(() {
        _widths = measured;
        _moreWidth = more;
      });
    }
  }

  int _fitting(double width) {
    if (_widths.length != widget.links.length) return 0;
    var used = 0.0;
    var shown = 0;
    while (shown < _widths.length &&
        used + (shown == 0 ? 0 : 8) + _widths[shown] <= width) {
      used += (shown == 0 ? 0 : 8) + _widths[shown++];
    }
    while (shown > 0 &&
        shown < _widths.length &&
        used + 8 + _moreWidth > width) {
      used -= _widths[--shown] + (shown == 0 ? 0 : 8);
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final signature =
          '${widget.links.map((link) => link.label).join('|')} ${MediaQuery.textScalerOf(context).scale(14)} ${Theme.of(context).textTheme}';
      if (_signature != signature) {
        _signature = signature;
        _widths = [];
      }
      if (_measureKeys.length != widget.links.length) {
        _measureKeys = [for (final _ in widget.links) GlobalKey()];
      }
      if (!_scheduled) {
        _scheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      }
      final shown = _fitting(constraints.maxWidth);
      final rest = widget.links.skip(shown).toList();
      Widget moreButton({Key? key, VoidCallback? onPressed}) => DButton(
        key: key,
        size: DButtonSize.filter,
        variant: DButtonVariant.secondary,
        icon: const DIcon(DIcons.ellipsis, size: 12),
        label: Text(context.l10n.more),
        onPressed: onPressed,
      );
      return Stack(
        key: const ValueKey('start-page-shortcuts'),
        children: [
          Offstage(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.links.length; i++)
                    SizedBox(key: _measureKeys[i], child: widget.links[i]),
                  moreButton(key: _moreKey, onPressed: () {}),
                ],
              ),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              ...widget.links.take(shown),
              if (rest.isNotEmpty)
                Flexible(
                  child: DDropdownMenu(
                    content: DDropdownMenuContent(
                      children: [
                        for (final link in rest)
                          DDropdownMenuItem(
                            leading: DIcon(link.icon, size: 12),
                            onPressed: link.onPressed,
                            child: Text(link.label),
                          ),
                      ],
                    ),
                    child: DDropdownMenuTrigger(
                      builder: (context, state) => DButton(
                        key: const ValueKey('start-page-more'),
                        size: DButtonSize.filter,
                        variant: DButtonVariant.secondary,
                        focusNode: state.focusNode,
                        hasPopup: true,
                        expanded: state.open,
                        icon: const DIcon(DIcons.ellipsis, size: 12),
                        label: Text(context.l10n.more),
                        onPressed: state.toggle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.url,
    this.content,
  });
  final String label;
  final DIconData icon;
  final VoidCallback onPressed;
  final String? url;
  final ContentRoute? content;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final button = DButton(
      variant: DButtonVariant.secondary,
      size: DButtonSize.filter,
      backgroundColor: tokens.footerBackground,
      interactiveBackgroundColor: tokens.buttonTheme.accent.hover,
      borderColor: Colors.transparent,
      icon: DIcon(icon, size: 12),
      label: Text(label),
      onPressed: onPressed,
    );
    if (url case final url?) return LinkTarget(url: url, child: button);
    if (content case final content?) {
      return LinkTarget.content(content: content, child: button);
    }
    return button;
  }
}
