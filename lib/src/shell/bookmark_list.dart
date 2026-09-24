import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/notification.dart';
import '../plugin_api/shell_extensions.dart';
import '../theme/d_icons.dart';
import 'account_activity_loader.dart';
import 'external_link.dart';
import 'notification_list.dart';
import 'open_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';
import 'user_menu_message.dart';

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
  Widget build(BuildContext context) => AccountActivityLoader.bookmarks(
    siteUrl: siteUrl,
    builder: (context, controller) => _BookmarkSectionView(
      controller: controller,
      siteUrl: siteUrl,
      onOpened: onOpened,
      page: page,
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

  Future<void> _open(String? path, {bool newTab = false}) async {
    if (path == null) return;

    final controller = widget.controller;
    final absolute = controller.absoluteUrl(path, siteUrl: widget.siteUrl);
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
    await _open(path, newTab: newTab);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.accountActivity.bookmarksListenable,
        controller,
      ]),
      builder: (context, _) {
        final feed = controller.bookmarksFor(widget.siteUrl);
        final entries = [
          for (final bookmark in feed.bookmarks)
            (bookmark: bookmark, presentation: _present(bookmark)),
        ];
        final filters = <String>{
          'Posts',
          'Topics',
          for (final presenter
              in controller.pluginSession
                  .capabilities<PluginBookmarkPresenter>())
            presenter.bookmarkFilterLabel,
          for (final entry in entries) entry.presentation.filterLabel,
        };
        final visibleEntries = entries
            .where(
              (entry) =>
                  !widget.page ||
                  _filter == null ||
                  entry.presentation.filterLabel == _filter,
            )
            .toList();
        final reminders = !widget.page || _filter == null
            ? feed.reminders
            : const <DiscourseNotification>[];

        Widget content() {
          if (feed.error case final error?) {
            return UserMenuMessage(
              text: error,
              onRetry: () => controller.loadBookmarks(widget.siteUrl),
            );
          }
          if (!feed.loaded) {
            return UserMenuLoading(
              semanticsLabel: 'Loading bookmarks',
              surface: widget.page
                  ? SkeletonSurface.page
                  : SkeletonSurface.floating,
            );
          }
          if (reminders.isEmpty && visibleEntries.isEmpty) {
            return UserMenuMessage(
              text: feed.isEmpty
                  ? 'Nothing bookmarked yet.'
                  : 'No bookmarks in this filter.',
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final reminder in reminders) ...[
                Builder(
                  builder: (context) {
                    final resolved = controller.plugins.registry
                        .resolveNotification(reminder);
                    return NotificationRow(
                      notification: reminder,
                      resolved: resolved,
                      siteUrl: widget.siteUrl,
                      onTap: () => _openReminder(reminder, resolved.path),
                      onMiddleClick: () =>
                          _openReminder(reminder, resolved.path, newTab: true),
                    );
                  },
                ),
                if (widget.page) const DSeparator(),
              ],
              for (final (index, entry) in visibleEntries.indexed) ...[
                if (widget.page && index > 0) const DSeparator(),
                BookmarkRow(
                  bookmark: entry.bookmark,
                  presentation: widget.page ? entry.presentation : null,
                  onTap: () => _open(entry.bookmark.path),
                ),
              ],
            ],
          );
        }

        if (!widget.page) return content();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(DSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Bookmarks',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
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
            ),
            content(),
          ],
        );
      },
    );
  }
}

class BookmarkRow extends StatelessWidget {
  const BookmarkRow({
    super.key,
    required this.bookmark,
    required this.onTap,
    this.presentation,
  });

  final Bookmark bookmark;
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
    if (name == null) return row;
    return DTooltip(
      message: name,
      excludeFromSemantics: true,
      hoverDelay: const Duration(milliseconds: 400),
      child: row,
    );
  }
}
