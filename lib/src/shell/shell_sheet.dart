import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';

/// Shows secondary content *over* the shell rather than replacing the main
/// region. Always slides up from the bottom and is drag-dismissable; on wide
/// windows it is capped and centered rather than stretched edge to edge.
///
/// Use it for anything the user should be able to dismiss without losing their
/// place — composing, quick actions, pickers.
///
/// Sheets nest: opening one from inside another leaves the first in place
/// behind it. Pass [nested] so the second one is headed by a way back to the
/// first rather than by a way out of both.
Future<T?> showShellSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  bool nested = false,
  EdgeInsetsGeometry padding = const EdgeInsets.all(20),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).shell.sidebar,
    constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
    builder: (context) => _SheetBody(
      title: title,
      builder: builder,
      nested: nested,
      padding: padding,
    ),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.builder,
    required this.nested,
    required this.padding,
  });

  final String title;
  final WidgetBuilder builder;
  final bool nested;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      key: const ValueKey('shell-sheet-keyboard-inset'),
      padding: EdgeInsets.only(bottom: keyboardInset),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(nested ? 4 : 20, 8, 8, 8),
            child: Row(
              children: [
                if (nested)
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const DIcon(DIcons.arrowLeft),
                    tooltip: 'Back',
                  ),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Dismissing a nested sheet means going back to the one under it,
                // which the arrow already says better than a close box would.
                if (!nested)
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const DIcon(DIcons.xmark),
                    tooltip: 'Close',
                  ),
              ],
            ),
          ),
          Divider(color: theme.shell.divider, height: 1),
          Flexible(
            child: SingleChildScrollView(
              // The sheet runs to the bottom edge, so the last row of a full one
              // would otherwise sit under the home indicator.
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              child: Padding(padding: padding, child: builder(context)),
            ),
          ),
        ],
      ),
    );
  }
}
