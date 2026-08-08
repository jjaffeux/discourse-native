import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/notification.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'notification_list.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_message.dart';

/// The bookmarks tab's contents: the site's own list.
///
/// Two runs of rows, the way `/u/{username}/user-menu-bookmarks` answers and
/// the way Discourse draws them: the reminders that have come due and not been
/// read, and then the bookmarks. A reminder is a notification like any other,
/// so it is drawn by the same row as the notifications tab uses — the point of
/// putting it first is that it is the one thing here the reader has not seen.
///
/// Draws itself as a column rather than a list of its own, so that it scrolls
/// inside whichever of the menu's two forms is showing it — a popover with a
/// fixed height, or a sheet that is one long scroll.
class BookmarkSection extends StatelessWidget {
  const BookmarkSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;

  /// Closes the menu, once a tap has led somewhere. Not called for the few
  /// rows that point at nothing reachable, which would otherwise close the menu
  /// onto an unchanged screen.
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<({ShellController controller, bool loaded})>(
        select: (controller) =>
            (controller: controller, loaded: controller.loaded),
        builder: (context, shell, _) => _BookmarkSectionView(
          controller: shell.controller,
          controllerLoaded: shell.loaded,
          siteUrl: siteUrl,
          onOpened: onOpened,
        ),
      );
}

class _BookmarkSectionView extends StatefulWidget {
  const _BookmarkSectionView({
    required this.controller,
    required this.controllerLoaded,
    required this.siteUrl,
    required this.onOpened,
  });

  final ShellController controller;
  final bool controllerLoaded;
  final String siteUrl;
  final VoidCallback onOpened;

  @override
  State<_BookmarkSectionView> createState() => _BookmarkSectionViewState();
}

class _BookmarkSectionViewState extends State<_BookmarkSectionView> {
  (ShellController, String)? _requestIdentity;
  (ShellController, String)? _loadedRequestIdentity;
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(_BookmarkSectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.siteUrl != widget.siteUrl ||
        (!oldWidget.controllerLoaded && widget.controllerLoaded)) {
      _request();
    }
  }

  void _request() {
    final controller = widget.controller;
    final siteUrl = widget.siteUrl;
    final identity = (controller, siteUrl);
    if (_loadedRequestIdentity == identity && controller.loaded) return;
    if (_requestIdentity == identity && _requestInFlight) return;
    _requestIdentity = identity;
    _requestInFlight = true;
    unawaited(_load(controller, siteUrl, identity));
  }

  Future<void> _load(
    ShellController controller,
    String siteUrl,
    (ShellController, String) identity,
  ) async {
    try {
      await controller.load();
      if (!mounted || _requestIdentity != identity || !controller.loaded) {
        return;
      }
      _loadedRequestIdentity = identity;
      await controller.loadBookmarks(siteUrl);
    } catch (_) {
      return;
    } finally {
      if (_requestIdentity == identity) _requestInFlight = false;
    }
  }

  /// Follows a bookmark to whatever it was put on.
  ///
  /// A topic on a site in the rail is something this app has a view for, so it
  /// opens here. Everything else a bookmark can be on — a chat message, a
  /// profile, whatever a plugin made bookmarkable — is a page this app does not
  /// have, and belongs in the browser rather than nowhere.
  Future<void> _open(String? path) async {
    if (path == null) return;

    final controller = widget.controller;
    final absolute = controller.absoluteUrl(path, siteUrl: widget.siteUrl);
    if (controller.openTopicUrl(absolute)) {
      widget.onOpened();
      return;
    }
    if (await openExternalLink(absolute) && mounted) widget.onOpened();
  }

  /// Marks a reminder read, then follows it — the same act as tapping it in
  /// the notifications tab.
  Future<void> _openReminder(DiscourseNotification reminder) async {
    ShellScope.read(context).readNotification(widget.siteUrl, reminder);
    await _open(reminder.path);
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
        // Not loaded and not loading is the moment before the fetch this widget
        // asked for has started, which is a wait like any other.
        if (!feed.loaded) return const UserMenuMessage(text: null);
        if (feed.isEmpty) {
          return const UserMenuMessage(text: 'Nothing bookmarked yet.');
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final reminder in feed.reminders)
              NotificationRow(
                notification: reminder,
                onTap: () => _openReminder(reminder),
              ),
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

/// One bookmark, drawn to the same measurements as the notification rows it
/// shares the tab with.
///
/// Discourse's own row is the author's avatar, their name, and the title. Using
/// the bookmark's icon in place of the avatar follows `NotificationRow`, and
/// keeps the two runs of rows in one column reading as one list; the icon says
/// whether a reminder is set, which is the one thing about a bookmark that is
/// not on its face.
class BookmarkRow extends StatelessWidget {
  const BookmarkRow({super.key, required this.bookmark, required this.onTap});

  final Bookmark bookmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
    );

    // What the reader wrote about why they kept it, where Discourse puts it:
    // on hover, rather than taking a second line from every row that has one.
    final name = bookmark.name;
    if (name == null) return row;
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      child: row,
    );
  }
}
