import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../foundation/icons/d_native_icons.dart';
import '../models/destination_bookmark.dart';
import 'bookmark_tile.dart';
import 'open_link.dart';
import 'shell_scope.dart';

class DestinationBookmarkRow extends StatelessWidget {
  const DestinationBookmarkRow({
    super.key,
    required this.siteUrl,
    required this.bookmark,
    this.onOpened,
    this.padding,
  });
  final String siteUrl;
  final DestinationBookmark bookmark;
  final VoidCallback? onOpened;

  /// The user menu's inset; the Bookmarks page keeps the tile's own.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final lease = shell.lifecycle.capture(siteUrl);
    final account = shell.currentAccountIdentity;
    final title = bookmark.route.title;
    final (kind, icon) = switch (bookmark.kind) {
      DestinationBookmarkKind.page => (
        context.l10n.destinationBookmarkPageType,
        DNativeIcons.windowMaximize,
      ),
      DestinationBookmarkKind.category => (context.l10n.category, DIcons.tag),
      DestinationBookmarkKind.chat => (context.l10n.chat, DIcons.comment),
    };
    // A chat is placed by its channel, as a chat message's bookmark is; a
    // page or category belongs to the forum as a whole.
    final where = bookmark.kind == DestinationBookmarkKind.chat
        ? title
        : shell.instances
                  .where((site) => site.url == siteUrl)
                  .firstOrNull
                  ?.title ??
              siteUrl;
    return LinkTarget.content(
      content: bookmark.route,
      siteUrl: siteUrl,
      child: BookmarkTile(
        key: ValueKey('destination-bookmark-row-${bookmark.identity}'),
        padding: padding,
        icon: icon,
        color: bookmark.route.color,
        title: title,
        details: '$kind · $where',
        semanticLabel: '$title, $kind, $where',
        onPressed: () => unawaited(() async {
          if (!lease.isCurrent || shell.currentAccountIdentity != account) {
            return;
          }
          final opened = await shell.openDestinationBookmark(siteUrl, bookmark);
          if (!context.mounted ||
              !lease.isCurrent ||
              shell.currentAccountIdentity != account) {
            return;
          }
          if (opened) {
            onOpened?.call();
          } else {
            DToast.show(context, context.l10n.destinationBookmarkUnavailable);
          }
        }()),
      ),
    );
  }
}
