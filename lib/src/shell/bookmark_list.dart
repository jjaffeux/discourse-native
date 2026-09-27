import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/bookmark_feed.dart';
import '../models/notification.dart';
import '../plugin_api/shell_extensions.dart';
import '../theme/d_icons.dart';
import '../utils/pagination.dart';
import 'account_activity_loader.dart';
import 'external_link.dart';
import 'notification_list.dart';
import 'open_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';
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

class _BookmarkSectionViewState extends State<_BookmarkSectionView> {
  String? _filter;
  final ScrollController _scrollController = ScrollController();
  bool _endCheckScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_BookmarkSectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.controller != widget.controller) {
      _filter = null;
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
      title: bookmark.title.isEmpty ? 'Bookmark' : bookmark.title,
      typeLabel: type == BookmarkTargetType.post
          ? bookmark.postNumber == null
                ? 'Post'
                : 'Post #${bookmark.postNumber}'
          : type == BookmarkTargetType.topic
          ? 'Topic'
          : 'Bookmark',
      filterLabel: type == BookmarkTargetType.post
          ? 'Posts'
          : type == BookmarkTargetType.topic
          ? 'Topics'
          : 'Other bookmarks',
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
    if (newTab) {
      await openLink(context, absolute, newTab: true);
      return;
    }
    if (await controller.openPluginUrl(
      absolute,
      origin: PluginLinkOrigin.inApp,
    )) {
      if (mounted) widget.onOpened();
      return;
    }
    // The Chat access check above can cross a credential and network boundary.
    // Do not navigate or dismiss a replacement section after this one has gone.
    if (!mounted) return;
    if (controller.openTopicUrl(absolute)) {
      widget.onOpened();
      return;
    }
    if (await openExternalLink(absolute) && mounted) widget.onOpened();
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
  static bool _canLoadMore(BookmarkListFeed feed) =>
      feed.loaded && feed.hasMore && !feed.loading && feed.error == null;

  void _loadMore() => unawaited(
    widget.controller.loadBookmarkList(widget.siteUrl, loadMore: true),
  );

  void _retry() {
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
    if (notification.depth == 0 &&
        notification.metrics.extentAfter <
            paginationPrefetchDistance(notification.metrics) &&
        _canLoadMore(_list)) {
      _loadMore();
    }
    return false;
  }

  /// A short list never scrolls, and a filter can hide every row the pages
  /// so far have held. Keep reading pages until what is shown fills the view
  /// or core has none left, so an empty filter is never claimed early.
  void _scheduleVisibleEndCheck(BookmarkListFeed feed) {
    if (_endCheckScheduled || !_canLoadMore(feed)) return;
    _endCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _endCheckScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      if (_canLoadMore(_list) &&
          _scrollController.position.extentAfter <= 0.5) {
        _loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.page
            ? controller.accountActivity.bookmarkListListenable
            : controller.accountActivity.bookmarksListenable,
        controller,
      ]),
      builder: (context, _) => widget.page ? _page(context) : _menu(context),
    );
  }

  Widget _menu(BuildContext context) {
    final controller = widget.controller;
    final feed = controller.bookmarksFor(widget.siteUrl);
    if (feed.error case final error?) {
      return UserMenuMessage(
        text: error,
        onRetry: () => controller.loadBookmarks(widget.siteUrl),
      );
    }
    if (!feed.loaded) {
      return const UserMenuLoading(semanticsLabel: 'Loading bookmarks');
    }
    if (!feed.hasRows) {
      return const UserMenuMessage(text: 'Nothing bookmarked yet.');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final reminder in feed.reminders)
          Builder(
            builder: (context) {
              final resolved = controller.plugins.registry.resolveNotification(
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
    final feed = _list;
    final entries = [
      for (final bookmark in feed.bookmarks)
        (bookmark: bookmark, presentation: _present(bookmark)),
    ];
    final filters = <String>{
      'Posts',
      'Topics',
      for (final presenter
          in controller.pluginSession.capabilities<PluginBookmarkPresenter>())
        presenter.bookmarkFilterLabel,
      for (final entry in entries) entry.presentation.filterLabel,
    };
    final visibleEntries = entries
        .where(
          (entry) =>
              _filter == null || entry.presentation.filterLabel == _filter,
        )
        .toList();
    _scheduleVisibleEndCheck(feed);

    Widget? state;
    if (visibleEntries.isEmpty) {
      if (feed.error case final error?) {
        state = UserMenuMessage(text: error, onRetry: _retry);
      } else if (!feed.loaded || feed.hasMore) {
        state = const UserMenuLoading(
          semanticsLabel: 'Loading bookmarks',
          surface: SkeletonSurface.page,
        );
      } else {
        state = UserMenuMessage(
          text: feed.isEmpty
              ? 'Nothing bookmarked yet.'
              : 'No bookmarks in this filter.',
        );
      }
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(child: _heading(context, filters)),
          if (state != null)
            SliverToBoxAdapter(child: state)
          else ...[
            SliverList.separated(
              itemCount: visibleEntries.length,
              separatorBuilder: (context, index) => const DSeparator(),
              itemBuilder: (context, index) {
                final entry = visibleEntries[index];
                return BookmarkRow(
                  bookmark: entry.bookmark,
                  siteUrl: widget.siteUrl,
                  presentation: entry.presentation,
                  onTap: () => _openBookmark(entry.bookmark),
                );
              },
            ),
            if (feed.error case final error?)
              SliverToBoxAdapter(
                child: UserMenuMessage(text: error, onRetry: _retry),
              )
            else if (feed.loading)
              SliverToBoxAdapter(
                child: Semantics(
                  liveRegion: true,
                  label: 'Loading more bookmarks',
                  child: const SizedBox.shrink(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, Set<String> filters) => Padding(
    padding: const EdgeInsets.all(DSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Bookmarks',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: DSpacing.lg),
        Row(
          children: [
            DSelect<String>.controlled(
              size: DControlSize.filter,
              semanticLabel: 'Filter bookmarks',
              value: _filter,
              entries: [
                const DSelectOption(
                  value: null,
                  label: 'All bookmarks',
                  child: Text('All bookmarks'),
                ),
                for (final filter in filters)
                  DSelectOption(
                    value: filter,
                    label: filter,
                    child: Text(filter),
                  ),
              ],
              onChanged: (value) => setState(() => _filter = value),
            ),
          ],
        ),
        const SizedBox(height: DSpacing.lg),
        const DSeparator(),
      ],
    ),
  );
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
  final BookmarkPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final details = presentation;
    final label = [
      if (details == null) ?bookmark.author,
      details?.title ?? (bookmark.title.isEmpty ? 'Bookmark' : bookmark.title),
      if (details != null) details.subtitle,
      if (bookmark.name case final name?) 'Note: $name',
    ].join(', ');
    final color = details?.color ?? tokens.mutedForeground;
    final row = DItem(
      key: ValueKey('bookmark-row-${bookmark.id}'),
      shape: details == null ? DItemShape.standard : DItemShape.fullWidth,
      selectionStyle: DItemSelectionStyle.leadingAccent,
      onPressed: onTap,
      semanticLabel: label,
      children: [
        DItemMedia(
          child: ExcludeSemantics(
            child: details == null
                ? DIcon(
                    bookmark.reminderAt == null
                        ? DIcons.bookmark
                        : DIcons.discourseBookmarkClock,
                    size: 16,
                    color: tokens.mutedForeground,
                  )
                : DAvatar(
                    decorative: true,
                    fallback: DAvatarFallback(
                      backgroundColor: color.withValues(alpha: .2),
                      foregroundColor: Color.lerp(
                        color,
                        tokens.foreground,
                        .35,
                      ),
                      child: DIcon(details.icon),
                    ),
                  ),
          ),
        ),
        DItemContent(
          spacing: DSpacing.xs,
          children: [
            ExcludeSemantics(
              child: Text(
                details?.title ?? [?bookmark.author, bookmark.title].join(' '),
                maxLines: details == null ? 2 : null,
                overflow: details == null
                    ? TextOverflow.ellipsis
                    : TextOverflow.clip,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (details != null)
              ExcludeSemantics(
                child: Text(
                  details.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.mutedForeground,
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    final name = bookmark.name;
    final presented = name == null
        ? row
        : DTooltip(
            message: name,
            excludeFromSemantics: true,
            hoverDelay: const Duration(milliseconds: 400),
            child: row,
          );
    final path = bookmark.path;
    return path == null
        ? presented
        : LinkTarget(url: path, siteUrl: siteUrl, child: presented);
  }
}
