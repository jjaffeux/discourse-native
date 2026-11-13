import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../foundation/icons/d_icons.dart';
import '../models/bookmark.dart';
import '../models/bookmark_feed.dart';
import '../models/destination_bookmark.dart';
import '../models/notification.dart';
import '../plugin_api/shell_extensions.dart';
import '../theme/discourse_typography.dart';
import '../utils/pagination.dart';
import 'account_activity_loader.dart';
import 'account_activity_paging_skeleton.dart';
import 'account_feed_viewport.dart';
import 'bookmark_tile.dart';
import 'desktop_header_menu.dart';
import 'destination_bookmark_ui.dart';
import 'directory_skeleton.dart';
import 'external_link.dart';
import 'notification_list.dart';
import 'open_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_message.dart';

/// The user menu's bookmarks tab, or with [page] the whole bookmarks page.
///
/// The menu reads core's twenty-row menu route. The page reads the paged list
/// behind the web client's bookmarks page and scrolls itself, so it must not
/// be placed inside another scroll view.
class BookmarkSection extends StatelessWidget {
  const BookmarkSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
    this.page = false,
  });

  final String siteUrl;

  final VoidCallback onOpened;
  final bool page;

  @override
  Widget build(BuildContext context) => page
      ? AccountActivityLoader.bookmarkList(
          siteUrl: siteUrl,
          builder: (context, controller) => _BookmarkSectionView(
            controller: controller,
            siteUrl: siteUrl,
            onOpened: onOpened,
            page: true,
          ),
        )
      : AccountActivityLoader.bookmarks(
          siteUrl: siteUrl,
          builder: (context, controller) => _BookmarkSectionView(
            controller: controller,
            siteUrl: siteUrl,
            onOpened: onOpened,
          ),
        );
}

class _BookmarkSectionView extends StatefulWidget {
  const _BookmarkSectionView({
    required this.controller,
    required this.siteUrl,
    required this.onOpened,
    this.page = false,
  });

  final ShellController controller;
  final String siteUrl;
  final VoidCallback onOpened;
  final bool page;

  @override
  State<_BookmarkSectionView> createState() => _BookmarkSectionViewState();
}

enum BookmarkReminderFilter { all, reminders, expired }

