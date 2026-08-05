import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows secondary content *over* the shell rather than replacing the main
/// region. Always slides up from the bottom and is drag-dismissable; on wide
/// windows it is capped and centered rather than stretched edge to edge.
///
/// Use it for anything the user should be able to dismiss without losing their
/// place — composing, quick actions, pickers.
Future<T?> showShellSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).shell.sidebar,
    constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
    builder: (context) => _SheetBody(title: title, builder: builder),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.builder});

  final String title;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        Divider(color: theme.shell.divider, height: 1),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: builder(context),
          ),
        ),
      ],
    );
  }
}
