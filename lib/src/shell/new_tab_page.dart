import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../foundation/calendar_day.dart';
import '../foundation/clock_time.dart';
import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/content_route.dart';
import '../models/forum_workspace.dart';
import '../models/sidebar.dart';
import '../models/topic.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'forum_icon.dart';
import 'forum_tabs_bar.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'site_url.dart';
import 'start_page_drag.dart';

/// The landing surface for an otherwise empty forum tab.
class NewTabPage extends StatefulWidget {
  const NewTabPage({super.key, required this.onBrowseTopics});

  final VoidCallback onBrowseTopics;

  @override
  State<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends State<NewTabPage> {
  static const _dismissedKey = 'discourse_native.panel_tutorial_dismissed';
  static const _compactKey = 'discourse_native.start_page_compact';
  bool? _dismissed;
  bool _compact = true;
  bool _compactChanged = false;
  String? _requestedLatestSite;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final instance = ShellScope.maybeOf(context)?.currentInstance;
    if (instance == null || (instance.loginRequired && !instance.isConnected)) {
      _requestedLatestSite = null;
      return;
    }
    if (_requestedLatestSite == instance.url) return;
    _requestedLatestSite = instance.url;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shell = ShellScope.maybeRead(context);
      if (shell?.currentInstance?.url != instance.url) return;
      unawaited(shell!.loadFeed(TopicListMode.latest.routeId));
    });
  }

  Future<void> _loadPreferences() async {
    bool dismissed;
    bool compact;
    try {
      final preferences = await SharedPreferences.getInstance();
      dismissed = preferences.getBool(_dismissedKey) ?? false;
      compact = preferences.getBool(_compactKey) ?? true;
    } catch (_) {
      dismissed = false;
      compact = true;
    }
    if (mounted) {
      setState(() {
        _dismissed = dismissed;
        if (!_compactChanged) _compact = compact;
      });
    }
  }

  void _setCompact(bool compact) {
    if (_compact == compact) return;
    _compactChanged = true;
    setState(() => _compact = compact);
    unawaited(_saveCompact(compact));
  }

  Future<void> _saveCompact(bool compact) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(
        _compactKey,
        compact,
      );
    } catch (_) {
      // Keep the selected layout for this page if storage is unavailable.
    }
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(
        _dismissedKey,
        true,
      );
    } catch (_) {
      // The current tab still honors the choice if local storage is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    if (shell == null) return _buildPage(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        shell.accountActivity.bookmarksListenable,
        shell.topicFeeds,
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
    final unreadChannels = [
      for (final section in pluginSections)
        for (final destination in section.destinations)
          if (destination.enabled &&
              RegExp(r'^chat-c-[1-9][0-9]*$').hasMatch(destination.id) &&
              (destination.badge?.isVisible ?? false))
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
    final categories = siteUrl == null
        ? <ContentRoute>[]
        : shell!.recentCategoriesFor(siteUrl);
    final categoryDetails = siteUrl == null
        ? <int, TopicCategory>{}
        : {
            for (final category in shell!.topicComposerCategories(siteUrl))
              category.id: category,
          };
    final latest = siteUrl == null
        ? <Topic>[]
        : shell!.cachedLatestTopicsFor(siteUrl).take(4).toList();
    final bookmarks = siteUrl == null
        ? <Bookmark>[]
        : shell!.bookmarksFor(siteUrl).loaded
        ? shell
              .bookmarksFor(siteUrl)
              .bookmarks
              .where((b) => b.path != null)
              .take(4)
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

    final categoryRows = [
      for (final route in categories.take(4))
        _StartPageEntry.fromRoute(
          route,
          () => _openRoute(context, route),
          siteUrl: siteUrl,
          count: route.categoryId == null
              ? null
              : shell!.categoryActivityCountFor(siteUrl!, route.categoryId!),
          description: categoryDetails[route.categoryId]?.descriptionExcerpt,
        ),
    ];
    final chatRows = [
      for (final destination in unreadChannels.take(4))
        _StartPageEntry.fromRoute(
          ContentRoute.fromDestination(destination),
          () => destination.onTap?.call(),
          siteUrl: siteUrl,
          destination: destination,
        ),
    ];
    final topicRows = [
      for (final topic in latest)
        _StartPageEntry(
          id: 'topic-${topic.id}',
          title: topic.title,
          icon: topic.pinned
              ? DIcons.thumbtack
              : topic.closed
              ? DIcons.lock
              : DIcons.layerGroup,
          count: topic.unreadCount,
          activityAt: topic.bumpedAt,
          description: topic.excerpt,
          path: shell!.siteLink('/t/${topic.slug}/${topic.id}'),
          onPressed: () =>
              openLink(context, shell.siteLink('/t/${topic.slug}/${topic.id}')),
        ),
    ];
    final bookmarkRows = [
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
          time: bookmark.reminderAt == null
              ? null
              : bookmark.reminderAt!.isBefore(DateTime.now())
              ? context.l10n.due
              : context.l10n.reminderNewtabpage,
          description: bookmark.name,
          reminderAt: bookmark.reminderAt,
          postNumber: bookmark.postNumber,
          path: bookmark.path,
          targetBookmark: bookmark,
          onPressed: () => openLink(context, bookmark.path!),
        ),
    ];
    final closedRows = [
      for (final tab in closed.take(4))
        _StartPageEntry(
          id: 'closed-${tab.id}',
          title: tab.currentContent.title,
          icon: tab.currentContent.icon,
          path: _recentRouteUrl(siteUrl, tab.currentContent),
          bookmarkUrl: tab.currentContent.topicId == null || siteUrl == null
              ? null
              : resolveSiteRootPath(
                  siteUrl,
                  '/t/${tab.currentContent.topicId}',
                ),
          onPressed: () => shell!.reopenClosedTab(tab.id),
        ),
    ];
    final primarySections = siteUrl == null
        ? <_StartSection>[]
        : <_StartSection>[
            if (bookmarkRows.isNotEmpty)
              _StartSection(
                title: context.l10n.bookmarks,
                icon: DIcons.bookmark,
                rows: bookmarkRows,
                compact: _compact,
                siteUrl: siteUrl,
                onHeading: openBookmarks,
              ),
            if (categoryRows.isNotEmpty)
              _StartSection(
                title: context.l10n.categories,
                icon: DIcons.tag,
                rows: categoryRows,
                compact: _compact,
                siteUrl: siteUrl,
                onHeading: openCategories,
              ),
            if (hasChat && chatRows.isNotEmpty)
              _StartSection(
                title: context.l10n.chat,
                icon: DIcons.comment,
                rows: chatRows,
                compact: _compact,
                siteUrl: siteUrl,
                onHeading: openChat,
              ),
            if (topicRows.isNotEmpty)
              _StartSection(
                title: context.l10n.latestTopics,
                icon: DIcons.layerGroup,
                rows: topicRows,
                compact: _compact,
                siteUrl: siteUrl,
                onHeading: widget.onBrowseTopics,
              ),
          ];

    final tokens = DTokens.of(context);
    return SingleChildScrollView(
      child: DPageReadingLaneBox(
        child: Align(
          alignment: AlignmentDirectional.topCenter,
          child: ConstrainedBox(
            key: const ValueKey('start-page-content'),
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Padding(
              padding: const EdgeInsets.all(DSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DSpacing.lg,
                children: [
                  Row(
                    spacing: DSpacing.md,
                    children: [
                      if (forum != null) ForumIcon(forum: forum, size: 46),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (siteUrl == null)
                              Text(
                                context.l10n.startPage,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              )
                            else
                              SiteEmojiText.plain(
                                forum!.title,
                                siteUrl: siteUrl,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            if (forum != null)
                              Text(
                                Uri.tryParse(forum.url)?.host ?? forum.url,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: tokens.mutedForeground),
                              ),
                          ],
                        ),
                      ),
                      DToggleGroup<bool>(
                        key: const ValueKey('start-page-density'),
                        values: [_compact],
                        onChanged: (values) {
                          if (values.isNotEmpty) _setCompact(values.single);
                        },
                        allowEmptySelection: false,
                        inset: true,
                        density: DToggleDensity.compactInset,
                        size: DToggleSize.small,
                        items: [
                          DToggleGroupItem<bool>.iconOnly(
                            value: false,
                            icon: const DIcon(DIcons.grip, size: 12),
                            semanticLabel: context.l10n.comfortable,
                            tooltip: context.l10n.comfortable,
                          ),
                          DToggleGroupItem<bool>.iconOnly(
                            value: true,
                            icon: const DIcon(DIcons.list, size: 12),
                            semanticLabel: context.l10n.compact,
                            tooltip: context.l10n.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_dismissed == false &&
                      (ShellScope.maybeRead(context)?.desktopPanelsEnabled ??
                          true))
                    _PanelTutorial(onDismiss: _dismiss),
                  if (shell != null) ...[
                    if (closedRows.isNotEmpty)
                      _StartSection(
                        title: context.l10n.recentlyClosedNewtabpage,
                        icon: DIcons.arrowRotateLeft,
                        rows: closedRows,
                        compact: _compact,
                        fullWidth: true,
                        siteUrl: siteUrl!,
                      ),
                    if (_compact)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = ((constraints.maxWidth + 18) / 256)
                              .floor()
                              .clamp(1, 6);
                          final width =
                              (constraints.maxWidth - (columns - 1) * 18) /
                              columns;
                          return Wrap(
                            spacing: 18,
                            runSpacing: 28,
                            children: [
                              for (final section in primarySections)
                                SizedBox(width: width, child: section),
                            ],
                          );
                        },
                      )
                    else
                      ...primarySections,
                    _StartSection(
                      title: context.l10n.everythingElse,
                      icon: DIcons.ellipsis,
                      rows: const [],
                      compact: _compact,
                      siteUrl: siteUrl!,
                      fullWidth: true,
                      content: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          key: const ValueKey('start-page-shortcuts'),
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            if (bookmarkRows.isEmpty && forum?.user != null)
                              _LinkButton(
                                label: context.l10n.bookmarks,
                                icon: DIcons.bookmark,
                                onPressed: openBookmarks,
                              ),
                            if (topicRows.isEmpty)
                              _LinkButton(
                                label: context.l10n.latestTopics,
                                icon: DIcons.layerGroup,
                                url: shell.siteLink('/latest'),
                                onPressed: widget.onBrowseTopics,
                              ),
                            if (categoryRows.isEmpty)
                              _LinkButton(
                                label: context.l10n.categories,
                                icon: DIcons.tag,
                                url: shell.siteLink('/categories'),
                                onPressed: openCategories,
                              ),
                            if (hasChat && chatRows.isEmpty)
                              _LinkButton(
                                label: context.l10n.chat,
                                icon: DIcons.comment,
                                content: ContentRoute.fromDestination(
                                  chatDestination,
                                ),
                                onPressed: openChat,
                              ),
                            if (forum?.user != null)
                              _LinkButton(
                                label: context.l10n.messages,
                                icon: DIcons.inbox,
                                url: shell.siteLink('/my/messages'),
                                onPressed: () => openLink(
                                  context,
                                  shell.siteLink('/my/messages'),
                                ),
                              ),
                            _LinkButton(
                              label: context.l10n.groups,
                              icon: DIcons.users,
                              url: shell.siteLink('/g'),
                              onPressed: () =>
                                  openLink(context, shell.siteLink('/g')),
                            ),
                            _LinkButton(
                              label: context.l10n.badges,
                              icon: DIcons.certificate,
                              url: shell.siteLink('/badges'),
                              onPressed: () =>
                                  openLink(context, shell.siteLink('/badges')),
                            ),
                            for (final shortcut in shortcuts)
                              _LinkButton(
                                label: shortcut.label,
                                icon: shortcut.icon,
                                onPressed: () =>
                                    shell.selectDestination(shortcut),
                              ),
                            _LinkButton(
                              label: context.l10n.users,
                              icon: DIcons.user,
                              url: shell.siteLink('/u'),
                              onPressed: () =>
                                  openLink(context, shell.siteLink('/u')),
                            ),
                            if (forum?.user != null)
                              _LinkButton(
                                label: context.l10n.preferences,
                                icon: DIcons.filter,
                                onPressed: () => shell.openPreferences(siteUrl),
                              ),
                            _LinkButton(
                              label: context.l10n.settings,
                              icon: DIcons.gear,
                              onPressed: () => shell.openForumSettings(siteUrl),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (_dismissed != null)
                    DButton(
                      onPressed: widget.onBrowseTopics,
                      label: Text(context.l10n.browseLatestTopics),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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

String _reminderDate(
  DateTime date, {
  String? accountTimezone,
  required bool use24HourClock,
}) {
  final environment = TimezoneEnvironment.instance;
  return reminderDateLabel(
    date,
    location: environment.location(
      environment.readerTimezone(accountTimezone),
    )!,
    now: DateTime.now(),
    use24HourClock: use24HourClock,
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
    this.reminderAt,
    this.postNumber,
    this.path,
    this.targetBookmark,
    this.bookmarkUrl,
  });

  factory _StartPageEntry.fromRoute(
    ContentRoute route,
    VoidCallback onPressed, {
    required String? siteUrl,
    SidebarDestination? destination,
    int? count,
    String? description,
  }) => _StartPageEntry(
    id: route.id,
    title: route.title,
    icon: destination?.icon ?? route.icon,
    color: destination?.iconColor ?? route.color,
    count: count ?? destination?.unreadCount ?? destination?.badge?.count,
    activityAt: destination?.lastActivityAt,
    description: description ?? destination?.preview ?? route.subtitle,
    path: _recentRouteUrl(siteUrl, route),
    bookmarkUrl: route.topicId == null || siteUrl == null
        ? null
        : resolveSiteRootPath(siteUrl, '/t/${route.topicId}'),
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
  final DateTime? reminderAt;
  final int? postNumber;
  final String? path;
  final String? bookmarkUrl;
  final Bookmark? targetBookmark;
  final VoidCallback? onPressed;

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
    required this.compact,
    required this.siteUrl,
    this.onHeading,
    this.fullWidth = false,
    this.content,
  });

  final String title;
  final DIconData icon;
  final List<_StartPageEntry> rows;
  final bool compact;
  final String siteUrl;
  final VoidCallback? onHeading;
  final bool fullWidth;
  final Widget? content;

  Widget _row(BuildContext context, _StartPageEntry entry) {
    final canDrag =
        entry.path != null && ShellScope.of(context).desktopPanelsEnabled;
    if (!compact) return _comfortableRow(context, entry, canDrag: canDrag);
    final tokens = DTokens.of(context);
    final metadata = (entry.count ?? 0) > 0
        ? DBadge(
            size: DBadgeSize.compact,
            variant: DBadgeVariant.secondary,
            child: Text(entry.count.toString()),
          )
        : entry.timeLabel(
            style: const TextStyle(
              fontSize: DiscourseTypography.metadata,
              fontWeight: FontWeight.w400,
            ),
          );
    final row = DItem(
      key: ValueKey('start-page-recent-${entry.id}'),
      variant: DItemVariant.standard,
      size: compact ? DItemSize.xs : DItemSize.standard,
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
        DIcon(entry.icon, size: compact ? 16 : 18, color: entry.color),
        DItemContent(
          children: [
            SiteEmojiText.plain(
              entry.title,
              siteUrl: siteUrl,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 13 : 13.5,
                fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
              ),
            ),
            if (!compact && entry.description?.isNotEmpty == true)
              DItemDescription(
                child: SiteEmojiText.plain(
                  entry.description!,
                  siteUrl: siteUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        ?metadata,
      ],
    );
    final card = DCard(
      spacing: 0,
      border: false,
      borderRadius: BorderRadius.circular(9),
      backgroundColor: tokens.footerBackground,
      child: row,
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

  Widget _comfortableRow(
    BuildContext context,
    _StartPageEntry entry, {
    required bool canDrag,
  }) {
    final tokens = DTokens.of(context);
    final accent = entry.color ?? tokens.primary;
    final metadata = entry.reminderAt != null
        ? null
        : (entry.count ?? 0) > 0
        ? DBadge(
            size: DBadgeSize.compact,
            variant: DBadgeVariant.primary,
            child: Text(entry.count.toString()),
          )
        : entry.timeLabel(
            maxLines: 1,
            style: TextStyle(
              fontSize: DiscourseTypography.metadata,
              color: tokens.mutedForeground,
            ),
          );
    final row = DItem(
      key: ValueKey('start-page-recent-${entry.id}'),
      variant: DItemVariant.standard,
      shape: DItemShape.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
        DItemContent(
          spacing: 7,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DItemMedia(
                  child: Container(
                    width: 29,
                    height: 29,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color.lerp(tokens.background, accent, .2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: DIcon(entry.icon, size: 13, color: accent),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: SiteEmojiText.plain(
                      entry.title,
                      siteUrl: siteUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DiscourseTypography.compact,
                        height: 18 / 13.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.foreground,
                      ),
                    ),
                  ),
                ),
                if (metadata != null) ...[const SizedBox(width: 4), metadata],
              ],
            ),
            if (entry.reminderAt case final reminder?)
              DItemDescription(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Row(
                      children: [
                        const DIcon(DIcons.farClock, size: 13),
                        const SizedBox(width: DSpacing.sm),
                        Flexible(
                          child: Text(
                            _reminderDate(
                              reminder,
                              accountTimezone: ShellScope.maybeRead(
                                context,
                              )?.currentUserFor(siteUrl)?.timezone,
                              use24HourClock: use24HourClockOf(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (entry.postNumber != null ||
                        entry.description?.isNotEmpty == true)
                      SiteEmojiText.plain(
                        [
                          if (entry.postNumber case final number?)
                            context.l10n.postNewtabpage((number).toString()),
                          if (entry.description?.isNotEmpty == true)
                            entry.description!,
                        ].join(' · '),
                        siteUrl: siteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              )
            else if (entry.description?.isNotEmpty == true)
              DItemDescription(
                child: SiteEmojiText.plain(
                  entry.description!,
                  siteUrl: siteUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: DiscourseTypography.preview,
                    height: 1.38,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    final card = DCard(
      spacing: 0,
      border: false,
      backgroundColor: tokens.footerBackground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 100),
        child: row,
      ),
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
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final headingStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontSize: DiscourseTypography.control,
      fontWeight: FontWeight.w700,
      color: tokens.foreground,
    );
    final heading = onHeading == null
        ? SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 9,
              children: [
                SizedBox(
                  width: 20,
                  child: Center(
                    child: DIcon(icon, size: 12, color: tokens.mutedForeground),
                  ),
                ),
                Text(title, style: headingStyle),
              ],
            ),
          )
        : DButton(
            variant: DButtonVariant.transparentBackground,
            size: DButtonSize.small,
            foregroundColor: tokens.foreground,
            icon: SizedBox(
              width: 20,
              child: Center(
                child: DIcon(icon, size: 12, color: tokens.mutedForeground),
              ),
            ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 9,
              children: [
                Text(title, style: headingStyle),
                DIcon(
                  DIcons.chevronRight,
                  size: 11,
                  color: tokens.mutedForeground,
                ),
              ],
            ),
            onPressed: onHeading,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 9,
      children: [
        heading,
        if (rows.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = compact ? 4.0 : 10.0;
              final across = compact && !fullWidth
                  ? 1
                  : ((constraints.maxWidth + gap) /
                            ((compact ? 250 : 190) + gap))
                        .floor()
                        .clamp(compact ? 1 : 2, 100);
              final columnWidth =
                  (constraints.maxWidth - (across - 1) * gap) / across;
              final width = compact && fullWidth
                  ? columnWidth.clamp(0.0, 280.0)
                  : columnWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final entry in rows)
                    SizedBox(width: width, child: _row(context, entry)),
                ],
              );
            },
          ),
        ?content,
      ],
    );
  }
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
      backgroundColor: tokens.footerBackground,
      interactiveBackgroundColor: tokens.buttonTheme.accent.hover,
      borderColor: Colors.transparent,
      icon: DIcon(icon, size: 16),
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

class _PanelTutorial extends StatelessWidget {
  const _PanelTutorial({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 920),
    child: DCard(
      spacing: 0,
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final instructions = Padding(
                padding: const EdgeInsets.all(DSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.md,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: compact ? DSpacing.xxl : 0,
                      ),
                      child: Text(
                        context.l10n.workWithTwoPanels,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    _PanelGestureHint(
                      keys: [context.l10n.middleClick],
                      description: context.l10n.opensANewTabInMainPanel,
                    ),
                    _PanelGestureHint(
                      keys: [context.l10n.shift, context.l10n.click],
                      description: context.l10n.openInSecondaryPanel,
                    ),
                    _PanelGestureHint(
                      keys: [context.l10n.shift, context.l10n.middleClick],
                      description: context.l10n.openInANewTabInSecondaryPanel,
                    ),
                  ],
                ),
              );
              final diagram = _PanelTutorialDiagram();
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [instructions, const DSeparator(), diagram],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: instructions),
                    const DSeparator(orientation: Axis.vertical),
                    Expanded(child: diagram),
                  ],
                ),
              );
            },
          ),
          PositionedDirectional(
            top: DSpacing.sm,
            end: DSpacing.sm,
            child: DButton.iconOnly(
              key: const ValueKey('dismiss-panel-tutorial'),
              icon: const DIcon(DIcons.xmark),
              tooltip: context.l10n.donTShowThisTutorialAgain,
              onPressed: onDismiss,
              variant: DButtonVariant.transparentBackground,
              size: DButtonSize.small,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PanelTutorialDiagram extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return ColoredBox(
      color: tokens.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DSpacing.xl,
          vertical: DSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DSpacing.md,
          children: [
            Text(
              context.l10n.tWOPANELS,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tokens.mutedForeground),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.sm,
              children: [
                Expanded(child: _PanelPreview(label: context.l10n.main)),
                Expanded(
                  child: _PanelPreview(
                    label: context.l10n.secondary,
                    backgroundColor: tokens.selected,
                    highlightFirstLine: true,
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                context.l10n.shiftClickOpensHere,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelPreview extends StatelessWidget {
  const _PanelPreview({
    required this.label,
    this.backgroundColor,
    this.highlightFirstLine = false,
  });

  final String label;
  final Color? backgroundColor;
  final bool highlightFirstLine;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return SizedBox(
      height: 148,
      child: DCard(
        spacing: 0,
        borderRadius: BorderRadius.circular(DRadius.control),
        backgroundColor: backgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DSpacing.sm,
                vertical: DSpacing.sm,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const DSeparator(),
            Padding(
              padding: const EdgeInsets.all(DSpacing.md),
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DSpacing.sm,
                  children: [
                    _PanelPreviewLine(
                      color: highlightFirstLine
                          ? tokens.primary
                          : tokens.border,
                    ),
                    _PanelPreviewLine(
                      width: constraints.maxWidth * .75,
                      color: tokens.border,
                    ),
                    _PanelPreviewLine(
                      width: constraints.maxWidth * .55,
                      color: tokens.border,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Illustration artwork for a panel's content, not a loading placeholder: it
/// is drawn in the illustration's own colors and never animates.
class _PanelPreviewLine extends StatelessWidget {
  const _PanelPreviewLine({required this.color, this.width});

  final Color color;
  final double? width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      key: const ValueKey('panel-preview-line'),
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(DTokens.of(context).radius * 0.8),
      ),
    ),
  );
}

class _PanelGestureHint extends StatelessWidget {
  const _PanelGestureHint({required this.keys, required this.description});

  final List<String> keys;
  final String description;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: DSpacing.sm,
    runSpacing: DSpacing.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [for (final key in keys) DKbd(key), Text(description)],
  );
}
