import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/content_route.dart';
import 'account_destination_bookmarks.dart';

/// Hands the account's local bookmarks to a menu item, so the item neither
/// compiles the shell nor wakes on its notifications.
class DestinationBookmarksScope extends InheritedWidget {
  const DestinationBookmarksScope({
    super.key,
    required this.bookmarks,
    required super.child,
  });

  final AccountDestinationBookmarks bookmarks;

  static AccountDestinationBookmarks? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DestinationBookmarksScope>()
      ?.bookmarks;

  @override
  bool updateShouldNotify(DestinationBookmarksScope oldWidget) =>
      !identical(bookmarks, oldWidget.bookmarks);
}

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
    final bookmarks = DestinationBookmarksScope.maybeOf(context);
    if (bookmarks == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: bookmarks,
      builder: (context, _) {
        final action = bookmarks.actionFor(route, siteUrl: siteUrl);
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
      },
    );
  }
}
