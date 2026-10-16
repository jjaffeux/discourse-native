import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/content_route.dart';
import '../models/destination_bookmark.dart';
import '../theme/d_icons.dart';
import 'open_link.dart';
import 'shell_scope.dart';

String destinationBookmarkTypeLabel(DestinationBookmarkKind kind) =>
    switch (kind) {
      DestinationBookmarkKind.page => appL10n.destinationBookmarkPageType,
      DestinationBookmarkKind.category => appL10n.category,
      DestinationBookmarkKind.chat => appL10n.chat,
    };

DIconData destinationBookmarkIcon(DestinationBookmarkKind kind) =>
    switch (kind) {
      DestinationBookmarkKind.page => DIcons.farFileLines,
      DestinationBookmarkKind.category => DIcons.tag,
      DestinationBookmarkKind.chat => DIcons.comment,
    };

class DestinationBookmarkMenuItem extends StatelessWidget {
  const DestinationBookmarkMenuItem({
    super.key,
    required this.route,
    this.siteUrl,
    this.dropdown = false,
  });
  final ContentRoute route;
  final String? siteUrl;
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    final action = shell?.destinationBookmarkAction(route, siteUrl: siteUrl);
    if (action == null) return const SizedBox.shrink();
    final label = action.bookmarked
        ? context.l10n.removeBookmark
        : context.l10n.bookmark;
    final toasts = DToast.maybeOf(context);
    void invoke() => unawaited(
      action.invoke().then((result) {
        if (result.message case final message?) {
          toasts?.add(DToastOptions(description: message));
        }
      }),
    );
    return dropdown
        ? DDropdownMenuItem(
            key: ValueKey('destination-bookmark-${route.id}'),
            leading: const DIcon(DIcons.bookmark),
            onPressed: invoke,
            child: Text(label),
          )
        : DContextMenuItem(
            key: ValueKey('destination-bookmark-${route.id}'),
            leading: const DIcon(DIcons.bookmark),
            onPressed: invoke,
            child: Text(label),
          );
  }
}

class DestinationBookmarkRow extends StatelessWidget {
  const DestinationBookmarkRow({
    super.key,
    required this.siteUrl,
    required this.bookmark,
    this.onOpened,
  });
  final String siteUrl;
  final DestinationBookmark bookmark;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final lease = shell.lifecycle.capture(siteUrl);
    final account = shell.currentAccountIdentity;
    final label = destinationBookmarkTypeLabel(bookmark.kind);
    final forum =
        shell.instances
            .where((site) => site.url == siteUrl)
            .firstOrNull
            ?.title ??
        siteUrl;
    return LinkTarget.content(
      content: bookmark.route,
      siteUrl: siteUrl,
      child: DItem(
        key: ValueKey('destination-bookmark-row-${bookmark.identity}'),
        shape: DItemShape.fullWidth,
        semanticLabel: '${bookmark.route.title}, $label, $forum',
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
        children: [
          DItemMedia(
            child: DAvatar(
              decorative: true,
              fallback: DAvatarFallback(
                backgroundColor:
                    (bookmark.route.color ??
                            DTokens.of(context).mutedForeground)
                        .withValues(alpha: .2),
                foregroundColor:
                    bookmark.route.color ?? DTokens.of(context).mutedForeground,
                child: DIcon(destinationBookmarkIcon(bookmark.kind)),
              ),
            ),
          ),
          DItemContent(
            children: [
              ExcludeSemantics(
                child: Text(
                  bookmark.route.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  '$label · $forum',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DTokens.of(context).mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
