import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/notification.dart';
import '../plugin_api/shell_extensions.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'account_activity_loader.dart';
import 'external_link.dart';
import 'notification_list.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_message.dart';

class BookmarkSection extends StatelessWidget {
  const BookmarkSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;

  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) => AccountActivityLoader.bookmarks(
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
  });

  final ShellController controller;
  final String siteUrl;
  final VoidCallback onOpened;

  @override
  State<_BookmarkSectionView> createState() => _BookmarkSectionViewState();
}

class _BookmarkSectionViewState extends State<_BookmarkSectionView> {
  Future<void> _open(String? path) async {
    if (path == null) return;

    final controller = widget.controller;
    final absolute = controller.absoluteUrl(path, siteUrl: widget.siteUrl);
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
    String? path,
  ) async {
    ShellScope.read(context).readNotification(widget.siteUrl, reminder);
    await _open(path);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller.accountActivity.bookmarksListenable,
      builder: (context, _) {
        final feed = controller.bookmarksFor(widget.siteUrl);

        if (feed.error case final error?) {
          return UserMenuMessage(
            text: error,
            onRetry: () => controller.loadBookmarks(widget.siteUrl),
          );
        }
        if (!feed.loaded) return const UserMenuMessage(text: null);
        if (feed.isEmpty) {
          return const UserMenuMessage(text: 'Nothing bookmarked yet.');
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...feed.reminders.map((reminder) {
              final resolved = controller.plugins.registry.resolveNotification(
                reminder,
              );
              return NotificationRow(
                notification: reminder,
                resolved: resolved,
                siteUrl: widget.siteUrl,
                onTap: () => _openReminder(reminder, resolved.path),
              );
            }),
            for (final bookmark in feed.bookmarks)
              BookmarkRow(
                bookmark: bookmark,
                onTap: () => _open(bookmark.path),
              ),
          ],
        );
      },
    );
  }
}

class BookmarkRow extends StatelessWidget {
  const BookmarkRow({super.key, required this.bookmark, required this.onTap});

  final Bookmark bookmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = [
      ?bookmark.author,
      if (bookmark.title.isNotEmpty) bookmark.title else 'Bookmark',
      if (bookmark.name case final name?) 'Note: $name',
    ].join(', ');

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Semantics(
        key: ValueKey('bookmark-row-${bookmark.id}'),
        label: label,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: DIcon(
                        bookmark.reminderAt == null
                            ? DIcons.bookmark
                            : DIcons.discourseBookmarkClock,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            if (bookmark.author case final author?)
                              TextSpan(
                                text: '$author ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            TextSpan(text: bookmark.title),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final name = bookmark.name;
    if (name == null) return row;
    return Tooltip(
      message: name,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 400),
      child: row,
    );
  }
}
