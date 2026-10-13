import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:timezone/timezone.dart' as tz;

import '../foundation/calendar_day.dart';
import '../foundation/clock_time.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
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
        shell.search,
        shell.draftList,
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
                .where((entry) => entry.title.toLowerCase().contains(term))
                .toList();
    }

    final closedRows = matching([
      for (final tab in closed)
        _closedEntry(context, tab, siteUrl!, categoryDetails, conversations),
    ]).take(query.isEmpty ? 8 : 16).toList();
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
          ),
        if (forum?.user != null)
          _StartSection(
            id: 'bookmarks',
            title: context.l10n.bookmarks,
            icon: DIcons.bookmark,
            rows: const [],
            siteUrl: siteUrl,
            onHeading: openBookmarks,
          ),
        _StartSection(
          id: 'categories',
          title: context.l10n.categories,
          icon: DIcons.tag,
          rows: const [],
          siteUrl: siteUrl,
          onHeading: openCategories,
        ),
        if (hasChat)
          _StartSection(
            id: 'chat',
            title: context.l10n.chat,
            icon: DIcons.comment,
            rows: const [],
            siteUrl: siteUrl,
            onHeading: openChat,
          ),
        _StartSection(
          id: 'topics',
          title: context.l10n.topics,
          icon: DIcons.layerGroup,
          rows: const [],
          siteUrl: siteUrl,
          onHeading: onBrowseTopics,
        ),
        if (forum?.user != null) ...[
          if (shell!.draftList
              .feedFor(siteUrl)
              .drafts
              .any((draft) => draft.canResume))
            _StartSection(
              id: 'drafts',
              title: context.l10n.drafts,
              icon: DIcons.pen,
              rows: const [],
              siteUrl: siteUrl,
              onHeading: () => shell.openDrafts(siteUrl),
            ),
          _StartSection(
            id: 'messages',
            title: context.l10n.messages,
            icon: DIcons.inbox,
            rows: const [],
            siteUrl: siteUrl,
            onHeading: () => openLink(context, shell.siteLink('/my/messages')),
          ),
          _StartSection(
            id: 'summary',
            title: context.l10n.summary,
            icon: DIcons.user,
            rows: const [],
            siteUrl: siteUrl,
            onHeading: () => shell.openUserSummary(siteUrl),
          ),
          _StartSection(
            id: 'activity',
            title: context.l10n.activity,
            icon: DIcons.barsStaggered,
            rows: const [],
            siteUrl: siteUrl,
            onHeading: () => shell.openUserActivity(siteUrl),
          ),
        ],
        _StartSection(
          id: 'groups',
          title: context.l10n.groups,
          icon: DIcons.userGroup,
          rows: const [],
          siteUrl: siteUrl,
          onHeading: () => openLink(context, shell!.siteLink('/g')),
        ),
        _StartSection(
          id: 'badges',
          title: context.l10n.badges,
          icon: DIcons.certificate,
          rows: const [],
          siteUrl: siteUrl,
          onHeading: () => openLink(context, shell!.siteLink('/badges')),
        ),
        _StartSection(
          id: 'users',
          title: context.l10n.users,
          icon: DIcons.users,
          rows: const [],
          siteUrl: siteUrl,
          onHeading: () => openLink(context, shell!.siteLink('/u')),
        ),
        for (final section in contributed.where((s) => s.destination.enabled))
          _StartSection(
            id: section.destination.id,
            title: section.destination.label,
            icon: section.destination.icon,
            rows: const [],
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
    final found = closedRows.length;
    final visibleSections = sections;
    visibleSections.sort((a, b) {
      if (a.id == 'recently-closed') return -1;
      if (b.id == 'recently-closed') return 1;
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
                                fontSize: DiscourseTypography.xxl,
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
      avatarUrl: destination?.avatarUrl,
      prefixBuilder: destination?.prefixBuilder,
      path: _recentRouteUrl(siteUrl, route),
      bookmarkUrl: route.topicId == null
          ? null
          : resolveSiteRootPath(siteUrl, '/t/${route.topicId}'),
      onPressed: () => shell.reopenClosedTab(tab.id),
    );
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

class _StartList extends StatelessWidget {
  const _StartList({
    super.key,
    required this.sections,
    required this.header,
    this.fallback,
  });
  final List<_StartSection> sections;
  final DPageHeaderGeometry header;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    primary: false,
    child: DPageReadingLaneBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header.spacer,
          Padding(
            key: const ValueKey('start-page-content'),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 20,
              children: [
                for (final section in sections.where(
                  (s) => s.id == 'recently-closed',
                ))
                  section,
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 8.0;
                    final columns = math.max(
                      1,
                      ((constraints.maxWidth + gap) /
                              (DButton.launcherMinimumExtent(context) + gap))
                          .floor(),
                    );
                    final width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      key: const ValueKey('start-page-shortcuts'),
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final section in sections.where(
                          (s) => s.id != 'recently-closed',
                        ))
                          SizedBox(width: width, child: section),
                      ],
                    );
                  },
                ),
                ?fallback,
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _StartPageEntry {
  const _StartPageEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.onPressed,
    this.color,
    this.path,
    this.bookmarkUrl,
    this.avatarUrl,
    this.prefixBuilder,
  });

  final String id;
  final String title;
  final DIconData icon;
  final Color? color;
  final String? path;
  final String? bookmarkUrl;
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
}

class _StartSection extends StatelessWidget {
  const _StartSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.rows,
    required this.siteUrl,
    this.onHeading,
  });

  final String id;
  final String title;
  final DIconData icon;
  final List<_StartPageEntry> rows;
  final String siteUrl;
  final VoidCallback? onHeading;

  Widget _row(BuildContext context, _StartPageEntry entry) {
    final siteUrl = this.siteUrl;
    final canDrag =
        entry.path != null && ShellScope.of(context).desktopPanelsEnabled;
    final row = DItem(
      key: ValueKey('start-page-recent-${entry.id}'),
      variant: DItemVariant.standard,
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
      ],
    );
    return entry.path == null
        ? row
        : LinkTarget(
            url: entry.path!,
            bookmarkUrl: entry.bookmarkUrl,
            title: entry.title,
            siteUrl: siteUrl,
            child: row,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (id != 'recently-closed') {
      return DButton(
        key: ValueKey('start-page-section-link-$title'),
        variant: DButtonVariant.launcher,
        isLink: true,
        icon: DIcon(icon),
        label: Text(title),
        onPressed: onHeading,
      );
    }
    return Column(
      key: ValueKey('start-page-section-$title'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DItem(
          key: ValueKey('start-page-section-link-$title'),
          size: DItemSize.xs,
          children: [
            DIcon(icon, size: 21, color: DTokens.of(context).mutedForeground),
            DItemContent(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
        for (final entry in rows) _row(context, entry),
      ],
    );
  }
}
