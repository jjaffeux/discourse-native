import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'platform.dart';

/// Shows secondary content *over* the shell rather than replacing the main
/// region. Slides up from the bottom and is drag-dismissable; on wide windows
/// it is capped and centered rather than stretched edge to edge.
///
/// Use it for anything the user should be able to dismiss without losing their
/// place — composing, quick actions, pickers.
///
/// Sheets nest: opening one from inside another leaves the first in place
/// behind it. Pass [nested] so the second one is headed by a way back to the
/// first rather than by a way out of both.
///
/// Pass [dialogOnDesktop] for a picker that belongs next to what opened it
/// rather than at the far bottom edge of a large window: on a pointer platform
/// it is then centered as a dialog, and stays a sheet everywhere a finger is
/// the only way in.
///
/// Pass [footerBuilder] for actions that must remain reachable while a long
/// body scrolls. The footer stays outside the body's scroll view and accounts
/// for the bottom safe area on touch platforms.
///
/// Set [enableDrag] to false for a body which temporarily guards its route
/// with [PopScope]. Flutter's drag-to-close path pops directly, while the
/// header and barrier use the guarded `maybePop` path.
Future<T?> showShellSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  WidgetBuilder? footerBuilder,
  bool nested = false,
  bool dialogOnDesktop = false,
  BoxConstraints desktopDialogConstraints = const BoxConstraints(
    maxWidth: 480,
    maxHeight: 560,
  ),
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 16,
  ),
  EdgeInsetsGeometry footerPadding = const EdgeInsets.fromLTRB(24, 12, 24, 16),
  bool enableDrag = true,
}) {
  if (dialogOnDesktop && !context.isTouch) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: desktopDialogConstraints,
          child: _SheetBody(
            title: title,
            builder: builder,
            footerBuilder: footerBuilder,
            nested: nested,
            padding: padding,
            footerPadding: footerPadding,
            // A dialog is already lifted clear of the keyboard and of the
            // screen edges by its own inset padding.
            insetsBottom: false,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: enableDrag,
    enableDrag: enableDrag,
    constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
    builder: (context) => _SheetBody(
      title: title,
      builder: builder,
      footerBuilder: footerBuilder,
      nested: nested,
      padding: padding,
      footerPadding: footerPadding,
    ),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.builder,
    required this.footerBuilder,
    required this.nested,
    required this.padding,
    required this.footerPadding,
    this.insetsBottom = true,
  });

  final String title;
  final WidgetBuilder builder;
  final WidgetBuilder? footerBuilder;
  final bool nested;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry footerPadding;

  /// Whether this body has to keep itself clear of the keyboard and of the
  /// bottom edge, as a sheet running to that edge does.
  final bool insetsBottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = insetsBottom
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;

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
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const DIcon(DIcons.arrowLeft),
                    tooltip: 'Back',
                  ),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Dismissing a nested sheet means going back to the one under it,
                // which the arrow already says better than a close box would.
                if (!nested)
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
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
                bottom: footerBuilder == null && insetsBottom
                    ? MediaQuery.paddingOf(context).bottom
                    : 0,
              ),
              child: Padding(padding: padding, child: builder(context)),
            ),
          ),
          if (footerBuilder case final footerBuilder?) ...[
            Divider(color: theme.shell.divider, height: 1),
            Padding(
              padding: EdgeInsets.only(
                bottom: insetsBottom ? MediaQuery.paddingOf(context).bottom : 0,
              ),
              child: Padding(
                padding: footerPadding,
                child: footerBuilder(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
