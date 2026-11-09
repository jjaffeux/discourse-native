import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/content_route.dart';
import 'shell_scope.dart';

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
    final bookmarks = ShellScope.maybeOf(context)?.accountDestinationBookmarks;
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
