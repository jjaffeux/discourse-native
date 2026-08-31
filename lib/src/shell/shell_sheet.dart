import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'platform.dart';

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
