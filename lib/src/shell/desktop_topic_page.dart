import 'package:flutter/material.dart';

import 'forum_search.dart';
import 'platform.dart';
import 'title_bar.dart';

/// Supplies search where the desktop window chrome cannot carry it.
/// Topic navigation and editing belong to the Ledger header and source list.
class DesktopTopicPage extends StatelessWidget {
  const DesktopTopicPage({
    super.key,
    required this.child,
    this.sourceListVisible = false,
  });

  final Widget child;
  final bool sourceListVisible;

  @override
  Widget build(BuildContext context) {
    if (context.isTouch || sourceListVisible || ShellTitleBar.isSupported) {
      return child;
    }
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ForumSearch(dense: true),
        ),
        Expanded(child: child),
      ],
    );
  }
}