class _BookmarkSectionViewState extends State<_BookmarkSectionView> {
  BookmarkReminderFilter _reminderFilter = BookmarkReminderFilter.all;
  Timer? _expiryTimer;
  ScrollController? _scrollController;
  bool _endCheckScheduled = false;
  bool _hasMatchingRows = false;
  Object? _pageSession;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_BookmarkSectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.controller != widget.controller) {
      _reminderFilter = BookmarkReminderFilter.all;
      _expiryTimer?.cancel();
    }
  }

  BookmarkPresentation _present(Bookmark bookmark) {
    final controller = widget.controller;
    for (final presenter
        in controller.pluginSession.capabilities<PluginBookmarkPresenter>()) {
      final presentation = presenter.presentBookmark(widget.siteUrl, bookmark);
      if (presentation != null) return presentation;
    }
    final category = controller.categoryFor(
      bookmark.categoryId,
      siteUrl: widget.siteUrl,
    );
    final type = bookmark.coreTargetType;
    return BookmarkPresentation(
      title: bookmark.title.isEmpty ? appL10n.bookmark : bookmark.title,
      typeLabel: type == BookmarkTargetType.post
          ? bookmark.postNumber == null
                ? appL10n.post
                : appL10n.postBookmarkui((bookmark.postNumber).toString())
          : type == BookmarkTargetType.topic
          ? appL10n.topic
          : appL10n.bookmark,
      contextLabel: category?.name,
      icon: type == BookmarkTargetType.post
          ? DIcons.reply
          : type == BookmarkTargetType.topic
          ? DIcons.layerGroup
          : DIcons.bookmark,
      color: category == null ? null : Color(category.colorValue),
    );
  }

  /// A bookmark's path is the link Discourse wrote, subfolder included.
  Future<void> _openBookmark(Bookmark bookmark) async {
    final path = bookmark.path;
    if (path == null) return;
    await _open(widget.controller.absoluteUrl(path, siteUrl: widget.siteUrl));
  }

  Future<void> _open(String absolute, {bool newTab = false}) async {
    final controller = widget.controller;
    final siteUrl = widget.siteUrl;
    final lease = controller.lifecycle.capture(siteUrl);
    bool current() =>
        mounted &&
        lease.isCurrent &&
        identical(widget.controller, controller) &&
        widget.siteUrl == siteUrl &&
        controller.currentInstance?.url == siteUrl;

    if (newTab) {
      await openLink(context, absolute, newTab: true);
      return;
    }
    if (await controller.openPluginUrl(
      absolute,
      origin: PluginLinkOrigin.inApp,
    )) {
      if (current()) widget.onOpened();
      return;
    }
    // The Chat access check above can cross a credential and network boundary.
    // Do not navigate or dismiss a replacement section after this one has gone.
    if (!current()) return;
    if (controller.openTopicUrl(absolute)) {
      widget.onOpened();
      return;
    }
    if (await openExternalLink(absolute) && current()) widget.onOpened();
  }

  Future<void> _openReminder(
    DiscourseNotification reminder,
    String? path, {
    bool newTab = false,
  }) async {
    ShellScope.read(context).readNotification(widget.siteUrl, reminder);
    if (path == null) return;
    await _open(
      widget.controller.siteLink(path, siteUrl: widget.siteUrl),
      newTab: newTab,
    );
  }

  BookmarkListFeed get _list =>
      widget.controller.accountActivity.bookmarkListFor(widget.siteUrl);

  // A failed page is retried only from its Retry row: every scroll
  // notification near the end would otherwise resend it as soon as it fails.
  static bool _admits(BookmarkListFeed feed, {required bool hasMore}) =>
      ScrollPagingGate(
        hasMore: hasMore,
        busy: feed.loading,
        lastPageFailed: feed.error != null,
      ).admits;

  static bool _canLoadMore(BookmarkListFeed feed) =>
      feed.loaded && _admits(feed, hasMore: feed.hasMore);

  void _loadMore() {
    unawaited(
      widget.controller.loadBookmarkList(widget.siteUrl, loadMore: true),
    );
  }

  void _loadPrevious() {
    final instance = widget.controller.instances
        .where((item) => item.url == widget.siteUrl)
        .firstOrNull;
    if (instance != null) {
      unawaited(
        widget.controller.accountActivity.loadBookmarkList(
          instance,
          loadPrevious: true,
        ),
      );
    }
  }

  void _changedFilter(VoidCallback update) {
    setState(update);
    if (_list.hasPrevious) {
      unawaited(
        widget.controller.loadBookmarkList(widget.siteUrl, refresh: true),
      );
    }
  }

  void _retry() {
    if (_list.retryPrevious) {
      _loadPrevious();
      return;
    }
    final fromStart = _list.retryFromStart;
    unawaited(
      widget.controller.loadBookmarkList(
        widget.siteUrl,
        refresh: fromStart,
        loadMore: !fromStart,
      ),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if ((notification is UserScrollNotification &&
                notification.direction == ScrollDirection.forward ||
            notification is ScrollUpdateNotification &&
                (notification.scrollDelta ?? 0) < 0) &&
        notification.metrics.extentBefore <
            (_list.retainedPageCount == 1
                ? 0.5
                : paginationPrefetchDistance(notification.metrics)) &&
        _admits(_list, hasMore: _list.hasPrevious)) {
      _loadPrevious();
    } else if ((notification is ScrollUpdateNotification &&
                (notification.scrollDelta ?? 0) > 0 ||
            notification is OverscrollNotification &&
                notification.overscroll > 0) &&
        notification.metrics.extentAfter <
            (_list.retainedPageCount == 1
                ? 0.5
                : paginationPrefetchDistance(notification.metrics)) &&
        _canLoadMore(_list)) {
      _loadMore();
    }
    return false;
  }

  bool _canFillViewport(BookmarkListFeed feed) {
    if (!_canLoadMore(feed)) return false;
    if (_reminderFilter == BookmarkReminderFilter.all) return !feed.hasPrevious;
    return !_hasMatchingRows;
  }

  void _scheduleVisibleEndCheck(BookmarkListFeed feed) {
    if (_endCheckScheduled || !_canFillViewport(feed)) {
      return;
    }
    _endCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _endCheckScheduled = false;
      _loadMoreIfEndVisible();
    });
  }

  void _loadMoreIfEndVisible() {
    final scroll = _scrollController;
    if (!mounted || scroll == null || !scroll.hasClients) return;
    if (_canFillViewport(_list) && scroll.position.extentAfter <= 0.5) {
      _loadMore();
    }
  }

  // A taller viewport reveals the end without rebuilding this page.
  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _loadMoreIfEndVisible();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.controller.accountActivity;
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.page
            ? activity.bookmarkListListenable
            : activity.bookmarksListenable,
        widget.controller.accountDestinationBookmarks,
      ]),
      builder: (context, _) => ShellSelector<_ShellDrawn>(
        select: (_) => _shellDrawn(),
        builder: (context, _, _) =>
            widget.page ? _page(context) : _menu(context),
      ),
    );
  }

  /// What this section draws from the shell and the clock. A row's
  /// presentation can read any plugin's state, so a shell notification is
  /// judged by what would be drawn, not by a list of sources believed to feed
  /// it.
  _ShellDrawn _shellDrawn() {
    final controller = widget.controller;
    final siteUrl = widget.siteUrl;
    final menu = widget.page ? null : controller.bookmarksFor(siteUrl);
    final bookmarks = menu?.bookmarks ?? _list.bookmarks;
    final now = DateTime.now();
    return _ShellDrawn([
      controller.lifecycle.capture(siteUrl).session,
      ...controller.accountDestinationBookmarks.entriesFor(siteUrl),
      for (final bookmark in bookmarks) bookmark.reminderExpiredAt(now),
      if (menu == null)
        for (final bookmark in bookmarks) _present(bookmark)
      else
        for (final reminder in menu.reminders)
          controller.pluginSession.resolveNotification(
            controller.plugins.registry,
            siteUrl,
            reminder,
          ),
    ]);
  }

  Widget _menu(BuildContext context) {
    final entries = widget.controller.accountDestinationBookmarks.entriesFor(
      widget.siteUrl,
    );
    if (entries.isEmpty || DesktopHeaderMenu.isActiveOf(context)) {
      return _serverMenu(context);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final bookmark in entries)
          DestinationBookmarkRow(
            siteUrl: widget.siteUrl,
            bookmark: bookmark,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onOpened: widget.onOpened,
          ),
        if (!widget.controller.bookmarksFor(widget.siteUrl).loaded ||
            widget.controller.bookmarksFor(widget.siteUrl).error != null ||
            widget.controller.bookmarksFor(widget.siteUrl).hasRows)
          _serverMenu(context),
      ],
    );
  }

  Widget _serverMenu(BuildContext context) {
    final controller = widget.controller;
    final feed = controller.bookmarksFor(widget.siteUrl);
    if (feed.error case final error?) {
      return UserMenuMessage(
        text: error,
        onRetry: () => controller.loadBookmarks(widget.siteUrl),
      );
    }
    if (!feed.loaded) {
      return UserMenuLoading(semanticsLabel: context.l10n.loadingBookmarks);
    }
    if (!feed.hasRows ||
        DesktopHeaderMenu.isActiveOf(context) && feed.reminders.isEmpty) {
      return UserMenuMessage(
        text: DesktopHeaderMenu.isActiveOf(context)
            ? context.l10n.nothingNew
            : context.l10n.nothingBookmarkedYet,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesktopHeaderMenu.isActiveOf(context) ? 2 : 0,
      children: [
        for (final reminder in feed.reminders)
          Builder(
            builder: (context) {
              final resolved = controller.pluginSession.resolveNotification(
                controller.plugins.registry,
                widget.siteUrl,
                reminder,
              );
              return NotificationRow(
                notification: reminder,
                resolved: resolved,
                siteUrl: widget.siteUrl,
                linkPath: resolved.path,
                onTap: () => _openReminder(reminder, resolved.path),
                onMiddleClick: () =>
                    _openReminder(reminder, resolved.path, newTab: true),
              );
            },
          ),
        if (!DesktopHeaderMenu.isActiveOf(context))
          for (final bookmark in feed.bookmarks)
            BookmarkRow(
              bookmark: bookmark,
              siteUrl: widget.siteUrl,
              onTap: () => _openBookmark(bookmark),
            ),
      ],
    );
  }

  Widget _page(BuildContext context) {
    final controller = widget.controller;
    final session = controller.lifecycle.capture(widget.siteUrl).session;
    if (_pageSession != session) {
      _pageSession = session;
      _reminderFilter = BookmarkReminderFilter.all;
    }
    final feed = _list;
    final entries = [
      for (final bookmark in feed.bookmarks)
        (bookmark: bookmark, presentation: _present(bookmark)),
    ];
    final localEntries = controller.accountDestinationBookmarks.entriesFor(
      widget.siteUrl,
    );
    final now = DateTime.now();
    _expiryTimer?.cancel();
    final upcoming =
        feed.bookmarks
            .map((bookmark) => bookmark.reminderAt)
            .whereType<DateTime>()
            .where((at) => at.isAfter(now))
            .toList()
          ..sort();
    if (upcoming.isNotEmpty) {
      _expiryTimer = Timer(upcoming.first.difference(now), () {
        if (mounted) setState(() {});
      });
    }
    final visibleEntries = entries
        .where(
          (entry) => switch (_reminderFilter) {
            BookmarkReminderFilter.all => true,
            BookmarkReminderFilter.reminders =>
              entry.bookmark.reminderAt != null,
            BookmarkReminderFilter.expired => entry.bookmark.reminderExpiredAt(
              now,
            ),
          },
        )
        .toList();
    final visibleLocalEntries = _reminderFilter == BookmarkReminderFilter.all
        ? localEntries
        : const <DestinationBookmark>[];
    _hasMatchingRows = visibleEntries.isNotEmpty;
    _scheduleVisibleEndCheck(feed);

    Widget? state;
    if (visibleEntries.isEmpty) {
      if (feed.error case final error?) {
        state = SliverToBoxAdapter(
          child: UserMenuMessage(text: error, onRetry: _retry),
        );
      } else if (!feed.loaded || feed.loading) {
        state = const SliverDirectorySkeleton(
          key: ValueKey('bookmarks-loading'),
          kind: DirectorySkeletonKind.bookmarks,
        );
      } else if (visibleLocalEntries.isEmpty &&
          !feed.hasMore &&
          !feed.hasPrevious) {
        state = SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              context.l10n.nothingBookmarkedHere,
              style: TextStyle(
                fontSize: DiscourseTypography.compact,
                height: DiscourseTypography.lineHeightSmall,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
          ),
        );
      }
    }

    final content = DPageSurface.headed(
      identity: widget.siteUrl,
      title: Text(context.l10n.bookmarks),
      controls: DReferenceTextScale(child: _heading(context)),
      bodyBuilder: (context, header) => DPageReadingLane(
        builder: (context, lane) => AccountFeedViewport(
          identity: (
            widget.controller,
            widget.siteUrl,
            session,
            _reminderFilter,
          ),
          rows: [for (final entry in visibleEntries) entry.bookmark.id],
          revealEnd: feed.window.lastPageWasPrevious,
          separated: true,
          builder: (context, viewport) {
            _scrollController = viewport.scrollController;
            return NotificationListener<ScrollMetricsNotification>(
              onNotification: _onScrollMetrics,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) =>
                    viewport.restoring ? false : _onScroll(notification),
                child: CustomScrollView(
                  controller: viewport.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: header.spacer),
                    SliverPadding(
                      padding: EdgeInsets.only(
                        left: lane.leftInset + 16,
                        right: lane.rightInset + 16,
                      ),
                      sliver: SliverMainAxisGroup(
                        slivers: _pageSlivers(
                          context,
                          feed: feed,
                          state: state,
                          viewport: viewport,
                          visibleEntries: visibleEntries,
                          visibleLocalEntries: visibleLocalEntries,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    return DScrollChromePagination(
      hasMore: feed.hasMore,
      loading: feed.loading,
      child: content,
    );
  }

  List<Widget> _pageSlivers(
    BuildContext context, {
    required BookmarkListFeed feed,
    required Widget? state,
    required AccountFeedViewportState viewport,
    required List<({Bookmark bookmark, BookmarkPresentation presentation})>
    visibleEntries,
    required List<DestinationBookmark> visibleLocalEntries,
  }) => [
    SliverList.separated(
      itemCount: visibleLocalEntries.length,
      separatorBuilder: (context, index) => const DSeparator(),
      itemBuilder: (context, index) => DestinationBookmarkRow(
        siteUrl: widget.siteUrl,
        bookmark: visibleLocalEntries[index],
        onOpened: widget.onOpened,
      ),
    ),
    if (visibleLocalEntries.isNotEmpty && visibleEntries.isNotEmpty)
      const SliverToBoxAdapter(child: DSeparator()),
    if (feed.hasPrevious)
      SliverToBoxAdapter(
        child: Center(
          child: DButton(
            label: Text(context.l10n.previous),
            loading: feed.loadingPrevious,
            onPressed: feed.loading ? null : _loadPrevious,
          ),
        ),
      ),
    if (state != null)
      state
    else ...[
      SuperSliverList.separated(
        listController: viewport.listController,
        findChildIndexCallback: viewport.indexForKey,
        itemCount: visibleEntries.length,
        separatorBuilder: (context, index) => const DSeparator(),
        itemBuilder: (context, index) {
          final entry = visibleEntries[index];
          return viewport.row(
            entry.bookmark.id,
            BookmarkRow(
              bookmark: entry.bookmark,
              siteUrl: widget.siteUrl,
              presentation: entry.presentation,
              onTap: () => _openBookmark(entry.bookmark),
            ),
          );
        },
      ),
      if (feed.error case final error?)
        SliverToBoxAdapter(
          child: UserMenuMessage(text: error, onRetry: _retry),
        )
      else if (feed.loading)
        SliverToBoxAdapter(
          child: AccountActivityPagingSkeleton(
            semanticsLabel: context.l10n.loadingMoreBookmarks,
          ),
        ),
    ],
  ];

  Widget _heading(BuildContext context) {
    String label(BookmarkReminderFilter filter) => switch (filter) {
      BookmarkReminderFilter.all => context.l10n.allBookmarks,
      BookmarkReminderFilter.reminders => context.l10n.bookmarkReminders,
      BookmarkReminderFilter.expired => context.l10n.expired,
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: DSelect<BookmarkReminderFilter>.controlled(
        size: DControlSize.filter,
        semanticLabel: context.l10n.filterBookmarks,
        value: _reminderFilter,
        entries: [
          for (final filter in BookmarkReminderFilter.values)
            DSelectOption(
              value: filter,
              label: label(filter),
              child: Text(label(filter)),
            ),
        ],
        onChanged: (value) => _changedFilter(
          () => _reminderFilter = value ?? BookmarkReminderFilter.all,
        ),
      ),
    );
  }
}

@immutable
final class _ShellDrawn {
  const _ShellDrawn(this.values);

  final List<Object?> values;

  @override
  bool operator ==(Object other) =>
      other is _ShellDrawn && listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);
}

class BookmarkRow extends StatelessWidget {
  const BookmarkRow({
    super.key,
    required this.bookmark,
    this.siteUrl,
    required this.onTap,
    this.presentation,
  });

  final Bookmark bookmark;
  final String? siteUrl;
  final VoidCallback onTap;

  /// Present on the Bookmarks page, which draws a [BookmarkTile]; the user
  /// menu's tab draws its compact row without one.
  final BookmarkPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final details = presentation;
    final expired = bookmark.reminderExpiredAt(DateTime.now());
    final name = bookmark.name;
    final label = [
      if (expired) context.l10n.bookmarkReminderExpired,
      if (details == null) ?bookmark.author,
      details?.title ??
          (bookmark.title.isEmpty ? context.l10n.bookmark : bookmark.title),
      if (details != null) details.subtitle,
      if (name != null) context.l10n.noteBookmarklist(name),
    ].join(', ');
    final row = details == null
        ? _menuRow(context, label: label, expired: expired)
        : BookmarkTile(
            key: ValueKey('bookmark-row-${bookmark.id}'),
            icon: details.icon,
            color: details.color,
            title: details.title,
            details: [
              if (name != null && name.isNotEmpty) name,
              details.subtitle,
            ].join(' · '),
            semanticLabel: label,
            expired: expired,
            onPressed: onTap,
          );
    final path = bookmark.path;
    return path == null
        ? row
        : LinkTarget(
            url: path,
            siteUrl: siteUrl,
            targetBookmark: bookmark,
            child: row,
          );
  }

  Widget _menuRow(
    BuildContext context, {
    required String label,
    required bool expired,
  }) {
    final tokens = DTokens.of(context);
    final row = DItem(
      key: ValueKey('bookmark-row-${bookmark.id}'),
      selectionStyle: DItemSelectionStyle.leadingAccent,
      selected: expired,
      showSelectionIndicator: false,
      onPressed: onTap,
      semanticLabel: label,
      children: [
        DItemMedia(
          child: ExcludeSemantics(
            child: DIcon(
              bookmark.reminderAt == null
                  ? DIcons.bookmark
                  : DIcons.discourseBookmarkClock,
              size: 16,
              color: tokens.mutedForeground,
            ),
          ),
        ),
        DItemContent(
          spacing: DSpacing.xs,
          children: [
            ExcludeSemantics(
              child: Text(
                [?bookmark.author, bookmark.title].join(' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
    final name = bookmark.name;
    return name == null
        ? row
        : DTooltip(
            message: name,
            excludeFromSemantics: true,
            hoverDelay: const Duration(milliseconds: 400),
            child: row,
          );
  }
}
