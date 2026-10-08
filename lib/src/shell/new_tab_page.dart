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
import '../models/badge.dart';
import '../models/badge_route.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/group.dart';
import '../models/list_link.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../models/user_summary.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import '../theme/discourse_typography.dart';
import 'avatar_image.dart';
import 'badges_page.dart';
import 'external_link.dart';
import 'forum_icon.dart';
import 'forum_tabs_bar.dart';
import 'groups_controller.dart';
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
        shell.accountActivity.userActivityListenable,
        shell.userSummary,
        shell.groups,
        shell.badges,
        shell.topicFeeds,
        shell.search,
        shell.startPage,
        shell.draftList,
        ...?PluginScope.maybeOf(
          context,
        )?.registry.startPageListenables(context),
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
    final latestTopics = siteUrl == null
        ? <Topic>[]
        : shell!.cachedLatestTopicsFor(siteUrl);
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

    final accountLease = siteUrl == null
        ? null
        : shell!.lifecycle.capture(siteUrl);
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
      for (final route in categories)
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
    ]).take(4).toList();
    final chatRows = matching([
      for (final destination in recentChats)
        _StartPageEntry.fromRoute(
          ContentRoute.fromDestination(destination),
          () => shell!.selectDestination(destination),
          siteUrl: siteUrl,
          destination: destination,
        ),
    ]).take(4).toList();
    final topicRows = matching([
      for (final topic in latestTopics)
        _StartPageEntry.fromTopic(
          ContentRoute.topic(
            topicId: topic.id,
            title: topic.title,
            slug: topic.slug,
          ),
          siteUrl!,
          topic,
          categoryDetails,
          () => shell!.openTopicFromList(topic),
        ),
    ]).take(4).toList();
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
    final draftRows = siteUrl == null || forum?.user == null
        ? <_StartPageEntry>[]
        : matching([
            for (final draft in shell!.draftList.feedFor(siteUrl).drafts)
              if (draft.canResume)
                _StartPageEntry(
                  id: 'draft-${draft.key}',
                  title: draft.displayTitle,
                  icon: DIcons.pen,
                  description: draft.excerpt,
                  activityAt: draft.createdAt,
                  onPressed: () => unawaited(
                    shell.resumeDraft(
                      siteUrl,
                      draft,
                      sourceIsCurrent: () => accountLease?.isCurrent == true,
                    ),
                  ),
                ),
          ]).take(4).toList();
    final activityRows = siteUrl == null || forum?.isConnected != true
        ? <_StartPageEntry>[]
        : matching([
            for (final item
                in shell!.accountActivity.userActivityFor(siteUrl).items)
              _StartPageEntry(
                id: 'activity-${item.identity}',
                title: item.title,
                icon: item.isTopic ? DIcons.layerGroup : DIcons.reply,
                activityAt: item.createdAt,
                description: item.plainExcerpt,
                path: resolveSiteRootPath(
                  siteUrl,
                  '/t/${item.topicId}/${item.postNumber}',
                ),
                onPressed: () => shell.openUserActivityItem(item),
              ),
          ]).take(4).toList();
    final groups = siteUrl == null
        ? null
        : shell!.groups.directoryState(siteUrl, const GroupDirectoryQuery());
    final hasMembership =
        groups?.groups.any((group) => group.isGroupUser) == true;
    final groupRows = matching([
      for (final group in groups?.groups ?? <Group>[])
        if (!hasMembership || group.isGroupUser)
          _StartPageEntry(
            id: 'group-${group.id}',
            title: group.displayName ?? group.name,
            icon: DIcons.userGroup,
            description: group.bioExcerpt,
            count: group.userCount,
            path: resolveSiteRootPath(
              siteUrl!,
              '/g/${Uri.encodeComponent(group.name)}',
            ),
            onPressed: () => openLink(
              context,
              shell!.siteLink('/g/${Uri.encodeComponent(group.name)}'),
            ),
          ),
    ]).take(4).toList();
    final catalog = siteUrl == null || forum?.config.badgesEnabled != true
        ? null
        : shell!.badges.stateFor(siteUrl, const BadgeRoute.directory()).catalog;
    final badgeRows = matching([
      for (final group in catalog?.groups ?? <BadgeGroup>[])
        for (final badge in group.badges)
          if (badge.hasBadge == true)
            _StartPageEntry(
              id: 'badge-${badge.id}',
              title: badge.name,
              icon: DIcons.certificate,
              description: badge.description,
              path: resolveSiteRootPath(
                siteUrl!,
                BadgeRoute.detail(badge.id).path,
              ),
              prefixBuilder: (context, size) =>
                  BadgeMedal(badge: badge, siteUrl: siteUrl),
              onPressed: () => openLink(
                context,
                shell!.siteLink(BadgeRoute.detail(badge.id).path),
              ),
            ),
    ]).take(4).toList();
    final summary = siteUrl == null || forum?.isConnected != true
        ? null
        : shell!.userSummary.stateFor(siteUrl).summary;
    final people = <String, (UserSummaryUser, int)>{};
    for (final person in [
      ...?summary?.mostRepliedToUsers,
      ...?summary?.mostLikedByUsers,
      ...?summary?.mostLikedUsers,
    ]) {
      people[person.username] = (
        person,
        (people[person.username]?.$2 ?? 0) + person.count,
      );
    }
    final rankedPeople = people.values.toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final userRows = matching([
      for (final (person, _) in rankedPeople)
        _StartPageEntry(
          id: 'user-${person.username}',
          title: person.displayName,
          description: '@${person.username}',
          icon: DIcons.user,
          avatarUrl: person.avatarUrl,
          path: resolveSiteRootPath(
            siteUrl!,
            '/u/${Uri.encodeComponent(person.username)}',
          ),
          onPressed: () => openLink(
            context,
            shell!.siteLink('/u/${Uri.encodeComponent(person.username)}'),
          ),
        ),
    ]).take(4).toList();
    final messageRows = siteUrl == null || forum?.isConnected != true
        ? <_StartPageEntry>[]
        : matching([
            for (final id
                in shell!.topicFeeds
                        .feedFor(siteUrl, ContentRoute.messages().id)
                        ?.topicIds ??
                    <int>[])
              if (shell.store.read<Topic>(siteUrl, id) case final topic?)
                _StartPageEntry(
                  id: 'message-$id',
                  title: topic.title,
                  icon: DIcons.envelope,
                  description: topic.excerpt,
                  activityAt: topic.bumpedAt,
                  count: topic.unreadCount,
                  path: resolveSiteRootPath(siteUrl, '/t/$id'),
                  onPressed: () => shell.openTopicFromList(topic),
                ),
          ]).take(4).toList();
    final contributed = registry?.startPageSections(context) ?? const [];
    final contributedIds = {
      for (final section in contributed) section.destination.id,
    };
    final sections = <_StartSection>[
      if (siteUrl != null) ...[
        if (closedRows.isNotEmpty)
          _StartSection(
            id: 'recently-closed',
            title: context.l10n.recentlyClosedNewtabpage,
            icon: DIcons.arrowRotateLeft,
            rows: closedRows,
            siteUrl: siteUrl,
            fullWidth: true,
          ),
        if (forum?.user != null)
          _StartSection(
            id: 'bookmarks',
            title: context.l10n.bookmarks,
            icon: DIcons.bookmark,
            rows: bookmarkRows,
            siteUrl: siteUrl,
            onHeading: openBookmarks,
          ),
        _StartSection(
          id: 'categories',
          title: context.l10n.categories,
          icon: DIcons.tag,
          rows: categoryRows,
          siteUrl: siteUrl,
          onHeading: openCategories,
        ),
        if (hasChat)
          _StartSection(
            id: 'chat',
            title: context.l10n.chat,
            icon: DIcons.comment,
            rows: chatRows,
            siteUrl: siteUrl,
            onHeading: openChat,
          ),
        _StartSection(
          id: 'topics',
          title: context.l10n.topics,
          icon: DIcons.layerGroup,
          rows: topicRows,
          siteUrl: siteUrl,
          onHeading: onBrowseTopics,
        ),
        if (forum?.user != null) ...[
          _StartSection(
            id: 'drafts',
            title: context.l10n.drafts,
            icon: DIcons.pen,
            rows: draftRows,
            siteUrl: siteUrl,
            onHeading: () => shell!.openDrafts(siteUrl),
          ),
          _StartSection(
            id: 'messages',
            title: context.l10n.messages,
            icon: DIcons.inbox,
            rows: messageRows,
            siteUrl: siteUrl,
            onHeading: () => openLink(context, shell!.siteLink('/my/messages')),
          ),
          _StartSection(
            id: 'summary',
            title: context.l10n.summary,
            icon: DIcons.user,
            rows: const [],
            siteUrl: siteUrl,
            onHeading: () => shell!.openUserSummary(siteUrl),
          ),
          _StartSection(
            id: 'activity',
            title: context.l10n.activity,
            icon: DIcons.barsStaggered,
            rows: activityRows,
            siteUrl: siteUrl,
            onHeading: () => shell!.openUserActivity(siteUrl),
          ),
        ],
        _StartSection(
          id: 'groups',
          title: context.l10n.groups,
          icon: DIcons.userGroup,
          rows: groupRows,
          siteUrl: siteUrl,
          onHeading: () => openLink(context, shell!.siteLink('/g')),
        ),
        _StartSection(
          id: 'badges',
          title: context.l10n.badges,
          icon: DIcons.certificate,
          rows: badgeRows,
          siteUrl: siteUrl,
          onHeading: () => openLink(context, shell!.siteLink('/badges')),
        ),
        _StartSection(
          id: 'users',
          title: context.l10n.users,
          icon: DIcons.users,
          rows: userRows,
          siteUrl: siteUrl,
          onHeading: () => openLink(context, shell!.siteLink('/u')),
        ),
        for (final section in contributed)
          _StartSection(
            id: section.destination.id,
            title: section.destination.label,
            icon: section.destination.icon,
            rows: matching([
              for (final entry in section.entries)
                _StartPageEntry.fromRoute(
                  ContentRoute.fromDestination(entry),
                  () => shell!.selectDestination(entry),
                  siteUrl: siteUrl,
                  destination: entry,
                ),
            ]).take(4).toList(),
            siteUrl: siteUrl,
            onHeading: () => shell!.selectDestination(section.destination),
          ),
        for (final shortcut in shortcuts)
          if (!contributedIds.contains(shortcut.id))
            _StartSection(
              id: shortcut.id,
              title: shortcut.label,
              icon: shortcut.icon,
              rows: const [],
              siteUrl: siteUrl,
              onHeading: () => shell!.selectDestination(shortcut),
            ),
        if (forum?.user != null)
          _StartSection(
            id: 'preferences',
            title: context.l10n.preferences,
            icon: DNativeIcons.sliders,
            rows: const [],
            siteUrl: siteUrl,
            onHeading: () => shell!.openPreferences(siteUrl),
          ),
        _StartSection(
          id: 'settings',
          title: context.l10n.settings,
          icon: DIcons.gear,
          rows: const [],
          siteUrl: siteUrl,
          onHeading: () => shell!.openForumSettings(siteUrl),
        ),
      ],
    ];
    final found = sections.fold(
      0,
      (count, section) => count + section.rows.length,
    );
    final pins = siteUrl == null
        ? const <String>[]
        : shell!.startPage.pinsFor(siteUrl);
    final visibleSections = sections
        .where(
          (section) =>
              query.trim().isEmpty ||
              section.rows.isNotEmpty ||
              section.title.toLowerCase().contains(query.trim().toLowerCase()),
        )
        .toList();
    visibleSections.sort((a, b) {
      final aPin = pins.indexOf(a.id), bPin = pins.indexOf(b.id);
      if (aPin >= 0 || bPin >= 0) {
        if (aPin < 0) return 1;
        if (bPin < 0) return -1;
        return aPin.compareTo(bPin);
      }
      const tail = ['preferences', 'settings'];
      final aTail = tail.indexOf(a.id), bTail = tail.indexOf(b.id);
      if (aTail >= 0 || bTail >= 0) {
        if (aTail < 0) return -1;
        if (bTail < 0) return 1;
        return aTail.compareTo(bTail);
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
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
      ],
    );
    return DPageSurface.scrollable(
      framed: false,
      hideHeaderOnScroll: true,
      revealHeaderAtEnd: false,
      identity: (siteUrl, ForumTabScope.idOf(context)),
      header: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          shell?.desktopPanelsEnabled == true ? 4 : 16,
          16,
          0,
        ),
        child: title,
      ),
      headerControls: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
      bodyBuilder: (context, header) => _StartList(
        key: ValueKey((siteUrl, ForumTabScope.idOf(context))),
        sections: visibleSections,
        pins: pins,
        header: header,
        fallback: shell == null
            ? DButton(
                onPressed: onBrowseTopics,
                label: Text(context.l10n.browseLatestTopics),
              )
            : null,
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

class _StartList extends StatefulWidget {
  const _StartList({
    super.key,
    required this.sections,
    required this.pins,
    required this.header,
    this.fallback,
  });
  final List<_StartSection> sections;
  final List<String> pins;
  final DPageHeaderGeometry header;
  final Widget? fallback;

  @override
  State<_StartList> createState() => _StartListState();
}

class _StartListState extends State<_StartList> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  bool _scrubbing = false;
  String? _target;
  Timer? _settle;

  void _jump(String id) {
    _target = id;
    if (id.isEmpty) {
      _settle?.cancel();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    void align() {
      if (!_scroll.hasClients) return;
      final box = _keys[id]?.currentContext?.findRenderObject();
      if (box == null) return;
      final offset = RenderAbstractViewport.of(
        box,
      ).getOffsetToReveal(box, 0).offset;
      _scroll.jumpTo(
        (offset - widget.header.visibleExtent - 8).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }

    align();
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 280), () {
      if (mounted && _target == id) align();
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final letters = <String, _StartSection>{};
      final pinned = widget.sections
          .where((section) => widget.pins.contains(section.id))
          .toList();
      for (final section in widget.sections) {
        if (widget.pins.contains(section.id) ||
            section.id == 'preferences' ||
            section.id == 'settings') {
          continue;
        }
        final letter = section.title.characters.first.toUpperCase();
        letters.putIfAbsent(letter, () => section);
      }
      final settings = widget.sections
          .where(
            (section) =>
                !widget.pins.contains(section.id) &&
                (section.id == 'preferences' || section.id == 'settings'),
          )
          .firstOrNull;
      final entries = [
        if (widget.sections.isNotEmpty)
          DAlphabetIndexEntry(
            value: pinned.firstOrNull?.id ?? '',
            label: pinned.isEmpty
                ? context.l10n.startPage
                : context.l10n.startPagePinnedSections,
            icon: DIcons.star,
          ),
        for (final letter in letters.entries)
          DAlphabetIndexEntry(value: letter.value.id, label: letter.key),
        if (settings != null)
          DAlphabetIndexEntry(
            value: settings.id,
            label: context.l10n.settings,
            icon: DIcons.gear,
          ),
      ];
      return Stack(
        children: [
          IgnorePointer(
            ignoring: _scrubbing,
            child: DScrollBar(
              controller: _scroll,
              showScrollbar: false,
              child: SingleChildScrollView(
                controller: _scroll,
                primary: false,
                child: DPageReadingLaneBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      widget.header.spacer,
                      Padding(
                        key: const ValueKey('start-page-content'),
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          18,
                          36,
                          24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final section in widget.sections)
                              KeyedSubtree(
                                key: _keys.putIfAbsent(
                                  section.id,
                                  GlobalKey.new,
                                ),
                                child: section,
                              ),
                            ?widget.fallback,
                            SizedBox(
                              height: math.max(
                                0,
                                constraints.maxHeight -
                                    widget.header.naturalExtent -
                                    64,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: 6,
            top: 18,
            bottom: 0,
            child: widget.header.inset(
              Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  primary: false,
                  clipBehavior: Clip.none,
                  child: DAlphabetIndex<String>(
                    key: const ValueKey('start-page-alphabet-index'),
                    entries: entries,
                    onSelected: _jump,
                    onScrubChanged: (active) =>
                        setState(() => _scrubbing = active),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
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
    required this.id,
    required this.title,
    required this.icon,
    required this.rows,
    required this.siteUrl,
    this.onHeading,
    this.fullWidth = false,
  });

  final String id;
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
    return entry.path == null
        ? row
        : LinkTarget(
            url: entry.path!,
            bookmarkUrl: entry.bookmarkUrl,
            targetBookmark: entry.targetBookmark,
            title: entry.title,
            siteUrl: siteUrl,
            child: row,
          );
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final pinned = shell.startPage.pinsFor(siteUrl).contains(id);
    final tokens = DTokens.of(context);
    final pin = DToggle.iconOnly(
      key: ValueKey('start-page-pin-$id'),
      size: DControlSize.chip,
      pressed: pinned,
      semanticLabel: pinned
          ? context.l10n.unpinStartSection(title)
          : context.l10n.pinStartSection(title),
      icon: const DIcon(DIcons.thumbtack, size: 11),
      onPressedChanged: (_) => shell.startPage.togglePin(siteUrl, id),
    );
    final heading = DItem(
      key: ValueKey('start-page-section-link-$title'),
      size: DItemSize.xs,
      onPressed: onHeading,
      cornerAction: pinned ? null : pin,
      children: [
        DIcon(icon, size: 21, color: tokens.mutedForeground),
        DItemContent(
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: DiscourseTypography.control,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (pinned) pin else const SizedBox(width: 24),
      ],
    );
    final contents = Column(
      key: ValueKey('start-page-section-$title'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading,
        if (fullWidth && rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(6),
            child: LayoutBuilder(
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
            ),
          )
        else if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 29),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final entry in rows) _row(context, entry)],
            ),
          ),
      ],
    );
    return pinned
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DCard(
              key: ValueKey('start-page-pinned-$id'),
              border: false,
              spacing: 0,
              backgroundColor: _wellColor(tokens.background),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: contents,
              ),
            ),
          )
        : contents;
  }
}

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
